local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_states = require("telescope.actions.state")
local conf = require("telescope.config").values

local ada_ls_conf_path = ""
local project_file = ""
local scenario_variables = {}
local scenario_vars_string = ""

local function get_path(str)
  return str:match("(.*[/\\])")
end

local function als_root_dir(startpath)
  local gpr_file = vim.fs.find(function(name)
    return name:match(".*%.gpr$")
  end, { upward = true })[1]
  local gpr_path = vim.fs.dirname(gpr_file)

  if gpr_path then
    ada_ls_conf_path = gpr_path
  else
    if vim.fn.isdirectory(".git") == 0 then
      ada_ls_conf_path = vim.fs.dirname(startpath)
    else
      ada_ls_conf_path = startpath
    end
  end

  return ada_ls_conf_path
end

local function notify_configuration_change(config)
  -- Set the new config and notify the language server
  vim.notify_once(
    "Ada_ls configuration:\n" .. vim.inspect(config) .. "\n",
    vim.log.levels.INFO
  )
  local client = assert(vim.lsp.get_clients({ name = "ada" })[1])
  config = { ada = config }
  client:notify("workspace/didChangeConfiguration", { settings = config })
end

local function save_new_configuration(root_dir, config)
  local path = root_dir .. ".als.json"
  local file_exists = vim.loop.fs_stat(path) ~= nil

  if not file_exists then
    local file = io.open(path, "w")
    if not file then
      vim.notify_once(
        "Could not save Ada_ls configuration at " .. path,
        vim.log.levels.ERROR
      )
      return
    end
    file:write(vim.json.encode(config))
  else
    vim.notify_once(
      "Ada_ls configuration saved at " .. path,
      vim.log.levels.INFO
    )
  end
end

local function set_scenario_var()
  if project_file == "" then
    return
  end

  for line in io.lines(project_file) do
    for _ in string.gmatch(line, "external") do
      local match = string.match(line, '[^"%s]+", "[^%s]+"')
      match = string.gsub(match, '"', "")
      local var = {}
      for w in string.gmatch(match, "([^, ]+)") do
        table.insert(var, w)
      end
      scenario_variables[var[1]] = var[2]
    end
  end
end

local function create_config(config)
  config["projectFile"] = project_file
  if next(scenario_variables) ~= nil then
    config["scenarioVariables"] = scenario_variables
  end
end

local function save_and_notify_config()
  if project_file == "" then
    vim.notify_once("No Ada project file selected.", vim.log.levels.WARN)
    return
  end

  local project_file_path = get_path(project_file)
  local json_file = project_file_path .. ".als.json"
  local file_exists = vim.loop.fs_stat(json_file) ~= nil
  local config = {}

  if not file_exists then
    create_config(config)
    save_new_configuration(project_file_path, config)
  else
    vim.notify_once("Custom config found", vim.log.levels.INFO)
    config = vim.fn.json_decode(vim.fn.readfile(json_file))
  end

  notify_configuration_change(config)
end

local function pick_project_file(files)
  local opts = {}
  local files_number = #files

  if files_number == 0 then
    vim.notify_once(
      "No Ada project files found in the current directory.",
      vim.log.levels.WARN
    )
    return
  elseif files_number == 1 then
    print("Only one Ada project file found: " .. files[1])
    project_file = files[1]
    set_scenario_var()
    save_and_notify_config()
  else
    pickers
      .new(opts, {
        prompt_title = "Ada project files picker",
        finder = finders.new_table({ results = files }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_buffer, _)
          actions.select_default:replace(function()
            actions.close(prompt_buffer)
            local selection = action_states.get_selected_entry()
            project_file = selection[1]
            set_scenario_var()
            save_and_notify_config()
          end)
          return true
        end,
      })
      :find()
  end
end

local function detect_project_files(root_dir)
  return vim.fs.find(function(name, _)
    return name:match(".*%.gpr$")
  end, { path = root_dir, limit = 10, type = "file" })
end

local function decode_json_config(json_config)
  if json_config["projectFile"] then
    project_file = json_config["projectFile"]
  end
  if json_config["scenarioVariables"] then
    for k, v in pairs(json_config["scenarioVariables"]) do
      scenario_vars_string = scenario_vars_string
        .. "-X"
        .. k
        .. "="
        .. tostring(v)
        .. "\\ "
    end
  end
end

local function makeprg_setup()
  if project_file == "" then
    vim.notify_once("No Ada project file selected.", vim.log.levels.WARN)
    return
  end
  vim.cmd(
    "set makeprg=gprbuild\\ "
      .. "\\ -d\\ -p\\ "
      .. scenario_vars_string
      .. "\\ -P\\ "
      .. project_file
  )
end

function M.setup()
  if vim.opt.diff:get() then
    return
  end

  local utils = require("ada_ls.utils")

  if utils.get_ada_ls() == nil then
    return
  end

  ada_ls_conf_path = als_root_dir()
  print(ada_ls_conf_path)

  local path = ada_ls_conf_path .. "/.als.json"
  local file = io.open(path, "r")

  if file then
    local json_config = vim.json.decode(file:read("*a"))
    decode_json_config(json_config)
    notify_configuration_change(json_config)
  else
    pick_project_file(detect_project_files(ada_ls_conf_path))
  end
  makeprg_setup()
  vim.notify_once(
    "Configuration loaded at " .. ada_ls_conf_path,
    vim.log.levels.INFO
  )
end

return M
