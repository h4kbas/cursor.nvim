local CursorManager = {}
CursorManager.__index = CursorManager

function CursorManager.new(opts)
  local self = setmetatable({}, CursorManager)

  opts = opts or {}

  -- ACP configuration (defaults to Cursor CLI `agent acp`)
  self.acp = opts.acp or {}
  if self.acp.enabled == nil then
    self.acp.enabled = true
  end
  self.acp.command = self.acp.command or 'agent'
  self.acp.args = self.acp.args or { 'acp' }
  self.acp.auth_method = self.acp.auth_method or 'cursor_login'

  -- Legacy model option is kept for compatibility but unused in ACP mode
  self.model = opts.model or 'auto'

  -- JSON-RPC / ACP state
  self.proc_job_id = nil
  self.next_id = 1
  self.pending = {}
  self.session_id = nil
  self.initialized = false
  self.authenticated = false
  self.current_prompt_id = nil
  self._active_request = nil
  self._stdout_buffer = {}
  self.terminals = {}

  return self
end

function CursorManager:_ensure_acp_process()
  if self.proc_job_id and self.proc_job_id > 0 then
    return true
  end

  if not self:_check_cursor_cli() then
    vim.notify('Cursor ACP CLI (`agent`) not found. Install Cursor and ensure `agent` is in PATH.', vim.log.levels.ERROR)
    return false
  end

  local cmd = { self.acp.command }
  for _, arg in ipairs(self.acp.args or {}) do
    table.insert(cmd, arg)
  end

  self.proc_job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    stdin = 'pipe',
    on_stdout = function(_, data, _)
      if not data or #data == 0 then
        return
      end

      for _, line in ipairs(data) do
        if line and line ~= '' then
          local ok, msg = pcall(vim.json.decode, line)
          if ok and msg then
            self:_handle_message(msg)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        local msg = table.concat(data, '\n')
        if msg and msg ~= '' then
          vim.notify('Cursor ACP stderr: ' .. msg, vim.log.levels.WARN)
        end
      end
    end,
    on_exit = function(_, _exit_code, _)
      self.proc_job_id = nil
      self.initialized = false
      self.authenticated = false
      self.session_id = nil
      self.current_prompt_id = nil
      self.pending = {}
      self._active_request = nil
    end,
  })

  if self.proc_job_id <= 0 then
    vim.notify('Failed to start Cursor ACP CLI. Make sure `agent` is installed and in PATH.', vim.log.levels.ERROR)
    self.proc_job_id = nil
    return false
  end

  return true
end

function CursorManager:_send_json(obj)
  if not (self.proc_job_id and self.proc_job_id > 0) then
    return
  end
  local ok, encoded = pcall(vim.json.encode, obj)
  if not ok or not encoded then
    return
  end
  vim.fn.chansend(self.proc_job_id, encoded .. '\n')
end

function CursorManager:_send_request(method, params, on_result)
  if not self:_ensure_acp_process() then
    return nil
  end

  local id = self.next_id
  self.next_id = self.next_id + 1

  if on_result then
    self.pending[id] = on_result
  end

  self:_send_json({
    jsonrpc = '2.0',
    id = id,
    method = method,
    params = params or {},
  })

  return id
end

function CursorManager:_send_response(id, result)
  if not id then
    return
  end
  self:_send_json({
    jsonrpc = '2.0',
    id = id,
    result = result,
  })
end

