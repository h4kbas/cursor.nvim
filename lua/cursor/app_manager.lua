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
  self.session_store = nil
  self.session_store_path = nil
  self.current_session_id = nil
  self.request_queue = {}
  self.request_in_flight = false
  self.current_request = nil
  self.next_request_id = 1
  
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

function AppManager:_get_project_root()
  if self.cursor_manager then
    return self.cursor_manager:get_project_root(vim.fn.getcwd())
  end
  return vim.fn.getcwd()
end

function AppManager:_get_session_store_path()
  if self.session_store_path then
    return self.session_store_path
  end

  local root = self:_get_project_root() or vim.fn.getcwd()
  local project_key = vim.fn.fnamemodify(root, ':p')
  project_key = project_key:gsub('[^%w%._%-]', '_')
  local base_dir = vim.fn.stdpath('data') .. '/cursor.nvim/sessions'
  vim.fn.mkdir(base_dir, 'p')
  self.session_store_path = base_dir .. '/' .. project_key .. '.json'
  return self.session_store_path
end

function AppManager:_default_session_data()
  return {
    current_session_id = nil,
    sessions = {},
  }
end

function AppManager:_create_session(name)
  local now = os.time()
  local id = tostring(now) .. '_' .. tostring(math.random(1000, 9999))
  return {
    id = id,
    name = name or ('Session ' .. os.date('%Y-%m-%d %H:%M')),
    updated_at = now,
    acp_session_id = nil,
    state = {
      messages = {},
      last_sent_message = '',
      affected_files = {},
    },
  }
end

function AppManager:_ensure_session_store()
  if self.session_store then
    return
  end

  local path = self:_get_session_store_path()
  local store = self:_default_session_data()

  if vim.fn.filereadable(path) == 1 then
    local ok_read, lines = pcall(vim.fn.readfile, path)
    if ok_read and type(lines) == 'table' then
      local raw = table.concat(lines, '\n')
      if raw ~= '' then
        local ok_decode, decoded = pcall(vim.json.decode, raw)
        if ok_decode and type(decoded) == 'table' then
          if type(decoded.sessions) == 'table' then
            store.sessions = decoded.sessions
            for _, session in ipairs(store.sessions) do
              if type(session) == 'table' and session.acp_session_id == nil then
                session.acp_session_id = nil
              end
            end
          end
          if type(decoded.current_session_id) == 'string' then
            store.current_session_id = decoded.current_session_id
          end
        end
      end
    end
  end

  if #store.sessions == 0 then
    local initial = self:_create_session('Session 1')
    table.insert(store.sessions, initial)
    store.current_session_id = initial.id
  end

  if not store.current_session_id or store.current_session_id == '' then
    store.current_session_id = store.sessions[1].id
  end

  self.session_store = store
  self.current_session_id = store.current_session_id
end

function AppManager:_save_session_store()
  if not self.session_store then
    return
  end

  self.session_store.current_session_id = self.current_session_id
  local path = self:_get_session_store_path()
  local encoded = vim.json.encode(self.session_store)
  vim.fn.writefile({ encoded }, path)
end

function AppManager:_get_current_session()
  self:_ensure_session_store()
  for _, session in ipairs(self.session_store.sessions) do
    if session.id == self.current_session_id then
      return session
    end
  end
  return nil
end

function AppManager:_persist_current_session()
  local session = self:_get_current_session()
  if not session then
    return
  end
  if self.cursor_manager and session then
    session.acp_session_id = self.cursor_manager:get_active_session_id()
  end
  session.state = self.chat_manager:get_state()
  session.updated_at = os.time()
  self:_save_session_store()
end

function AppManager:_sync_queue_display(update_window)
  local session = self:_get_current_session()
  self.window_manager:set_panel_state({
    model = self.opts.model or 'auto',
    session_name = session and session.name or nil,
    affected_files = self.chat_manager:get_affected_files(),
    current_request = self.current_request,
    request_queue = self.request_queue,
  })
  if update_window and self.is_open then
    self.window_manager:update_chat_display(self.chat_manager)
  end
end

