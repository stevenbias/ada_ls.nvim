local M = {
  is_setup = false,
  project_file = "",
  scenario_variables = {},
}

local function get_abspath(str)
  local abspath = vim.fs.abspath(str)
  return abspath:match("(.*[/\\])")
end

local function als_root_dir(startpath)
  local gpr_file = vim.fs.find(function(name)
    return name:match(".*%.gpr$")
  end, { upward = true, path = startpath, limit = 10 })[1]
  local gpr_path = vim.fs.dirname(gpr_file)

  if gpr_path then
    return gpr_path
  end

  local ada_ls_conf_path
  if vim.fn.isdirectory(".git") == 0 then
    ada_ls_conf_path = vim.fs.dirname(startpath)
  else
    ada_ls_conf_path = startpath
  end

  return ada_ls_conf_path
end

local function notify_configuration_change(config)
  config = { ada = config }
  require("ada_ls.utils").notify_server(
    "workspace/didChangeConfiguration",
    { settings = config }
  )
end

local function save_new_configuration(root_dir, config)
  local path = vim.fs.joinpath(root_dir, ".als.json")

  local file = io.open(path, "w+")
  if not file then
    vim.notify_once(
      "Could not save Ada_ls configuration at " .. path,
      vim.log.levels.ERROR
    )
    return
  end
  file:write(vim.json.encode(config))
  file:close()
end

local function set_scenario_var()
  if M.project_file == "" then
    return
  end

  local config = { ["projectFile"] = M.project_file }
  notify_configuration_change(config)

  -- Sometimes the notification is not immediate
  require("ada_ls.lsp_cmd").get_prj_file()

  local gpr_files = { M.project_file }
  local uri_gpr_files = require("ada_ls.lsp_cmd").get_prj_dependencies()

  if uri_gpr_files and next(uri_gpr_files) then
    for _, f in pairs(uri_gpr_files) do
      table.insert(gpr_files, vim.uri_to_fname(f.uri))
    end
  end

  for _, file in pairs(gpr_files) do
    if not file or vim.fn.filereadable(file) ~= 1 then
      require("ada_ls.utils").notify(
        "Could not read Ada project file: " .. file,
        vim.log.levels.WARN
      )
      return
    end

    for line in io.lines(file) do
      for _ in string.gmatch(line, "external") do
        local match = string.match(line, '[^"%s]+", "[^%s]+"')
        match = string.gsub(match, '"', "")
        local var = {}
        for w in string.gmatch(match, "([^, ]+)") do
          table.insert(var, w)
        end
        M.scenario_variables[var[1]] = var[2]
      end
    end
  end
end

local function create_config(config)
  config["projectFile"] = M.project_file
  if next(M.scenario_variables) ~= nil then
    config["scenarioVariables"] = M.scenario_variables
  end
end

local function save_config()
  local utils = require("ada_ls.utils")
  if M.project_file == "" then
    utils.notify("No Ada project file selected.", vim.log.levels.WARN)
    return
  end

  local project_file_path = get_abspath(M.project_file)
  local config = {}

  create_config(config)
  save_new_configuration(project_file_path, config)

  require("ada_ls.utils").reset_als_client()
end

local function detect_project_files(root_dir)
  local find_downward = vim.fs.find(function(name)
    return name:match(".*%.gpr$")
  end, { path = root_dir, limit = 10, type = "file" })

  if find_downward and next(find_downward) then
    return find_downward
  else
    return vim.fs.find(function(name)
      return name:match(".*%.gpr$")
    end, { upward = true, path = root_dir, limit = 10, type = "file" })
  end
end

function M.pick_gpr_file()
  local utils = require("ada_ls.utils")
  local files =
    detect_project_files(als_root_dir(get_abspath(utils.get_bufpath())))
  local opts = {}
  local files_number = #files

  if files_number == 0 then
    vim.notify_once(
      "No Ada project files found in the current directory.",
      vim.log.levels.WARN
    )
    return
  elseif files_number == 1 then
    utils.notify(
      "Only one Ada project file found: " .. files[1],
      vim.log.levels.INFO
    )
    M.project_file = files[1]
    set_scenario_var()
    save_config()
  else
    require("telescope.pickers")
      .new(opts, {
        prompt_title = "Ada project files picker",
        finder = require("telescope.finders").new_table({ results = files }),
        sorter = require("telescope.config").values.generic_sorter(opts),
        attach_mappings = function(prompt_buffer, _)
          local actions = require("telescope.actions")
          actions.select_default:replace(function()
            actions.close(prompt_buffer)
            local selection =
              require("telescope.actions.state").get_selected_entry()
            M.project_file = selection[1]
            set_scenario_var()
            save_config()
          end)
          return true
        end,
      })
      :find()
  end
end

function M.decode_json_config(json_config_path)
  local file = io.open(json_config_path, "r")
  if not file then
    return nil, nil, nil
  end

  local raw = file:read("*a")
  file:close()

  local ok, json_config = pcall(vim.json.decode, raw)
  if not ok then
    return nil, nil, nil
  end

  if json_config["projectFile"] then
    M.project_file = json_config["projectFile"]
  end
  local scenario_vars_string = ""
  if json_config["scenarioVariables"] then
    for k, v in pairs(json_config["scenarioVariables"]) do
      scenario_vars_string = scenario_vars_string
        .. " -X"
        .. k
        .. "="
        .. tostring(v)
    end
  end
  return M.project_file, scenario_vars_string, json_config
end

function M.setup()
  if vim.opt.diff:get() or M.is_setup then
    return
  end

  local utils = require("ada_ls.utils")

  if utils.get_ada_ls() == nil then
    return
  end

  local ada_ls_conf_path = als_root_dir(get_abspath(utils.get_bufpath()))

  local path = vim.fs.joinpath(ada_ls_conf_path, ".als.json")

  if vim.fn.filereadable(path) ~= 1 then
    return
  end

  local _, _, json_config = M.decode_json_config(path)
  if not json_config then
    utils.notify(
      "Failed to decode Ada LSP configuration from " .. path,
      vim.log.levels.ERROR
    )
    return
  end

  notify_configuration_change(json_config)
  require("ada_ls.gpr").makeprg_setup()
  vim.notify_once(
    "Configuration loaded from " .. ada_ls_conf_path,
    vim.log.levels.INFO
  )
  M.is_setup = true
end

function M.clear()
  M.project_file = ""
  M.scenario_variables = {}
  M.is_setup = false
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._get_abspath = get_abspath
  M._als_root_dir = als_root_dir
  M._detect_project_files = detect_project_files
  M._notify_configuration_change = notify_configuration_change
  M._save_new_configuration = save_new_configuration
  M._create_config = create_config
  M._save_config = save_config
  M._set_scenario_var = set_scenario_var
end

return M
