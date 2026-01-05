local CursorManager = {}
CursorManager.__index = CursorManager

function CursorManager.new(opts)
  local self = setmetatable({}, CursorManager)
  
  opts = opts or {}
  self.model = opts.model or 'auto'
  self.current_job_id = nil
  
  if not self:_check_cursor_cli() then
    vim.notify('cursor-agent CLI not found. Install it with: curl https://cursor.com/install -fsS | bash', vim.log.levels.WARN)
  end
  
  return self
end

function CursorManager:send_chat_message(message, callback)
  local current_file = vim.api.nvim_buf_get_name(0)
  local project_context = self:get_project_context(current_file)
  
  local full_prompt = project_context
  if full_prompt ~= '' then
    full_prompt = full_prompt .. '\n\nUser request: ' .. message
  else
    full_prompt = message
  end
  
  local args = {'--print', '--output-format', 'stream-json', '--stream-partial-output'}
  
  if self.model then
    table.insert(args, '--model')
    table.insert(args, self.model)
  end
  
  self._was_stopped = false
  
  local accumulated_content = ''
  local accumulated_changes = {}
  local current_file_for_changes = current_file
  local partial_json = ''
  local has_received_text_delta = false
  local has_thinking_section = false
  local was_stopped = false
  
  local last_update_content = ''
  local function schedule_update()
    if callback and accumulated_content ~= last_update_content then
      last_update_content = accumulated_content
      vim.schedule(function()
        callback(accumulated_content, accumulated_changes, true)
      end)
    end
  end
  
  self.current_job_id = vim.fn.jobstart({'cursor-agent', unpack(args)}, {
    stdout_buffered = false,
    stderr_buffered = false,
    stdin = 'pipe',
    on_stdout = function(_, data, _)
      if not data or #data == 0 then
        return
      end
      
      for _, chunk in ipairs(data) do
        if chunk and chunk ~= '' then
          partial_json = partial_json .. chunk
          
          while true do
            local start_pos = partial_json:find('{')
            if not start_pos then
              break
            end
            
            local depth = 0
            local end_pos = nil
            for i = start_pos, #partial_json do
              local char = partial_json:sub(i, i)
              if char == '{' then
                depth = depth + 1
              elseif char == '}' then
                depth = depth - 1
                if depth == 0 then
                  end_pos = i
                  break
                end
              end
            end
            
            if end_pos then
              local json_str = partial_json:sub(start_pos, end_pos)
              local ok, json_data = pcall(vim.json.decode, json_str)
              if ok and json_data then
                if json_data.type == 'text_delta' and json_data.text then
                  has_received_text_delta = true
                  if has_thinking_section and not accumulated_content:match('\n\n---\n\n') then
                    accumulated_content = accumulated_content .. '\n\n---\n\n'
                  end
                  accumulated_content = accumulated_content .. json_data.text
                  schedule_update()
                elseif json_data.type == 'thinking' and json_data.subtype == 'delta' then
                  if json_data.text and json_data.text ~= '' then
                    if not has_thinking_section then
                      accumulated_content = '**Thinking:**\n\n' .. accumulated_content
                      has_thinking_section = true
                    end
                    accumulated_content = accumulated_content .. json_data.text
                    schedule_update()
                  end
                elseif json_data.type == 'assistant' then
                  has_received_text_delta = true
                  local new_content = ''
                  if json_data.content then
                    if type(json_data.content) == 'string' then
                      new_content = json_data.content
                    elseif type(json_data.content) == 'table' then
                      for _, item in ipairs(json_data.content) do
                        if item.type == 'text' and item.text then
                          new_content = new_content .. item.text
                        end
                      end
                    end
                  elseif json_data.message and json_data.message.content then
                    if type(json_data.message.content) == 'string' then
                      new_content = json_data.message.content
                    elseif type(json_data.message.content) == 'table' then
                      for _, item in ipairs(json_data.message.content) do
                        if item.type == 'text' and item.text then
                          new_content = new_content .. item.text
                        end
                      end
                    end
                  elseif json_data.text then
                    new_content = json_data.text
                  end
                  
                  if new_content ~= '' and #new_content > #accumulated_content then
                    accumulated_content = new_content
                    schedule_update()
                  end
                elseif json_data.type == 'result' then
                elseif json_data.type == 'thinking' then
                  if json_data.text and json_data.text ~= '' then
                    if not has_thinking_section then
                      accumulated_content = '**Thinking:**\n\n' .. accumulated_content
                      has_thinking_section = true
                    end
                    accumulated_content = accumulated_content .. json_data.text
                    schedule_update()
                  end
                elseif json_data.type == 'system' or json_data.type == 'init' or json_data.type == 'user' then
                elseif json_data.type == 'message' and json_data.content then
                  if not has_received_text_delta then
                    if type(json_data.content) == 'string' then
                      accumulated_content = accumulated_content .. json_data.content
                      schedule_update()
                    elseif type(json_data.content) == 'table' then
                      for _, item in ipairs(json_data.content) do
                        if item.type == 'text' and item.text then
                          accumulated_content = accumulated_content .. item.text
                          schedule_update()
                        end
                      end
                    end
                  end
                end
              end
              partial_json = partial_json:sub(end_pos + 1)
            else
              break
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        local error_msg = table.concat(data, '\n')
        if error_msg and error_msg ~= '' then
          accumulated_content = accumulated_content .. '\n[Error: ' .. error_msg .. ']'
          schedule_update()
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      self.current_job_id = nil
      
      if self._was_stopped then
        if callback then
          vim.schedule(function()
            callback(accumulated_content, accumulated_changes, false)
          end)
        end
        return
      end
      if exit_code ~= 0 then
        vim.notify('cursor-agent exited with code ' .. exit_code, vim.log.levels.ERROR)
      end
      
      if partial_json ~= '' then
        local trimmed = partial_json:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed ~= '' then
          local remaining = trimmed
          while true do
            local start_pos = remaining:find('{')
            if not start_pos then
              break
            end
            
            local depth = 0
            local end_pos = nil
            for i = start_pos, #remaining do
              local char = remaining:sub(i, i)
              if char == '{' then
                depth = depth + 1
              elseif char == '}' then
                depth = depth - 1
                if depth == 0 then
                  end_pos = i
                  break
                end
              end
            end
            
            if end_pos then
              local json_str = remaining:sub(start_pos, end_pos)
              local ok, json_data = pcall(vim.json.decode, json_str)
              if ok and json_data then
                if json_data.type == 'text_delta' and json_data.text then
                  has_received_text_delta = true
                  accumulated_content = accumulated_content .. json_data.text
                elseif json_data.type == 'thinking' and json_data.subtype == 'delta' and json_data.text then
                  if not has_thinking_section then
                    accumulated_content = '**Thinking:**\n\n' .. accumulated_content
                    has_thinking_section = true
                  end
                  accumulated_content = accumulated_content .. json_data.text
                  has_received_text_delta = true
                elseif json_data.type == 'assistant' or json_data.type == 'result' then
                elseif json_data.type == 'message' and json_data.content then
                  if not has_received_text_delta then
                    if type(json_data.content) == 'string' then
                      accumulated_content = accumulated_content .. json_data.content
                    elseif type(json_data.content) == 'table' then
                      for _, item in ipairs(json_data.content) do
                        if item.type == 'text' and item.text then
                          accumulated_content = accumulated_content .. item.text
                        end
                      end
                    end
                  end
                end
              end
              remaining = remaining:sub(end_pos + 1)
            else
              break
            end
          end
        end
      end
      
      if accumulated_content == '' or accumulated_content:match('^%s*$') then
        if partial_json ~= '' then
          local trimmed = partial_json:gsub('^%s+', ''):gsub('%s+$', '')
          if trimmed ~= '' then
            local ok, json_data = pcall(vim.json.decode, trimmed)
            if ok and json_data then
              if json_data.type == 'text_delta' and json_data.text then
                accumulated_content = accumulated_content .. json_data.text
              elseif json_data.text then
                accumulated_content = accumulated_content .. json_data.text
              elseif json_data.content and type(json_data.content) == 'string' then
                accumulated_content = accumulated_content .. json_data.content
              end
          end
        end
      end
      
      if (accumulated_content == '' or accumulated_content:match('^%s*$')) and not self._was_stopped then
          accumulated_content = 'No response received from cursor-agent. Please check your CURSOR_API_KEY and try again.'
        end
      end
      
      if accumulated_content:match('^```') or accumulated_content:match('```') then
        local code_blocks = {}
        for block in accumulated_content:gmatch('```[^`]*```') do
          table.insert(code_blocks, block)
        end
        if #code_blocks > 0 then
          accumulated_changes = self:_parse_code_changes(code_blocks, current_file_for_changes)
        end
      end
      
      if callback then
        vim.schedule(function()
          callback(accumulated_content, accumulated_changes, false)
        end)
      end
    end,
  })
  
  if self.current_job_id <= 0 then
    vim.notify('Failed to start cursor-agent job. Make sure Cursor CLI is installed: curl https://cursor.com/install -fsS | bash', vim.log.levels.ERROR)
    self.current_job_id = nil
    callback('', {}, false)
    return
  end
  
  vim.fn.chansend(self.current_job_id, full_prompt .. '\n')
  vim.fn.chanclose(self.current_job_id, 'stdin')
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
  local handle = io.popen('which cursor-agent 2>/dev/null')
  if handle then
    local result = handle:read('*a')
    handle:close()
    if result and result ~= '' then
      return true
    end
  end
  
  local handle2 = io.popen('cursor-agent --version 2>/dev/null')
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
        local content = self:get_file_context(filepath)
        if content then
          table.insert(buffers, {
            path = filepath,
            content = content
          })
        end
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

function CursorManager:stop()
  if self.current_job_id and self.current_job_id > 0 then
    self._was_stopped = true
    vim.fn.jobstop(self.current_job_id)
    self.current_job_id = nil
    return true
  end
  return false
end

return CursorManager