function AppManager:_load_current_session_into_chat()
  local session = self:_get_current_session()
  if not session then
    self.chat_manager:initialize()
    if self.cursor_manager then
      self.cursor_manager:set_active_session_id(nil)
    end
    return
  end
  if self.cursor_manager then
    self.cursor_manager:set_active_session_id(session.acp_session_id)
  end
  self.chat_manager:load_state(session.state or {})
  self:_sync_queue_display(false)
end

function AppManager:new_session(name)
  self:_ensure_session_store()
  self:_persist_current_session()

  local created = self:_create_session(name)
  table.insert(self.session_store.sessions, 1, created)
  self.current_session_id = created.id
  self:_load_current_session_into_chat()
  self:_save_session_store()

  if self.is_open then
    self.window_manager:update_chat_display(self.chat_manager)
    self.window_manager:focus_input()
  end
end

function AppManager:switch_session(session_id)
  if type(session_id) ~= 'string' or session_id == '' then
    return
  end

  self:_ensure_session_store()
  self:_persist_current_session()

  local found = false
  for _, session in ipairs(self.session_store.sessions) do
    if session.id == session_id then
      found = true
      break
    end
  end
  if not found then
    return
  end

  self.current_session_id = session_id
  self:_load_current_session_into_chat()
  self:_save_session_store()

  if self.is_open then
    self.window_manager:update_chat_display(self.chat_manager)
    self.window_manager:focus_input()
  end
end

function AppManager:delete_session(session_id)
  if type(session_id) ~= 'string' or session_id == '' then
    return
  end

  self:_ensure_session_store()
  local kept = {}
  for _, session in ipairs(self.session_store.sessions) do
    if session.id ~= session_id then
      table.insert(kept, session)
    end
  end
  self.session_store.sessions = kept

  if #self.session_store.sessions == 0 then
    local created = self:_create_session('Session 1')
    table.insert(self.session_store.sessions, created)
    self.current_session_id = created.id
  elseif self.current_session_id == session_id then
    self.current_session_id = self.session_store.sessions[1].id
  end

  self:_load_current_session_into_chat()
  self:_save_session_store()

  if self.is_open then
    self.window_manager:update_chat_display(self.chat_manager)
    self.window_manager:focus_input()
  end
end

function AppManager:list_sessions()
  self:_ensure_session_store()
  return self.session_store.sessions, self.current_session_id
end

function AppManager:manage_sessions()
  self:_ensure_session_store()
  self:_persist_current_session()

  local sessions, current_id = self:list_sessions()
  local entries = {}
  local map = {}

  table.insert(entries, '+ New session')
  map['+ New session'] = { action = 'new' }

  for _, session in ipairs(sessions) do
    local prefix = session.id == current_id and '* ' or '  '
    local label = prefix .. (session.name or session.id) .. ' [' .. session.id .. ']'
    table.insert(entries, label)
    map[label] = { action = 'switch', id = session.id }
  end

  vim.ui.select(entries, {
    prompt = 'Cursor sessions',
  }, function(choice)
    local selected = map[choice or '']
    if not selected then
      return
    end

    if selected.action == 'new' then
      vim.ui.input({ prompt = 'Session name: ' }, function(input)
        if input and input ~= '' then
          self:new_session(input)
        else
          self:new_session(nil)
        end
      end)
      return
    end

    if selected.action == 'switch' and selected.id then
      self:switch_session(selected.id)
    end
  end)
end

