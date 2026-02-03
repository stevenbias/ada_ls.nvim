local M = {}

M.plugin_name = "Ada_ls"

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
  if M.is_loaded("notify") then
    require("notify")(msg, lvl, { title = title })
  else
    vim.notify(title .. ": " .. msg, lvl)
  end
end

function M.is_loaded(plugin_name)
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

return M
