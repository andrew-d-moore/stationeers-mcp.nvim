-- stationeers_mcp/ops.lua
-- All MCP tool calls: chip management, devices, docs, debug

local http = require("stationeers_mcp.http")
local ui = require("stationeers_mcp.ui")

local M = {}

-- Will be injected by init.lua
M._cfg = nil
M._state = nil

local function cfg()
	return M._cfg
end
local function state()
	return M._state
end

local function rpc(method, params, cb)
	http.rpc(cfg(), method, params, cb)
end

-- ── Connection ────────────────────────────────────────────────────────────

function M.connect(callback)
	http.rpc(cfg(), "initialize", {
		protocolVersion = "2024-11-05",
		clientInfo = { name = "stationeers-mcp.nvim", version = "1.0.0" },
		capabilities = {},
	}, function(err, result)
		if err then
			state().connected = false
			ui.error("Connect failed: " .. err)
			if callback then
				callback(false)
			end
		else
			state().connected = true
			state().server_info = result
			local name = (result and result.serverInfo and result.serverInfo.name) or "unknown"
			ui.info("Connected to " .. name)
			if callback then
				callback(true)
			end
		end
	end)
end

function M.disconnect()
	state().connected = false
	state().server_info = nil
	state().current_chip_ref = nil
	state().chips = {}
	ui.info("Disconnected")
end

-- ── Tool call helper ──────────────────────────────────────────────────────

local function tool(name, args, on_ok, on_err)
	rpc("tools/call", { name = name, arguments = args or {} }, function(err, result)
		if err then
			ui.error(name .. ": " .. err)
			if on_err then
				on_err(err)
			end
		else
			if on_ok then
				on_ok(result)
			end
		end
	end)
end

-- ── Editor & Chip ─────────────────────────────────────────────────────────

function M.get_editor_state()
	tool("get_editor_state", {}, function(r)
		ui.show_result("Editor State", r, "json")
	end)
end

function M.list_chips(callback)
	tool("list_chips", {}, function(r)
		local chips = (r and r.chips) or {}
		state().chips = chips
		if callback then
			callback(chips)
		else
			ui.show_result("Chip List", r, "json")
		end
	end)
end

--- Interactively pick a chip and set it as the active chip.
function M.chip_select()
	M.list_chips(function(chips)
		if #chips == 0 then
			ui.warn("No chips found on network")
			return
		end
		ui.pick(chips, function(c)
			local ref = type(c) == "table" and (c.ref or c.ref_id) or tostring(c)
			local name = type(c) == "table" and (c.name or ref) or ref
			return string.format("[%s]  %s", ref, name)
		end, function(choice)
			local ref = type(choice) == "table" and (choice.ref or choice.ref_id) or tostring(choice)
			state().current_chip_ref = ref
			local name = type(choice) == "table" and (choice.name or ref) or ref
			ui.info("Active chip → " .. name .. " (" .. ref .. ")")
		end)
	end)
end

--- Pull active chip source into a new buffer.
function M.pull_chip()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected — run :McpChipSelect first")
		return
	end
	tool("get_chip_code", { ref_id = ref }, function(r)
		local code = (r and r.code) or tostring(r)
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].buftype = ""
		vim.api.nvim_buf_set_name(buf, "stationeers://" .. ref .. ".lua")
		vim.api.nvim_set_current_buf(buf)
		ui.info("Pulled chip " .. ref)
	end)
end

--- Push current buffer contents to the active chip (compiles immediately).
function M.push_buffer()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected — run :McpChipSelect first")
		return
	end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local code = table.concat(lines, "\n")
	tool("set_chip_code", { ref_id = ref, code = code }, function(r)
		ui.info("Pushed to chip " .. ref .. (r and r.ok and " — compiled OK" or ""))
	end)
end

--- Diff-push: send only changed substrings using patch_chip_code.
function M.patch_chip()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected — run :McpChipSelect first")
		return
	end
	-- Fetch current chip source, diff against buffer, build replacements
	tool("get_chip_code", { ref_id = ref }, function(r)
		local remote = (r and r.code) or ""
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local local_ = table.concat(lines, "\n")

		if remote == local_ then
			ui.info("No changes — chip source is already up to date")
			return
		end

		-- Simple whole-file replacement via patch (substring = entire old code)
		-- For a smarter diff you could integrate vim.diff() here
		local replacements = { { old = remote, new = local_ } }
		tool("patch_chip_code", { ref_id = ref, replacements = replacements }, function(pr)
			ui.info("Patched chip " .. ref)
		end)
	end)