function AppManager:open_chat()
  if self.is_open then
    return
  end
  
  if not self.cursor_manager then
    self.cursor_manager = CursorManager.new(self.opts)
  end

  self.cursor_manager:set_permission_request_handler(function(content)
    self.chat_manager:add_message('assistant', content)
    self:_persist_current_session()
    self.window_manager:update_chat_display(self.chat_manager)
  end)
  self.cursor_manager:set_activity_update_handler(function(content, _, affected_files)
    self.chat_manager:add_affected_files(affected_files)
    self.chat_manager:upsert_activity_message(content)
    self:_persist_current_session()
    self:_sync_queue_display(false)
    self.window_manager:update_chat_display(self.chat_manager)
  end)
  
  self.window_manager.opts = self.opts
  
  self.window_manager:create_chat_window()
  self:_ensure_session_store()
  self:_load_current_session_into_chat()
  self.is_open = true
  self:_sync_queue_display(false)
  
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
  local conversation_context = self.chat_manager:get_conversation_context(
    self.opts.context_max_messages or 40,
    self.opts.context_max_chars or 12000
  )
  
  self.chat_manager:set_last_sent_message(message)
  self.chat_manager:clear_affected_files()
  self.chat_manager:add_message('user', message)
  self:_persist_current_session()
  self.window_manager:clear_input()
  self.window_manager:update_chat_display(self.chat_manager)
  vim.schedule(function()
    self.window_manager:focus_input()
  end)
  
  table.insert(self.request_queue, {
    id = self.next_request_id,
    message = message,
    conversation_context = conversation_context,
  })
  self.next_request_id = self.next_request_id + 1
  self:_sync_queue_display(true)

  self:_process_next_request()
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
  self:_persist_current_session()
  self.chat_manager:cleanup()
  self.is_open = false
end

function AppManager:open_affected_file_under_cursor()
  if not self.window_manager or not self.window_manager.chat_bufnr then
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local in_chat = current_buf == self.window_manager.chat_bufnr
  local in_affected = self.window_manager.affected_bufnr and current_buf == self.window_manager.affected_bufnr
  local in_queue = self.window_manager.queue_bufnr and current_buf == self.window_manager.queue_bufnr
  if not in_chat and not in_affected and not in_queue then
    return false
  end

  local line = vim.api.nvim_get_current_line()
  if line:match('^%-%s+%[') then
    return false
  end
  local path = line:match('^%-%s+(.+)$')
  if not path or path == '' then
    return false
  end

  if vim.fn.filereadable(path) ~= 1 and vim.fn.isdirectory(path) ~= 1 then
    return false
  end

  local chat_winid = self.window_manager.chat_winid
  local input_winid = self.window_manager.input_winid
  local target_winid = nil
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, winid in ipairs(wins) do
    if winid ~= chat_winid and winid ~= input_winid and vim.api.nvim_win_is_valid(winid) then
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg and (cfg.relative == nil or cfg.relative == '') then
        target_winid = winid
        break
      end
    end
  end

  if target_winid and vim.api.nvim_win_is_valid(target_winid) then
    vim.api.nvim_set_current_win(target_winid)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  else
    vim.cmd('leftabove vsplit ' .. vim.fn.fnameescape(path))
  end

  return true
end

