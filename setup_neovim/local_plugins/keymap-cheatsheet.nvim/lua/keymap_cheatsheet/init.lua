local M = {}
M.opts = {
  -- Optional user-provided descriptions without rewriting mappings.
  -- Structure: { n = { ["<leader>ff"] = "Find files" }, i = { ["jj"] = "Exit insert mode" }, ... }
  desc = {},
}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strw(s)
  return vim.fn.strdisplaywidth(tostring(s or ""))
end

local function normalize_path(p)
  if not p or p == "" then
    return ""
  end
  p = vim.fn.expand(p)
  p = vim.fn.fnamemodify(p, ":p")
  return p
end

local function last_set_path(last_set_line)
  local l = trim(last_set_line or "")
  if l == "" then
    return nil
  end
  local path = l:match("^Last set from (.+) line %d+")
  if not path then
    path = l:match("^Last set from (.+)$")
  end
  return path
end

local function parse_last_set(last_set_line)
  local l = trim(last_set_line or "")
  if l == "" then
    return nil, nil
  end
  local path, lnum = l:match("^Last set from (.+) line (%d+)")
  if path and lnum then
    return path, tonumber(lnum)
  end
  path = l:match("^Last set from (.+)$")
  if path then
    return path, nil
  end
  return nil, nil
end

local function extract_lhs_from_map_line(map_line)
  local line = trim(map_line or "")
  if line == "" then
    return nil
  end
  -- Many map listings start with a mode prefix (e.g. "n  ..."); tolerate both forms.
  line = line:gsub("^[nivxsoct]%s+", "")
  return line:match("^(%S+)")
end

local function get_user_desc(lhs, mode)
  -- mode is single-letter ('n', 'i', ...)
  local t = (M.opts and M.opts.desc and M.opts.desc[mode]) or nil
  if type(t) == "table" and t[lhs] and t[lhs] ~= "" then
    return tostring(t[lhs])
  end
  local g = vim.g.keymap_cheatsheet_desc
  if type(g) == "table" and type(g[mode]) == "table" and g[mode][lhs] and g[mode][lhs] ~= "" then
    return tostring(g[mode][lhs])
  end
  return nil
end

local function describe_map(lhs, mode)
  local user_desc = get_user_desc(lhs, mode)
  if user_desc and user_desc ~= "" then
    return user_desc
  end
  local ok, info = pcall(vim.fn.maparg, lhs, mode, false, true)
  if ok and type(info) == "table" then
    local desc = trim(info.desc or "")
    if desc ~= "" then
      return desc
    end
    if info.callback and (info.rhs == nil or info.rhs == "") then
      return "<Lua callback>"
    end
    local rhs = trim(info.rhs or "")
    if rhs ~= "" then
      return rhs
    end
  end
  return ""
end

