# cursor.nvim

A Neovim plugin that connects Neovim to Cursor's agent via **ACP (Agent Client Protocol)**, providing a Cursor‑like chat and code‑editing experience inside Neovim.

<img width="1470" height="879" alt="Screenshot 2026-03-18 at 07 15 28" src="https://github.com/user-attachments/assets/b6a9ffbf-62d2-48dd-a785-6b618531af22" />


**Note**: This project is still ongoing and under active development!

## Features

### Working Features

- **Multi-Panel Chat UI**: Dedicated floating sections for `Chat`, `Affected Files`, `Queue`, and `Input` (with stable titled boxes).
- **Streaming Responses**: Real‑time, token‑by‑token streaming of AI responses using Cursor's ACP implementation (`agent acp`), very close to how Cursor desktop behaves.
- **ACP Integration**: Uses Cursor's ACP server instead of the old `cursor-agent` streaming protocol, with a small JSON‑RPC client implemented in Lua.
- **File & Terminal Tools**: Implements ACP filesystem and terminal methods so the agent can read/write files and run commands in your Neovim project (when you allow it).
- **Permission Prompts with Context**: Permission requests show command/tool details in both chat and the selection dialog, so approvals are easier to review.
- **Live Activity Feed**: Chat shows a live activity line for tool progress (pending/in_progress/completed), including extra context like target file/cwd when available.
- **Affected Files Panel**: Dedicated box populated from tool activity; file entries are jumpable.
- **Queue Panel + Controls**: Requests are queued serially and displayed in a dedicated queue box with reorder/cancel controls.
- **Focus Cycling**: `<C-]>` cycles across chat panes (`Chat -> Affected Files -> Queue -> Input`).
- **Model Indicator**: Active model label (`Auto`, etc.) is shown near input.
- **Image Attachments**: Pasted/drag-dropped image paths are captured and sent as ACP image attachments, while preserving free-form text prompting.
- **Change View (Current Batch)**: When a response includes structured edits (via code blocks), the plugin shows a quickfix list of changed files and lets you apply or revert them with simple keybinds.
- **Status Indicators**: Lightweight status line in the chat buffer showing whether the agent is idle, processing, streaming, or stopped.
- **Project-Persistent Sessions**: Chat history is persisted per project, with support for multiple sessions and session switching.
- **Real Session Mapping (UI <-> ACP)**: Each UI session stores its own backend ACP session binding, so switching sessions also switches backend context.
- **Configurable Chat Layout & Bindings**: `chat_width` and bindings can be customized from `require('cursor').setup(...)` to match your Neovim UI preferences.
- **Cursor CLI Integration**: Relies on the official Cursor CLI (`agent`) so you use the same models, settings, and MCP configuration as in Cursor desktop.

## Installation

Using lazy.nvim:

```lua
require('cursor').setup({
  chat_width = 50,                            -- Width of chat window
  model = 'auto',                             -- Model to use (optional, default: 'auto')
  ui = {
    input_height = 3,                         -- Input panel height
    affected_height = 4,                      -- Affected Files panel height
    queue_height = 4,                         -- Queue panel height
    section_gap = 2,                          -- Vertical gap between boxed sections
    show_chat_title = true,                   -- Show Chat title
    show_input_title = true,                  -- Show Input title
    show_affected_title = true,               -- Show Affected Files title
    show_queue_title = true,                  -- Show Queue title
    show_model_indicator = true,              -- Show model label near input
    auto_hide_affected_when_empty = false,    -- Hide Affected Files box when empty
    auto_hide_queue_when_empty = false,       -- Hide Queue box when empty
  },
  bindings = {                                -- Keybinding configuration
    chat = {
      send_message = "<CR>",
      close = "q",
      stop = "<C-c>",
      focus_toggle = "<C-]>",                 -- Cycle focus across chat panes
      open_item = "<CR>",                     -- Open item under cursor (files)
      open_item_alt = "gf",                   -- Alternative open key
      queue_cancel = "X",                     -- Cancel queued request under cursor
      queue_move_up = "<C-k>",                -- Move queued request up
      queue_move_down = "<C-j>",              -- Move queued request down
    },
  },
})
```

### UI Options

- `ui.input_height`: input panel height
- `ui.affected_height`: affected files panel height
- `ui.queue_height`: queue panel height
- `ui.section_gap`: spacing between boxed panes
- `ui.show_chat_title`: show/hide chat window title
- `ui.show_input_title`: show/hide input window title
- `ui.show_affected_title`: show/hide affected files title
- `ui.show_queue_title`: show/hide queue title
- `ui.show_model_indicator`: show/hide model label in input area
- `ui.auto_hide_affected_when_empty`: hide affected files panel when empty
- `ui.auto_hide_queue_when_empty`: hide queue panel when empty

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
  - `<C-]>` cycle focus (`Chat -> Affected Files -> Queue -> Input`)
- Chat / Affected Files / Queue buffers:
  - `q` close chat
  - `<CR>` open affected file under cursor
  - `gf` open affected file under cursor
  - `X` cancel queued request under cursor (`Queue` entries like `- [n] ...`)
  - `<C-k>` move queued request up
  - `<C-j>` move queued request down
  - `<C-]>` cycle focus (`Chat -> Affected Files -> Queue -> Input`)

**Prerequisites**: 
- Neovim 0.7+
- Cursor CLI installed ([Cursor CLI](https://cursor.com/blog/cli)) with `agent` available in `PATH`. The plugin uses your existing Cursor account/settings.