end

--- Set the in-game editor draft (no compile).
function M.push_editor()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local code = table.concat(lines, "\n")
	tool("set_editor_code", { code = code }, function()
		ui.info("Staged in IC editor draft")
	end)
end

-- ── Errors & Logs ─────────────────────────────────────────────────────────

function M.chip_errors()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected")
		return
	end
	tool("get_chip_errors", { ref_id = ref }, function(r)
		local errors = (r and r.errors) or {}
		if #errors == 0 then
			ui.info("No errors on chip " .. ref)
			return
		end

		-- Also populate quickfix list
		local qf = {}
		for _, e in ipairs(errors) do
			table.insert(qf, {
				lnum = e.line or 0,
				col = 0,
				text = e.message or tostring(e),
				type = "E",
			})
		end
		vim.fn.setqflist(qf, "r")
		vim.fn.setqflist({}, "a", { title = "Stationeers chip errors: " .. ref })
		vim.cmd("copen")
		ui.info(#errors .. " error(s) loaded into quickfix")
	end)
end

--- Stream chip logs into a floating log window, polling every 2s.
function M.chip_logs()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected")
		return
	end

	local win = ui.log_window("Chip Logs — " .. ref, 300)
	local since = 0
	local timer = vim.loop.new_timer()

	local function fetch()
		if not vim.api.nvim_buf_is_valid(win.buf) then
			timer:stop()
			timer:close()
			return
		end
		tool("get_chip_logs", { ref_id = ref, since_revision = since }, function(r)
			if not r then
				return
			end
			local logs = r.logs or {}
			for _, line in ipairs(logs) do
				win:append(line)
			end
			if r.revision then
				since = r.revision
			end
		end)
	end

	fetch()
	timer:start(2000, 2000, vim.schedule_wrap(fetch))

	-- Stop timer when the window closes
	vim.api.nvim_buf_attach(win.buf, false, {
		on_detach = function()
			timer:stop()
			timer:close()
		end,
	})
end

-- ── Device & Network ──────────────────────────────────────────────────────

function M.get_devices()
	tool("get_network_devices", {}, function(r)
		ui.show_result("Network Devices", r, "json")
	end)
end

function M.get_all_devices()
	tool("get_all_network_devices", {}, function(r)
		ui.show_result("All Network Devices", r, "json")
	end)
end

function M.read_device_value(ref_id, logic_type)
	if not ref_id then
		ref_id = vim.fn.input("Device ref ID: ")
	end
	if not logic_type then
		logic_type = vim.fn.input("LogicType (e.g. Pressure): ")
	end
	tool("read_device_value", { ref_id = ref_id, logic_type = logic_type }, function(r)
		ui.show_result("Device Value", r, "json")
	end)
end

-- ── World ─────────────────────────────────────────────────────────────────

function M.game_state()
	tool("get_game_state", {}, function(r)
		local lines = {
			"  World : " .. (r and r.world or "?"),
			"  Time  : " .. (r and r.time or "?"),
			"  Tick  : " .. tostring(r and r.tick or "?"),
		}
		ui.show_result("Game State", r, "json")
	end)
end

function M.search_docs(query)
	if not query or query == "" then
		query = vim.fn.input("Search docs: ")
	end
	if query == "" then
		return
	end
	tool("search_docs", { query = query }, function(r)
		ui.show_result("Docs: " .. query, r, "markdown")
	end)
end

-- ── Debug (requires EnableExtensionApi) ───────────────────────────────────

function M.debug_session(ref_id)
	ref_id = ref_id or state().current_chip_ref
	if not ref_id then
		ui.warn("No chip selected")
		return
	end
	tool("get_debug_session_state", { ref_id = ref_id }, function(r)
		ui.show_result("Debug Session", r, "json")
	end)
end

function M.debug_stack(ref_id)
	ref_id = ref_id or state().current_chip_ref
	if not ref_id then
		ui.warn("No chip selected")
		return
	end
	tool("get_debug_stack_trace", { ref_id = ref_id }, function(r)
		ui.show_result("Stack Trace", r, "json")
	end)
end

return M
