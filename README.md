# cursor.nvim

A Neovim plugin that brings Cursor IDE (using cursor-agent) integration into Neovim, featuring a chat interface with streaming responses.

**Note**: This project is still ongoing and under active development.

## Features

### Working Features

- **Chat Interface**: Two-buffer design with read-only history at the top and modifiable input at the bottom
- **Streaming Responses**: Real-time character-by-character streaming of AI responses, just like Cursor IDE
- **Status Indicators**: Visual indicators showing current state (processing, streaming, stopped, idle)
- **Cursor CLI Integration**: Uses Cursor's official CLI (`cursor-agent`) to leverage your Cursor subscription

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
- Cursor CLI installed (`cursor-agent` command). The plugin uses Cursor's official CLI (`cursor-agent`) which automatically uses your Cursor subscription - no additional costs!


Using packer.nvim:

```lua
use 'h4kbas/cursor.nvim'
```

Using vim-plug:

```vim
Plug 'h4kbas/cursor.nvim'
```