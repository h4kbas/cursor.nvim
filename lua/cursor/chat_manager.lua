local ChatManager = {}
ChatManager.__index = ChatManager

function ChatManager.new()
  local self = setmetatable({}, ChatManager)
  
  self.messages = {}
  self.last_changes = {}
  self.input_buffer = {}
  self.streaming_response = ''
  self.status = 'idle'
  self.last_sent_message = ''
  
  return self
end

function ChatManager:initialize()
  self.messages = {}
  self.last_changes = {}
  self.input_buffer = {}
  self.status = 'idle'
end

function ChatManager:cleanup()
  self.messages = {}
  self.last_changes = {}
  self.input_buffer = {}
end

function ChatManager:add_message(role, content)
  table.insert(self.messages, {
    role = role,
    content = content,
    timestamp = os.time()
  })
end

function ChatManager:get_messages()
  return self.messages
end

function ChatManager:get_input()
  return table.concat(self.input_buffer, '\n')
end

function ChatManager:set_input(input)
  self.input_buffer = {}
  for line in input:gmatch('[^\r\n]+') do
    table.insert(self.input_buffer, line)
  end
end

function ChatManager:clear_input()
  self.input_buffer = {}
end

function ChatManager:set_last_changes(changes)
  self.last_changes = changes
end

function ChatManager:get_last_changes()
  return self.last_changes
end

function ChatManager:clear_last_changes()
  self.last_changes = {}
end

function ChatManager:set_streaming_response(response)
  self.streaming_response = response
end

function ChatManager:clear_streaming_response()
  self.streaming_response = ''
end

function ChatManager:get_streaming_response()
  return self.streaming_response
end

function ChatManager:set_status(status)
  self.status = status or 'idle'
end

function ChatManager:get_status()
  return self.status
end

function ChatManager:get_status_indicator()
  local status_indicators = {
    idle = '',
    processing = '⏳ Processing...',
    streaming = '✨ Streaming...',
    stopped = '⏹ Stopped',
  }
  return status_indicators[self.status] or ''
end

function ChatManager:set_last_sent_message(message)
  self.last_sent_message = message or ''
end

function ChatManager:get_last_sent_message()
  return self.last_sent_message
end

function ChatManager:format_messages_for_display()
  local formatted = {}
  
  for i, msg in ipairs(self.messages) do
    if msg.role == 'user' then
      table.insert(formatted, '## You')
      table.insert(formatted, '')
      
      local content_lines = {}
      for line in msg.content:gmatch('[^\r\n]+') do
        table.insert(content_lines, line)
      end
      
      if #content_lines == 0 then
        table.insert(content_lines, msg.content)
      end
      
      for _, line in ipairs(content_lines) do
        table.insert(formatted, line)
      end
      
      table.insert(formatted, '')
    elseif msg.role == 'assistant' then
      table.insert(formatted, '## Assistant')
      table.insert(formatted, '')
      
      local content_lines = {}
      for line in msg.content:gmatch('[^\r\n]+') do
        table.insert(content_lines, line)
      end
      
      if #content_lines == 0 then
        table.insert(content_lines, msg.content)
      end
      
      for _, line in ipairs(content_lines) do
        table.insert(formatted, line)
      end
      
      table.insert(formatted, '')
      table.insert(formatted, '---')
      table.insert(formatted, '')
    end
  end
  
  return formatted
end

return ChatManager

