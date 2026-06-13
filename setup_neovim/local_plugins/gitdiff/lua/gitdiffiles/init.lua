local M = {}

local WORKDIR_ID = "WORKDIR"

local config = {
  log_max = 0,
  log_view = "oneline",
  diff_mode = "pr",
  ui = {
    open_in_tab = true,
    file_height = nil,
    log_height = nil,
  },
  keys = {
    open = "<CR>",
    refresh = "r",
    quit = "q",
    set_source = "s",
    set_target = "t",
    toggle_log = "L",
    toggle_mode = "m",
  },
}

local state = {
  root = nil,
  source = nil,
  target = nil,
  log_items = {},
  log_entries = {},
  log_item_by_id = {},
  log_line_map = {},
  log_graph_short = {},
  log_graph_full = {},
  log_view = "oneline",
  file_items = {},
  file_line_map = {},
  diff_mode = "pr",
  compare_target = nil,
  merge_base = nil,
  base_source = nil,
  buf = { files = nil, log = nil },
  win = { files = nil, log = nil },
  ns = vim.api.nvim_create_namespace("gitdiff"),
}

local short_hash
local is_workdir_target
local ref_label
local set_ref
local default_source_from_log

local ANSI_COLOR_GROUP_BY_CODE = {
  [30] = "GitDiffAnsiBlack",
  [31] = "GitDiffAnsiRed",
  [32] = "GitDiffAnsiGreen",
  [33] = "GitDiffAnsiYellow",
  [34] = "GitDiffAnsiBlue",
  [35] = "GitDiffAnsiMagenta",
  [36] = "GitDiffAnsiCyan",
  [37] = "GitDiffAnsiWhite",
  [90] = "GitDiffAnsiBrightBlack",
  [91] = "GitDiffAnsiBrightRed",
  [92] = "GitDiffAnsiBrightGreen",
  [93] = "GitDiffAnsiBrightYellow",
  [94] = "GitDiffAnsiBrightBlue",
  [95] = "GitDiffAnsiBrightMagenta",
  [96] = "GitDiffAnsiBrightCyan",
  [97] = "GitDiffAnsiBrightWhite",
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "GitDiff" })
end

local function git_cmd(args)
  local cmd = vim.deepcopy(args)
  table.insert(cmd, 1, "git")
  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, output
  end
  return output, nil
end

local function get_git_root()
  local output = git_cmd({ "rev-parse", "--show-toplevel" })
  if not output or #output == 0 then
    return nil
  end
  return output[1]
end

local function resolve_ref(ref)
  if not ref or ref == "" then
    return nil
  end
  local output = git_cmd({ "rev-parse", ref })
  if not output or #output == 0 then
    return nil
  end
  return output[1]
end

local function commit_ref_from_hash(hash, display)
  if not hash or hash == "" then
    return nil
  end
  local short = short_hash(hash) or hash:sub(1, 7)
  return {
    kind = "commit",
    spec = hash,
    hash = hash,
    short = short,
    display = display or short,
  }
end

local function clone_ref(ref)
  if not ref then
    return nil
  end
  return vim.deepcopy(ref)
end

local function normalize_log_max(value)
  local n = tonumber(value)
  if not n or n <= 0 then
    return nil
  end
  return math.floor(n)
end

local function append_log_max(args)
  local log_max = normalize_log_max(config.log_max)
  if log_max then
    table.insert(args, "--max-count")
    table.insert(args, tostring(log_max))
  end
  return args
end

local function normalize_diff_mode(value)
  if value == "all" then
    return "all"
  end
  return "pr"
end

local function apply_ansi_codes(codes, active_group)
  if codes == nil then
    return active_group
  end
  if codes == "" then
    return nil
  end

  local group = active_group
  for code_text in codes:gmatch("%d+") do
    local code = tonumber(code_text)
    if code == 0 or code == 39 then
      group = nil
    elseif ANSI_COLOR_GROUP_BY_CODE[code] then
      group = ANSI_COLOR_GROUP_BY_CODE[code]
    end
  end
  return group
end

