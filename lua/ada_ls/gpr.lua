local M = {}

function M.clean()
  local conf_file = require("ada_ls.utils").get_conf_file()
  if conf_file == nil then
    vim.notify_once("No configugation file found", vim.log.levels.WARN)
    return
  end
  local prj_file = require("ada_ls.project").decode_json_config(conf_file)
  if prj_file == "" then
    vim.notify_once("No Ada project file selected.", vim.log.levels.WARN)
    return
  end
  vim.cmd("!gprclean " .. " -r -P " .. prj_file)
end

local function gprbuild_cmd()
  local conf_file = require("ada_ls.utils").get_conf_file()
  if conf_file == nil then
    vim.notify_once("No configugation file found", vim.log.levels.WARN)
    return
  end

  local prj_file, scenar_vars =
    require("ada_ls.project").decode_json_config(conf_file)
  if prj_file == "" then
    vim.notify_once("No Ada project file selected.", vim.log.levels.WARN)
    return
  end
  return ("gprbuild " .. " -d -p -gnatef " .. scenar_vars .. "-P " .. prj_file)
end

function M.makeprg_setup()
  local cmd = gprbuild_cmd()
  if cmd == nil then
    return
  end
  vim.cmd("let &makeprg='" .. cmd .. "'")
  -- set your gprbuild errorformat once
  local err_format = table.concat({
    "%f:%l:%c: %t%*[^:]: %m",
    "%f:%l: %t%*[^:]: %m",
    "%f:%l:%c: %m",
    "%f:%l: %m",
    "%*[^:]: %f:%l:%c: %m",
    "%*[^:]: %f:%l: %m",
    "%-G%.%#",
  }, ",")
  vim.cmd("let &errorformat='" .. err_format .. "'")
end

-- auto-open quickfix only when :make produced entries
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = "make",
  callback = function()
    if #vim.fn.getqflist() > 0 then
      vim.cmd("copen")
    end
  end,
})

return M
