-- Legacy: python-based project-tags has been archived under legacy/.
-- Set g:project_tags_legacy_enable = 1 to re-enable explicitly.
if vim.g.project_tags_legacy_enable ~= 1 then
  return {}
end

local M = {}
local uv = vim.loop

local default_config = {
  ctags_bin = nil,
  project_config_files = { ".nvim-tags.lua", ".project-tags.lua" },
  root_markers = {
    ".git",
    ".hg",
    ".svn",
    "compile_commands.json",
    "Makefile",
    "CMakeLists.txt",
    "package.json",
    "pyproject.toml",
    "go.mod",
  },
  ignore = {
    ".git",
    ".ccls",
    ".ccls-cache",
    "node_modules",
    "build",
    "dist",
    "out",
    ".cache",
    ".venv",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".idea",
    ".vscode",
  },
  extra_ctags_args = {},
  search = {
    default_mode = "fuzzy",
    max_results = 2000,
    case_sensitive = false,
  },
  auto_enable = false,
  auto_build = true,
  update_on_save = true,
  statusline = "progress",
  ui = {
    max_results = 2000,
    max_display = 200,
    preview_lines = 8,
    width = 0.55,
    height = 0.6,
    preview_width = 0.45,
  },
  server = {
    enabled = true,
    python = "python3",
    watch = true,
    poll_interval = 5,
    socket_name = "ptags",
    socket_dir = nil,
  },
  log = "warn",
}

local state = {
  root = nil,
  config = nil,
  format = nil,
  running = false,
  pending_full = false,
  job_id = nil,
  tags = {},
  tags_by_file = {},
  file_mtime = {},
  last_build = nil,
  enabled = false,
  enabled_roots = {},
  build_token = nil,
  progress = nil,
  spinner_idx = 1,
  spinner_timer = nil,
  ui = nil,
  debug = {
    enabled = false,
    lines = {},
    buf = nil,
    win = nil,
    max = 500,
  },
  server = {
    job_id = nil,
    socket = nil,
    pipe = nil,
    buf = "",
    seq = 0,
    pending_seq = 0,
    connected = false,
    ready = false,
    last_status = nil,
    connecting = false,
    stderr = {},
    last_error = nil,
  },
}

local ui_refresh
local server_stop
local server_query
local server_index
local server_status_request

local json_decode = vim.json and vim.json.decode or vim.fn.json_decode
local json_encode = vim.json and vim.json.encode or vim.fn.json_encode