local function strip_ansi_and_collect_spans(raw_line)
  local out = {}
  local spans = {}
  local out_col = 0
  local idx = 1
  local active_group = nil

  while idx <= #raw_line do
    local esc_idx = raw_line:find(string.char(27), idx, true)
    if not esc_idx then
      local chunk = raw_line:sub(idx)
      if chunk ~= "" then
        table.insert(out, chunk)
        local start_col = out_col
        out_col = out_col + #chunk
        if active_group then
          table.insert(spans, {
            hl_group = active_group,
            start_col = start_col,
            end_col = out_col,
          })
        end
      end
      break
    end

    if esc_idx > idx then
      local chunk = raw_line:sub(idx, esc_idx - 1)
      if chunk ~= "" then
        table.insert(out, chunk)
        local start_col = out_col
        out_col = out_col + #chunk
        if active_group then
          table.insert(spans, {
            hl_group = active_group,
            start_col = start_col,
            end_col = out_col,
          })
        end
      end
    end

    local s, e, codes = raw_line:find("\27%[([0-9;]*)m", esc_idx)
    if s == esc_idx then
      active_group = apply_ansi_codes(codes, active_group)
      idx = e + 1
    else
      idx = esc_idx + 1
    end
  end

  return table.concat(out), spans
end

local function diff_mode_label(mode)
  return normalize_diff_mode(mode) == "all" and "ALL" or "PR"
end

local function next_diff_mode_label()
  if normalize_diff_mode(state.diff_mode) == "all" then
    return "PR"
  end
  return "ALL"
end

local function current_target_spec()
  if is_workdir_target() then
    return "HEAD"
  end
  return state.target and state.target.spec or nil
end

local function build_compare_target_ref()
  local spec = current_target_spec()
  if not spec then
    return nil
  end
  local ref = set_ref(spec)
  if ref then
    ref.display = spec
  end
  return ref
end

local function compute_merge_base_ref(source_spec, target_spec)
  if not source_spec or source_spec == "" or not target_spec or target_spec == "" then
    return nil
  end
  local output = git_cmd({ "merge-base", source_spec, target_spec })
  if not output or #output == 0 then
    return nil
  end
  return commit_ref_from_hash(output[1])
end

local function update_compare_refs()
  state.compare_target = build_compare_target_ref()
  state.merge_base = nil

  if not state.base_source or not state.base_source.spec then
    return
  end

  local target_spec = state.compare_target and state.compare_target.spec
  if not target_spec then
    return
  end

  state.merge_base = compute_merge_base_ref(state.base_source.spec, target_spec)
end

local function effective_source_ref()
  if normalize_diff_mode(state.diff_mode) == "all" then
    return state.source
  end
  return state.merge_base or state.base_source or state.source
end

local function effective_source_kind()
  if normalize_diff_mode(state.diff_mode) == "all" then
    return "source"
  end
  return "merge-base"
end

short_hash = function(hash)
  if not hash then
    return nil
  end
  local output = git_cmd({ "rev-parse", "--short", hash })
  if not output or #output == 0 then
    return nil
  end
  return output[1]
end

local function set_buf_name_unique(buf, name)
  local ok = pcall(vim.api.nvim_buf_set_name, buf, name)
  if ok then
    return
  end
  local suffix = 1
  while true do
    local candidate = string.format("%s (%d)", name, suffix)
    if vim.fn.bufnr(candidate) == -1 then
      pcall(vim.api.nvim_buf_set_name, buf, candidate)
      return
    end
    suffix = suffix + 1
  end
end