function CursorManager:_handle_message(msg)
  if msg.id and (msg.result or msg.error) then
    local cb = self.pending[msg.id]
    self.pending[msg.id] = nil
    if cb then
      cb(msg.result, msg.error)
    end
    return
  end

  if msg.method == 'session/update' and msg.params and msg.params.update then
    self:_handle_session_update(msg.params.update)
    return
  end

  if msg.method == 'session/request_permission' then
    self:_handle_request_permission(msg.id, msg.params)
    return
  end

  if msg.method == 'fs/read_text_file' or msg.method == 'fs/readTextFile' then
    self:_handle_fs_read_text_file(msg.id, msg.params)
    return
  end

  if msg.method == 'fs/write_text_file' or msg.method == 'fs/writeTextFile' then
    self:_handle_fs_write_text_file(msg.id, msg.params)
    return
  end

  if msg.method == 'terminal/create' then
    self:_handle_terminal_create(msg.id, msg.params)
    return
  end

  if msg.method == 'terminal/output' then
    self:_handle_terminal_output(msg.id, msg.params)
    return
  end

  if msg.method == 'terminal/wait_for_exit' then
    self:_handle_terminal_wait_for_exit(msg.id, msg.params)
    return
  end

  if msg.method == 'terminal/kill' then
    self:_handle_terminal_kill(msg.id, msg.params)
    return
  end

  if msg.method == 'terminal/release' then
    self:_handle_terminal_release(msg.id, msg.params)
    return
  end

  -- Ignore other notifications and Cursor extension methods for now
end

function CursorManager:_handle_fs_read_text_file(id, params)
  if not id then
    return
  end

  local path = params and params.path or nil
  local line = params and params.line or nil
  local limit = params and params.limit or nil

  if not path or path == '' then
    self:_send_response(id, { content = '' })
    return
  end

  local content_lines = nil

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if buf_path == path then
        content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        break
      end
    end
  end

  if not content_lines then
    if vim.fn.filereadable(path) ~= 1 then
      self:_send_response(id, { content = '' })
      return
    end
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or not lines then
      self:_send_response(id, { content = '' })
      return
    end
    content_lines = lines
  end

  local start_idx = 1
  if type(line) == 'number' and line > 0 then
    start_idx = line
  end

  local end_idx = #content_lines
  if type(limit) == 'number' and limit > 0 then
    end_idx = math.min(end_idx, start_idx + limit - 1)
  end

  local slice = {}
  for i = start_idx, end_idx do
    if content_lines[i] == nil then
      break
    end
    table.insert(slice, content_lines[i])
  end

  local content = table.concat(slice, '\n')
  if content ~= '' then
    content = content .. '\n'
  end

  self:_send_response(id, { content = content })
end

function CursorManager:_handle_fs_write_text_file(id, params)
  if not id then
    return
  end

  local path = params and params.path or nil
  local content = params and params.content or ''

  if not path or path == '' then
    self:_send_response(id, vim.NIL)
    return
  end

  local lines = {}
  for line in tostring(content):gmatch('[^\r\n]+') do
    table.insert(lines, line)
  end
  if #lines == 0 then
    lines = { '' }
  end

  pcall(function()
    vim.fn.writefile(lines, path)
  end)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if buf_path == path then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        break
      end
    end
  end

  self:_send_response(id, vim.NIL)
end

function CursorManager:_handle_terminal_create(id, params)
  if not id then
    return
  end

  local command = params and params.command or nil
  local args = params and params.args or {}
  local cwd = params and params.cwd or nil
  local env_param = params and params.env or {}
  local output_byte_limit = params and params.outputByteLimit or 1048576

  if not command or command == '' then
    self:_send_response(id, { terminalId = nil })
    return
  end

  local cmd = { command }
  if type(args) == 'table' then
    for _, a in ipairs(args) do
      table.insert(cmd, a)
    end
  end

  local env = nil
  if type(env_param) == 'table' then
    env = {}
    for _, pair in ipairs(env_param) do
      if pair.name and pair.value then
        env[pair.name] = pair.value
      end
    end
  end

  local term_id = 'term_' .. tostring(self.next_id)
  self.next_id = self.next_id + 1

  local state = {
    id = term_id,
    output = '',
    truncated = false,
    exit_status = { exitCode = nil, signal = nil },
    byte_limit = output_byte_limit,
    waiters = {},
  }

  local function append_output(chunk)
    if not chunk or chunk == '' then
      return
    end
    local new_output = state.output .. chunk
    if #new_output > state.byte_limit then
      local excess = #new_output - state.byte_limit
      new_output = new_output:sub(excess + 1)
      state.truncated = true
    end
    state.output = new_output
  end

  local job_opts = {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data, _)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line and line ~= '' then
          append_output(line .. '\n')
        end
      end
    end,
    on_stderr = function(_, data, _)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line and line ~= '' then
          append_output(line .. '\n')
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      state.exit_status.exitCode = exit_code
      state.exit_status.signal = nil
      if state.waiters then
        for _, waiter_id in ipairs(state.waiters) do
          self:_send_response(waiter_id, {
            exitCode = state.exit_status.exitCode,
            signal = state.exit_status.signal,
          })
        end
        state.waiters = {}
      end
    end,
  }

  if cwd and cwd ~= '' then
    job_opts.cwd = cwd
  end
  if env then
    job_opts.env = env
  end

  local job_id = vim.fn.jobstart(cmd, job_opts)
  if job_id <= 0 then
    self:_send_response(id, { terminalId = nil })
    return
  end

  state.job_id = job_id
  self.terminals[term_id] = state

  self:_send_response(id, { terminalId = term_id })
