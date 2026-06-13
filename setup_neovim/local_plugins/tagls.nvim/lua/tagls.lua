local M = {}
M._VERSION = '0.1.0'

-- Resolve the runtime directory and prefer a full local tagls source tree when present.
local runtime_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
local source_dir = vim.fn.expand('~/software/tagls')
local plugin_dir = vim.fn.isdirectory(source_dir) == 1 and source_dir or runtime_dir

-- Find the tagls binary (prefer release build, then debug, then PATH)
local function find_binary()
  local candidates = {
    plugin_dir .. '/build-release/tagls',
    plugin_dir .. '/build/tagls',
    plugin_dir .. '/build-debug/tagls',
  }
  for _, path in ipairs(candidates) do
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  if vim.fn.executable('tagls') == 1 then
    return 'tagls'
  end
  return nil
end

-- Build tagls from source (release mode). Blocks until done.
local function build_sync()
  local build_script = plugin_dir .. '/build.sh'
  if vim.fn.filereadable(build_script) ~= 1 then
    vim.notify('tagls: build.sh not found at ' .. build_script, vim.log.levels.ERROR)
    return false
  end
  vim.notify('tagls: building (release)...')
  vim.fn.system({ 'sh', build_script })
  if vim.v.shell_error ~= 0 then
    vim.notify('tagls: build failed', vim.log.levels.ERROR)
    return false
  end
  vim.notify('tagls: build complete')
  return true
end

-- Return binary path or nil. Offers to build if missing.
local function get_binary()
  local bin = find_binary()
  if bin then return bin end
  local choice = vim.fn.confirm('tagls binary not found. Build now?', '&Yes\n&No')
  if choice ~= 1 then return nil end
  if not build_sync() then return nil end
  return find_binary()
end

-- Walk up from cwd looking for .tagls.json
local function find_root()
  local dir = vim.fn.getcwd()
  while dir ~= '/' do
    if vim.fn.filereadable(dir .. '/.tagls.json') == 1 then
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return nil
end

-- Find the server log file for this project root.
local function find_server_log(root)
  local cache_dir = vim.fn.expand('~/.cache/tagls')
  if vim.fn.isdirectory(cache_dir) ~= 1 then return nil end
  -- Hash must match the server's hashing; check all logs for one mentioning our root
  -- Simpler: find the most recently modified .log file
  local logs = vim.fn.glob(cache_dir .. '/*.log', false, true)
  local best, best_mtime = nil, 0
  for _, path in ipairs(logs) do
    local mtime = vim.fn.getftime(path)
    if mtime > best_mtime then
      best_mtime = mtime
      best = path
    end
  end
  return best
end

-- Check if server log contains the "indexed" completion line.
local function server_indexed(log_path)
  if not log_path then return false end
  local f = io.open(log_path, 'r')
  if not f then return false end
  local content = f:read('*a')
  f:close()
  return content:find('indexed %d+ tags from %d+ files') ~= nil
end

-- If a server for `root` is already running but started before the current
-- binary was built, stop it so the next start picks up the rebuilt binary.
-- This removes the "I rebuilt but tagls shows old results" footgun: the daemon
-- is long-lived and ensure_server otherwise just reconnects to the stale one.
-- Linux: compare each server process's start time (/proc/<pid>) to bin mtime.
local function restart_if_stale(bin, root)
  -- ERE for pgrep -f: match the daemon's "...server... -d <root>" cmdline.
  -- Escape regex metacharacters in the path (mainly '.').
  local esc_root = vim.fn.escape(root, '.*+?^$()[]{}|\\')
  local pat = 'server.*-d ' .. esc_root
  local pids = vim.fn.systemlist({ 'pgrep', '-f', pat })
  if vim.v.shell_error ~= 0 or #pids == 0 then return end -- none running

  local bin_mtime = vim.fn.getftime(bin)
  local stale = false
  for _, p in ipairs(pids) do
    local pid = tonumber(p)
    if pid then
      local started = tonumber((vim.fn.systemlist({ 'stat', '-c', '%Y', '/proc/' .. pid })[1] or ''))
      if started and bin_mtime > started then stale = true end
    end
  end
  if not stale then return end

  vim.fn.system({ bin, '--stop', '-d', root })
  vim.fn.system({ 'pkill', '-9', '-f', pat })
  vim.fn.system({ 'sleep', '0.3' }) -- let the socket be released