function AppManager:cycle_focus_forward()
  if not self.window_manager then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local chat_win = self.window_manager.chat_winid
  local affected_win = self.window_manager.affected_winid
  local queue_win = self.window_manager.queue_winid
  local input_win = self.window_manager.input_winid

  local order = {
    chat_win,
    affected_win,
    queue_win,
    input_win,
  }

  local valid = {}
  for _, winid in ipairs(order) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      table.insert(valid, winid)
    end
  end

  if #valid == 0 then
    return
  end

  local idx = 0
  for i, winid in ipairs(valid) do
    if winid == current_win then
      idx = i
      break
    end
  end

  local next_idx = 1
  if idx > 0 then
    next_idx = (idx % #valid) + 1
  end
  local target = valid[next_idx]

  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
    if target == input_win then
      vim.api.nvim_win_set_cursor(input_win, {1, 0})
      vim.cmd('stopinsert')
      vim.defer_fn(function()
        vim.api.nvim_feedkeys('i', 'n', false)
      end, 10)
    else
      vim.cmd('stopinsert')
    end
  end
end


function AppManager:_process_next_request()
  if self.request_in_flight then
    return
  end

  local next_item = table.remove(self.request_queue, 1)
  if not next_item then
    self.current_request = nil
    self:_sync_queue_display(true)
    return
  end

  self.current_request = next_item
  self:_sync_queue_display(true)
  self:send_message(next_item)
end

function AppManager:send_message(message_or_item)
  local message = message_or_item
  local conversation_context = ''
  if type(message_or_item) == 'table' then
    message = message_or_item.message
    conversation_context = message_or_item.conversation_context or ''
  end

  self.request_in_flight = true

  self.chat_manager:set_status('processing')
  self.window_manager:update_chat_display(self.chat_manager)
  
  self.cursor_manager:send_chat_message(message, function(response, changes, streaming)
    if streaming then
      self.chat_manager:set_status('streaming')
      self.chat_manager:set_streaming_response(response)
      self.window_manager:update_chat_display_streaming(self.chat_manager, response)
    else
      local has_response = response and response ~= '' and not response:match('^%s*$')
      if has_response then
        self.chat_manager:add_message('assistant', response)
      end

      self.chat_manager:clear_streaming_response()
      self.chat_manager:set_status('idle')

      if changes and #changes > 0 then
        self.chat_manager:set_last_changes(changes)
        self:show_last_changes()
      end

      self:_persist_current_session()
      self.window_manager:update_chat_display(self.chat_manager)
      self.window_manager:focus_input()

      self.request_in_flight = false
      self.current_request = nil
      self:_sync_queue_display(true)
      self:_process_next_request()
    end
  end, {
    conversation_context = conversation_context,
  })
end


function AppManager:stop_request()
  if self.cursor_manager then
    local stopped = self.cursor_manager:stop()
    if stopped then
      self.request_in_flight = false
      self.current_request = nil
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
      self:_sync_queue_display(true)
      self:_process_next_request()
    end
    return stopped
  end
  return false
end

function AppManager:_queue_index_from_current_line()
  if not self.window_manager or not self.window_manager.chat_bufnr then
    return nil
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local in_chat = current_buf == self.window_manager.chat_bufnr
  local in_affected = self.window_manager.affected_bufnr and current_buf == self.window_manager.affected_bufnr
  local in_queue = self.window_manager.queue_bufnr and current_buf == self.window_manager.queue_bufnr
  if not in_chat and not in_affected and not in_queue then
    return nil
  end

  local line = vim.api.nvim_get_current_line()
  return tonumber(line:match('^%-%s+%[(%d+)%]%s+'))
end

function AppManager:cancel_queued_request_under_cursor()
  local idx = self:_queue_index_from_current_line()
  if not idx or idx < 1 or idx > #self.request_queue then
    return false
  end

  table.remove(self.request_queue, idx)
  self:_sync_queue_display(true)
  return true
end

function AppManager:move_queued_request_up_under_cursor()
  local idx = self:_queue_index_from_current_line()
  if not idx or idx <= 1 or idx > #self.request_queue then
    return false
  end

  self.request_queue[idx - 1], self.request_queue[idx] = self.request_queue[idx], self.request_queue[idx - 1]
  self:_sync_queue_display(true)
  return true
end

function AppManager:move_queued_request_down_under_cursor()
  local idx = self:_queue_index_from_current_line()
  if not idx or idx < 1 or idx >= #self.request_queue then
    return false
  end

  self.request_queue[idx + 1], self.request_queue[idx] = self.request_queue[idx], self.request_queue[idx + 1]
  self:_sync_queue_display(true)
  return true
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

function AppManager:show_last_changes()
  local last_changes = self.chat_manager:get_last_changes()
  if not last_changes or #last_changes == 0 then
    return
  end

  local qf_items = {}
  for _, change in ipairs(last_changes) do
    if change.type == 'edit' and change.file then
      local bufnr = vim.fn.bufnr(change.file, false)
      table.insert(qf_items, {
        bufnr = bufnr ~= -1 and bufnr or nil,
        filename = change.file,
        lnum = change.start_line or 1,
        col = 1,
        text = 'Cursor change: ' .. change.file,
      })
    end
  end
  
  if #qf_items == 0 then
    return
  end
  
  vim.fn.setqflist(qf_items, 'r', { title = 'Cursor Changes' })
  vim.cmd('botright copen')
  
  local info = vim.fn.getqflist({ winid = 1 })
  local winid = info.winid
  if winid ~= nil and winid ~= 0 and vim.api.nvim_win_is_valid(winid) then
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if self.binding_manager then
      self.binding_manager:register_diff_bindings_for_buffer(bufnr)
    end
  end
end

return AppManager