end

function CursorManager:_handle_terminal_output(id, params)
  if not id then
    return
  end

  local terminal_id = params and params.terminalId or nil
  if not terminal_id then
    self:_send_response(id, {
      output = '',
      truncated = false,
      exitStatus = nil,
    })
    return
  end

  local state = self.terminals[terminal_id]
  if not state then
    self:_send_response(id, {
      output = '',
      truncated = false,
      exitStatus = nil,
    })
    return
  end

  self:_send_response(id, {
    output = state.output or '',
    truncated = state.truncated or false,
    exitStatus = state.exit_status,
  })
end

function CursorManager:_handle_terminal_wait_for_exit(id, params)
  if not id then
    return
  end

  local terminal_id = params and params.terminalId or nil
  if not terminal_id then
    self:_send_response(id, {
      exitCode = nil,
      signal = nil,
    })
    return
  end

  local state = self.terminals[terminal_id]
  if not state then
    self:_send_response(id, {
      exitCode = nil,
      signal = nil,
    })
    return
  end

  if state.exit_status and state.exit_status.exitCode ~= nil then
    self:_send_response(id, {
      exitCode = state.exit_status.exitCode,
      signal = state.exit_status.signal,
    })
    return
  end

  state.waiters = state.waiters or {}
  table.insert(state.waiters, id)
end

function CursorManager:_handle_terminal_kill(id, params)
  if not id then
    return
  end

  local terminal_id = params and params.terminalId or nil
  if not terminal_id then
    self:_send_response(id, vim.NIL)
    return
  end

  local state = self.terminals[terminal_id]
  if state and state.job_id and state.job_id > 0 then
    vim.fn.jobstop(state.job_id)
  end

  self:_send_response(id, vim.NIL)
end

function CursorManager:_handle_terminal_release(id, params)
  if not id then
    return
  end

  local terminal_id = params and params.terminalId or nil
  if not terminal_id then
    self:_send_response(id, vim.NIL)
    return
  end

  local state = self.terminals[terminal_id]
  if state and state.job_id and state.job_id > 0 then
    vim.fn.jobstop(state.job_id)
  end

  self.terminals[terminal_id] = nil
  self:_send_response(id, vim.NIL)
end

function CursorManager:_handle_session_update(update)
  if not self._active_request or not update then
    return
  end

  local update_type = update.sessionUpdate or update.type
  if update_type ~= 'agent_message_chunk' then
    return
  end

  local content = update.content or {}
  local text = ''
  if type(content) == 'table' then
    if content.text and type(content.text) == 'string' then
      text = content.text
    elseif content.type == 'text' and content.value then
      text = content.value
    end
  elseif type(content) == 'string' then
    text = content
  end

  if text == '' then
    return
  end

  local current = self._active_request.content or ''
  current = current .. text
  self._active_request.content = current

  local cb = self._active_request.callback
  if cb and current ~= self._active_request.last_stream_content then
    self._active_request.last_stream_content = current
    local changes = self._active_request.changes or {}
    vim.schedule(function()
      cb(current, changes, true)
    end)
  end
end

