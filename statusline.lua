-- stationeers_mcp/statusline.lua
-- Provides a statusline component other plugins / lualine can consume.

local M = {}

M._state = nil  -- injected by init

--- Returns a short string suitable for a statusline segment.
--- Example output: " MCP ● PressureCtrl"
function M.component()
  local state = M._state
  if not state then return "" end
  if not state.connected then
    return "%#Comment# MCP ○%#Normal#"
  end
  local chip = state.current_chip_ref or ""
  if chip == "" then
    return "%#String# MCP ●%#Normal#"
  end
  return "%#String# MCP ● " .. chip .. "%#Normal#"
end

--- lualine component table — use in lualine sections like:
---   require("lualine").setup({ sections = { lualine_x = { require("stationeers_mcp.statusline").lualine } } })
M.lualine = {
  function()
    local state = M._state
    if not state or not state.connected then return "MCP ○" end
    local chip = state.current_chip_ref or ""
    return "MCP ● " .. (chip ~= "" and chip or "no chip")
  end,
  color = function()
    local state = M._state
    if state and state.connected then
      return { fg = "#3fb950" }
    end
    return { fg = "#888780" }
  end,
}

return M