local log_levels = {
  trace = vim.log.levels.TRACE,
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

local function should_notify(level)
  local cfg = state.config or default_config
  local setting = cfg.log
  if setting == false then
    return false
  end
  if setting == true or setting == nil then
    return true
  end
  if type(setting) == "number" then
    return level >= setting
  end
  if type(setting) == "string" then
    local threshold = log_levels[setting:lower()]
    if threshold then
      return level >= threshold
    end
  end
  return true
end

local function notify(msg, level)
  local lvl = level or vim.log.levels.INFO
  if not should_notify(lvl) then
    return
  end
  vim.notify(msg, lvl, { title = "ProjectTags" })
end

local function debug_log(msg)
  if not state.debug or not state.debug.enabled then
    return
  end
  local line = os.date("%H:%M:%S") .. " " .. msg
  table.insert(state.debug.lines, line)
  if #state.debug.lines > state.debug.max then
    table.remove(state.debug.lines, 1)
  end
  local buf = state.debug.buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.debug.lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end
end

local function redraw_status()
  vim.schedule(function()
    pcall(vim.cmd, "redrawstatus")
  end)
end

local function stop_spinner()
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
  state.spinner_idx = 1
end

local function start_spinner()
  stop_spinner()
  state.spinner_timer = uv.new_timer()
  state.spinner_timer:start(0, 150, vim.schedule_wrap(function()
    if not state.running then
      stop_spinner()
      return
    end
    state.spinner_idx = state.spinner_idx + 1
    redraw_status()
  end))
end

local function is_enabled(root)
  if not root or root == "" then
    return false
  end
  return state.enabled_roots[root] == true
end

local function set_enabled(root, enabled)
  if not root or root == "" then
    return
  end
  if enabled then
    state.enabled_roots[root] = true
  else
    state.enabled_roots[root] = nil
  end
end

local function reset_index()
  state.tags = {}
  state.tags_by_file = {}
  state.file_mtime = {}
  state.last_build = nil
  state.progress = nil
end

local function stop_job()
  if state.job_id and state.job_id > 0 then
    pcall(vim.fn.jobstop, state.job_id)
  end
  state.job_id = nil
  state.running = false
  state.pending_full = false
  state.build_token = nil
  state.progress = nil
  stop_spinner()
end

local function current_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    path = vim.loop.cwd()
  end
  return path
end

local function append_unique(base, extra)
  local result = vim.deepcopy(base or {})
  local seen = {}
  for _, value in ipairs(result) do
    seen[value] = true
  end
  for _, value in ipairs(extra or {}) do
    if not seen[value] then
      table.insert(result, value)
      seen[value] = true
    end
  end
  return result
end

local function normalize_root(root)
  if not root or root == "" then
    return nil
  end
  root = root:gsub("/+$", "")
  if root == "" then
    root = "/"
  end
  return root
end

local function is_abs(path)
  if not path or path == "" then
    return false
  end
  if path:sub(1, 1) == "/" then
    return true
  end
  if path:match("^%a:[/\\]") then
    return true
  end
  return false
end

local function relpath(root, path)
  if not root or not path or path == "" then
    return path
  end
  root = normalize_root(root)
  if is_abs(path) then
    if root == "/" then
      return path:sub(2)
    end
    if path:sub(1, #root) == root then
      local rel = path:sub(#root + 2)
      if rel == "" then
        return "."
      end
      return rel
    end
  end
  return path
end

local function abs_path(root, path)
  if not root or not path or path == "" then
    return path
  end
  if is_abs(path) then
    return path
  end
  if root == "/" then
    return "/" .. path
  end
  return root .. "/" .. path
end

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  local parts = { ... }
  local path = table.concat(parts, "/")
  path = path:gsub("//+", "/")
  return path
end

local function hash_root(root)
  if vim.fn.exists("*sha256") == 1 then
    return vim.fn.sha256(root)
  end
  return root:gsub("[^%w._-]", "_")
end

local function cache_root()
  return joinpath(vim.fn.stdpath("cache"), "project-tags")
end

local function cache_file(root, name)
  if not root then
    return nil
  end
  return joinpath(cache_root(), hash_root(root), name)
end

local function server_socket_path(root, cfg)
  local server_cfg = cfg.server or default_config.server
  local socket_name = server_cfg.socket_name or "ptags"
  local base = server_cfg.socket_dir
  if not base or base == "" then
    base = vim.fn.stdpath("run")
  end
  if not base or base == "" then
    base = "/tmp"
  end
  if socket_name:sub(1, 1) == "/" then
    return socket_name
  end
  socket_name = socket_name:gsub("%.sock$", "")
  local short_hash = hash_root(root):sub(1, 12)
  return joinpath(base, socket_name .. "-" .. short_hash .. ".sock")
end

local function find_root(start_path, cfg)
  local path = start_path
  if not path or path == "" then
    path = vim.loop.cwd()
  end
  local dir = vim.fs and vim.fs.dirname and vim.fs.dirname(path) or vim.fn.fnamemodify(path, ":p:h")
  if dir == "" then
    dir = vim.loop.cwd()
  end

  local markers = cfg.root_markers or default_config.root_markers
  local root = nil

  if vim.fs and vim.fs.find then
    local found = vim.fs.find(markers, { path = dir, upward = true })
    if found and #found > 0 then
      root = vim.fs.dirname(found[1])
    end
  else
    for _, marker in ipairs(markers) do
      local file = vim.fn.findfile(marker, dir .. ";")
      if file ~= "" then
        root = vim.fn.fnamemodify(file, ":p:h")
        break
      end
      local directory = vim.fn.finddir(marker, dir .. ";")
      if directory ~= "" then
        root = vim.fn.fnamemodify(directory, ":p:h")
        break
      end
    end
  end

  if not root or root == "" then
    root = vim.loop.cwd()
  end
  return normalize_root(root)
end

local function resolve_ctags_bin(cfg)
  if cfg.ctags_bin and cfg.ctags_bin ~= "" then
    return cfg.ctags_bin
  end
  if vim.g.tagbar_ctags_bin and vim.g.tagbar_ctags_bin ~= "" then
    return vim.g.tagbar_ctags_bin
  end
  local path = vim.fn.exepath("ctags")
  if path ~= "" then
    return path
  end
  return "ctags"
end

local function load_project_config(root, cfg)
  local files = cfg.project_config_files or {}
  for _, file in ipairs(files) do
    local path = joinpath(root, file)
    if uv.fs_stat(path) then
      local ok, project_cfg = pcall(dofile, path)
      if ok and type(project_cfg) == "table" then
        return project_cfg
      end
      notify("Failed to load project tags config: " .. path, vim.log.levels.WARN)
    end
  end
  return {}
end

local function merge_config(base, project)
  local cfg = vim.deepcopy(base)
  if type(project) ~= "table" then
    return cfg
  end
  if project.ignore ~= nil then
    cfg.ignore = project.ignore
  end
  if project.extra_ignore ~= nil then
    cfg.ignore = append_unique(cfg.ignore, project.extra_ignore)
  end
  if project.extra_ctags_args ~= nil then
    cfg.extra_ctags_args = append_unique(cfg.extra_ctags_args, project.extra_ctags_args)
  end
  if project.ctags_bin ~= nil then
    cfg.ctags_bin = project.ctags_bin
  end
  if project.root_markers ~= nil then
    cfg.root_markers = project.root_markers
  end
  if project.search ~= nil then
    cfg.search = vim.tbl_deep_extend("force", cfg.search, project.search)
  end
  if project.ui ~= nil then
    cfg.ui = vim.tbl_deep_extend("force", cfg.ui or {}, project.ui)
  end
  if project.server ~= nil then
    cfg.server = vim.tbl_deep_extend("force", cfg.server or {}, project.server)
  end
  if project.statusline ~= nil then
    cfg.statusline = project.statusline
  end
  if project.auto_enable ~= nil then
    cfg.auto_enable = project.auto_enable
  end
  if project.auto_build ~= nil then
    cfg.auto_build = project.auto_build
  end
  if project.update_on_save ~= nil then
    cfg.update_on_save = project.update_on_save
  end
  if project.log ~= nil then
    cfg.log = project.log
  end
  return cfg
end

local function is_ignored_path(path, cfg)
  if not path or path == "" then
    return false
  end
  local ignore = cfg.ignore or {}
  if #ignore == 0 then
    return false
  end
  local segments = vim.split(path, "/", { plain = true })
  for _, segment in ipairs(segments) do
    for _, entry in ipairs(ignore) do
      if segment == entry then
        return true
      end
    end
  end
  return false
end

local function detect_format(bin)
  local result = vim.fn.systemlist({ bin, "--list-formats" })
  if vim.v.shell_error == 0 then
    for _, line in ipairs(result) do
      if line:match("%f[%w]json%f[%W]") then
        return "json"
      end
    end
  end
  return "tags"
end

local function build_ctags_cmd(cfg, format, target)
  local cmd = { cfg.ctags_bin }
  if format == "json" then
    vim.list_extend(cmd, { "--output-format=json", "--fields=+n", "--sort=no", "-f", "-" })
  else
    vim.list_extend(cmd, { "--fields=+n", "--sort=no", "--excmd=number", "-f", "-" })
  end
  for _, entry in ipairs(cfg.ignore or {}) do
    table.insert(cmd, "--exclude=" .. entry)
  end
  for _, entry in ipairs(cfg.extra_ctags_args or {}) do
    table.insert(cmd, entry)
  end
  if target then
    table.insert(cmd, target)
  else
    table.insert(cmd, "-R")
    table.insert(cmd, ".")
  end
  return cmd
end

local function parse_json_line(line)
  local ok, obj = pcall(json_decode, line)
  if not ok or type(obj) ~= "table" then
    return nil
  end
  if obj._type and obj._type ~= "tag" then
    return nil
  end
  local file = obj.path or obj.file or obj.filename
  if not obj.name or not file then
    return nil
  end
  if file:sub(1, 2) == "./" then
    file = file:sub(3)
  end
  return {
    name = obj.name,
    file = file,
    line = tonumber(obj.line) or nil,
    kind = obj.kind or obj.kind_long or "",
    scope = obj.scope or "",
    signature = obj.signature or "",
  }
end

local function parse_tags_line(line)
  if line == "" or line:sub(1, 1) == "!" then
    return nil
  end
  local parts = vim.split(line, "\t", { plain = true })
  if #parts < 3 then
    return nil
  end
  local name = parts[1]
  local file = parts[2]
  local excmd = parts[3]
  if file:sub(1, 2) == "./" then
    file = file:sub(3)
  end
  local line_nr = tonumber(excmd:match("^(%d+)"))
  local kind = ""
  local scope = ""
  for index = 4, #parts do
    local field = parts[index]
    if #field == 1 then
      kind = field
    else
      local key, value = field:match("^([^:]+):(.+)$")
      if key == "kind" then
        kind = value
      elseif key == "line" then
        local number = tonumber(value)
        if number then
          line_nr = number
        end
      elseif key == "scope" or key == "class" then
        scope = value
      end
    end
  end
  return {
    name = name,
    file = file,
    line = line_nr,
    kind = kind,
    scope = scope,
    signature = "",
  }
end

local function run_ctags(cmd, cwd, format, on_done, progress)
  local tags = {}
  local parser = format == "json" and parse_json_line or parse_tags_line

  local function handle_line(line)
    if not line or line == "" then
      return
    end
    local tag = parser(line)
    if tag and tag.name and tag.file then
      if progress then
        progress.tags = progress.tags + 1
        if progress.files then
          if not progress.seen[tag.file] then
            progress.seen[tag.file] = true
            progress.files = progress.files + 1
          end
        end
      end
      if not tag.line or tag.line < 1 then
        tag.line = 1
      end
      table.insert(tags, tag)
    end
  end

  local job_id = vim.fn.jobstart(cmd, {
    cwd = cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        handle_line(line)
      end
    end,
    on_exit = function(_, code)
      if on_done then
        on_done(code, tags)
      end
    end,
  })

  if job_id <= 0 then
    notify("Failed to start ctags job", vim.log.levels.ERROR)
    return nil
  end

  return job_id
end

local function group_by_file(tags)
  local by_file = {}
  for _, tag in ipairs(tags) do
    local file = tag.file
    if file and file ~= "" then
      by_file[file] = by_file[file] or {}
      table.insert(by_file[file], tag)
    end
  end
  return by_file
end

local function rebuild_tag_list()
  local list = {}
  for _, file_tags in pairs(state.tags_by_file) do
    for _, tag in ipairs(file_tags) do
      table.insert(list, tag)
    end
  end
  state.tags = list
end

local function update_mtime(rel, abs)
  local stat = uv.fs_stat(abs)
  if stat and stat.mtime then
    state.file_mtime[rel] = stat.mtime.sec
  end
end

local function should_update_file(rel, abs)
  local stat = uv.fs_stat(abs)
  if not stat or not stat.mtime then
    return false
  end
  local previous = state.file_mtime[rel]
  if not previous then
    state.file_mtime[rel] = stat.mtime.sec
    return false
  end
  if stat.mtime.sec ~= previous then
    state.file_mtime[rel] = stat.mtime.sec
    return true
  end
  return false
end

local function ensure_state(path)
  local base = M.config or default_config
  local root = find_root(path, base)
  if not root then
    return nil
  end
  if state.root ~= root then
    if state.running then
      stop_job()
    end
    if state.server and state.server.connected then
      server_stop()
    end
    local project_cfg = load_project_config(root, base)
    local merged = merge_config(base, project_cfg)
    merged.ctags_bin = resolve_ctags_bin(merged)
    state.root = root
    state.config = merged
    state.format = nil
    state.running = false
    state.pending_full = false
    state.job_id = nil
    state.tags = {}
    state.tags_by_file = {}
    state.file_mtime = {}
    state.last_build = nil
    state.build_token = nil
    state.progress = nil
    stop_spinner()
    state.enabled = is_enabled(root)
    state.server.socket = server_socket_path(root, merged)
    state.server.buf = ""
    state.server.seq = 0
    state.server.pending_seq = 0
    state.server.connected = false
    state.server.ready = false
    state.server.connecting = false
    redraw_status()
  end
  return state.root
end

local function tag_text(tag)
  if tag._search_text then
    return tag._search_text
  end
  local parts = { tag.name or "" }
  if tag.kind and tag.kind ~= "" then
    table.insert(parts, tag.kind)
  end
  if tag.scope and tag.scope ~= "" then
    table.insert(parts, tag.scope)
  end
  if tag.signature and tag.signature ~= "" then
    table.insert(parts, tag.signature)
  end
  if tag.file and tag.file ~= "" then
    table.insert(parts, tag.file)
  end
  tag._search_text = table.concat(parts, " ")
  return tag._search_text
end

local function sanitize_field(value)
  if value == nil then
    return ""
  end
  return tostring(value):gsub("\t", " ")
end

local function cache_line(tag)
  local name = sanitize_field(tag.name)
  local file = sanitize_field(tag.file)
  local line = sanitize_field(tag.line or 1)
  local kind = sanitize_field(tag.kind)
  local scope = sanitize_field(tag.scope)
  local signature = sanitize_field(tag.signature)
  return table.concat({ name, file, line, kind, scope, signature }, "\t")
end

local function build_matcher(mode, query, case_sensitive)
  if mode == "regex" then
    local pattern = query
    if not case_sensitive and not pattern:find("\\c") and not pattern:find("\\C") then
      pattern = "\\c" .. pattern
    end
    local ok, regex = pcall(vim.regex, pattern)
    if not ok then
      return nil, "Invalid regex: " .. query
    end
    return function(text)
      return regex:match_str(text) ~= nil
    end
  end

  local query_text = query
  if not case_sensitive then
    query_text = query_text:lower()
  end

  if mode == "literal" then
    return function(text)
      local hay = case_sensitive and text or text:lower()
      return hay:find(query_text, 1, true) ~= nil
    end
  end

  local tokens = {}
  for word in query_text:gmatch("%S+") do
    table.insert(tokens, word)
  end
  return function(text)
    local hay = case_sensitive and text or text:lower()
    for _, token in ipairs(tokens) do
      if token ~= "" and not hay:find(token, 1, true) then
        return false
      end
    end
    return true
  end
end

local function open_quickfix(tags)
  local items = {}
  for _, tag in ipairs(tags) do
    local file = abs_path(state.root, tag.file)
    local text = tag.name or ""
    if tag.kind and tag.kind ~= "" then
      text = text .. " [" .. tag.kind .. "]"
    end
    if tag.scope and tag.scope ~= "" then
      text = text .. " " .. tag.scope
    end
    table.insert(items, {
      filename = file,
      lnum = tag.line or 1,
      text = text,
    })
  end
  vim.fn.setqflist({}, " ", { title = "Project Tags", items = items })
  vim.cmd("copen")
end

function M.build()
  local path = current_path()
  local root = ensure_state(path)
  if not root then
    return
  end
  if not is_enabled(root) then
    notify("Project tags disabled. Run :PTagsEnable", vim.log.levels.WARN)
    return
  end
  local cfg = state.config or M.config or default_config

  local server_cfg = cfg.server or default_config.server
  if server_cfg and server_cfg.enabled then
    if state.server.last_status == nil then
      state.server.last_status = {}
    end
    state.server.last_status.indexing = true
    server_index(cfg)
    return
  end

  if state.running then
    state.pending_full = true
    return
  end

  if vim.fn.executable(cfg.ctags_bin) ~= 1 then
    notify("ctags not executable: " .. cfg.ctags_bin, vim.log.levels.ERROR)
    return
  end

  state.running = true
  state.progress = { tags = 0, files = 0, seen = {} }
  start_spinner()
  redraw_status()
  local format = state.format or detect_format(cfg.ctags_bin)
  state.format = format
  local cmd = build_ctags_cmd(cfg, format, nil)

  notify("Indexing tags for " .. root .. " ...")

  local token = {}
  state.build_token = token
  state.job_id = run_ctags(cmd, root, format, function(code, tags)
    if state.build_token ~= token then
      return
    end
    state.running = false
    state.job_id = nil
    state.build_token = nil
    state.progress = nil
    stop_spinner()
    redraw_status()

    if code ~= 0 then
      notify("ctags failed (exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
      return
    end

    state.tags_by_file = group_by_file(tags)
    rebuild_tag_list()
    state.last_build = os.time()

    notify("Tags indexed: " .. tostring(#state.tags), vim.log.levels.INFO)

    if state.ui and state.ui.active then
      local cfg_now = state.config or M.config or default_config
      ui_refresh(state.ui, cfg_now, true)
    end

    if state.pending_full then
      state.pending_full = false
      M.build()
    end
  end, state.progress)

  if not state.job_id then
    state.running = false
    state.build_token = nil
    state.progress = nil
    stop_spinner()
    redraw_status()
  end
end

function M.update_file(path)
  local root = state.root
  if not root then
    return
  end
  if not is_enabled(root) then
    return
  end
  local cfg = state.config or M.config or default_config
  local server_cfg = cfg.server or default_config.server
  if server_cfg and server_cfg.enabled then
    return
  end
  if state.running then
    return
  end

  local rel = relpath(root, path)
  local abs = abs_path(root, rel)
  if is_ignored_path(abs, cfg) then
    return
  end

  if vim.fn.executable(cfg.ctags_bin) ~= 1 then
    notify("ctags not executable: " .. cfg.ctags_bin, vim.log.levels.ERROR)
    return
  end

  local format = state.format or detect_format(cfg.ctags_bin)
  state.format = format
  local cmd = build_ctags_cmd(cfg, format, rel)

  run_ctags(cmd, root, format, function(code, tags)
    if code ~= 0 then
      notify("ctags failed for " .. rel, vim.log.levels.ERROR)
      return
    end
    state.tags_by_file[rel] = tags
    rebuild_tag_list()
    update_mtime(rel, abs)

    if state.ui and state.ui.active then
      local cfg_now = state.config or M.config or default_config
      ui_refresh(state.ui, cfg_now, true)
    end
  end)
end

function M.enable(opts)
  local path = (opts and opts.path) or current_path()
  local root = ensure_state(path)
  if not root then
    return
  end
  set_enabled(root, true)
  state.enabled = true
  redraw_status()
  if not opts or opts.build ~= false then
    M.build()
  end
  if not opts or opts.notify ~= false then
    notify("Project tags enabled for " .. root)
  end
end

function M.disable(opts)
  local path = (opts and opts.path) or current_path()
  local root = ensure_state(path)
  if not root then
    return
  end
  set_enabled(root, false)
  if state.root == root then
    stop_job()
    if state.server and state.server.connected then
      server_stop()
    end
    reset_index()
    state.enabled = false
  end
  redraw_status()
  if not opts or opts.notify ~= false then
    notify("Project tags disabled for " .. root)
  end
end

function M.toggle(opts)
  local path = (opts and opts.path) or current_path()
  local root = ensure_state(path)
  if not root then
    return
  end
  if is_enabled(root) then
    M.disable({ path = path })
  else
    M.enable({ path = path })
  end
end

function M.search(opts)
  M.open_ui(opts or {})
end

local function ui_state()
  if not state.ui then
    state.ui = {
      active = false,
      input_buf = nil,
      list_buf = nil,
      preview_buf = nil,
      input_win = nil,
      list_win = nil,
      preview_win = nil,
      origin_win = nil,
      mode = "fuzzy",
      query = "",
      kind_filter = nil,
      matches = {},
      total_matches = 0,
      kinds = {},
      available_kinds = {},
      header_lines = 2,
      ns = vim.api.nvim_create_namespace("ProjectTagsUI"),
      debounce_timer = nil,
      limit_hit = false,
      pending = false,
      last_query = nil,
      last_mode = nil,
      last_filter_key = nil,
      scanned = 0,
    }
  end
  return state.ui
end

local function ui_cleanup_timer(ui)
  if ui.debounce_timer then
    ui.debounce_timer:stop()
    ui.debounce_timer:close()
    ui.debounce_timer = nil
  end
end

local function ui_close()
  local ui = state.ui
  if not ui or not ui.active then
    return
  end
  ui_cleanup_timer(ui)
  if ui.input_win and vim.api.nvim_win_is_valid(ui.input_win) then
    vim.api.nvim_win_close(ui.input_win, true)
  end
  if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
    vim.api.nvim_win_close(ui.list_win, true)
  end
  if ui.preview_win and vim.api.nvim_win_is_valid(ui.preview_win) then
    vim.api.nvim_win_close(ui.preview_win, true)
  end
  if ui.input_buf and vim.api.nvim_buf_is_valid(ui.input_buf) then
    vim.api.nvim_buf_delete(ui.input_buf, { force = true })
  end
  if ui.list_buf and vim.api.nvim_buf_is_valid(ui.list_buf) then
    vim.api.nvim_buf_delete(ui.list_buf, { force = true })
  end
  if ui.preview_buf and vim.api.nvim_buf_is_valid(ui.preview_buf) then
    vim.api.nvim_buf_delete(ui.preview_buf, { force = true })
  end
  ui.active = false
  ui.input_buf = nil
  ui.list_buf = nil
  ui.preview_buf = nil
  ui.input_win = nil
  ui.list_win = nil
  ui.preview_win = nil
  ui.matches = {}
  ui.kinds = {}
  ui.available_kinds = {}
end

local function ui_get_query(ui)
  if not ui.input_buf or not vim.api.nvim_buf_is_valid(ui.input_buf) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(ui.input_buf, 0, -1, false)
  local line = ""
  for i = #lines, 1, -1 do
    local candidate = lines[i] or ""
    if candidate ~= "" and not candidate:match("^%s*$") then
      line = candidate
      break
    end
  end
  if line == "" then
    line = lines[1] or ""
  end
  return line
end

local function ui_kind_key(tag)
  if not tag.kind or tag.kind == "" then
    return "?"
  end
  return tostring(tag.kind)
end

local function ui_format_kind_line(kinds, filter)
  local keys = {}
  for key in pairs(kinds) do
    table.insert(keys, key)
  end
  table.sort(keys)
  if #keys == 0 then
    return "Kinds: (none)"
  end
  local parts = { "Kinds:" }
  for _, key in ipairs(keys) do
    local enabled = filter == nil or filter[key]
    local suffix = enabled and "+" or "-"
    table.insert(parts, string.format("%s%s%d", key, suffix, kinds[key]))
  end
  return table.concat(parts, " ")
end

local function ui_format_line(tag)
  local name = tag.name or ""
  local kind = tag.kind or ""
  local scope = tag.scope or ""
  local file = tag.file or ""
  local line = tostring(tag.line or 1)
  local parts = { name }
  if kind ~= "" then
    table.insert(parts, "[" .. kind .. "]")
  end
  if scope ~= "" then
    table.insert(parts, scope)
  end
  table.insert(parts, file .. ":" .. line)
  return table.concat(parts, " ")
end

local function ui_render(ui, cfg)
  if not ui.list_buf or not vim.api.nvim_buf_is_valid(ui.list_buf) then
    return
  end

  local current_line = nil
  if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
    current_line = vim.api.nvim_win_get_cursor(ui.list_win)[1]
  end

  local width = vim.api.nvim_win_get_width(ui.list_win)
  local total_text = ui.limit_hit and (tostring(ui.total_matches) .. "+") or tostring(ui.total_matches)
  local total_tags = #state.tags
  if cfg.server and cfg.server.enabled and state.server and state.server.last_status and state.server.last_status.tag_count then
    total_tags = state.server.last_status.tag_count
  end
  local header = string.format("Project Tags  mode:%s  matches:%d/%s  scanned:%d/%d", ui.mode, #ui.matches,
    total_text, ui.scanned, total_tags)
  local server_indexing = state.server and state.server.last_status and state.server.last_status.indexing
  if state.running or server_indexing then
    header = header .. "  indexing..."
  elseif ui.pending then
    header = header .. "  searching..."
  end
  if ui.query ~= "" then
    header = header .. "  query:" .. ui.query
  else
    header = header .. "  query:(type to search)"
  end
  if #header > width then
    header = header:sub(1, math.max(1, width - 1))
  end

  local kinds_line = ui_format_kind_line(ui.kinds, ui.kind_filter)
  if #kinds_line > width then
    kinds_line = kinds_line:sub(1, math.max(1, width - 1))
  end

  local lines = { header, kinds_line }
  local max_display = cfg.ui.max_display or 200
  local shown = 0
  for _, tag in ipairs(ui.matches) do
    table.insert(lines, ui_format_line(tag))
    shown = shown + 1
    if shown >= max_display then
      break
    end
  end

  if shown == 0 then
    if state.running then
      table.insert(lines, "-- indexing tags --")
    else
      table.insert(lines, "-- no matches --")
    end
  end

  vim.api.nvim_buf_set_option(ui.list_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui.list_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui.list_buf, "modifiable", false)

  local target_line = ui.header_lines + 1
  if shown == 0 then
    target_line = math.min(#lines, ui.header_lines + 1)
  end
  if current_line then
    local max_line = math.max(ui.header_lines + 1, ui.header_lines + shown)
    target_line = math.max(ui.header_lines + 1, math.min(current_line, max_line))
  end
  if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
    vim.api.nvim_win_set_cursor(ui.list_win, { target_line, 0 })
  end
end

local function ui_selected_tag(ui)
  if not ui.list_win or not vim.api.nvim_win_is_valid(ui.list_win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(ui.list_win)
  local index = cursor[1] - ui.header_lines
  if index < 1 or index > #ui.matches then
    return nil
  end
  return ui.matches[index]
end

local function ui_update_preview(ui, cfg)
  local tag = ui_selected_tag(ui)
  if not tag or not ui.preview_buf or not vim.api.nvim_buf_is_valid(ui.preview_buf) then
    return
  end

  local file = abs_path(state.root, tag.file)
  local lnum = tonumber(tag.line) or 1
  local context = cfg.ui.preview_lines or 8

  local file_buf = vim.fn.bufadd(file)
  vim.fn.bufload(file_buf)
  local total = vim.api.nvim_buf_line_count(file_buf)
  local start = math.max(lnum - context - 1, 0)
  local finish = math.min(lnum + context, total)
  local lines = vim.api.nvim_buf_get_lines(file_buf, start, finish, false)

  local numbered = {}
  for i, text in ipairs(lines) do
    local line_no = start + i
    numbered[i] = string.format("%6d | %s", line_no, text)
  end

  vim.api.nvim_buf_set_option(ui.preview_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui.preview_buf, 0, -1, false, numbered)
  vim.api.nvim_buf_set_option(ui.preview_buf, "modifiable", false)
  vim.api.nvim_buf_clear_namespace(ui.preview_buf, ui.ns, 0, -1)

  local target = lnum - start
  if target >= 1 and target <= #numbered then
    vim.api.nvim_buf_add_highlight(ui.preview_buf, ui.ns, "CursorLine", target - 1, 0, -1)
    local name = tag.name or ""
    if name ~= "" then
      local line_text = numbered[target]
      local col = line_text:find(name, 1, true)
      if col then
        vim.api.nvim_buf_add_highlight(ui.preview_buf, ui.ns, "Search", target - 1, col - 1, col - 1 + #name)
      end
    end
  end
end

local function ui_start_search(ui, cfg)
  ui.pending = false
  ui.limit_hit = false
  ui.total_matches = 0
  ui.kinds = {}
  ui.available_kinds = {}
  ui.scanned = 0

  local query = ui.query
  if query == "" then
    ui.matches = {}
    ui_render(ui, cfg)
    ui_update_preview(ui, cfg)
    return
  end

  ui.pending = true
  ui_render(ui, cfg)

  local server_cfg = cfg.server or default_config.server
  if server_cfg and server_cfg.enabled then
    if server_query(ui, cfg) then
      return
    end
    ui.pending = false
    ui_render(ui, cfg)
    return
  end

  if #state.tags == 0 then
    if state.running then
      ui.pending = true
      ui_render(ui, cfg)
      return
    end
    ui.matches = {}
    ui_render(ui, cfg)
    return
  end

  local matcher, err = build_matcher(ui.mode, query, cfg.search.case_sensitive)
  if not matcher then
    notify(err, vim.log.levels.ERROR)
    ui.matches = {}
    ui_render(ui, cfg)
    ui_update_preview(ui, cfg)
    return
  end

  local max_results = cfg.ui.max_results or cfg.search.max_results or 2000
  local matches = {}
  local kinds = {}
  local total = 0
  for _, tag in ipairs(state.tags) do
    if matcher(tag_text(tag)) then
      total = total + 1
      local kind_key = ui_kind_key(tag)
      kinds[kind_key] = (kinds[kind_key] or 0) + 1
      if not ui.kind_filter or ui.kind_filter[kind_key] then
        if #matches < max_results then
          table.insert(matches, tag)
        else
          ui.limit_hit = true
        end
      end
    end
  end

  ui.pending = false
  ui.total_matches = total
  ui.kinds = kinds
  ui.available_kinds = vim.tbl_keys(kinds)
  table.sort(ui.available_kinds)
  ui.matches = matches
  ui.scanned = #state.tags
  ui_render(ui, cfg)
  ui_update_preview(ui, cfg)
end

local function ui_filter_key(filter)
  if not filter then
    return ""
  end
  local keys = {}
  for key, enabled in pairs(filter) do
    if enabled then
      table.insert(keys, key)
    end
  end
  table.sort(keys)
  return table.concat(keys, ",")
end

ui_refresh = function(ui, cfg, force)
  local query = ui_get_query(ui)
  local filter_key = ui_filter_key(ui.kind_filter)
  if not force and query == ui.last_query and ui.mode == ui.last_mode and filter_key == ui.last_filter_key and not ui.pending then
    return
  end
  if state.debug and state.debug.enabled then
    local raw = vim.api.nvim_buf_get_lines(ui.input_buf, 0, -1, false)
    debug_log(string.format("refresh query='%s' last='%s' mode=%s raw=%s", query, tostring(ui.last_query), ui.mode, vim.inspect(raw)))
  end
  ui.last_query = query
  ui.last_mode = ui.mode
  ui.last_filter_key = filter_key
  ui.query = query
  ui_start_search(ui, cfg)
end

local function ui_schedule_refresh(ui, cfg)
  ui_cleanup_timer(ui)
  ui.debounce_timer = uv.new_timer()
  ui.debounce_timer:start(80, 0, vim.schedule_wrap(function()
    if not ui.active then
      return
    end
    ui_refresh(ui, cfg)
  end))
end

local function ui_open_selected(ui)
  local tag = ui_selected_tag(ui)
  if not tag then
    return
  end
  local origin = ui.origin_win
  ui_close()
  if origin and vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  local file = abs_path(state.root, tag.file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(tag.line) or 1, 0 })
end

local function ui_toggle_kind(ui, cfg)
  if #ui.available_kinds == 0 then
    return
  end
  local input = vim.fn.input("Toggle kind (* for all): ")
  if input == "" then
    return
  end
  if input == "*" then
    ui.kind_filter = nil
    ui_refresh(ui, cfg)
    return
  end

  local targets = {}
  for _, kind in ipairs(ui.available_kinds) do
    if kind == input or kind:sub(1, 1) == input then
      table.insert(targets, kind)
    end
  end
  if #targets == 0 then
    return
  end

  ui.kind_filter = ui.kind_filter or {}
  for _, kind in ipairs(targets) do
    if ui.kind_filter[kind] then
      ui.kind_filter[kind] = nil
    else
      ui.kind_filter[kind] = true
    end
  end
  if next(ui.kind_filter) == nil then
    ui.kind_filter = nil
  end
  ui_refresh(ui, cfg)
end

local function ui_set_mode(ui, cfg, mode)
  ui.mode = mode
  ui_refresh(ui, cfg)
end

function M.open_ui(opts)
  local cfg = state.config or M.config or default_config
  local ui = ui_state()
  if ui.active then
    if opts.mode then
      ui.mode = opts.mode
    end
    if opts.query and ui.input_buf and vim.api.nvim_buf_is_valid(ui.input_buf) then
      vim.api.nvim_buf_set_lines(ui.input_buf, 0, -1, false, { opts.query })
    end
    if state.debug and state.debug.enabled then
      debug_log("open_ui reuse")
    end
    ui_refresh(ui, cfg)
    return
  end

  local path = current_path()
  local root = ensure_state(path)
  if not root then
    return
  end

  if not is_enabled(root) then
    M.enable({ notify = false })
  end

  if #state.tags == 0 and cfg.auto_build and not state.running then
    M.build()
  end

  local server_cfg = cfg.server or default_config.server
  if server_cfg and server_cfg.enabled then
    server_status_request(cfg)
  end

  ui.origin_win = vim.api.nvim_get_current_win()
  ui.mode = opts.mode or cfg.search.default_mode or "fuzzy"
  ui.query = opts.query or ""

  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.max(60, math.floor(columns * (cfg.ui.width or 0.55)))
  local height = math.max(10, math.floor(lines * (cfg.ui.height or 0.6)))
  height = math.min(height, math.max(8, lines - 2))
  local preview_width = math.max(40, math.floor(columns * (cfg.ui.preview_width or 0.45)))
  if width + preview_width + 2 > columns then
    preview_width = math.max(20, math.floor(columns * 0.35))
    width = math.max(40, columns - preview_width - 2)
  end
  local row = math.max(0, math.floor((lines - height) / 2) - 1)
  local col = math.max(0, math.floor((columns - width - preview_width - 2) / 2))

  ui.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(ui.input_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(ui.input_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(ui.input_buf, "swapfile", false)
  vim.api.nvim_buf_set_option(ui.input_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui.input_buf, 0, -1, false, { "" })

  ui.list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(ui.list_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(ui.list_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(ui.list_buf, "swapfile", false)
  vim.api.nvim_buf_set_option(ui.list_buf, "modifiable", false)

  ui.preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(ui.preview_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(ui.preview_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(ui.preview_buf, "swapfile", false)
  vim.api.nvim_buf_set_option(ui.preview_buf, "modifiable", false)

  ui.input_win = vim.api.nvim_open_win(ui.input_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    border = "none",
  })

  ui.list_win = vim.api.nvim_open_win(ui.list_buf, false, {
    relative = "editor",
    row = row + 1,
    col = col,
    width = width,
    height = height - 1,
    style = "minimal",
    border = "single",
  })

  ui.preview_win = vim.api.nvim_open_win(ui.preview_buf, false, {
    relative = "editor",
    row = row,
    col = col + width + 2,
    width = preview_width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(ui.list_win, "cursorline", true)
  vim.api.nvim_win_set_option(ui.list_win, "wrap", false)
  vim.api.nvim_win_set_option(ui.preview_win, "wrap", false)

  ui.active = true
  if state.debug and state.debug.enabled then
    debug_log("open_ui new")
  end

  if ui.query ~= "" then
    vim.api.nvim_buf_set_lines(ui.input_buf, 0, -1, false, { ui.query })
  end

  local group = vim.api.nvim_create_augroup("ProjectTagsUI", { clear = false })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged", "TextChangedP" }, {
    group = group,
    buffer = ui.input_buf,
    callback = function()
      ui_schedule_refresh(ui, cfg)
    end,
  })

  vim.api.nvim_buf_attach(ui.input_buf, false, {
    on_lines = function()
      if ui.active then
        ui_schedule_refresh(ui, cfg)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = ui.list_buf,
    callback = function()
      ui_update_preview(ui, cfg)
    end,
  })

  vim.keymap.set("i", "<CR>", function()
    ui_open_selected(ui)
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-n>", function()
    if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
      vim.api.nvim_win_set_cursor(ui.list_win, {
        math.min(vim.api.nvim_win_get_cursor(ui.list_win)[1] + 1, vim.api.nvim_buf_line_count(ui.list_buf)),
        0,
      })
    end
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<Down>", function()
    if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
      vim.api.nvim_win_set_cursor(ui.list_win, {
        math.min(vim.api.nvim_win_get_cursor(ui.list_win)[1] + 1, vim.api.nvim_buf_line_count(ui.list_buf)),
        0,
      })
    end
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-p>", function()
    if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
      vim.api.nvim_win_set_cursor(ui.list_win, {
        math.max(vim.api.nvim_win_get_cursor(ui.list_win)[1] - 1, ui.header_lines + 1),
        0,
      })
    end
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<Up>", function()
    if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
      vim.api.nvim_win_set_cursor(ui.list_win, {
        math.max(vim.api.nvim_win_get_cursor(ui.list_win)[1] - 1, ui.header_lines + 1),
        0,
      })
    end
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<Esc>", function()
    ui_close()
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-c>", function()
    ui_close()
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<Tab>", function()
    if ui.list_win and vim.api.nvim_win_is_valid(ui.list_win) then
      vim.api.nvim_set_current_win(ui.list_win)
    end
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-t>", function()
    ui_toggle_kind(ui, cfg)
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-f>", function()
    ui_set_mode(ui, cfg, "fuzzy")
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-r>", function()
    ui_set_mode(ui, cfg, "regex")
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("i", "<C-l>", function()
    ui_set_mode(ui, cfg, "literal")
  end, { buffer = ui.input_buf, silent = true })

  vim.keymap.set("n", "q", function()
    ui_close()
  end, { buffer = ui.list_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    ui_close()
  end, { buffer = ui.list_buf, silent = true })
  vim.keymap.set("n", "<CR>", function()
    ui_open_selected(ui)
  end, { buffer = ui.list_buf, silent = true })
  vim.keymap.set("n", "t", function()
    ui_toggle_kind(ui, cfg)
  end, { buffer = ui.list_buf, silent = true })
  vim.keymap.set("n", "i", function()
    if ui.input_win and vim.api.nvim_win_is_valid(ui.input_win) then
      vim.api.nvim_set_current_win(ui.input_win)
      vim.cmd("startinsert")
    end
  end, { buffer = ui.list_buf, silent = true })

  vim.keymap.set("n", "q", function()
    ui_close()
  end, { buffer = ui.input_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    ui_close()
  end, { buffer = ui.input_buf, silent = true })

  vim.keymap.set("n", "q", function()
    ui_close()
  end, { buffer = ui.preview_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    ui_close()
  end, { buffer = ui.preview_buf, silent = true })

  ui_refresh(ui, cfg)
  vim.cmd("startinsert")
end

local function status_lines()
  local root = state.root or "(none)"
  local format = state.format or "unknown"
  local status = state.running and "running" or "idle"
  local count = tostring(#state.tags)
  local enabled = is_enabled(state.root) and "enabled" or "disabled"
  local last_build = state.last_build and os.date("%Y-%m-%d %H:%M:%S", state.last_build) or "(never)"
  local socket = (state.server and state.server.socket) or "(none)"
  local server_state = (state.server and state.server.connected) and "connected" or "disconnected"
  local server_status = state.server and state.server.last_status or {}
  local server_tags = server_status.tag_count or 0
  local server_files = server_status.file_count or 0
  local server_indexing = server_status.indexing and "yes" or "no"
  local server_ready = server_status.ready and "yes" or "no"
  local server_error = state.server.last_error or "(none)"
  local socket_exists = (state.server.socket and uv.fs_stat(state.server.socket)) and "yes" or "no"
  local lines = {
    "Project Tags Status",
    "",
    "Root: " .. root,
    "Enabled: " .. enabled,
    "Local tags: " .. count,
    "Index: " .. status,
    "Format: " .. format,
    "Last build: " .. last_build,
    "Server: " .. server_state,
    "Socket: " .. socket,
    "Socket exists: " .. socket_exists,
    "Server tags: " .. tostring(server_tags),
    "Server files: " .. tostring(server_files),
    "Server indexing: " .. server_indexing,
    "Server ready: " .. server_ready,
    "Server last error: " .. server_error,
  }
  local roots = {}
  for key in pairs(state.enabled_roots) do
    table.insert(roots, key)
  end
  table.sort(roots)
  if #roots > 0 then
    table.insert(lines, "")
    table.insert(lines, "Enabled roots:")
    for _, key in ipairs(roots) do
      table.insert(lines, "  - " .. key)
    end
  end
  return lines
end

local function open_status_window(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "projecttags-status")

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, math.min(#lines + 2, math.max(8, math.floor(vim.o.lines * 0.3))))
  vim.api.nvim_win_set_option(win, "wrap", false)

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
end

local function open_debug_window()
  state.debug.enabled = true
  if state.debug.buf and vim.api.nvim_buf_is_valid(state.debug.buf) then
    if state.debug.win and vim.api.nvim_win_is_valid(state.debug.win) then
      vim.api.nvim_set_current_win(state.debug.win)
      return
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.debug.lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "projecttags-debug")

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, math.min(#state.debug.lines + 2, math.max(8, math.floor(vim.o.lines * 0.3))))
  vim.api.nvim_win_set_option(win, "wrap", false)

  state.debug.buf = buf
  state.debug.win = win

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
end

function M.status()
  local cfg = state.config or M.config or default_config
  if server_status_request(cfg) then
    vim.defer_fn(function()
      open_status_window(status_lines())
    end, 100)
  else
    open_status_window(status_lines())
  end
end

local function server_script_path()
  return joinpath(vim.fn.stdpath("config"), "pack", "local", "start", "project-tags.nvim", "lua", "project_tags",
    "ptags_server.py")
end

local function server_start(cfg)
  local server_cfg = cfg.server or default_config.server
  if not (server_cfg and server_cfg.enabled) then
    return false
  end
  local socket = state.server.socket
  if not socket or socket == "" then
    return false
  end

  local dir = vim.fs and vim.fs.dirname and vim.fs.dirname(socket) or vim.fn.fnamemodify(socket, ":h")
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end

  if uv.fs_stat(socket) then
    pcall(uv.fs_unlink, socket)
  end

  local script = server_script_path()
  if not uv.fs_stat(script) then
    notify("Server script not found: " .. script, vim.log.levels.ERROR)
    return false
  end

  local cmd = {
    server_cfg.python or "python3",
    script,
    "--root",
    state.root,
    "--socket",
    socket,
    "--ctags",
    state.config.ctags_bin,
    "--poll",
    tostring(server_cfg.poll_interval or 5),
  }

  if server_cfg.watch == false then
    table.insert(cmd, "--no-watch")
  end

  for _, entry in ipairs(state.config.ignore or {}) do
    table.insert(cmd, "--ignore")
    table.insert(cmd, entry)
  end

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          if state.debug and state.debug.enabled then
            debug_log("server stdout: " .. line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(state.server.stderr, line)
          if #state.server.stderr > 50 then
            table.remove(state.server.stderr, 1)
          end
          state.server.last_error = line
          if state.debug and state.debug.enabled then
            debug_log("server stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function()
      state.server.job_id = nil
      state.server.connected = false
      if state.debug and state.debug.enabled then
        debug_log("server exit")
      end
    end,
  })
  if job_id <= 0 then
    notify("Failed to start server", vim.log.levels.ERROR)
    return false
  end
  state.server.job_id = job_id
  if state.debug and state.debug.enabled then
    debug_log("server start: " .. socket)
  end
  return true
end

server_stop = function()
  local s = state.server
  if s.pipe then
    pcall(s.pipe.read_stop, s.pipe)
    pcall(s.pipe.close, s.pipe)
  end
  s.pipe = nil
  s.connected = false
  s.connecting = false
  s.buf = ""
  s.last_error = nil
  s.stderr = {}
  if s.job_id and s.job_id > 0 then
    pcall(vim.fn.jobstop, s.job_id)
  end
  s.job_id = nil
  if s.socket and uv.fs_stat(s.socket) then
    pcall(uv.fs_unlink, s.socket)
  end
end

local function server_connect(cfg)
  if state.server.connected then
    return true
  end
  if state.server.connecting then
    return false
  end
  local socket = state.server.socket
  if not socket or not uv.fs_stat(socket) then
    return false
  end
  state.server.connecting = true
  local pipe = uv.new_pipe(false)
  pipe:connect(socket, function(err)
    if err then
      state.server.connected = false
      state.server.connecting = false
      pipe:close()
      if state.debug and state.debug.enabled then
        debug_log("server connect failed: " .. tostring(err))
      end
      return
    end
    state.server.connected = true
    state.server.connecting = false
    state.server.pipe = pipe
    if state.debug and state.debug.enabled then
      debug_log("server connected")
    end
    pipe:read_start(function(read_err, chunk)
      if read_err then
        state.server.connected = false
        return
      end
      if not chunk then
        return
      end
      local text = state.server.buf .. chunk
      local parts = vim.split(text, "\n", { plain = true })
      state.server.buf = table.remove(parts) or ""
      for _, line in ipairs(parts) do
        if line ~= "" then
          local ok, resp = pcall(json_decode, line)
          if ok and type(resp) == "table" then
            if resp.cmd == "search" and resp.seq == state.server.pending_seq and state.ui and state.ui.active then
              if state.server.last_status == nil then
                state.server.last_status = {}
              end
              if resp.indexing ~= nil then
                state.server.last_status.indexing = resp.indexing
              end
              local ui = state.ui
              local cfg_now = state.config or M.config or default_config
              if resp.ready == false then
                ui.pending = true
                ui.total_matches = 0
                ui.kinds = {}
                ui.limit_hit = false
                ui.scanned = 0
                ui.available_kinds = {}
                ui.matches = {}
                vim.defer_fn(function()
                  if state.ui and state.ui.active then
                    server_query(state.ui, cfg_now)
                  end
                end, 500)
              else
                ui.pending = false
                ui.total_matches = resp.total or 0
                ui.kinds = resp.kinds or {}
                ui.limit_hit = resp.limit_hit or false
                ui.scanned = resp.scanned or 0
                ui.available_kinds = vim.tbl_keys(ui.kinds)
                table.sort(ui.available_kinds)
                ui.matches = {}
                for _, item in ipairs(resp.matches or {}) do
                  table.insert(ui.matches, {
                    name = item[1] or "",
                    file = item[2] or "",
                    line = tonumber(item[3]) or 1,
                    kind = item[4] or "",
                    scope = item[5] or "",
                    signature = item[6] or "",
                  })
                end
              end
              if state.debug and state.debug.enabled then
                debug_log(string.format("server resp seq=%d matches=%d total=%d", resp.seq, #ui.matches, ui.total_matches))
              end
              ui_render(ui, cfg_now)
              ui_update_preview(ui, cfg_now)
            elseif resp.cmd == "status" then
              state.server.last_status = resp.status or {}
            end
          else
            if state.debug and state.debug.enabled then
              debug_log("server parse error: " .. line)
            end
          end
        end
      end
    end)
  end)
  return true
end

local function server_ensure(cfg)
  if state.server.connected then
    return true
  end
  if not server_connect(cfg) then
    if not state.server.connecting then
      server_start(cfg)
      vim.defer_fn(function()
        server_connect(cfg)
      end, 200)
    end
    return false
  end
  return state.server.connected
end

server_query = function(ui, cfg)
  if not server_ensure(cfg) then
    vim.defer_fn(function()
      if state.ui and state.ui.active then
        server_query(ui, cfg)
      end
    end, 300)
    return true
  end
  local s = state.server
  s.seq = s.seq + 1
  s.pending_seq = s.seq
  local kinds = nil
  if ui.kind_filter then
    kinds = {}
    for key, enabled in pairs(ui.kind_filter) do
      if enabled then
        table.insert(kinds, key)
      end
    end
  end
  local req = {
    cmd = "search",
    seq = s.seq,
    query = ui.query,
    mode = ui.mode,
    max = cfg.ui.max_results or cfg.search.max_results or 2000,
    kinds = kinds,
    case_sensitive = cfg.search.case_sensitive or false,
  }
  local payload = json_encode(req)
  if s.pipe then
    s.pipe:write(payload .. "\n")
  end
  if state.debug and state.debug.enabled then
    debug_log(string.format("server send seq=%d query='%s' mode=%s", s.seq, ui.query, ui.mode))
  end
  return true
end

server_index = function(cfg)
  if not server_ensure(cfg) then
    vim.defer_fn(function()
      server_index(cfg)
    end, 300)
    return true
  end
  local req = { cmd = "index" }
  local payload = json_encode(req)
  if state.server.pipe then
    state.server.pipe:write(payload .. "\n")
  end
  return true
end

server_status_request = function(cfg)
  if not server_ensure(cfg) then
    return false
  end
  local s = state.server
  s.seq = s.seq + 1
  local req = { cmd = "status", seq = s.seq }
  local payload = json_encode(req)
  if s.pipe then
    s.pipe:write(payload .. "\n")
  end
  return true
end

function M.self_test()
  local cfg = state.config or M.config or default_config
  local tags = {
    { name = "alpha", file = "a.c", line = 1, kind = "f" },
    { name = "alpine", file = "a.c", line = 2, kind = "f" },
    { name = "beta", file = "b.c", line = 3, kind = "v" },
  }

  local function run(query, pool)
    local matcher, err = build_matcher("fuzzy", query, cfg.search.case_sensitive)
    if not matcher then
      return { error = err, matches = {} }
    end
    local matches = {}
    for _, tag in ipairs(pool) do
      if matcher(tag_text(tag)) then
        table.insert(matches, tag)
      end
    end
    return { matches = matches }
  end

  local r1 = run("a", tags)
  local r2 = run("al", r1.matches or {})
  local r3 = run("alp", r2.matches or {})
  local r4 = run("alx", r3.matches or {})
  local ok = #r1.matches >= 2 and #r2.matches >= 2 and #r3.matches >= 2 and #r4.matches == 0

  local lines = {
    "Project Tags Self-Test",
    "",
    ok and "PASS" or "FAIL",
    "",
    "query='a'   matches=" .. tostring(#r1.matches),
    "query='al'  matches=" .. tostring(#r2.matches),
    "query='alp' matches=" .. tostring(#r3.matches),
    "query='alx' matches=" .. tostring(#r4.matches),
  }
  if r1.error or r2.error or r3.error or r4.error then
    table.insert(lines, "")
    table.insert(lines, "Errors:")
    if r1.error then table.insert(lines, "  a: " .. r1.error) end
    if r2.error then table.insert(lines, "  al: " .. r2.error) end
    if r3.error then table.insert(lines, "  alp: " .. r3.error) end
    if r4.error then table.insert(lines, "  alx: " .. r4.error) end
  end

  open_status_window(lines)
end

function M.probe(prefix)
  local path = current_path()
  local root = ensure_state(path)
  if not root then
    return
  end
  if #state.tags == 0 then
    open_status_window({ "Project Tags Probe", "", "No tags loaded." })
    return
  end

  local cfg = state.config or M.config or default_config
  local function count(query)
    local matcher, err = build_matcher("fuzzy", query, cfg.search.case_sensitive)
    if not matcher then
      return 0, err
    end
    local total = 0
    for _, tag in ipairs(state.tags) do
      if matcher(tag_text(tag)) then
        total = total + 1
      end
    end
    return total, nil
  end

  local q1 = prefix
  local q2 = nil
  local picked = nil

  if not q1 or q1 == "" then
    for _, tag in ipairs(state.tags) do
      local name = tag.name or ""
      if #name >= 2 then
        picked = name
        q1 = name:sub(1, 1)
        q2 = name:sub(1, 2)
        break
      end
    end
  else
    if #q1 >= 2 then
      q2 = q1
      q1 = q1:sub(1, 1)
    else
      q2 = q1 .. q1
    end
  end

  local c1, e1 = count(q1)
  local c2, e2 = count(q2)

  local lines = {
    "Project Tags Probe",
    "",
    "Root: " .. root,
    "Picked tag: " .. (picked or "(none)"),
    "Query 1: " .. (q1 or "(nil)") .. "  matches: " .. tostring(c1),
    "Query 2: " .. (q2 or "(nil)") .. "  matches: " .. tostring(c2),
  }
  if e1 or e2 then
    table.insert(lines, "")
    table.insert(lines, "Errors:")
    if e1 then table.insert(lines, "  q1: " .. e1) end
    if e2 then table.insert(lines, "  q2: " .. e2) end
  end
  open_status_window(lines)
end

function M.statusline()
  local cfg = state.config or M.config or default_config
  local mode = cfg.statusline or "progress"
  if mode == "off" then
    return ""
  end
  if not state.root or not is_enabled(state.root) then
    return ""
  end
  local server_indexing = state.server and state.server.last_status and state.server.last_status.indexing
  if state.running or server_indexing then
    local spinner = { "|", "/", "-", "\\" }
    local idx = ((state.spinner_idx - 1) % #spinner) + 1
    local suffix = ""
    if state.progress and state.progress.files and state.progress.files > 0 then
      suffix = " " .. tostring(state.progress.files) .. "f"
    end
    return " PT" .. spinner[idx] .. suffix
  end
  if mode == "enabled" then
    return " PT"
  end
  return ""
end

function M.on_buf_enter(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end
  if path:match("^%w+://") then
    return
  end

  local root = ensure_state(path)
  if not root then
    return
  end

  local cfg = state.config or M.config or default_config
  local enabled = is_enabled(root)
  if cfg.auto_enable and not enabled then
    set_enabled(root, true)
    state.enabled = true
    enabled = true
    redraw_status()
  end

  local server_cfg = cfg.server or default_config.server
  if enabled and server_cfg and server_cfg.enabled then
    if cfg.auto_build then
      local ready = state.server.last_status and state.server.last_status.ready
      if not ready then
        server_index(cfg)
      else
        server_ensure(cfg)
      end
    else
      server_ensure(cfg)
    end
    return
  end

  if enabled and cfg.auto_build and not state.running and #state.tags == 0 then
    M.build()
  end

  if enabled then
    local rel = relpath(root, path)
    local abs = abs_path(root, rel)
    if state.tags_by_file[rel] then
      if not state.file_mtime[rel] then
        M.update_file(path)
      elseif should_update_file(rel, abs) then
        M.update_file(path)
      end
    end
  end
end

function M.on_buf_write(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end
  if path:match("^%w+://") then
    return
  end

  local root = ensure_state(path)
  if not root then
    return
  end

  local cfg = state.config or M.config or default_config
  if not cfg.update_on_save then
    return
  end

  local server_cfg = cfg.server or default_config.server
  if server_cfg and server_cfg.enabled then
    return
  end

  if is_enabled(root) then
    M.update_file(path)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
  M.config.ctags_bin = resolve_ctags_bin(M.config)

  _G.ProjectTagsStatusline = function()
    return require("project_tags").statusline()
  end

  vim.api.nvim_create_user_command("PTagsBuild", function()
    M.enable({ build = true, notify = false })
  end, {})

  vim.api.nvim_create_user_command("PTagsEnable", function()
    M.enable()
  end, {})

  vim.api.nvim_create_user_command("PTagsDisable", function()
    M.disable()
  end, {})

  vim.api.nvim_create_user_command("PTagsToggle", function()
    M.toggle()
  end, {})

  vim.api.nvim_create_user_command("PTagsSearch", function(command_opts)
    M.search({ mode = "fuzzy", query = table.concat(command_opts.fargs, " ") })
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("PTagsSearchRegex", function(command_opts)
    M.search({ mode = "regex", query = table.concat(command_opts.fargs, " ") })
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("PTagsSearchLiteral", function(command_opts)
    M.search({ mode = "literal", query = table.concat(command_opts.fargs, " ") })
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("PTagsStatus", function()
    M.status()
  end, {})

  vim.api.nvim_create_user_command("PTagsSelfTest", function()
    M.self_test()
  end, {})

  vim.api.nvim_create_user_command("PTagsDebug", function()
    open_debug_window()
  end, {})

  vim.api.nvim_create_user_command("PTagsProbe", function(command_opts)
    local arg = command_opts.fargs[1] or ""
    M.probe(arg)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("PTagsTui", function()
    local cfg = state.config or M.config or default_config
    local root = ensure_state(current_path())
    if not root then
      return
    end
    if not is_enabled(root) then
      M.enable({ notify = false })
    end
    server_ensure(cfg)
    local socket = state.server.socket
    local script = joinpath(vim.fn.stdpath("config"), "pack", "local", "start", "project-tags.nvim", "lua", "project_tags",
      "ptags_tui.py")
    vim.cmd("botright split")
    vim.fn.termopen({ (cfg.server and cfg.server.python) or "python3", script, "--socket", socket })
  end, {})

  local group = vim.api.nvim_create_augroup("ProjectTags", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = group,
    callback = function(args)
      M.on_buf_enter(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      M.on_buf_write(args.buf)
    end,
  })
end

return M
