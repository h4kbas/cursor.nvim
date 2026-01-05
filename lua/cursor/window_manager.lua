local WindowManager = {}
WindowManager.__index = WindowManager

function WindowManager.new()
  local self = setmetatable({}, WindowManager)
  
  self.chat_width = 50
  self.chat_bufnr = nil
  self.chat_winid = nil
  self.input_bufnr = nil
  self.input_winid = nil
  self.history_separator_line = 0
  self.last_displayed_content = ''
  
  return self
end

function WindowManager:create_chat_window()
  local chat_width = self.chat_width
  if self.opts and self.opts.chat_width then
    chat_width = self.opts.chat_width
  end
  
  local ui = vim.api.nvim_list_uis()[1]
  local width = ui.width
  local height = ui.height
  
  self.chat_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(self.chat_bufnr, 'cursor-chat-history')
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
  
  self.input_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(self.input_bufnr, 'cursor-chat-input')
  vim.api.nvim_buf_set_option(self.input_bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(self.input_bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(self.input_bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(self.input_bufnr, 'modifiable', true)
  
  local input_height = 3
  local history_height = height - input_height - 4
  
  self.chat_winid = vim.api.nvim_open_win(self.chat_bufnr, true, {
    relative = 'editor',
    width = chat_width,
    height = history_height,
    col = width - chat_width - 1,
    row = 1,
    style = 'minimal',
    border = 'single',
  })
  
  vim.api.nvim_win_set_option(self.chat_winid, 'number', false)
  vim.api.nvim_win_set_option(self.chat_winid, 'relativenumber', false)
  vim.api.nvim_win_set_option(self.chat_winid, 'wrap', true)
  vim.api.nvim_win_set_option(self.chat_winid, 'cursorline', false)
  vim.api.nvim_win_set_option(self.chat_winid, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(self.chat_winid, 'foldcolumn', '0')
  
  self.input_winid = vim.api.nvim_open_win(self.input_bufnr, true, {
    relative = 'editor',
    width = chat_width,
    height = input_height,
    col = width - chat_width - 1,
    row = history_height + 2,
    style = 'minimal',
    border = 'single',
  })
  
  vim.api.nvim_win_set_option(self.input_winid, 'number', false)
  vim.api.nvim_win_set_option(self.input_winid, 'relativenumber', false)
  vim.api.nvim_win_set_option(self.input_winid, 'wrap', true)
  vim.api.nvim_win_set_option(self.input_winid, 'cursorline', false)
  vim.api.nvim_win_set_option(self.input_winid, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(self.input_winid, 'foldcolumn', '0')
  
  vim.api.nvim_buf_set_lines(self.input_bufnr, 0, -1, false, {''})
  vim.api.nvim_win_set_cursor(self.input_winid, {1, 0})
  vim.api.nvim_feedkeys('i', 'n', false)
  
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.chat_bufnr, 0, -1, false, {'# Cursor Chat', ''})
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
  
  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = self.chat_bufnr,
    callback = function()
      self.chat_winid = nil
      self.chat_bufnr = nil
    end,
  })
  
  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = self.input_bufnr,
    callback = function()
      self.input_winid = nil
      self.input_bufnr = nil
    end,
  })
end

function WindowManager:close_chat_window()
  if self.chat_winid and vim.api.nvim_win_is_valid(self.chat_winid) then
    vim.api.nvim_win_close(self.chat_winid, true)
  end
  if self.input_winid and vim.api.nvim_win_is_valid(self.input_winid) then
    vim.api.nvim_win_close(self.input_winid, true)
  end
  self.chat_winid = nil
  self.chat_bufnr = nil
  self.input_winid = nil
  self.input_bufnr = nil
end

