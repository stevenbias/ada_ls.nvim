local M = {
  als = nil,
  plugin_name = "Ada_ls",
}

local LOG_LEVELS = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
local function log_lvl_tostring(lvl)
  return LOG_LEVELS[lvl] or "ERROR"
end

function M.notify(msg, lvl)
  local title = M.plugin_name .. " " .. log_lvl_tostring(lvl) .. " message"
  if M.try_require("notify") then
    require("notify")(msg, lvl, { title = title })
  else
    vim.notify(title .. ": " .. msg, lvl)
  end
end

function M.try_require(plugin_name)
  return pcall(require, plugin_name) -- will also load the package if it isn't loaded already
end

function M.get_bufid()
  return vim.api.nvim_get_current_buf()
end

function M.get_bufpath()
  return vim.fn.expand("%")
end

function M.get_filename()
  return vim.fs.basename(M.get_bufpath())
end

function M.get_bufdir()
  return vim.fs.dirname(M.get_bufpath())
end

function M.get_ada_ls()
  if M.als ~= nil then
    return M.als
  end

  local clients = vim.lsp.get_clients({ name = "ada" })
  if not clients or #clients == 0 then
    return nil, "Ada LSP client not found"
  else
    M.als = clients[1]
    return M.als
  end
end

function M.get_conf_file()
  local root_dir = require("ada_ls.lsp_cmd").get_root_dir()
  if root_dir == nil then
    return
  end

  return root_dir .. "/.als.json"
end

function M.notify_server(method, params)
  local client = M.get_ada_ls()
  if client ~= nil then
    return client:notify(method, params)
  end
  return false
end

function M.reset_als_client()
  M.clear()
  for _, client in pairs(vim.lsp.get_clients({ name = "ada" })) do
    client:stop(true)
  end
  vim.defer_fn(function()
    vim.cmd("e") -- Reopen buffer to trigger LSP attach
  end, 100)
end

function M.clear()
  M.als = nil
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._log_lvl_tostring = log_lvl_tostring
end

return M