end

-- Ensure server is running and indexed. Shows a loading popup if needed.
-- Calls callback() once the server responds to queries.
local function ensure_server(bin, root, callback)
  -- Pick up a freshly rebuilt binary by retiring any stale daemon first.
  restart_if_stale(bin, root)
  -- Start server daemon
  vim.fn.system({ bin, '--server', '-d', root })

  -- Quick check: already indexed?
  local log_path = find_server_log(root)
  if server_indexed(log_path) then
    callback()
    return
  end

  -- Show loading popup with progress bar
  local bar_width = 30
  local buf = vim.api.nvim_create_buf(false, true)
  local width = bar_width + 16
  local height = 3
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:Normal,FloatBorder:Normal', { win = win })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('cursorline', false, { win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win })

  local function draw_bar(pct)
    local filled = math.floor(pct / 100 * bar_width)
    local empty = bar_width - filled
    local bar = string.rep('█', filled) .. string.rep('░', empty)
    local line = string.format('  %s %3d%%', bar, pct)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', line, '' })
    end
  end

  draw_bar(0)

  local timer = (vim.uv or vim.loop).new_timer()
  local attempts = 0
  local done = false
  timer:start(200, 200, vim.schedule_wrap(function()
    if done then return end
    attempts = attempts + 1
    if not vim.api.nvim_win_is_valid(win) then
      done = true
      timer:stop()
      timer:close()
      return
    end

    -- Animate progress toward 90% while waiting, then jump to 100% when done
    local ready = server_indexed(log_path) or attempts > 150
    if ready then
      draw_bar(100)
      done = true
      timer:stop()
      timer:close()
      -- Show 100% briefly before closing
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        callback()
      end, 500)
    else
      -- Ease toward 90% — fast at first, slowing down
      local pct = math.floor(90 * (1 - 1 / (1 + attempts * 0.3)))
      draw_bar(pct)
    end
  end))
end

-- Write a .tagls.state file with given query (empty string for clean slate).
local function write_state(root, query)
  local state_file = root .. '/.tagls.state'
  local f = io.open(state_file, 'w')
  if f then
    f:write('query=' .. query .. '\n')
    f:write('file_filter=\n')
    f:write('scope_filter=\n')
    f:write('search_field=symbol\n')
    f:write('search_mode=boundary\n')
    f:write('selected=0\n')
    f:write('preview=true\n')
    f:write('mode=normal\n')
    f:close()
  end
end

-- Open tagls TUI in a floating window, leaving the caller's window untouched.
-- init_input: optional string to type into the TUI after it starts.
local function open_float_term(cmd_args, callback, init_input)
  local orig_win = vim.api.nvim_get_current_win()
  local term_buf = vim.api.nvim_create_buf(false, true)
  local width = vim.o.columns - 2
  local height = vim.o.lines - 2
  local float_win = vim.api.nvim_open_win(term_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:Normal,FloatBorder:Normal', { win = float_win })

  local chan = vim.fn.termopen(cmd_args, {
    on_exit = function(_, code)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(float_win) then
          vim.api.nvim_win_close(float_win, true)
        end
        if vim.api.nvim_buf_is_valid(term_buf) then
          vim.api.nvim_buf_delete(term_buf, { force = true })
        end
        if vim.api.nvim_win_is_valid(orig_win) then
          vim.api.nvim_set_current_win(orig_win)
        end
        callback(code)
      end)
    end,
  })

  vim.cmd('startinsert')

  if init_input and init_input ~= '' then
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(term_buf) then
        vim.fn.chansend(chan, init_input)
      end
    end, 150)
  end
end