function WindowManager:update_chat_display(chat_manager)
  if not self.chat_bufnr or not vim.api.nvim_buf_is_valid(self.chat_bufnr) then
    return
  end
  
  self.last_displayed_content = ''
  local formatted = chat_manager:format_messages_for_display()
  
  if #formatted == 0 then
    formatted = {'# Cursor Chat', ''}
  end
  
  local status = chat_manager:get_status()
  if status ~= 'idle' then
    local status_indicator = chat_manager:get_status_indicator()
    if status_indicator ~= '' then
      local has_assistant = false
      for _, line in ipairs(formatted) do
        if line == '## Assistant' then
          has_assistant = true
          break
        end
      end
      
      if not has_assistant then
        table.insert(formatted, '## Assistant')
        table.insert(formatted, '')
      end
      
      table.insert(formatted, status_indicator)
    end
  end
  
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', false)
  vim.api.nvim_buf_set_lines(self.chat_bufnr, 0, -1, false, formatted)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
  
  if self.chat_winid and vim.api.nvim_win_is_valid(self.chat_winid) then
    local line_count = vim.api.nvim_buf_line_count(self.chat_bufnr)
    if line_count > 0 then
      local cursor_line = math.min(line_count, #formatted)
      vim.api.nvim_win_set_cursor(self.chat_winid, {cursor_line, 0})
    end
  end
end

function WindowManager:update_chat_display_streaming(chat_manager, streaming_response)
  if not self.chat_bufnr or not vim.api.nvim_buf_is_valid(self.chat_bufnr) then
    return
  end
  
  local new_content = streaming_response or ''
  if new_content == '' then
    return
  end
  
  local clean_content = new_content
  clean_content = clean_content:gsub('{%s*"[^"]*"%s*:%s*[^}]*}', '')
  clean_content = clean_content:gsub('"type"%s*:%s*"[^"]*"', '')
  clean_content = clean_content:gsub('"text"%s*:%s*"([^"]*)"', '%1')
  
  if clean_content == '' or clean_content:match('^%s*{%s*$') then
    return
  end
  
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', false)
  
  local current_lines = vim.api.nvim_buf_get_lines(self.chat_bufnr, 0, -1, false)
  local assistant_start_idx = nil
  local streaming_marker_idx = nil
  
  for i, line in ipairs(current_lines) do
      if line == '## Assistant' then
        assistant_start_idx = i
      elseif line:match('^[⏳✨⏹]') or line:match('Processing') or line:match('Streaming') or line:match('Stopped') then
        streaming_marker_idx = i
    end
  end
  
  if not assistant_start_idx then
    local formatted = chat_manager:format_messages_for_display()
    table.insert(formatted, '## Assistant')
    table.insert(formatted, '')
    vim.api.nvim_buf_set_lines(self.chat_bufnr, 0, -1, false, formatted)
    assistant_start_idx = #formatted
    streaming_marker_idx = nil
  end
  
  local delta = ''
  if #clean_content > #self.last_displayed_content then
    delta = clean_content:sub(#self.last_displayed_content + 1)
  elseif clean_content ~= self.last_displayed_content then
    delta = clean_content
    self.last_displayed_content = ''
  end
  
  if delta ~= '' then
    -- Remove streaming marker if it exists
    if streaming_marker_idx then
      local marker_start = streaming_marker_idx - 1
      if marker_start > 0 and current_lines[marker_start] == '' then
        marker_start = marker_start - 1
      end
      vim.api.nvim_buf_set_lines(self.chat_bufnr, marker_start, streaming_marker_idx, false, {})
    end
    
    local parts = {}
    local current_part = ''
    
    for i = 1, #delta do
      local char = delta:sub(i, i)
      if char == '\n' then
        if current_part ~= '' then
          table.insert(parts, {text = current_part, newline = true})
          current_part = ''
        else
          table.insert(parts, {text = '', newline = true})
        end
      elseif char ~= '\r' then
        current_part = current_part .. char
      end
    end
    
    if current_part ~= '' then
      table.insert(parts, {text = current_part, newline = false})
    end
    
    for _, part in ipairs(parts) do
      if not vim.api.nvim_buf_is_valid(self.chat_bufnr) then
        break
      end
      
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', true)
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', false)
      
      local line_count = vim.api.nvim_buf_line_count(self.chat_bufnr)
      
      if part.newline then
        if part.text ~= '' then
          vim.api.nvim_buf_set_lines(self.chat_bufnr, -1, -1, false, {part.text})
        else
          vim.api.nvim_buf_set_lines(self.chat_bufnr, -1, -1, false, {''})
        end
      else
        if line_count > 0 then
          local last_idx = line_count - 1
          local last_line = vim.api.nvim_buf_get_lines(self.chat_bufnr, last_idx, last_idx + 1, false)[1] or ''
          vim.api.nvim_buf_set_lines(self.chat_bufnr, last_idx, last_idx + 1, false, {last_line .. part.text})
        else
          vim.api.nvim_buf_set_lines(self.chat_bufnr, -1, -1, false, {part.text})
        end
      end
    end
    
    self.last_displayed_content = clean_content
    
    local current_lines = vim.api.nvim_buf_get_lines(self.chat_bufnr, 0, -1, false)
    local status_line_idx = nil
    
    for i, line in ipairs(current_lines) do
      if line:match('^[⏳✨⏹]') or line:match('Processing') or line:match('Streaming') or line:match('Stopped') then
        status_line_idx = i
        break
      end
    end
    
    local status_indicator = chat_manager:get_status_indicator()
    if status_indicator ~= '' then
      if status_line_idx then
        vim.api.nvim_buf_set_lines(self.chat_bufnr, status_line_idx - 1, status_line_idx, false, {status_indicator})
      else
        vim.api.nvim_buf_set_lines(self.chat_bufnr, -1, -1, false, {'', status_indicator})
      end
    elseif status_line_idx then
      local marker_start = status_line_idx - 1
      if marker_start > 0 and current_lines[marker_start] == '' then
        marker_start = marker_start - 1
      end
      vim.api.nvim_buf_set_lines(self.chat_bufnr, marker_start, status_line_idx, false, {})
    end
    
    vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
    vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
    
    if self.chat_winid and vim.api.nvim_win_is_valid(self.chat_winid) then
      local line_count = vim.api.nvim_buf_line_count(self.chat_bufnr)
      if line_count > 0 then
        vim.api.nvim_win_set_cursor(self.chat_winid, {line_count, 0})
      end
    end
    return
  else
    local status_indicator = chat_manager:get_status_indicator()
    if status_indicator ~= '' then
      local current_lines = vim.api.nvim_buf_get_lines(self.chat_bufnr, 0, -1, false)
      local status_line_idx = nil
      
      for i, line in ipairs(current_lines) do
        if line:match('^[⏳✨⏹]') or line:match('Processing') or line:match('Streaming') or line:match('Stopped') then
          status_line_idx = i
          break
        end
      end
      
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', true)
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', false)
      
      if status_line_idx then
        vim.api.nvim_buf_set_lines(self.chat_bufnr, status_line_idx - 1, status_line_idx, false, {status_indicator})
      else
        vim.api.nvim_buf_set_lines(self.chat_bufnr, -1, -1, false, {'', status_indicator})
      end
      
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
    else
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'modifiable', false)
      vim.api.nvim_buf_set_option(self.chat_bufnr, 'readonly', true)
    end
    
    if self.chat_winid and vim.api.nvim_win_is_valid(self.chat_winid) then
      local line_count = vim.api.nvim_buf_line_count(self.chat_bufnr)
      if line_count > 0 then
        vim.api.nvim_win_set_cursor(self.chat_winid, {line_count, 0})
      end
    end
  end
end

function WindowManager:get_user_input()
  if not self.input_bufnr or not vim.api.nvim_buf_is_valid(self.input_bufnr) then
    return ''
  end
  
  local lines = vim.api.nvim_buf_get_lines(self.input_bufnr, 0, -1, false)
  local message = table.concat(lines, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
  return message
end

function WindowManager:focus_input()
  if self.input_winid and vim.api.nvim_win_is_valid(self.input_winid) then
    vim.api.nvim_set_current_win(self.input_winid)
    vim.api.nvim_win_set_cursor(self.input_winid, {1, 0})
    vim.cmd('stopinsert')
    vim.defer_fn(function()
      vim.api.nvim_feedkeys('i', 'n', false)
    end, 10)
  end
end

function WindowManager:clear_input()
  if self.input_bufnr and vim.api.nvim_buf_is_valid(self.input_bufnr) then
    vim.api.nvim_buf_set_lines(self.input_bufnr, 0, -1, false, {''})
  end
end

function WindowManager:set_input_text(text)
  if self.input_bufnr and vim.api.nvim_buf_is_valid(self.input_bufnr) then
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do
      table.insert(lines, line)
    end
    if #lines == 0 then
      lines = {text}
    end
    vim.api.nvim_buf_set_lines(self.input_bufnr, 0, -1, false, lines)
  end
end

return WindowManager

