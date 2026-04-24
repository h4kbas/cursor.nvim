local Commands = {}
Commands.__index = Commands

function Commands.new(app_manager)
  local self = setmetatable({}, Commands)
  self.app_manager = app_manager
  return self
end

function Commands:register()
  vim.api.nvim_create_user_command("CursorChat", function()
    self.app_manager:open_chat()
  end, {
    desc = "Open Cursor chat window",
  })

  vim.api.nvim_create_user_command("CursorClose", function()
    self.app_manager:close()
  end, {
    desc = "Close Cursor chat window",
  })

  vim.api.nvim_create_user_command("CursorStop", function()
    self.app_manager:stop_request()
  end, {
    desc = "Stop current cursor request",
  })

  vim.api.nvim_create_user_command("CursorSessionNew", function(opts)
    local name = opts.args
    if name == '' then
      name = nil
    end
    self.app_manager:new_session(name)
  end, {
    desc = "Create new cursor chat session",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CursorSessionManage", function()
    self.app_manager:manage_sessions()
  end, {
    desc = "Manage cursor chat sessions",
  })

  vim.api.nvim_create_user_command("CursorSessionDelete", function(opts)
    local id = opts.args
    if id == '' then
      local _, current_id = self.app_manager:list_sessions()
      id = current_id
    end
    self.app_manager:delete_session(id)
  end, {
    desc = "Delete cursor chat session",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CursorSessionSwitch", function(opts)
    local id = opts.args
    if id == '' then
      self.app_manager:manage_sessions()
      return
    end
    self.app_manager:switch_session(id)
  end, {
    desc = "Switch cursor chat session",
    nargs = "?",
  })
end

return Commands