function CursorManager:_handle_request_permission(id, params)
  if not id then
    return
  end

  local request = params or {}
  local options = request.options or {}

  -- If no UI is available or no options provided, fall back to allow-once
  if not vim.ui or not vim.ui.select or type(options) ~= 'table' or #options == 0 then
    self:_send_response(id, {
      outcome = {
        outcome = 'selected',
        optionId = 'allow-once',
      },
    })
    return
  end

  local items = {}
  for _, opt in ipairs(options) do
    local label = opt.label or opt.id or opt.optionId or ''
    local id_or_option = opt.id or opt.optionId or ''
    if id_or_option ~= '' then
      table.insert(items, label .. ' [' .. id_or_option .. ']')
    else
      table.insert(items, label)
    end
  end

  local function choose_default_option()
    local reject_idx = nil
    local allow_once_idx = nil

    for idx, opt in ipairs(options) do
      local oid = opt.id or opt.optionId or ''
      if oid == 'reject-once' and not reject_idx then
        reject_idx = idx
      elseif oid == 'allow-once' and not allow_once_idx then
        allow_once_idx = idx
      end
    end

    if reject_idx then
      return options[reject_idx]
    end
    if allow_once_idx then
      return options[allow_once_idx]
    end
    return options[1]
  end

  vim.schedule(function()
    vim.ui.select(items, {
      prompt = request.title or 'Cursor agent requests permission',
    }, function(_choice, idx)
      local selected = options[idx]
      if not selected then
        selected = choose_default_option()
      end

      local option_id = selected.id or selected.optionId or 'allow-once'
      self:_send_response(id, {
        outcome = {
          outcome = 'selected',
          optionId = option_id,
        },
      })
    end)
  end)
end

function CursorManager:_ensure_session(current_file, cb)
  if not self:_ensure_acp_process() then
    cb(false)
    return
  end

  local function ensure_initialized(done)
    if self.initialized then
      done(true)
      return
    end

    self:_send_request('initialize', {
      protocolVersion = 1,
      clientCapabilities = {
        fs = { readTextFile = true, writeTextFile = true },
        terminal = true,
      },
      clientInfo = {
        name = 'cursor-nvim',
        version = '0.1.0',
      },
    }, function(result, _err)
      if result then
        self.initialized = true
        done(true)
      else
        done(false)
      end
    end)
  end

  local function ensure_authenticated(done)
    if self.authenticated then
      done(true)
      return
    end

    self:_send_request('authenticate', {
      methodId = self.acp.auth_method or 'cursor_login',
    }, function(result, _err)
      if result then
        self.authenticated = true
        done(true)
      else
        done(false)
      end
    end)
  end

  local function ensure_session_id(done)
    if self.session_id then
      done(true)
      return
    end

    local cwd = self:get_project_root(current_file)
    self:_send_request('session/new', {
      cwd = cwd,
      mcpServers = {},
    }, function(result, _err)
      if result and result.sessionId then
        self.session_id = result.sessionId
        done(true)
      else
        done(false)
      end
    end)
  end

  ensure_initialized(function(ok)
    if not ok then
      cb(false)
      return
    end
    ensure_authenticated(function(ok2)
      if not ok2 then
        cb(false)
        return
      end
      ensure_session_id(function(ok3)
        cb(ok3)
      end)
    end)
  end)
end

