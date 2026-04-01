# stationeers-mcp.nvim

A Neovim plugin that connects to the **StationeersLua MCP server** running
inside your game client, giving you full chip read/write, log streaming, error
inspection, and documentation search — without leaving your editor.

## Requirements

- Neovim ≥ 0.9
- `curl` on your `$PATH`
- StationeersLua mod with `Enabled = true` in `[MCP Server]` config (port 3030)

## Installation

### lazy.nvim

```lua
{
  "andrew-d-moore/stationeers-mcp.nvim",
  config = function()
    require("stationeers_mcp").setup({
      host = "127.0.0.1",
      port = 3030,
      auto_connect = false,         -- set true to connect on startup
      keymaps = {
        open_hub    = "<leader>mh",
        push_buffer = "<leader>mp",
        pull_chip   = "<leader>mr",
        chip_list   = "<leader>ml",
        chip_errors = "<leader>me",
        chip_logs   = "<leader>mg",
        game_state  = "<leader>ms",
        search_docs = "<leader>md",
        patch_chip  = "<leader>mk",
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "andrew-d-moore/stationeers-mcp.nvim",
  config = function()
    require("stationeers_mcp").setup()
  end,
}
```

### vim-plug / manual

```vim
Plug 'andrew-d-moore/stationeers-mcp.nvim'
```
Then in `init.lua`:
```lua
require("stationeers_mcp").setup()
```

## Commands

| Command | Description |
|---|---|
| `:McpConnect` | Handshake with the game MCP server |
| `:McpDisconnect` | Drop connection state |
| `:McpHub` | Open dashboard window |
| `:McpChipList` | List chips on the current network |
| `:McpChipSelect` | Interactively pick the active chip |
| `:McpPullChip` | Pull active chip source into a new buffer |
| `:McpPushBuffer` | Push current buffer → active chip (compiles) |
| `:McpPatchChip` | Diff-push current buffer (uses `patch_chip_code`) |
| `:McpPushEditor` | Stage buffer in IC editor draft (no compile) |
| `:McpChipErrors` | Load chip errors into the quickfix list |
| `:McpChipLogs` | Stream `print()` output in a floating window |
| `:McpEditorState` | Show current in-game editor selection |
| `:McpGameState` | Show world name, time, tick |
| `:McpDevices` | List devices on current data network |
| `:McpAllDevices` | List all networks and devices |
| `:McpReadDevice <ref> <LogicType>` | Read a logic value from a device |
| `:McpSearchDocs [query]` | Full-text search across embedded docs |
| `:McpDebugSession` | Show VS Code debugger session state |
| `:McpDebugStack` | Show stack trace for paused chip |

## Typical Workflow

```
:McpConnect          → handshake
:McpChipSelect       → pick PressureCtrl
:McpPullChip         → opens stationeers://chip_abc.lua in a buffer
[edit the file]
:McpPushBuffer       → compiles and exports to chip immediately
:McpChipErrors       → any errors → quickfix
:McpChipLogs         → floating live log window (polls every 2s)
```

Saving a `stationeers://...` buffer (`:w`) automatically calls `:McpPushBuffer`.

## Statusline / lualine

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_x = {
      require("stationeers_mcp.statusline").lualine,
    },
  },
})
```

Shows `MCP ●` (green, with chip name) when connected, `MCP ○` (grey) when not.

## Configuration

```lua
require("stationeers_mcp").setup({
  host         = "127.0.0.1",
  port         = 3030,
  auto_connect = false,
  keymaps = {
    open_hub    = "<leader>mh",   -- set to false to disable
    push_buffer = "<leader>mp",
    pull_chip   = "<leader>mr",
    chip_list   = "<leader>ml",
    chip_errors = "<leader>me",
    chip_logs   = "<leader>mg",
    game_state  = "<leader>ms",
    search_docs = "<leader>md",
    patch_chip  = "<leader>mk",
  },
  log = {
    max_lines = 500,
  },
  log_poll_ms = 500, -- chip log polling interval in milliseconds
})
```

## Multiplayer Note

The HTTP listener only runs in non-dedicated game clients. On multiplayer
sessions the debug proxy uses in-game mod network messages — this plugin's
HTTP calls still target `localhost` in the local client.
