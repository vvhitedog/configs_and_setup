local M = {}

local WORKDIR_ID = "WORKDIR"

local config = {
  log_max = 200,
  log_view = "oneline",
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
  log_full_lines = {},
  log_view = "oneline",
  file_items = {},
  buf = { files = nil, log = nil },
  win = { files = nil, log = nil },
  ns = vim.api.nvim_create_namespace("gitdiff"),
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

local function short_hash(hash)
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

local function build_log_entries()
  local entries = {}
  local output, err = git_cmd({
    "--no-pager",
    "log",
    "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s",
    "--date=iso",
    "--max-count",
    tostring(config.log_max),
  })
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

local function build_log_full_lines()
  local output, err = git_cmd({
    "--no-pager",
    "log",
    "--pretty=medium",
    "--date=iso",
    "--max-count",
    tostring(config.log_max),
  })
  if not output then
    notify(table.concat(err or {}, "\n"), vim.log.levels.ERROR)
    return nil
  end
  return output
end

local function is_workdir_target()
  return state.target and state.target.kind == "workdir"
end

local function ref_label(ref)
  if not ref then
    return "?"
  end
  if ref.kind == "workdir" then
    return WORKDIR_ID
  end
  return ref.short or ref.spec or ref.hash or "?"
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
  state.log_line_map = {}

  if state.log_view == "full" then
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
      lines[line_idx] = ""
      line_idx = line_idx + 1
    end

    local current_item = nil
    for _, raw in ipairs(state.log_full_lines) do
      local commit_id = raw:match("^commit%s+(%x+)")
      if commit_id then
        local item = state.log_item_by_id[commit_id]
        if item then
          current_item = item
          local marker, kind = marker_for_item(item)
          lines[line_idx] = string.format("%-2s %s", marker, raw)
          state.log_line_map[line_idx] = item
          if kind then
            marker_lines[line_idx] = kind
          end
        else
          lines[line_idx] = "   " .. raw
        end
      else
        lines[line_idx] = "   " .. raw
        if current_item then
          state.log_line_map[line_idx] = current_item
        end
      end
      line_idx = line_idx + 1
    end
  else
    for i, item in ipairs(state.log_items) do
      local marker, kind = marker_for_item(item)
      lines[i] = string.format("%-2s %s", marker, item.label)
      state.log_line_map[i] = item
      if kind then
        marker_lines[i] = kind
      end
    end
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
  if not state.source or not state.source.spec then
    return {}
  end
  local args = { "diff", "--name-status" }
  if is_workdir_target() then
    table.insert(args, state.source.spec)
  else
    table.insert(args, state.source.spec .. ".." .. state.target.spec)
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
  if #state.file_items == 0 then
    lines = { "No changes" }
  else
    for i, item in ipairs(state.file_items) do
      lines[i] = item.display
    end
  end
  set_buf_lines(state.buf.files, lines)
end

local function winbar_text(title, detail)
  return string.format("=== GitDiff %s ===%%=%%<%s", title, detail or "")
end

local function update_winbars()
  local source_label = ref_label(state.source)
  local target_label = ref_label(state.target)
  if state.win.files and vim.api.nvim_win_is_valid(state.win.files) then
    vim.wo[state.win.files].winbar = winbar_text(
      "FILES",
      string.format("source=%s  target=%s", source_label, target_label)
    )
  end
  if state.win.log and vim.api.nvim_win_is_valid(state.win.log) then
    local view = state.log_view == "full" and "FULL" or "ONELINE"
    vim.wo[state.win.log].winbar = winbar_text(
      "LOG " .. view,
      string.format("source=%s  target=%s", source_label, target_label)
    )
    vim.wo[state.win.log].wrap = state.log_view == "full"
    vim.wo[state.win.log].linebreak = state.log_view == "full"
    vim.wo[state.win.log].breakindent = state.log_view == "full"
  end
end

local function set_ref(ref)
  local hash = resolve_ref(ref)
  local short = hash and short_hash(hash)
  return {
    kind = "commit",
    spec = ref,
    hash = hash,
    short = short or ref,
  }
end

local function default_source_from_log()
  local first_commit = state.log_items[2]
  if first_commit then
    return {
      kind = "commit",
      spec = first_commit.id,
      hash = first_commit.id,
      short = first_commit.short,
    }
  end
  return nil
end

local function refresh()
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
    local full_lines = build_log_full_lines()
    if full_lines then
      state.log_full_lines = full_lines
    end
  end
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
  return state.file_items[line]
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
  if not state.source or not state.source.spec then
    notify("No source commit set", vim.log.levels.ERROR)
    return
  end

  local source_label = state.source.short or state.source.spec
  local target_label = is_workdir_target() and WORKDIR_ID
    or (state.target and (state.target.short or state.target.spec))
  local source_title = "SOURCE " .. source_label
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
    "SOURCE " .. source_label,
    source_path or "(missing)"
  )

  local left_lines = {}
  if source_path then
    local lines, err = git_show_lines(state.source.spec, source_path)
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
  state.log_full_lines = build_log_full_lines() or {}
  state.log_view = config.log_view == "full" and "full" or "oneline"

  if opts.source and opts.source ~= "" then
    state.source = set_ref(opts.source)
    if not state.source.hash then
      notify("Invalid source ref: " .. opts.source, vim.log.levels.WARN)
      state.source = default_source_from_log()
    end
  else
    state.source = default_source_from_log()
  end

  if not state.source then
    notify("Unable to determine source commit", vim.log.levels.ERROR)
    return
  end

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
