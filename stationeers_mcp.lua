-- stationeers-mcp.nvim entry point
-- Loaded automatically by Neovim's plugin system

if vim.g.loaded_stationeers_mcp then
  return
end
vim.g.loaded_stationeers_mcp = true

require("stationeers_mcp").setup()