-- Read tmpfile, parse "file:line:name", jump to location.
local function jump_to_result(tmpfile, root)
  local lines = {}
  local f = io.open(tmpfile, 'r')
  if f then
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()
  end
  os.remove(tmpfile)

  if #lines == 0 then return end

  local output = lines[1]
  local file, lnum = output:match('^(.+):(%d+):')
  if not file or not lnum then return end

  if file:sub(1, 1) ~= '/' then
    file = root .. '/' .. file
  end

  -- Save current position in jumplist before navigating
  vim.cmd("normal! m'")

  local abs_path = vim.fn.fnamemodify(file, ':p')
  local existing = vim.fn.bufnr(abs_path)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    vim.cmd('buffer ' .. existing)
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(file))
  end

  local line_nr = tonumber(lnum)
  if line_nr then
    vim.api.nvim_win_set_cursor(0, { line_nr, 0 })
    vim.cmd('normal! zz')
  end
end

function M.build()
  build_sync()
end

function M.init()
  local bin = get_binary()
  if not bin then return end
  local cwd = vim.fn.getcwd()
  vim.fn.system({ bin, 'init', '-d', cwd })
  vim.notify('tagls: created .tagls.json in ' .. cwd)
end

-- Alt+n: general symbol browser
function M.open()
  local bin = get_binary()
  if not bin then return end
  local root = find_root()
  if not root then
    vim.notify('tagls: no .tagls.json found (run :TaglsInit first)', vim.log.levels.WARN)
    return
  end
  local cur_file = vim.fn.expand('%:p')
  local cur_line = tostring(vim.fn.line('.'))
  ensure_server(bin, root, function()
    local tmpfile = vim.fn.tempname()
    open_float_term({ bin, '-d', root, '--file', cur_file, '--line', cur_line, '--output', tmpfile }, function(code)
      if code ~= 0 then return end
      jump_to_result(tmpfile, root)
    end)
  end)
end

-- Alt+u: references for word under cursor
function M.open_ref()
  local bin = get_binary()
  if not bin then return end
  local root = find_root()
  if not root then
    vim.notify('tagls: no .tagls.json found (run :TaglsInit first)', vim.log.levels.WARN)
    return
  end
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    vim.notify('tagls: no word under cursor', vim.log.levels.WARN)
    return
  end
  local cur_file = vim.fn.expand('%:p')
  local cur_line = tostring(vim.fn.line('.'))
  ensure_server(bin, root, function()
    write_state(root, '')
    local tmpfile = vim.fn.tempname()
    open_float_term({ bin, '-d', root, '--ref', word, '--file', cur_file, '--line', cur_line, '--output', tmpfile }, function(code)
      if code ~= 0 then return end
      jump_to_result(tmpfile, root)
    end)
  end)
end

-- Alt+i: TUI with word under cursor pre-filled
function M.open_at()
  local bin = get_binary()
  if not bin then return end
  local root = find_root()
  if not root then
    vim.notify('tagls: no .tagls.json found (run :TaglsInit first)', vim.log.levels.WARN)
    return
  end
  local word = vim.fn.expand('<cword>')
  if not word or word == '' then
    vim.notify('tagls: no word under cursor', vim.log.levels.WARN)
    return
  end
  local cur_file = vim.fn.expand('%:p')
  local cur_line = tostring(vim.fn.line('.'))
  ensure_server(bin, root, function()
    write_state(root, word)
    local tmpfile = vim.fn.tempname()
    open_float_term({ bin, '-d', root, '--file', cur_file, '--line', cur_line, '--output', tmpfile }, function(code)
      if code ~= 0 then return end
      jump_to_result(tmpfile, root)
    end)
  end)
end

function M.stop()
  local bin = find_binary()
  if not bin then return end
  local root = find_root()
  if not root then
    vim.notify('tagls: no .tagls.json found', vim.log.levels.WARN)
    return
  end
  vim.fn.system({ bin, '--stop', '-d', root })
  vim.notify('tagls: server stopped')
end

-- Stop servers on VimLeave
vim.api.nvim_create_autocmd('VimLeave', {
  callback = function()
    local root = find_root()
    if not root then return end
    local bin = find_binary()
    if not bin then return end
    vim.fn.system({ bin, '--stop', '-d', root })
  end,
})

return M
