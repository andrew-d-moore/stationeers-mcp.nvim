-- stationeers_mcp/config.lua
-- Default configuration and runtime state

local M = {}

M.defaults = {
	host = "127.0.0.1",
	port = 3030,
	-- Auto-connect on startup
	auto_connect = false,
	-- Keymaps (set to false to disable)
	keymaps = {
		open_hub = "<leader>mh",
		push_buffer = "<leader>mp",
		pull_chip = "<leader>mr",
		chip_select = "<leader>mc",
		chip_list = "<leader>ml",
		chip_errors = "<leader>me",
		chip_logs = "<leader>mg",
		game_state = "<leader>ms",
		search_docs = "<leader>md",
		patch_chip = "<leader>mk",
	},
	-- Signs used in the floating log window
	log = {
		max_lines = 500,
	},
	log_poll_ms = 500, -- chip log polling interval in milliseconds
}

-- Runtime state (not user config)
M.state = {
	connected = false,
	server_info = nil,
	current_chip_ref = nil,
	chips = {},
}

return M
