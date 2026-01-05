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
end

return Commands

