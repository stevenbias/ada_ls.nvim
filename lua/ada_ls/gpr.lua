local M = {}

function M.clean()
  local notify = require("ada_ls.utils").notify
  local conf_file = require("ada_ls.utils").get_conf_file()
  if conf_file == nil then
    notify("No configuration file found", vim.log.levels.WARN)
    return
  end
  local prj_file = require("ada_ls.project").decode_json_config(conf_file)
  if not prj_file then
    notify("No Ada project file selected.", vim.log.levels.WARN)
    return
  end
  vim.system({ "gprclean", "-r", "-P", prj_file }, {
    cwd = vim.fn.getcwd(),
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        notify("Clean failed: " .. result.stderr, vim.log.levels.ERROR)
      else
        notify("Clean successful", vim.log.levels.INFO)
      end
    end)
  end)
end

---@param json_config? table Pre-decoded .als.json content to avoid redundant I/O
local function gprbuild_cmd(json_config)
  local notify = require("ada_ls.utils").notify
  local prj_file, scenar_vars

  if json_config then
    prj_file = json_config["projectFile"]
    scenar_vars = ""
    if json_config["scenarioVariables"] then
      for k, v in pairs(json_config["scenarioVariables"]) do
        scenar_vars = scenar_vars .. " -X" .. k .. "=" .. tostring(v)
      end
    end
  else
    local conf_file = require("ada_ls.utils").get_conf_file()
    if conf_file == nil then
      notify("No configuration file found", vim.log.levels.WARN)
      return nil
    end
    prj_file, scenar_vars =
      require("ada_ls.project").decode_json_config(conf_file)
  end

  if not prj_file then
    notify("No Ada project file selected.", vim.log.levels.WARN)
    return nil
  end
  return ("gprbuild" .. " -d -p -gnatef" .. scenar_vars .. " -P " .. prj_file)
end

---@param json_config? table Pre-decoded .als.json content to avoid redundant I/O
function M.makeprg_setup(json_config)
  local cmd = gprbuild_cmd(json_config)
  if cmd == nil then
    return
  end
  vim.o.makeprg = cmd

  local err_format = table.concat({
    "%f:%l:%c: %t%*[^:]: %m",
    "%f:%l: %t%*[^:]: %m",
    "%f:%l:%c: %m",
    "%f:%l: %m",
    "%*[^:]: %f:%l:%c: %m",
    "%*[^:]: %f:%l: %m",
    "%-G%.%#",
  }, ",")
  vim.o.errorformat = err_format
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._gprbuild_cmd = gprbuild_cmd
end

return M
