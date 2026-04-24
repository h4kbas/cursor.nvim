# cursor.nvim

A Neovim plugin that connects Neovim to Cursor's agent via **ACP (Agent Client Protocol)**, providing a Cursor‑like chat and code‑editing experience inside Neovim.

<img width="1470" height="879" alt="Screenshot 2026-03-18 at 07 15 28" src="https://github.com/user-attachments/assets/b6a9ffbf-62d2-48dd-a785-6b618531af22" />


**Note**: This project is still ongoing and under active development!

## Features

### Working Features

- **Chat Interface**: Two‑buffer layout with read‑only history on the right and a modifiable input buffer, optimized for chatting while keeping your code visible.
- **Streaming Responses**: Real‑time, token‑by‑token streaming of AI responses using Cursor's ACP implementation (`agent acp`), very close to how Cursor desktop behaves.
- **ACP Integration**: Uses Cursor's ACP server instead of the old `cursor-agent` streaming protocol, with a small JSON‑RPC client implemented in Lua.
- **File & Terminal Tools**: Implements ACP filesystem and terminal methods so the agent can read/write files and run commands in your Neovim project (when you allow it).
- **Permission Prompts**: Neovim UI prompt for `session/request_permission` where you can choose `allow-once`, `allow-always`, or `reject-once` for tool calls and commands.
- **Change View (Current Batch)**: When a response includes structured edits (via code blocks), the plugin shows a quickfix list of changed files and lets you apply or revert them with simple keybinds.
- **Status Indicators**: Lightweight status line in the chat buffer showing whether the agent is idle, processing, streaming, or stopped.
- **Configurable Chat Layout**: `chat_width` and bindings can be customized from `require('cursor').setup(...)` to match your Neovim UI preferences.
- **Cursor CLI Integration**: Relies on the official Cursor CLI (`agent`) so you use the same models, settings, and MCP configuration as in Cursor desktop.

## Installation

Using lazy.nvim:

```lua
require('cursor').setup({
  chat_width = 50,                            -- Width of chat window
  model = 'auto',                             -- Model to use (optional, default: 'auto')
  bindings = {                                -- Keybinding configuration
    chat = {
      send_message = "<CR>",
      close = "q",
      stop = "<C-c>",
    },
  },
})
```

**Prerequisites**: 
- Neovim 0.7+
- Cursor Agent CLI installed (https://cursor.com/blog/cli). The plugin uses Cursor's official CLI which automatically uses your Cursor subscription - no additional costs!
