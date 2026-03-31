-- stationeers_mcp/http.lua
-- Async HTTP using curl (no external deps required)

local M = {}

local _req_id = 0
local function next_id()
  _req_id = _req_id + 1
  return _req_id
end

--- Send a JSON-RPC request to the MCP server.
--- @param cfg        table  { host, port }
--- @param method     string  JSON-RPC method
--- @param params     table   method params
--- @param callback   function(err: string|nil, result: any)
function M.rpc(cfg, method, params, callback)
  local payload = vim.json.encode({
    jsonrpc = "2.0",
    id = next_id(),
    method = method,
    params = params or {},
  })

  local url = string.format("http://%s:%d/mcp", cfg.host, cfg.port)

  local stdout_chunks = {}
  local stderr_chunks = {}

  local job = vim.fn.jobstart({
    "curl",
    "--silent",
    "--show-error",
    "--max-time", "10",
    "--connect-timeout", "3",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
    "-d", payload,
    url,
  }, {
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stdout_chunks, chunk)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stderr_chunks, chunk)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local err = table.concat(stderr_chunks, " ")
        return callback("curl error (exit " .. code .. "): " .. err, nil)
      end
      local raw = table.concat(stdout_chunks, "")
      if raw == "" then
        return callback("empty response from server", nil)
      end
      local ok, decoded = pcall(vim.json.decode, raw)
      if not ok then
        return callback("JSON decode error: " .. tostring(decoded), nil)
      end
      if decoded.error then
        return callback(decoded.error.message or "RPC error", nil)
      end
      callback(nil, decoded.result)
    end,
  })

  if job <= 0 then
    callback("failed to start curl — is it installed?", nil)
  end
end

--- Blocking version for use in synchronous contexts (uses vim.fn.system).
--- @param cfg    table
--- @param method string
--- @param params table
--- @return string|nil err, any result
function M.rpc_sync(cfg, method, params)
  local payload = vim.json.encode({
    jsonrpc = "2.0",
    id = next_id(),
    method = method,
    params = params or {},
  })
  local url = string.format("http://%s:%d/mcp", cfg.host, cfg.port)

  local cmd = string.format(
    "curl --silent --show-error --max-time 10 --connect-timeout 3 "
    .. "-X POST -H 'Content-Type: application/json' -H 'Accept: application/json' "
    .. "-d %s %s",
    vim.fn.shellescape(payload),
    vim.fn.shellescape(url)
  )
  local raw = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return "curl error (exit " .. vim.v.shell_error .. "): " .. raw, nil
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    return "JSON decode error: " .. tostring(decoded), nil
  end
  if decoded.error then
    return decoded.error.message or "RPC error", nil
  end
  return nil, decoded.result
end

return M
