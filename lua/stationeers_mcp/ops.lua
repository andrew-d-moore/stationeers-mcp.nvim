-- stationeers_mcp/ops.lua
-- All MCP tool calls: chip management, devices, docs, debug

local http = require("stationeers_mcp.http")
local ui = require("stationeers_mcp.ui")

local M = {}

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

-- ── Envelope unwrapper ────────────────────────────────────────────────────
-- The server wraps every tool result as:
--   { content = { { type = "text", text = "<json string>" } } }
-- This decodes the inner JSON and returns the Lua value.

local function unwrap(r)
	if type(r) ~= "table" then
		return r
	end

	-- Server uses two envelope shapes depending on the tool:
	--   array:  { content = { { type="text", text="..." } } }
	--   plain:  { content = { type="text", text="..." } }
	local text
	if type(r.content) == "table" then
		if r.content[1] and r.content[1].text then
			text = r.content[1].text -- array envelope
		elseif r.content.text then
			text = r.content.text -- plain table envelope
		end
	end

	if type(text) ~= "string" then
		return r
	end

	local ok, decoded = pcall(vim.json.decode, text)
	if not ok then
		return r
	end
	if type(decoded) == "string" then
		local ok2, decoded2 = pcall(vim.json.decode, decoded)
		if ok2 then
			return decoded2
		end
	end
	return decoded
end

-- ── Tool call helper ──────────────────────────────────────────────────────
-- unwrap() is called here so every callback receives clean data automatically.

local function tool(name, args, on_ok, on_err)
	rpc("tools/call", { name = name, arguments = args or {} }, function(err, result)
		if err then
			ui.error(name .. ": " .. err)
			if on_err then
				on_err(err)
			end
		else
			if on_ok then
				on_ok(unwrap(result))
			end
		end
	end)
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

-- ── Editor & Chip ─────────────────────────────────────────────────────────

function M.get_editor_state()
	tool("get_editor_state", {}, function(r)
		ui.show_result("Editor State", r, "json")
	end)
end

