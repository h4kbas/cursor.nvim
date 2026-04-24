local BindingManager = {}
BindingManager.__index = BindingManager

function BindingManager.new(app_manager)
  local self = setmetatable({}, BindingManager)
  self.app_manager = app_manager
  self.default_bindings = {
    chat = {
      send_message = "<CR>",
      send_message_insert = "<C-CR>",
      close = "q",
      stop = "<C-c>",
    },
    diff = {
      apply = "a",
      revert = "r",
      close = "q",
    },
  }
  self.bindings = {}
  self.enabled = true
  return self
end

function BindingManager:setup(opts)
  opts = opts or {}
  
  if opts.enabled == false then
    self.enabled = false
    return
  end

  self.enabled = true
  
  self.bindings = {
    chat = vim.tbl_extend("force", self.default_bindings.chat, opts.chat or {}),
    diff = vim.tbl_extend("force", self.default_bindings.diff, opts.diff or {}),
  }
end

function BindingManager:register_chat_bindings(window_manager)
  if not self.enabled or not self.bindings.chat then
    return
  end

  local app_mgr = self.app_manager
  local input_bufnr = window_manager.input_bufnr
  local chat_bufnr = window_manager.chat_bufnr

  if not input_bufnr or not chat_bufnr then
    return
  end

  local function close_chat()
    app_mgr:close()
  end

  if self.bindings.chat.close then
    vim.keymap.set('n', self.bindings.chat.close, close_chat, {
      buffer = chat_bufnr,
      desc = "cursor chat: close",
      silent = true,
      noremap = true,
    })
  end

  local function open_affected_file()
    app_mgr:open_affected_file_under_cursor()
  end

  vim.keymap.set('n', '<CR>', open_affected_file, {
    buffer = chat_bufnr,
    desc = "cursor chat: open affected file",
    silent = true,
    noremap = true,
  })

  vim.keymap.set('n', 'gf', open_affected_file, {
    buffer = chat_bufnr,
    desc = "cursor chat: go to affected file",
    silent = true,
    noremap = true,
  })

  vim.keymap.set('i', '<CR>', function()
    local message = window_manager:get_user_input()
    
    if message ~= '' and not message:match('^%s*$') then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      vim.schedule(function()
        app_mgr:handle_send_message(message)
      end)
      return
    end
    
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
  end, {
    buffer = input_bufnr,
    desc = "cursor chat: send message or newline",
    silent = true,
    noremap = true,
  })
  
  if self.bindings.chat.close then
    vim.keymap.set('n', self.bindings.chat.close, close_chat, {
      buffer = input_bufnr,
      desc = "cursor chat: close",
      silent = true,
      noremap = true,
    })
  end

  if self.bindings.chat.stop then
    local function stop_request()
      app_mgr:stop_request()
    end
    vim.keymap.set('n', self.bindings.chat.stop, stop_request, {
      buffer = input_bufnr,
      desc = "cursor chat: stop request",
      silent = true,
      noremap = true,
    })
    vim.keymap.set('i', self.bindings.chat.stop, function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      vim.schedule(function()
        app_mgr:stop_request()
      end)
    end, {
      buffer = input_bufnr,
      desc = "cursor chat: stop request",
      silent = true,
      noremap = true,
    })
  end
end

function BindingManager:register_diff_bindings(bufnr)
  if not self.enabled or not self.bindings.diff then
    return
  end

  local function apply_changes()
    self.app_manager:apply_changes()
  end

  local function revert_changes()
    self.app_manager:revert_changes()
  end

  local function close_diff()
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  local commands = {
    apply = apply_changes,
    revert = revert_changes,
    close = close_diff,
  }

  for action, keymap in pairs(self.bindings.diff) do
    if commands[action] then
      vim.keymap.set("n", keymap, commands[action], {
        buffer = bufnr,
        desc = "cursor diff: " .. action,
        silent = true,
        noremap = true,
      })
    end
  end
end

function BindingManager:register_all_bindings(window_manager)
  if not window_manager then
    return
  end

  if window_manager.chat_bufnr and window_manager.input_bufnr then
    self:register_chat_bindings(window_manager)
  end
end

function BindingManager:register_diff_bindings_for_buffer(bufnr)
  if bufnr then
    self:register_diff_bindings(bufnr)
  end
end

function BindingManager:add_custom_binding(window_type, keymap, action, desc)
  if not self.enabled then
    return
  end

  if not self.bindings[window_type] then
    self.bindings[window_type] = {}
  end

  local bufnr = nil
  if window_type == "chat" and self.app_manager.window_manager then
    bufnr = self.app_manager.window_manager.chat_bufnr
  elseif window_type == "diff" then
    return
  end

  if bufnr then
    vim.keymap.set("n", keymap, action, {
      buffer = bufnr,
      desc = desc or "cursor custom",
      silent = true,
      noremap = true,
    })
  end
end

function BindingManager:get_bindings()
  return vim.deepcopy(self.bindings)
end

return BindingManager

