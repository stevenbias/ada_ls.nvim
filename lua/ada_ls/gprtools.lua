local M = {}

local function scenario_args(json_config)
  local variables = json_config and json_config.scenarioVariables or {}
  local names = {}
  for name in pairs(variables) do
    table.insert(names, name)
  end
  table.sort(names)

  local args = {}
  for _, name in ipairs(names) do
    table.insert(args, "-X" .. name .. "=" .. tostring(variables[name]))
  end
  return args
end

function M.clean()
  local notify = require("ada_ls.utils").notify
  local conf_file = require("ada_ls.utils").get_conf_file()
  if conf_file == nil then
    notify("No configuration file found", vim.log.levels.WARN)
    return
  end
  local prj_file, _, json_config =
    require("ada_ls.project").decode_json_config(conf_file)
  if not prj_file then
    notify("No Ada project file selected.", vim.log.levels.WARN)
    return
  end
  local args = { "gprclean", "-r", "-P", prj_file }
  vim.list_extend(args, scenario_args(json_config))
  vim.system(args, {
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
  local prj_file

  if json_config then
    prj_file = json_config["projectFile"]
  else
    local conf_file = require("ada_ls.utils").get_conf_file()
    if conf_file == nil then
      notify("No configuration file found", vim.log.levels.WARN)
      return nil
    end
    local _
    prj_file, _, json_config =
      require("ada_ls.project").decode_json_config(conf_file)
  end

  if not prj_file then
    notify("No Ada project file selected.", vim.log.levels.WARN)
    return nil
  end
  local args = { "gprbuild", "-d", "-p", "-gnatef" }
  vim.list_extend(args, scenario_args(json_config))
  vim.list_extend(args, { "-P", prj_file })
  for i, arg in ipairs(args) do
    -- Quote each argument so spaces and shell syntax remain literal.
    -- The true flag also protects % and # from expansion by :make.
    -- It adds a backslash before ! too. :make leaves that backslash in the
    -- argument, so remove it here to preserve the original value.
    args[i] = vim.fn.shellescape(arg, true):gsub("\\!", "!")
  end
  return table.concat(args, " ")
end

---@param json_config? table Pre-decoded .als.json content to avoid redundant I/O
function M.makeprg_setup(json_config)
  local cmd = gprbuild_cmd(json_config)
  if cmd == nil then
    return
  end

  local err_format = table.concat({
    "%f:%l:%c: %m",
    "%-G%.%#",
  }, ",")

  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("AdaMakeCmd", { clear = true }),
    pattern = { "*.ad[bs]", "*.gpr" },
    callback = function()
      vim.bo.makeprg = cmd
      vim.bo.errorformat = err_format
    end,
  })

  vim.bo.makeprg = cmd
  vim.bo.errorformat = err_format
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._gprbuild_cmd = gprbuild_cmd
end

return M
