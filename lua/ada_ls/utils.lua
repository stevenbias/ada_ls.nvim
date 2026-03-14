local M = {
  als = nil,
  plugin_name = "Ada_ls",
}

local function log_lvl_tostring(lvl)
  if lvl == 0 then
    return "TRACE"
  elseif lvl == 1 then
    return "DEBUG"
  elseif lvl == 2 then
    return "INFO"
  elseif lvl == 3 then
    return "WARN"
  elseif lvl == 4 then
    return "ERROR"
  elseif lvl == 5 then
    return "OFF"
  else
    return "ERROR"
  end
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

  local info = ""
  local debug_info = debug.getinfo(2)

  if debug_info then
    info = debug_info.name
  end

  local clients = vim.lsp.get_clients({ name = "ada" })
  if not clients or #clients == 0 then
    M.notify("Ada LSP client not found for " .. info, vim.log.levels.WARN)
    return nil
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

return M
