local AppManager = require('cursor.app_manager')

local M = {}
M.app_manager = nil

function M.setup(opts)
  opts = opts or {}
  
  M.app_manager = AppManager.new()
  M.app_manager.opts = opts
  
  M.app_manager:setup_commands()
  
  if opts.bindings ~= false then
    local binding_opts = {
      enabled = opts.bindings ~= false,
      chat = opts.bindings and opts.bindings.chat,
      diff = opts.bindings and opts.bindings.diff,
    }
    M.app_manager:setup_bindings(binding_opts)
  end
end

function M.open_chat()
  if not M.app_manager then
    error("cursor not initialized. Call require('cursor').setup() first.")
  end
  M.app_manager:open_chat()
end

function M.close()
  if M.app_manager then
    M.app_manager:close()
  end
end

function M.get_app_manager()
  return M.app_manager
end

return M