function CursorManager:send_chat_message(message, callback)
  if not self.acp.enabled then
    vim.notify('ACP is disabled in CursorManager options.', vim.log.levels.ERROR)
    if callback then
      callback('', {}, false)
    end
    return
  end

  local current_file = vim.api.nvim_buf_get_name(0)
  local full_prompt = self:get_session_context(current_file)
  if full_prompt ~= '' then
    full_prompt = full_prompt .. '\n\nUser request: ' .. message
  else
    full_prompt = message
  end

  local function finalize_request()
    if not self._active_request then
      return
    end

    local accumulated_content = self._active_request.content or ''
    local accumulated_changes = {}

    if self._active_request.changes and #self._active_request.changes > 0 then
      for _, ch in ipairs(self._active_request.changes) do
        table.insert(accumulated_changes, ch)
      end
    end

    if accumulated_content ~= '' and accumulated_content:match('```') then
      local code_blocks = {}
      for block in accumulated_content:gmatch('```[^`]*```') do
        table.insert(code_blocks, block)
      end
      if #code_blocks > 0 then
        local parsed = self:_parse_code_changes(code_blocks, current_file)
        for _, ch in ipairs(parsed) do
          table.insert(accumulated_changes, ch)
        end
      end
    end

    local cb = self._active_request.callback
    self._active_request = nil
    if cb then
      vim.schedule(function()
        cb(accumulated_content, accumulated_changes, false)
      end)
    end
  end

  local function start_prompt()
    self._active_request = {
      callback = callback,
      content = '',
      changes = {},
      last_stream_content = '',
    }

    local prompt_items = {
      { type = 'text', text = full_prompt },
    }

    local params = {
      sessionId = self.session_id,
      prompt = prompt_items,
    }

    self.current_prompt_id = self:_send_request('session/prompt', params, function(_result)
      finalize_request()
    end)
  end

  self:_ensure_session(current_file, function(ok)
    if not ok then
      if callback then
        callback('Failed to initialize ACP session. Make sure `agent` CLI is installed and authenticated (run `agent login`).', {}, false)
      end
      return
    end
    start_prompt()
  end)
end

function CursorManager:_parse_code_changes(code_blocks, current_file)
  local changes = {}
  
  for _, block in ipairs(code_blocks) do
    local filepath = current_file
    local lines = {}
    
    for line in block:gmatch('[^\n]+') do
      if line:match('^```') then
        local lang_match = line:match('^```([^:]+):(.+)')
        if lang_match then
          filepath = lang_match
        end
      elseif not line:match('^```') then
        table.insert(lines, line)
      end
    end
    
    if #lines > 0 then
      table.insert(changes, {
        type = 'edit',
        file = filepath or current_file,
        start_line = 1,
        end_line = 1,
        lines = lines,
      })
    end
  end
  
  return changes
end

function CursorManager:_check_cursor_cli()
  local handle = io.popen('which ' .. (self.acp.command or 'agent') .. ' 2>/dev/null')
  if handle then
    local result = handle:read('*a')
    handle:close()
    if result and result ~= '' then
      return true
    end
  end
  
  local handle2 = io.popen((self.acp.command or 'agent') .. ' --version 2>/dev/null')
  if handle2 then
    local result = handle2:read('*a')
    handle2:close()
    if result and result ~= '' then
      return true
    end
  end
  
  return false
end

function CursorManager:get_file_context(filepath)
  if not filepath or filepath == '' then
    return nil
  end
  
  if vim.fn.filereadable(filepath) ~= 1 then
    return nil
  end
  
  local ok, lines = pcall(function()
    local result = {}
    for line in io.lines(filepath) do
      table.insert(result, line)
    end
    return result
  end)
  
  if not ok or not lines then
    return nil
  end
  
  return table.concat(lines, '\n')
end

