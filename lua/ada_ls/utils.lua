local M = {
  als = nil,
  plugin_name = "Ada_ls",
  server_project_name = nil,
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
  local bufid = M.get_bufid()
  local ls_name = "ada_ls"

  local clients = vim.lsp.get_clients({ bufnr = bufid, name = ls_name })

  if not clients or #clients == 0 then
    -- check if there is an ada language client configured for gpr
    ls_name = "gpr_ls"
    clients = vim.lsp.get_clients({ bufnr = bufid, name = ls_name })

    if not clients or #clients == 0 then
      return nil, "Ada LSP client not found"
    end
  end

  M.als = clients[1]
  return M.als
end

function M.get_conf_file()
  local root_dir = require("ada_ls.lsp_cmd").get_root_dir()
  if root_dir == nil then
    return nil
  end

  local conf_file = vim.fs.joinpath(root_dir, ".als.json")

  if vim.fn.filereadable(conf_file) ~= 1 then
    return nil
  end
  return conf_file
end

function M.get_subprogram_name_from_line(lnum)
  local symbols = require("ada_ls.lsp_cmd").get_symbols()
  if not symbols then
    return nil
  end

  for _, symbol in ipairs(symbols) do
    for _, child in ipairs(symbol.children or {}) do
      local range = child.range or child.selectionRange
      if
        range
        and range.start
        and range["end"]
        and range.start.line + 1 <= lnum
        and lnum <= range["end"].line + 1
      then
        return child.name,
          {
            start = {
              line = tonumber(range.start.line + 1),
              character = tonumber(range.start.character + 1),
            },
            end_ = {
              line = tonumber(range["end"].line + 1),
              character = tonumber(range["end"].character + 1),
            },
          }
      end
    end
  end

  return nil
end

local function set_server_project_name(params)
  if
    params
    and params.settings
    and params.settings.ada
    and params.settings.ada.projectFile
  then
    M.server_project_name = vim.fs.basename(params.settings.ada.projectFile)
  end
end

function M.get_server_project_name()
  return M.server_project_name
end

function M.notify_server(method, params)
  local client = M.get_ada_ls()
  if client ~= nil then
    set_server_project_name(params)
    return client:notify(method, params)
  end
  return false
end

function M.reset_als_client()
  M.clear()
  for _, client in pairs(vim.lsp.get_clients({ name = "ada_ls" })) do
    client.stop(client, true)
  end
  vim.cmd("e") -- Reopen buffer to trigger LSP attach
end

function M.clear()
  M.als = nil
  M.server_project_name = nil
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._log_lvl_tostring = log_lvl_tostring
end

return M
