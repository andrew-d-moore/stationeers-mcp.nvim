-- stationeers_mcp/init.lua
-- Public API: setup(), connect(), and all user-facing commands

local M = {}

local defaults = require("stationeers_mcp.config").defaults
local state    = require("stationeers_mcp.config").state

M.state = state  -- expose for statusline etc.

local function get_ops()
  return require("stationeers_mcp.ops")
end

local function get_ui()
  return require("stationeers_mcp.ui")
end

-- ── Setup ─────────────────────────────────────────────────────────────────

--- @param opts table|nil  Override any field in defaults
function M.setup(opts)
  M.cfg = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Inject config/state into ops and statusline
  local ops = require("stationeers_mcp.ops")
  ops._cfg   = M.cfg
  ops._state = state

  local sl = require("stationeers_mcp.statusline")
  sl._state = state

  M._register_commands()
  M._register_keymaps()

  if M.cfg.auto_connect then
    -- Defer until VimEnter so the UI is ready
    vim.api.nvim_create_autocmd("VimEnter", {
      once     = true,
      callback = function() ops.connect() end,
    })
  end

  -- Autocmd: when saving a stationeers:// buffer, auto-push
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern  = "stationeers://*.lua",
    callback = function()
      ops.push_buffer()
      vim.bo.modified = false
    end,
  })
end

-- ── Commands ──────────────────────────────────────────────────────────────

function M._register_commands()
  local cmd = vim.api.nvim_create_user_command

  cmd("McpConnect", function()
    get_ops().connect()
  end, { desc = "Connect to StationeersLua MCP server" })

  cmd("McpDisconnect", function()
    get_ops().disconnect()
  end, { desc = "Disconnect from MCP server" })

  cmd("McpHub", function()
    get_ui().hub_dashboard(M.cfg.host, M.cfg.port, state)
  end, { desc = "Open MCP Hub dashboard" })

  cmd("McpChipList", function()
    get_ops().list_chips()
  end, { desc = "List chips on current network" })

  cmd("McpChipSelect", function()
    get_ops().chip_select()
  end, { desc = "Interactively select active chip" })

  cmd("McpPullChip", function()
    get_ops().pull_chip()
  end, { desc = "Pull active chip source into buffer" })

  cmd("McpPushBuffer", function()
    get_ops().push_buffer()
  end, { desc = "Push current buffer to active chip (compile)" })

  cmd("McpPatchChip", function()
    get_ops().patch_chip()
  end, { desc = "Diff-push current buffer to active chip" })

  cmd("McpPushEditor", function()
    get_ops().push_editor()
  end, { desc = "Stage current buffer in IC editor draft" })

  cmd("McpChipErrors", function()
    get_ops().chip_errors()
  end, { desc = "Show chip errors in quickfix" })

  cmd("McpChipLogs", function()
    get_ops().chip_logs()
  end, { desc = "Stream chip print() logs" })

  cmd("McpEditorState", function()
    get_ops().get_editor_state()
  end, { desc = "Show in-game editor state" })

  cmd("McpGameState", function()
    get_ops().game_state()
  end, { desc = "Show game world/time state" })

  cmd("McpDevices", function()
    get_ops().get_devices()
  end, { desc = "List network devices" })

  cmd("McpAllDevices", function()
    get_ops().get_all_devices()
  end, { desc = "List all network devices across all networks" })

  cmd("McpReadDevice", function(a)
    local args = vim.split(a.args, "%s+")
    get_ops().read_device_value(args[1], args[2])
  end, { nargs = "*", desc = "Read device logic value: <ref_id> <LogicType>" })

  cmd("McpSearchDocs", function(a)
    get_ops().search_docs(a.args)
  end, { nargs = "*", desc = "Search embedded StationeersLua documentation" })

  cmd("McpDebugSession", function()
    get_ops().debug_session()
  end, { desc = "Show VS Code debugger session state for active chip" })

  cmd("McpDebugStack", function()
    get_ops().debug_stack()
  end, { desc = "Show stack trace for paused chip" })
end

-- ── Keymaps ───────────────────────────────────────────────────────────────

function M._register_keymaps()
  local km = M.cfg.keymaps
  if not km then return end

  local function map(lhs, rhs, desc)
    if lhs and lhs ~= false then
      vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
    end
  end

  map(km.open_hub,    "<cmd>McpHub<cr>",         "MCP: open hub dashboard")
  map(km.push_buffer, "<cmd>McpPushBuffer<cr>",  "MCP: push buffer → chip")
  map(km.pull_chip,   "<cmd>McpPullChip<cr>",    "MCP: pull chip → buffer")
  map(km.chip_list,   "<cmd>McpChipList<cr>",    "MCP: list chips")
  map(km.chip_errors, "<cmd>McpChipErrors<cr>",  "MCP: chip errors → quickfix")
  map(km.chip_logs,   "<cmd>McpChipLogs<cr>",    "MCP: stream chip logs")
  map(km.game_state,  "<cmd>McpGameState<cr>",   "MCP: game state")
  map(km.patch_chip,  "<cmd>McpPatchChip<cr>",   "MCP: patch chip")
  map(km.search_docs, function()
    local q = vim.fn.input("Docs search: ")
    if q ~= "" then
      get_ops().search_docs(q)
    end
  end, "MCP: search docs")
end

-- ── Public API ────────────────────────────────────────────────────────────

--- Direct access to ops for scripting.
M.connect       = function() get_ops().connect()       end
M.disconnect    = function() get_ops().disconnect()    end
M.push_buffer   = function() get_ops().push_buffer()   end
M.pull_chip     = function() get_ops().pull_chip()     end
M.patch_chip    = function() get_ops().patch_chip()    end
M.chip_select   = function() get_ops().chip_select()   end
M.chip_errors   = function() get_ops().chip_errors()   end
M.chip_logs     = function() get_ops().chip_logs()     end
M.game_state    = function() get_ops().game_state()    end
M.search_docs   = function(q) get_ops().search_docs(q) end

return M
