-- stationeers_mcp/ui.lua
-- Floating windows, log panel, chip picker

local M = {}

--- Open a scratch buffer in a centred floating window.
--- Returns { buf, win }
function M.float(opts)
  opts = opts or {}
  local width  = opts.width  or math.floor(vim.o.columns * 0.75)
  local height = opts.height or math.floor(vim.o.lines   * 0.70)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype    = opts.filetype or "lua"
  vim.bo[buf].bufhidden   = "wipe"
  vim.bo[buf].swapfile    = false
  vim.bo[buf].modifiable  = opts.modifiable ~= false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = opts.title and (" " .. opts.title .. " ") or nil,
    title_pos = "center",
  })
  vim.wo[win].wrap       = opts.wrap ~= false
  vim.wo[win].cursorline = true
  vim.wo[win].number     = opts.number ~= false

  -- q or <Esc> closes the window
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })

  return { buf = buf, win = win, close = close }
end

--- Write lines into a buffer (handles modifiable flag).
function M.set_lines(buf, lines, filetype)
  local ok = pcall(function()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if filetype then vim.bo[buf].filetype = filetype end
    vim.bo[buf].modifiable = false
  end)
  return ok
end

--- Small ephemeral notification (uses vim.notify).
function M.info(msg)  vim.notify("[stationeers-mcp] " .. msg, vim.log.levels.INFO)  end
function M.warn(msg)  vim.notify("[stationeers-mcp] " .. msg, vim.log.levels.WARN)  end
function M.error(msg) vim.notify("[stationeers-mcp] " .. msg, vim.log.levels.ERROR) end

--- Simple telescope-free picker using vim.ui.select.
--- @param items   table   list of items
--- @param display function(item) -> string
--- @param on_choice function(item)
function M.pick(items, display, on_choice)
  if #items == 0 then
    M.warn("No items to pick from")
    return
  end
  vim.ui.select(items, {
    prompt = "Stationeers MCP",
    format_item = display,
  }, function(choice)
    if choice then on_choice(choice) end
  end)
end

--- Open a readonly floating window showing JSON/text content.
function M.show_result(title, content, filetype)
  filetype = filetype or "json"
  local lines
  if type(content) == "table" then
    local encoded = vim.json.encode(content)
    -- Pretty-print via jq if available, else indent manually
    lines = vim.split(vim.fn.system("jq . <<< " .. vim.fn.shellescape(encoded)), "\n")
    if vim.v.shell_error ~= 0 then
      lines = vim.split(encoded, "\n")
    end
  else
    lines = vim.split(tostring(content), "\n")
  end

  local f = M.float({
    title    = title,
    filetype = filetype,
    modifiable = false,
    width  = math.min(120, vim.o.columns - 4),
    height = math.min(#lines + 4, math.floor(vim.o.lines * 0.8)),
  })
  M.set_lines(f.buf, lines, filetype)
end

--- Open a log-style floating window with append support.
--- Returns a table with :append(line) and :close()
function M.log_window(title, max_lines)
  max_lines = max_lines or 200
  local f = M.float({
    title    = title,
    filetype = "log",
    modifiable = true,
    number = false,
  })
  vim.bo[f.buf].modifiable = true

  local obj = { buf = f.buf, win = f.win }

  function obj:append(line)
    if not vim.api.nvim_buf_is_valid(self.buf) then return end
    vim.schedule(function()
      vim.bo[self.buf].modifiable = true
      local count = vim.api.nvim_buf_line_count(self.buf)
      if count >= max_lines then
        vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, {})
        count = count - 1
      end
      vim.api.nvim_buf_set_lines(self.buf, count, -1, false, { line })
      if vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_set_cursor(self.win, { count + 1, 0 })
      end
    end)
  end

  function obj:close()
    f.close()
  end

  return obj
end

--- Show the Hub dashboard (static overview of commands).
function M.hub_dashboard(cfg_host, cfg_port, state)
  local lines = {
    "╭─────────────────────────────────────────────────────────────────╮",
    "│              StationeersLua MCP Hub — Neovim                   │",
    "╰─────────────────────────────────────────────────────────────────╯",
    "",
    string.format("  Endpoint : http://%s:%d/mcp", cfg_host, cfg_port),
    string.format("  Status   : %s", state.connected and "● connected" or "○ disconnected"),
    string.format("  Chip     : %s", state.current_chip_ref or "(none selected)"),
    "",
    "─────────────────────  Commands  ────────────────────────────────",
    "",
    "  :McpConnect              — Handshake with the game server",
    "  :McpDisconnect           — Drop connection state",
    "  :McpChipList             — List chips on current network",
    "  :McpChipSelect           — Pick active chip interactively",
    "  :McpPushBuffer           — Push current buffer → active chip",
    "  :McpPullChip             — Pull active chip → new buffer",
    "  :McpPatchChip            — Diff-push: only changed lines",
    "  :McpChipErrors           — Show errors for active chip",
    "  :McpChipLogs             — Stream print() log for active chip",
    "  :McpEditorState          — Show in-game editor state",
    "  :McpGameState            — Show world/time info",
    "  :McpDevices              — List network devices",
    "  :McpSearchDocs <query>   — Search embedded documentation",
    "  :McpHub                  — Re-open this dashboard",
    "",
    "─────────────────────  Keymaps  ─────────────────────────────────",
    "",
    "  <leader>mh  Open hub         <leader>mp  Push buffer",
    "  <leader>mr  Pull chip        <leader>ml  Chip list",
    "  <leader>me  Chip errors      <leader>mg  Chip logs",
    "  <leader>ms  Game state       <leader>md  Search docs",
    "  <leader>mk  Patch chip",
    "",
    "  q / <Esc>  close this window",
    "",
  }

  local f = M.float({
    title      = "MCP Hub",
    filetype   = "markdown",
    modifiable = false,
    width      = 70,
    height     = #lines + 2,
    number     = false,
    wrap       = false,
  })
  M.set_lines(f.buf, lines, "markdown")

  -- Syntax highlights
  vim.api.nvim_buf_call(f.buf, function()
    vim.cmd([[
      syntax match McpHeader /╭.*╮\|│.*│\|╰.*╯/
      syntax match McpSection /─.*─/
      syntax match McpCmd /\v:\w+/
      syntax match McpKey /<[^>]+>/
      syntax match McpConnected /● connected/
      syntax match McpDisconn /○ disconnected/
      highlight McpHeader    guifg=#7f77dd
      highlight McpSection   guifg=#3f3f46
      highlight McpCmd       guifg=#58a6ff
      highlight McpKey       guifg=#3fb950
      highlight McpConnected guifg=#3fb950
      highlight McpDisconn   guifg=#888780
    ]])
  end)
end

return M
