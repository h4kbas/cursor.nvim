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
- **Permission Prompts with Context**: Permission requests show command/tool details in both chat and the selection dialog, so approvals are easier to review.
- **Live Activity Feed**: Chat shows a live activity line for tool progress (pending/in_progress/completed), including extra context like target file/cwd when available.
- **Affected Files Panel**: Chat includes an embedded affected files list gathered from tool activity.
- **Jump to Affected Files**: In chat history, place cursor on an affected file line and press `<CR>` or `gf` to open it in a regular editor window.
- **Change View (Current Batch)**: When a response includes structured edits (via code blocks), the plugin shows a quickfix list of changed files and lets you apply or revert them with simple keybinds.
- **Status Indicators**: Lightweight status line in the chat buffer showing whether the agent is idle, processing, streaming, or stopped.
- **Project-Persistent Sessions**: Chat history is persisted per project, with support for multiple sessions and session switching.
- **Configurable Chat Layout & Bindings**: `chat_width` and bindings can be customized from `require('cursor').setup(...)` to match your Neovim UI preferences.
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
      focus_toggle = "<C-]>",                 -- Toggle focus between input and readonly history
    },
  },
})
```

## Commands

- `:CursorChat` - Open chat window
- `:CursorClose` - Close chat window
- `:CursorStop` - Stop current request
- `:CursorSessionManage` - Open session picker (new/switch)
- `:CursorSessionNew [name]` - Create and switch to a new session
- `:CursorSessionSwitch [session_id]` - Switch session (without args opens picker)
- `:CursorSessionDelete [session_id]` - Delete session (without args deletes current)

## Default Keybindings

- Input buffer:
  - `<CR>` send message
  - `<C-c>` stop current request
  - `<C-]>` focus readonly history buffer
- History (readonly) buffer:
  - `q` close chat
  - `<CR>` open affected file under cursor
  - `gf` open affected file under cursor
  - `<C-]>` focus input buffer

**Prerequisites**: 
- Neovim 0.7+
- Cursor CLI installed ([Cursor CLI](https://cursor.com/blog/cli)) with `agent` available in `PATH`. The plugin uses your existing Cursor account/settings.