local function format_source(last_set_line, config_dir_p)
  local path, lnum = parse_last_set(last_set_line)
  if not path then
    return ""
  end
  local pnorm = normalize_path(path)
  local p = pnorm
  if config_dir_p ~= "" and pnorm:sub(1, #config_dir_p) == config_dir_p then
    p = pnorm:sub(#config_dir_p + 1)
    p = p:gsub("^/", "")
  end
  if lnum then
    return p .. ":" .. tostring(lnum)
  end
  return p
end

local function collect_verbose_maps_for(cmd, title, config_dir_p)
  local ok, out = pcall(vim.fn.execute, "silent verbose " .. cmd)
  if not ok or not out or out == "" then
    return {}
  end

  local raw = vim.split(out, "\n", { plain = true })
  local res = { title = title, mode = cmd:sub(1, 1), entries = {} }
  local mode = cmd:sub(1, 1)

  local i = 1
  while i <= #raw do
    local map_line = raw[i] or ""
    local next_line = raw[i + 1] or ""

    local p = last_set_path(next_line)
    if trim(map_line) ~= "" and p then
      local pnorm = normalize_path(p)
      if pnorm:sub(1, #config_dir_p) == config_dir_p then
        local lhs = extract_lhs_from_map_line(map_line) or "?"
        local desc = describe_map(lhs, mode)
        if desc == "" then
          -- Fallback: show the raw listing line (still better than blank).
          desc = trim(map_line)
        end
        local source = format_source(next_line, config_dir_p)
        table.insert(res.entries, { key = lhs, desc = desc, source = source })
        i = i + 2
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  return res
end

local function take_prefix_by_width(s, width)
  s = tostring(s or "")
  if width <= 0 or s == "" then
    return "", s
  end
  local lo, hi = 0, vim.fn.strchars(s)
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    local part = vim.fn.strcharpart(s, 0, mid)
    if strw(part) <= width then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local head = vim.fn.strcharpart(s, 0, lo)
  local tail = vim.fn.strcharpart(s, lo)
  return head, tail
end

local function wrap_text(s, width)
  s = tostring(s or "")
  if width <= 0 then
    return { s }
  end
  s = trim(s)
  if s == "" then
    return { "" }
  end

  local out = {}
  local words = vim.split(s, "%s+", { trimempty = true })
  local line = ""
  for _, w in ipairs(words) do
    if line == "" then
      if strw(w) <= width then
        line = w
      else
        local rest = w
        while rest ~= "" do
          local head
          head, rest = take_prefix_by_width(rest, width)
          table.insert(out, head)
        end
        line = ""
      end
    else
      local candidate = line .. " " .. w
      if strw(candidate) <= width then
        line = candidate
      else
        table.insert(out, line)
        line = ""
        if strw(w) <= width then
          line = w
        else
          local rest = w
          while rest ~= "" do
            local head
            head, rest = take_prefix_by_width(rest, width)
            table.insert(out, head)
          end
        end
      end
    end
  end
  if line ~= "" then
    table.insert(out, line)
  end
  return out
end

local function pad_right(s, width)
  s = tostring(s or "")
  local w = strw(s)
  if w >= width then
    return s
  end
  return s .. string.rep(" ", width - w)
end

local function build_lines(preferred_width)
  local config_dir_p = normalize_path(vim.fn.stdpath("config"))

  local lines = {
    "## Keymap Cheatsheet",
    "",
    "Showing mappings whose **Last set from** is under:",
    "",
    "- `" .. config_dir_p .. "`",
    "",
    "Search: `/your-term`",
    "",
    "Close: `q` / `<Esc>`",
    "",
  }

  local sections = {
    collect_verbose_maps_for("nmap", "Normal mode", config_dir_p),
    collect_verbose_maps_for("imap", "Insert mode", config_dir_p),
    collect_verbose_maps_for("vmap", "Visual mode (vmap)", config_dir_p),
    collect_verbose_maps_for("xmap", "Visual mode (xmap)", config_dir_p),
    collect_verbose_maps_for("smap", "Select mode", config_dir_p),
    collect_verbose_maps_for("omap", "Operator-pending mode", config_dir_p),
    collect_verbose_maps_for("cmap", "Command-line mode", config_dir_p),
    collect_verbose_maps_for("tmap", "Terminal mode", config_dir_p),
  }

  local total_entries = 0
  for _, sec in ipairs(sections) do
    total_entries = total_entries + (sec.entries and #sec.entries or 0)
  end

  if total_entries == 0 then
    table.insert(lines, "### (No mappings found)")
    table.insert(lines, "")
    table.insert(lines, "Either you have no custom mappings, or they were set from outside your config directory.")
    table.insert(lines, "")
    return lines, math.min(preferred_width or 80, math.floor(vim.o.columns * 0.90))
  end

  -- Compute column widths (fixed-width aligned table).
  local target_w = preferred_width or math.floor(vim.o.columns * 0.90)
  target_w = math.min(target_w, math.floor(vim.o.columns * 0.95))
  target_w = math.max(target_w, 60)

  local key_w, src_w = 3, 6
  for _, sec in ipairs(sections) do
    for _, e in ipairs(sec.entries or {}) do
      key_w = math.max(key_w, math.min(strw(e.key), 30))
      src_w = math.max(src_w, math.min(strw(e.source), 50))
    end
  end
  key_w = math.min(key_w, 30)
  src_w = math.min(src_w, 50)

  -- Two spaces between columns.
  local sep = "  "
  local desc_w = target_w - key_w - src_w - (2 * #sep)
  if desc_w < 20 then
    -- If the screen is narrow, shrink source column first.
    local need = 20 - desc_w
    src_w = math.max(20, src_w - need)
    desc_w = target_w - key_w - src_w - (2 * #sep)
  end
  desc_w = math.max(desc_w, 20)

  local header = pad_right("Key", key_w) .. sep .. pad_right("Description", desc_w) .. sep .. pad_right("Source", src_w)
  local rule = string.rep("-", key_w) .. sep .. string.rep("-", desc_w) .. sep .. string.rep("-", src_w)

  for _, sec in ipairs(sections) do
    if sec.entries and #sec.entries > 0 then
      table.insert(lines, "### " .. sec.title)
      table.insert(lines, "")
      table.insert(lines, header)
      table.insert(lines, rule)

      for _, e in ipairs(sec.entries) do
        local key_lines = wrap_text(e.key, key_w)
        local desc_lines = wrap_text(e.desc, desc_w)
        local src_lines = wrap_text(e.source, src_w)
        local rows = math.max(#key_lines, #desc_lines, #src_lines)
        for r = 1, rows do
          local k = pad_right(key_lines[r] or "", key_w)
          local d = pad_right(desc_lines[r] or "", desc_w)
          local s = pad_right(src_lines[r] or "", src_w)
          table.insert(lines, k .. sep .. d .. sep .. s)
        end
      end
      table.insert(lines, "")
    end
  end

  return lines, target_w
end

local function open_float(lines, preferred_width)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "text"

  local cols = vim.o.columns
  local total_lines = vim.o.lines
  local width = math.min(math.max((preferred_width or 70) + 4, 60), math.floor(cols * 0.95))
  local height = math.min(math.max(#lines, 12), math.floor(total_lines * 0.80))

  local row = math.max(0, math.floor((total_lines - height) / 2 - 1))
  local col = math.max(0, math.floor((cols - width) / 2))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  })

  -- We wrap ourselves to preserve alignment; keep normal search (/term).
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })
end

function M.open()
  local preferred_width = math.floor(vim.o.columns * 0.90)
  local lines, used_width = build_lines(preferred_width)
  open_float(lines, used_width)
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts or {}, opts or {})
end

return M