function M.list_chips(callback)
	tool("list_chips", {}, function(r)
		-- r may still be a JSON string if the server double-encodes
		if type(r) == "string" then
			local ok, decoded = pcall(vim.json.decode, r)
			if ok then
				r = decoded
			end
		end

		local chips = {}
		if type(r) == "table" then
			if vim.islist(r) then
				chips = r
			elseif r.chips and vim.islist(r.chips) then
				chips = r.chips
			end
		end
		state().chips = chips
		if callback then
			callback(chips)
		else
			ui.show_result("Chip List", chips, "json")
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

		-- Build flat string labels and a lookup map so vim.ui.select
		-- works correctly regardless of which UI plugin is installed.
		local labels = {}
		local by_label = {}
		for _, c in ipairs(chips) do
			local ref = tostring(type(c) == "table" and (c.ref_id or c.ref) or c)
			local name = type(c) == "table" and (c.housing_name or c.name or ref) or ref
			local label = string.format("%s  [%s]", name, ref)
			table.insert(labels, label)
			by_label[label] = c
		end

		vim.ui.select(labels, { prompt = "Select chip:" }, function(label)
			if not label then
				return
			end
			local c = by_label[label]
			local ref = tostring(type(c) == "table" and (c.ref_id or c.ref) or c)
			local name = type(c) == "table" and (c.housing_name or c.name or ref) or ref
			state().current_chip_ref = ref
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
		local code
		if type(r) == "string" then
			code = r
		elseif type(r) == "table" then
			code = r.source or r.code or vim.inspect(r)
		else
			code = tostring(r)
		end
		local bufname = "stationeers://" .. tostring(ref) .. ".lua"
		-- Reuse existing buffer if already open, otherwise create a new one
		local buf = vim.fn.bufnr(bufname)
		if buf == -1 then
			buf = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_buf_set_name(buf, bufname)
		end
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].buftype = ""
		vim.bo[buf].modified = false
		vim.api.nvim_set_current_buf(buf)
		ui.info("Pulled chip " .. tostring(ref))
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
	tool("set_chip_code", { ref_id = ref, source = code }, function(r)
		local ok = type(r) == "table" and r.ok
		ui.info("Pushed to chip " .. tostring(ref) .. (ok and " — compiled OK" or ""))
		-- Sync the in-game IC editor draft so it reflects the pushed source
		tool("set_editor_code", { source = code }, function(_) end)
	end)
end

--- patch_chip: uses vim.diff to compute line-level hunks and sends only changed
--- regions via patch_chip_code. Falls back to push_buffer on any failure.
function M.patch_chip()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected — run :McpChipSelect first")
		return
	end
	tool("get_chip_code", { ref_id = ref }, function(r)
		local remote
		if type(r) == "string" then
			remote = r
		elseif type(r) == "table" then
			remote = r.source or r.code or ""
		else
			remote = ""
		end
		remote = remote:gsub("\r\n", "\n"):gsub("\r", "\n")

		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local local_ = table.concat(lines, "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")

		if remote == local_ then
			ui.info("No changes — chip source matches server exactly")
			return
		end
		-- Show a diff summary so you know what's being sent
		vim.notify(
			string.format("[stationeers-mcp] remote=%d bytes  local=%d bytes", #remote, #local_),
			vim.log.levels.DEBUG
		)

		-- Build line-level replacements using vim.diff
		local replacements = {}
		local ok, hunks = pcall(vim.diff, remote, local_, { result_type = "indices" })
		if ok and hunks and #hunks > 0 then
			local remote_lines = vim.split(remote, "\n")
			local local_lines = vim.split(local_, "\n")
			for _, hunk in ipairs(hunks) do
				-- hunk = { ra, rc, ba, bc } (start line, count for each side, 1-indexed)
				local ra, rc, ba, bc = hunk[1], hunk[2], hunk[3], hunk[4]
				local old_chunk = {}
				for i = ra, ra + rc - 1 do
					table.insert(old_chunk, remote_lines[i] or "")
				end
				local new_chunk = {}
				for i = ba, ba + bc - 1 do
					table.insert(new_chunk, local_lines[i] or "")
				end
				local old_str = table.concat(old_chunk, "\n")
				local new_str = table.concat(new_chunk, "\n")
				if old_str ~= new_str and old_str ~= "" then
					table.insert(replacements, { old = old_str, new = new_str })
				end
			end
		end

		if #replacements == 0 then
			-- Diff produced no actionable hunks — fall back to full push
			ui.info("Falling back to full push")
			M.push_buffer()
			return
		end

		tool("patch_chip_code", { ref_id = ref, replacements = replacements }, function(res)
			local err = type(res) == "table" and res.error
			if err then
				ui.warn("Patch failed (" .. tostring(err) .. "), falling back to full push")
				M.push_buffer()
			else
				ui.info("Patched chip " .. tostring(ref) .. " (" .. #replacements .. " hunk(s))")
				-- Sync the in-game IC editor draft so it reflects the patched source
				tool("set_editor_code", { source = local_ }, function(_) end)
			end
		end)
	end)
end

--- Set the in-game editor draft (no compile).
function M.push_editor()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local code = table.concat(lines, "\n")
	tool("set_editor_code", { source = code }, function(_)
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
		if type(r) ~= "table" then
			ui.info("No error info for chip " .. tostring(ref))
			return
		end
		-- Response is a single object: { last_error_message, last_error_line, has_runtime, ... }
		if not r.last_error_message and not r.error_code then
			ui.info("No errors on chip " .. tostring(ref))
			return
		end
		local line = r.last_error_line or 0
		local msg = r.last_error_message or r.error_code or "unknown error"
		-- Strip colour tags from error_code e.g. <color=red>Unknown</color>
		msg = msg:gsub("<[^>]+>", "")
		local qf = { { lnum = line, col = 0, text = msg, type = "E" } }
		if r.last_error_traceback and r.last_error_traceback ~= "" then
			table.insert(qf, { lnum = 0, col = 0, text = r.last_error_traceback, type = "W" })
		end
		vim.fn.setqflist(qf, "r")
		vim.fn.setqflist({}, "a", { title = "Stationeers chip errors: " .. tostring(ref) })
		vim.cmd("copen")
		ui.info("Error at line " .. tostring(line) .. " loaded into quickfix")
	end)
end

--- Stream chip logs into a floating log window, polling every 2s.
function M.chip_logs()
	local ref = state().current_chip_ref
	if not ref then
		ui.warn("No chip selected")
		return
	end

	local win = ui.log_window("Chip Logs — " .. tostring(ref), 300)
	local since = 0
	local timer = vim.loop.new_timer()

	local function fetch()
		if not vim.api.nvim_buf_is_valid(win.buf) then
			timer:stop()
			timer:close()
			return
		end
		tool("get_chip_logs", { ref_id = ref, since_revision = since }, function(r)
			if not r or type(r) ~= "table" then
				return
			end
			-- Response: { log_text = "line1\nline2\n...", log_revision = N, has_logs = bool }
			if r.has_logs and r.log_text then
				-- Only show new lines since last revision
				if r.log_revision and r.log_revision ~= since then
					local lines = vim.split(r.log_text, "\n", { plain = true })
					for _, line in ipairs(lines) do
						if line ~= "" then
							win:append(line)
						end
					end
					since = r.log_revision
				end
			end
		end)
	end

	fetch()
	timer:start(cfg().log_poll_ms or 500, cfg().log_poll_ms or 500, vim.schedule_wrap(fetch))

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
	if not ref_id or ref_id == "" then
		ref_id = vim.fn.input("Device ref ID: ")
	end
	if not logic_type or logic_type == "" then
		logic_type = vim.fn.input("LogicType (e.g. Pressure): ")
	end
	tool("read_device_value", { ref_id = ref_id, logic_type = logic_type }, function(r)
		ui.show_result("Device Value", r, "json")
	end)
end

-- ── World ─────────────────────────────────────────────────────────────────

function M.game_state()
	tool("get_game_state", {}, function(r)
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
		ui.show_result("Docs: " .. query, r, "json")
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