function CursorManager:get_project_root(filepath)
  if not filepath or filepath == '' then
    filepath = vim.fn.getcwd()
  end
  
  local dir = vim.fn.fnamemodify(filepath, ':h')
  local root_markers = {'.git', '.hg', '.svn', 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod', 'pom.xml', 'build.gradle', 'Makefile', 'CMakeLists.txt'}
  
  local current = dir
  while current ~= '/' and current ~= '' do
    for _, marker in ipairs(root_markers) do
      local marker_path = current .. '/' .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        return current
      end
    end
    current = vim.fn.fnamemodify(current, ':h')
  end
  
  return dir
end

function CursorManager:get_project_structure(project_root, max_depth, max_files)
  max_depth = max_depth or 1
  max_files = max_files or 20
  local structure = {}
  local file_count = 0
  
  local function scan_dir(dir, depth, prefix)
    if depth > max_depth or file_count >= max_files then
      return
    end
    
    local escaped_dir = vim.fn.shellescape(dir)
    local handle = io.popen('find ' .. escaped_dir .. ' -maxdepth 1 -not -path ' .. escaped_dir .. ' 2>/dev/null | head -20')
    if not handle then
      return
    end
    
    local entries = {}
    for line in handle:lines() do
      if line and line ~= '' then
        table.insert(entries, line)
      end
    end
    handle:close()
    
    table.sort(entries)
    
    for _, entry in ipairs(entries) do
      if file_count >= max_files then
        break
      end
      
      local name = vim.fn.fnamemodify(entry, ':t')
      local is_dir = vim.fn.isdirectory(entry) == 1
      
      if not name:match('^%.') or name == '.git' then
        if is_dir then
          table.insert(structure, prefix .. name .. '/')
          if depth < max_depth then
            scan_dir(entry, depth + 1, prefix .. '  ')
          end
        else
          table.insert(structure, prefix .. name)
          file_count = file_count + 1
        end
      end
    end
  end
  
  scan_dir(project_root, 0, '')
  return structure
end

function CursorManager:get_config_files(project_root)
  local config_files = {}
  local config_patterns = {
    'package.json', 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
    'requirements.txt', 'Pipfile', 'poetry.lock', 'pyproject.toml',
    'Cargo.toml', 'Cargo.lock',
    'go.mod', 'go.sum',
    'pom.xml', 'build.gradle', 'settings.gradle',
    'Makefile', 'CMakeLists.txt',
    'tsconfig.json', 'jsconfig.json',
    '.gitignore', '.env.example', 'README.md', 'LICENSE'
  }
  
  for _, pattern in ipairs(config_patterns) do
    local filepath = project_root .. '/' .. pattern
    if vim.fn.filereadable(filepath) == 1 then
      local content = self:get_file_context(filepath)
      if content then
        table.insert(config_files, {
          name = pattern,
          content = content
        })
      end
    end
  end
  
  return config_files
end

function CursorManager:get_open_buffers_context()
  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      if filepath and filepath ~= '' and vim.fn.filereadable(filepath) == 1 then
        table.insert(buffers, {
          path = filepath,
        })
      end
    end
  end
  return buffers
end

function CursorManager:get_project_context(current_file)
  local context_parts = {}
  
  local project_root = self:get_project_root(current_file)
  local working_dir = vim.fn.getcwd()
  
  if project_root then
    table.insert(context_parts, 'Project root: ' .. project_root)
  end
  
  if working_dir and working_dir ~= '' and working_dir ~= project_root then
    table.insert(context_parts, 'Working directory: ' .. working_dir)
  end
  
  if current_file and current_file ~= '' and vim.fn.filereadable(current_file) == 1 then
    table.insert(context_parts, 'Current file: ' .. current_file)
  end
  
  return table.concat(context_parts, '\n')
end

function CursorManager:get_session_context(current_file)
  local parts = {}

  local project_root = self:get_project_root(current_file)
  local project_structure = self:get_project_structure(project_root, 1, 30)
  local open_buffers = self:get_open_buffers_context()

  table.insert(parts, '## Neovim Session Context')
  table.insert(parts, '')

  if project_root then
    table.insert(parts, 'Project root: ' .. project_root)
  end

  if current_file and current_file ~= '' then
    table.insert(parts, 'Current file: ' .. current_file)
  end

  if #open_buffers > 0 then
    table.insert(parts, '')
    table.insert(parts, 'Open buffers:')
    for _, buf in ipairs(open_buffers) do
      table.insert(parts, '- ' .. buf.path)
    end
  end

  if project_structure and #project_structure > 0 then
    table.insert(parts, '')
    table.insert(parts, 'Project structure (shallow):')
    for _, entry in ipairs(project_structure) do
      table.insert(parts, '- ' .. entry)
    end
  end

  return table.concat(parts, '\n')
end

function CursorManager:stop()
  local stopped = false

  if self.session_id and self.proc_job_id then
    local ok = pcall(function()
      self:_send_request('session/cancel', { sessionId = self.session_id }, function() end)
    end)
    if ok then
      stopped = true
    end
  end

  if self.proc_job_id and self.proc_job_id > 0 then
    vim.fn.jobstop(self.proc_job_id)
    self.proc_job_id = nil
    stopped = true
  end

  if self._active_request then
    self._active_request = nil
  end

  return stopped
end

return CursorManager