local function create_buf(name, lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  set_buf_name_unique(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.bo[buf].modifiable = false
  if filetype then
    vim.bo[buf].filetype = filetype
  end
  return buf
end

local function set_buf_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function setup_window(win, opts)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.wrap = false
  wo.cursorline = opts and opts.cursorline or false
  if wo.winhl == "" then
    wo.winhl = "WinBar:Title,WinBarNC:Title"
  elseif not wo.winhl:match("WinBar:") then
    wo.winhl = wo.winhl .. ",WinBar:Title,WinBarNC:Title"
  end
end

local function build_log_entries(range)
  local entries = {}
  local args = append_log_max({
    "--no-pager",
    "log",
    "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s",
    "--date=iso",
  })
  if range then
    table.insert(args, range)
  end
  local output, err = git_cmd(args)
  if not output then
    notify(table.concat(err or {}, "\n"), vim.log.levels.ERROR)
    return nil
  end

  for _, line in ipairs(output) do
    if line ~= "" then
      local fields = vim.split(line, "\x1f", { plain = true })
      local id = fields[1]
      if id and id ~= "" then
        table.insert(entries, {
          id = id,
          short = fields[2],
          author = fields[3] or "",
          date = fields[4] or "",
          subject = fields[5] or "",
        })
      end
    end
  end

  return entries
end

local function build_log_graph_lines(view, range)
  local pretty = "%C(auto)%h %d %s%Creset%x1f%H"
  if view == "full" then
    pretty = "%C(auto)%h %d %s%Creset%x1f%H%nAuthor: %an <%ae>%nDate:   %ad%n%n%B"
  end

  local args = append_log_max({
    "--no-pager",
    "log",
    "--graph",
    "--decorate",
    "--color=always",
    "--pretty=format:" .. pretty,
    "--date=iso",
  })
  if range then
    table.insert(args, range)
  end
  local output, err = git_cmd(args)
  if not output then
    notify(table.concat(err or {}, "\n"), vim.log.levels.ERROR)
    return nil
  end

  local rows = {}
  local current_commit_id = nil
  for _, raw in ipairs(output) do
    local visible = raw
    local commit_id = nil

    local sep = raw:find("\x1f", 1, true)
    if sep then
      visible = raw:sub(1, sep - 1)
      commit_id = raw:sub(sep + 1)
      if commit_id == "" then
        commit_id = nil
      end
    end

    local text, ansi_spans = strip_ansi_and_collect_spans(visible)
    if commit_id then
      current_commit_id = commit_id
    end

    table.insert(rows, {
      text = text,
      commit_id = commit_id or current_commit_id,
      is_commit_line = commit_id ~= nil,
      ansi_spans = ansi_spans,
    })
  end

  return rows
end

is_workdir_target = function()
  return state.target and state.target.kind == "workdir"
end

ref_label = function(ref)
  if not ref then
    return "?"
  end
  if ref.kind == "workdir" then
    return WORKDIR_ID
  end
  return ref.display or ref.short or ref.spec or ref.hash or "?"
end

local function marker_for_item(item)
  local is_source = state.source
    and state.source.hash
    and item.type == "commit"
    and item.id == state.source.hash
  local is_target = false
  if is_workdir_target() then
    is_target = item.type == "workdir"
  else
    is_target = state.target
      and state.target.hash
      and item.type == "commit"
      and item.id == state.target.hash
  end

  if is_source and is_target then
    return "ST", "both"
  end
  if is_source then
    return "S", "source"
  end
  if is_target then
    return "T", "target"
  end
  return " ", nil
end

local function render_log_buffer()
  if not state.buf.log then
    return
  end

  local lines = {}
  local marker_lines = {}
  local line_highlights = {}
  state.log_line_map = {}
  local graph_rows = state.log_view == "full" and state.log_graph_full or state.log_graph_short

  local function add_line_highlight(line, hl_group, start_col, end_col)
    if not line_highlights[line] then
      line_highlights[line] = {}
    end
    table.insert(line_highlights[line], {
      hl_group = hl_group,
      start_col = start_col,
      end_col = end_col,
    })
  end

  local line_idx = 1
  local work_item = state.log_items[1]
  if work_item then
    local marker, kind = marker_for_item(work_item)
    lines[line_idx] = string.format("%-2s %s", marker, work_item.label)
    state.log_line_map[line_idx] = work_item
    if kind then
      marker_lines[line_idx] = kind
    end
    line_idx = line_idx + 1
    if state.log_view == "full" then
      lines[line_idx] = ""
      line_idx = line_idx + 1
    end
  end

  for _, row in ipairs(graph_rows or {}) do
    local item = nil
    if row.commit_id then
      item = state.log_item_by_id[row.commit_id]
    end

    local marker = " "
    local kind = nil
    if item then
      marker, kind = marker_for_item(item)
      state.log_line_map[line_idx] = item
    end

    local text = row.text or ""
    lines[line_idx] = string.format("%-2s %s", marker, text)
    if kind then
      marker_lines[line_idx] = kind
    end

    if row.ansi_spans then
      for _, span in ipairs(row.ansi_spans) do
        add_line_highlight(
          line_idx,
          span.hl_group,
          span.start_col + 3,
          span.end_col + 3
        )
      end
    end

    if state.merge_base and row.is_commit_line and row.commit_id == state.merge_base.hash then
      add_line_highlight(line_idx, "GitDiffMergeBaseMarker", 3, #lines[line_idx])
    end

    line_idx = line_idx + 1
  end

  set_buf_lines(state.buf.log, lines)
  vim.api.nvim_buf_clear_namespace(state.buf.log, state.ns, 0, -1)

  for line, kind in pairs(marker_lines) do
    if kind == "both" then
      vim.api.nvim_buf_add_highlight(
        state.buf.log,
        state.ns,
        "GitDiffSourceTarget",
        line - 1,
        0,
        2
      )
    elseif kind == "source" then
      vim.api.nvim_buf_add_highlight(
        state.buf.log,
        state.ns,
        "GitDiffSourceMarker",
        line - 1,
        0,
        1
      )
    elseif kind == "target" then
      vim.api.nvim_buf_add_highlight(
        state.buf.log,
        state.ns,
        "GitDiffTargetMarker",
        line - 1,
        0,
        1
      )
    end
  end

  for line, highlights in pairs(line_highlights) do
    for _, highlight in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(
        state.buf.log,
        state.ns,
        highlight.hl_group,
        line - 1,
        highlight.start_col,
        highlight.end_col
      )
    end
  end
end

local function parse_name_status(lines)
  local items = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      local parts = vim.split(line, "\t", { plain = true })
      local status = parts[1] or ""
      local status_letter = status:sub(1, 1)
      if #parts == 2 then
        local path = parts[2]
        local item = {
          status = status_letter,
          source_path = path,
          target_path = path,
          display = string.format("%-2s %s", status_letter, path),
        }
        if status_letter == "A" then
          item.source_path = nil
        elseif status_letter == "D" then
          item.target_path = nil
        end
        table.insert(items, item)
      elseif #parts >= 3 then
        local old_path = parts[2]
        local new_path = parts[3]
        local arrow = " -> "
        table.insert(items, {
          status = status_letter,
          source_path = old_path,
          target_path = new_path,
          display = string.format("%-2s %s%s%s", status_letter, old_path, arrow, new_path),
        })
      end
    end
  end
  return items
end

local function build_file_items()
  local source = effective_source_ref()
  if not source or not source.spec then
    return {}
  end
  local args = { "diff", "--name-status" }
  if is_workdir_target() then
    table.insert(args, source.spec)
  else
    table.insert(args, source.spec .. ".." .. state.target.spec)
  end

  local output, err = git_cmd(args)
  if not output then
    notify(table.concat(err or {}, "\n"), vim.log.levels.ERROR)
    return {}
  end
  return parse_name_status(output)
end

local function render_files_buffer()
  if not state.buf.files then
    return
  end
  local lines = {}
  state.file_line_map = {}
  if #state.file_items == 0 then
    lines[1] = "No changes"
  else
    for i, item in ipairs(state.file_items) do
      local line_idx = i
      lines[line_idx] = item.display
      state.file_line_map[line_idx] = item
    end
  end
  set_buf_lines(state.buf.files, lines)
  vim.api.nvim_buf_clear_namespace(state.buf.files, state.ns, 0, -1)
end

local function winbar_text(title, detail)
  return string.format("=== GitDiff %s ===%%=%%<%s", title, detail or "")
end

local function update_winbars()
  local source_label = ref_label(state.source)
  local target_label = ref_label(state.target)
  local baseline = effective_source_ref()
  local baseline_label = baseline and ref_label(baseline) or "?"
  local mode_detail = string.format(
    "mode=%s [%s=%s] %s=%s",
    diff_mode_label(state.diff_mode),
    config.keys.toggle_mode,
    next_diff_mode_label(),
    effective_source_kind(),
    baseline_label
  )
  if state.win.files and vim.api.nvim_win_is_valid(state.win.files) then
    vim.wo[state.win.files].winbar = winbar_text(
      "FILES",
      string.format("source=%s  target=%s  %s", source_label, target_label, mode_detail)
    )
  end
  if state.win.log and vim.api.nvim_win_is_valid(state.win.log) then
    local view = state.log_view == "full" and "FULL" or "ONELINE"
    vim.wo[state.win.log].winbar = winbar_text(
      "LOG " .. view,
      string.format("source=%s  target=%s  %s", source_label, target_label, mode_detail)
    )
    vim.wo[state.win.log].wrap = state.log_view == "full"
    vim.wo[state.win.log].linebreak = state.log_view == "full"
    vim.wo[state.win.log].breakindent = state.log_view == "full"
  end
end

set_ref = function(ref)
  local hash = resolve_ref(ref)
  local short = hash and short_hash(hash)
  return {
    kind = "commit",
    spec = ref,
    hash = hash,
    short = short or ref,
    display = ref,
  }
end

local function default_source_ref()
  local candidates = { "origin/HEAD", "origin/main", "origin/master", "main", "master" }
  for _, candidate in ipairs(candidates) do
    local ref = set_ref(candidate)
    if ref and ref.hash then
      return ref
    end
  end
  return default_source_from_log()
end

default_source_from_log = function()
  local first_commit = state.log_items[2]
  if first_commit then
    return {
      kind = "commit",
      spec = first_commit.id,
      hash = first_commit.id,
      short = first_commit.short,
      display = first_commit.short,
    }
  end
  return nil
end

local function refresh()
  update_compare_refs()
  local new_entries = build_log_entries()
  if new_entries then
    state.log_entries = new_entries
    state.log_items = {
      { type = "workdir", id = WORKDIR_ID, label = "WORKDIR (uncommitted changes)" },
    }
    for _, entry in ipairs(state.log_entries) do
      local short = entry.short or (entry.id and entry.id:sub(1, 7)) or ""
      table.insert(state.log_items, {
        type = "commit",
        id = entry.id,
        short = short,
        label = short .. " " .. (entry.subject or ""),
      })
    end

    state.log_item_by_id = {}
    for _, item in ipairs(state.log_items) do
      if item.type == "commit" then
        state.log_item_by_id[item.id] = item
      end
    end
  end

  state.log_graph_short = build_log_graph_lines("oneline") or {}
  state.log_graph_full = build_log_graph_lines("full") or {}

  state.file_items = build_file_items()
  render_files_buffer()
  render_log_buffer()
  update_winbars()
end

local function get_log_item_at_cursor()
  if not (state.win.log and vim.api.nvim_win_is_valid(state.win.log)) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.win.log)[1]
  if state.log_line_map[line] then
    return state.log_line_map[line]
  end
  for idx = line, 1, -1 do
    if state.log_line_map[idx] then
      return state.log_line_map[idx]
    end
  end
  return nil
end

local function get_file_item_at_cursor()
  if not (state.win.files and vim.api.nvim_win_is_valid(state.win.files)) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.win.files)[1]
  return state.file_line_map[line]
end

local function git_show_lines(ref, path)
  local output, err = git_cmd({ "--no-pager", "show", ref .. ":" .. path })
  if not output then
    return nil, table.concat(err or {}, "\n")
  end
  return output, nil
end

local function set_filetype_for_path(buf, path)
  if not path or path == "" then
    return
  end
  if vim.filetype and vim.filetype.match then
    local ft = vim.filetype.match({ filename = path })
    if ft then
      vim.bo[buf].filetype = ft
    end
  end
end

local function open_diff_for_item(item)
  if not item then
    item = get_file_item_at_cursor()
  end
  if not item then
    notify("No file selected", vim.log.levels.WARN)
    return
  end
  local source = effective_source_ref()
  if not source or not source.spec then
    notify("No source commit set", vim.log.levels.ERROR)
    return
  end

  local source_label = ref_label(source)
  local target_label = ref_label(state.target)
  local source_title = "BASE " .. source_label
  local target_title = "TARGET " .. target_label

  local source_path = item.source_path
  local target_path = item.target_path

  vim.cmd("tabnew")
  vim.cmd("lcd " .. vim.fn.fnameescape(state.root))

  local left_win = vim.api.nvim_get_current_win()
  local left_buf = create_buf(
    "[GitDiff] " .. source_title .. ":" .. (source_path or "(missing)"),
    {},
    "git"
  )
  vim.api.nvim_win_set_buf(left_win, left_buf)
  setup_window(left_win, { cursorline = false })
  vim.wo[left_win].winbar = winbar_text(
    "BASE " .. diff_mode_label(state.diff_mode) .. " " .. source_label,
    source_path or "(missing)"
  )

  local left_lines = {}
  if source_path then
    local lines, err = git_show_lines(source.spec, source_path)
    if lines then
      left_lines = lines
    else
      left_lines = { err or "Unable to read file from source commit" }
    end
  end
  set_buf_lines(left_buf, left_lines)
  set_filetype_for_path(left_buf, source_path)

  local old_splitright = vim.o.splitright
  vim.o.splitright = true
  vim.cmd("vsplit")
  vim.o.splitright = old_splitright
  local right_win = vim.api.nvim_get_current_win()
  setup_window(right_win, { cursorline = false })

  local right_buf
  if is_workdir_target() then
    if target_path then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      right_buf = vim.api.nvim_get_current_buf()
      vim.wo[right_win].winbar = winbar_text(
        "TARGET " .. target_label,
        target_path
      )
    else
      right_buf = create_buf(
        "[GitDiff] " .. target_title .. ":(missing)",
        {},
        "git"
      )
      vim.api.nvim_win_set_buf(right_win, right_buf)
      vim.wo[right_win].winbar = winbar_text(
        "TARGET " .. target_label,
        "(missing)"
      )
    end
  else
    right_buf = create_buf(
      "[GitDiff] " .. target_title .. ":" .. (target_path or "(missing)"),
      {},
      "git"
    )
    vim.api.nvim_win_set_buf(right_win, right_buf)
    vim.wo[right_win].winbar = winbar_text(
      "TARGET " .. target_label,
      target_path or "(missing)"
    )
    if target_path then
      local lines, err = git_show_lines(state.target.spec, target_path)
      if lines then
        set_buf_lines(right_buf, lines)
      else
        set_buf_lines(right_buf, { err or "Unable to read file from target commit" })
      end
      set_filetype_for_path(right_buf, target_path)
    end
  end

  vim.cmd("windo diffthis")
  vim.api.nvim_set_current_win(right_win)
end

local function close_ui()
  if config.ui.open_in_tab then
    vim.cmd("tabclose")
    return
  end
  if state.win.log and vim.api.nvim_win_is_valid(state.win.log) then
    pcall(vim.api.nvim_win_close, state.win.log, true)
  end
  if state.win.files and vim.api.nvim_win_is_valid(state.win.files) then
    pcall(vim.api.nvim_win_close, state.win.files, true)
  end
end

local function toggle_log_view()
  if state.log_view == "full" then
    state.log_view = "oneline"
  else
    state.log_view = "full"
  end
  render_log_buffer()
  update_winbars()
end

local function toggle_diff_mode()
  if normalize_diff_mode(state.diff_mode) == "all" then
    state.diff_mode = "pr"
  else
    state.diff_mode = "all"
  end
  refresh()
  notify(
    string.format(
      "Diff mode: %s (press %s to switch to %s)",
      diff_mode_label(state.diff_mode),
      config.keys.toggle_mode,
      next_diff_mode_label()
    )
  )
end

local function set_keymaps()
  if state.buf.files then
    vim.keymap.set("n", config.keys.open, open_diff_for_item, {
      buffer = state.buf.files,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.refresh, refresh, {
      buffer = state.buf.files,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.quit, close_ui, {
      buffer = state.buf.files,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.toggle_mode, toggle_diff_mode, {
      buffer = state.buf.files,
      nowait = true,
      silent = true,
    })
  end

  if state.buf.log then
    vim.keymap.set("n", config.keys.set_source, function()
      local item = get_log_item_at_cursor()
      if not item then
        return
      end
      if item.type ~= "commit" then
        notify("Source must be a commit", vim.log.levels.WARN)
        return
      end
      state.source = {
        kind = "commit",
        spec = item.id,
        hash = item.id,
        short = item.short,
        display = item.short,
      }
      refresh()
    end, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })

    vim.keymap.set("n", config.keys.set_target, function()
      local item = get_log_item_at_cursor()
      if not item then
        return
      end
      if item.type == "workdir" then
        state.target = { kind = "workdir" }
      else
        state.target = {
          kind = "commit",
          spec = item.id,
          hash = item.id,
          short = item.short,
          display = item.short,
        }
      end
      refresh()
    end, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })

    vim.keymap.set("n", config.keys.refresh, refresh, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.toggle_log, toggle_log_view, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.toggle_mode, toggle_diff_mode, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })
    vim.keymap.set("n", config.keys.quit, close_ui, {
      buffer = state.buf.log,
      nowait = true,
      silent = true,
    })
  end
end

local function open_ui()
  if config.ui.open_in_tab then
    vim.cmd("tabnew")
  end
  vim.cmd("silent! only")
  vim.cmd("lcd " .. vim.fn.fnameescape(state.root))

  local files_buf = create_buf("[GitDiff] files", {}, "git")
  state.buf.files = files_buf
  state.win.files = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win.files, files_buf)
  setup_window(state.win.files, { cursorline = true })

  vim.cmd("belowright split")
  local log_buf = create_buf("[GitDiff] log", {}, "git")
  state.buf.log = log_buf
  state.win.log = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win.log, log_buf)
  setup_window(state.win.log, { cursorline = true })

  if config.ui.log_height and config.ui.log_height > 0 then
    pcall(vim.api.nvim_win_set_height, state.win.log, config.ui.log_height)
  elseif config.ui.file_height and config.ui.file_height > 0 then
    pcall(vim.api.nvim_win_set_height, state.win.files, config.ui.file_height)
  end

  set_keymaps()
  refresh()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  config.diff_mode = normalize_diff_mode(config.diff_mode)
  if config.ui and config.ui.open_in_tab ~= nil then
    local v = config.ui.open_in_tab
    if v == 0 or v == "0" or v == "false" then
      config.ui.open_in_tab = false
    elseif v == 1 or v == "1" or v == "true" then
      config.ui.open_in_tab = true
    end
  end
