local CursorManager = require('cursor.cursor_manager')
local WindowManager = require('cursor.window_manager')
local ChatManager = require('cursor.chat_manager')
local BindingManager = require('cursor.binding_manager')
local Commands = require('cursor.commands')

local AppManager = {}
AppManager.__index = AppManager

function AppManager.new()
  local self = setmetatable({}, AppManager)
  
  self.opts = {}
  self.cursor_manager = nil
  self.window_manager = WindowManager.new()
  self.chat_manager = ChatManager.new()
  self.binding_manager = nil
  self.commands = nil
  
  self.is_open = false
  
  return self
end

function AppManager:setup_bindings(binding_opts)
  self.binding_manager = BindingManager.new(self)
  self.binding_manager:setup(binding_opts)
end

function AppManager:setup_commands()
  self.commands = Commands.new(self)
  self.commands:register()
end

function AppManager:open_chat()
  if self.is_open then
    return
  end
  
  if not self.cursor_manager then
    self.cursor_manager = CursorManager.new(self.opts)
  end
  
  self.window_manager.opts = self.opts
  
  self.window_manager:create_chat_window()
  self.chat_manager:initialize()
  self.is_open = true
  
  if self.binding_manager then
    self.binding_manager:register_all_bindings(self.window_manager)
  end
  
  self.window_manager:update_chat_display(self.chat_manager)
end

function AppManager:handle_send_message(message_text)
  if not self.window_manager.chat_bufnr then
    return
  end
  
  local message = message_text
  if not message or message == '' or message:match('^%s*$') then
    return
  end
  
  self.chat_manager:set_last_sent_message(message)
  self.chat_manager:add_message('user', message)
  self.window_manager:clear_input()
  self.window_manager:update_chat_display(self.chat_manager)
  vim.schedule(function()
    self.window_manager:focus_input()
  end)
  
  self:send_message(message)
end

function AppManager:close()
  if not self.is_open then
    return
  end
  
  local chat_content = self.chat_manager:format_messages_for_display()
  local streaming_response = self.chat_manager:get_streaming_response()
  if streaming_response and streaming_response ~= '' then
    local has_assistant = false
    for _, line in ipairs(chat_content) do
      if line == '## Assistant' then
        has_assistant = true
        break
      end
    end
    
    if not has_assistant then
      table.insert(chat_content, '## Assistant')
      table.insert(chat_content, '')
    end
    
    local streaming_lines = {}
    for line in streaming_response:gmatch('[^\r\n]+') do
      table.insert(streaming_lines, line)
    end
    if #streaming_lines == 0 then
      table.insert(streaming_lines, streaming_response)
    end
    
    for _, line in ipairs(streaming_lines) do
      table.insert(chat_content, line)
    end
  end
  
  local status = self.chat_manager:get_status()
  if status ~= 'idle' then
    local status_indicator = self.chat_manager:get_status_indicator()
    if status_indicator ~= '' then
      table.insert(chat_content, '')
      table.insert(chat_content, status_indicator)
    end
  end
  
  local chat_bufnr = vim.fn.bufnr('cursor-chat-history', true)
  if chat_bufnr == -1 then
    chat_bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(chat_bufnr, 'cursor-chat-history')
  end
  
  vim.api.nvim_buf_set_option(chat_bufnr, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(chat_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(chat_bufnr, 'readonly', false)
  vim.api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, chat_content)
  vim.cmd('split')
  vim.api.nvim_set_current_buf(chat_bufnr)
  
  self.window_manager:close_chat_window()
  self.chat_manager:cleanup()
  self.is_open = false
end


function AppManager:send_message(message)
  local is_streaming = false
  local last_response = ''
  
  self.chat_manager:set_status('processing')
  self.window_manager:update_chat_display(self.chat_manager)
  
  self.cursor_manager:send_chat_message(message, function(response, changes, streaming)
    is_streaming = streaming or false
    last_response = response
    
    if streaming then
      self.chat_manager:set_status('streaming')
      self.chat_manager:set_streaming_response(response)
      self.window_manager:update_chat_display_streaming(self.chat_manager, response)
    else
      if response and response ~= '' and not response:match('^%s*$') then
        self.chat_manager:add_message('assistant', response)
        self.chat_manager:clear_streaming_response()
        self.chat_manager:set_status('idle')
        if changes and #changes > 0 then
          self.chat_manager:set_last_changes(changes)
        end
        self.window_manager:update_chat_display(self.chat_manager)
        self.window_manager:focus_input()
      else
        self.chat_manager:clear_streaming_response()
        self.chat_manager:set_status('idle')
        self.window_manager:update_chat_display(self.chat_manager)
        self.window_manager:focus_input()
      end
    end
  end)
end


function AppManager:stop_request()
  if self.cursor_manager then
    local stopped = self.cursor_manager:stop()
    if stopped then
      self.chat_manager:set_status('stopped')
      local current_response = self.chat_manager:get_streaming_response()
      if current_response and current_response ~= '' then
        self.window_manager:update_chat_display_streaming(self.chat_manager, current_response)
      else
        self.window_manager:update_chat_display(self.chat_manager)
      end
      
      local last_message = self.chat_manager:get_last_sent_message()
      if last_message and last_message ~= '' then
        self.window_manager:set_input_text(last_message)
      end
      
      self.window_manager:focus_input()
    end
    return stopped
  end
  return false
end

function AppManager:apply_changes()
  local last_changes = self.chat_manager:get_last_changes()
  if not last_changes or #last_changes == 0 then
    return
  end
  
  for _, change in ipairs(last_changes) do
    if change.type == 'edit' and change.file then
      local bufnr = vim.fn.bufnr(change.file, true)
      if bufnr == -1 then
        bufnr = vim.fn.bufadd(change.file)
      end
      
      if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
      end
      
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local start_line = change.start_line or 1
      local end_line = change.end_line or #current_lines
      
      change.original_lines = {}
      for i = start_line, end_line do
        local line_idx = i - 1
        if current_lines[line_idx] then
          table.insert(change.original_lines, current_lines[line_idx])
        end
      end
      
      vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line - 1, false, change.lines or {})
    end
  end
end

function AppManager:revert_changes()
  local last_changes = self.chat_manager:get_last_changes()
  if not last_changes or #last_changes == 0 then
    return
  end
  
  for _, change in ipairs(last_changes) do
    if change.type == 'edit' and change.file then
      local bufnr = vim.fn.bufnr(change.file, true)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        local original_lines = change.original_lines or {}
        local start_line = change.start_line or 1
        vim.api.nvim_buf_set_lines(bufnr, start_line - 1, start_line + #original_lines - 1, false, original_lines)
      end
    end
  end
  
  self.chat_manager:clear_last_changes()
end

return AppManager