end

function M.open(opts)
  opts = opts or {}

  local root = get_git_root()
  if not root then
    notify("Not in a git repo", vim.log.levels.ERROR)
    return
  end
  state.root = root

  state.log_entries = build_log_entries() or {}
  if #state.log_entries == 0 then
    notify("No git log entries found", vim.log.levels.ERROR)
    return
  end
  state.log_items = {
    { type = "workdir", id = WORKDIR_ID, label = "WORKDIR (uncommitted changes)" },
  }
  for _, entry in ipairs(state.log_entries) do
    local short = entry.short or (entry.id and entry.id:sub(1, 7)) or ""
    table.insert(state.log_items, {
      type = "commit",
      id = entry.id,
      short = short,
      label = short .. " " .. (entry.subject or ""),
    })
  end
  state.log_item_by_id = {}
  for _, item in ipairs(state.log_items) do
    if item.type == "commit" then
      state.log_item_by_id[item.id] = item
    end
  end
  state.log_graph_short = build_log_graph_lines("oneline") or {}
  state.log_graph_full = build_log_graph_lines("full") or {}
  state.log_view = config.log_view == "full" and "full" or "oneline"
  state.diff_mode = normalize_diff_mode(config.diff_mode)

  if opts.source and opts.source ~= "" then
    state.source = set_ref(opts.source)
    if not state.source.hash then
      notify("Invalid source ref: " .. opts.source, vim.log.levels.WARN)
      state.source = default_source_ref()
    end
  else
    state.source = default_source_ref()
  end

  if not state.source then
    notify("Unable to determine source commit", vim.log.levels.ERROR)
    return
  end
  state.base_source = clone_ref(state.source)

  local target = opts.target
  local target_upper = target and target:upper() or ""
  if not target or target == "" or target_upper == WORKDIR_ID or target_upper == "WORKTREE" then
    state.target = { kind = "workdir" }
  else
    state.target = set_ref(target)
    if not state.target.hash then
      notify("Invalid target ref: " .. target, vim.log.levels.WARN)
      state.target = { kind = "workdir" }
    end
  end

  open_ui()
end

function M.open_from_cmd(opts)
  local args = opts.fargs or {}
  M.open({ source = args[1], target = args[2] })
end

return M
