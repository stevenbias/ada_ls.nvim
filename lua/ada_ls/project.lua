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

local function notify_workspace_folders_add(folders)
  local params = { event = { added = {} } }

  for _, folder in pairs(folders) do
    local added =
      { uri = vim.uri_from_fname(folder), name = vim.fs.dirname(folder) }
    table.insert(params.event.added, added)
  end

  require("ada_ls.utils").notify_server(
    "workspace/didChangeWorkspaceFolders",
    params
  )
end

local function save_new_configuration(root_dir, config)
  local json_path = vim.fs.joinpath(root_dir, ".als.json")

  local file = io.open(json_path, "w+")
  if not file then
    require("ada_ls.utils").notify(
      "Could not save Ada_ls configuration at " .. json_path,
      vim.log.levels.ERROR
    )
    return
  end

  -- Save the project file name instead of the full path to avoid issues with
  -- different environments
  local cfg = vim.deepcopy(config)
  cfg.projectFile = vim.fs.basename(M.project_file)
  file:write(vim.json.encode(cfg))
  file:close()

  require("ada_ls.gprtools").makeprg_setup(cfg)
end

local function set_scenario_var()
  if M.project_file == "" then
    return
  end

  M.scenario_variables = {}
  local gpr_files = { M.project_file }
  local uri_gpr_files =
    require("ada_ls.lsp_cmd").get_prj_dependencies(M.project_file)

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

local function create_config()
  local config = {}
  config["projectFile"] = M.project_file
  if next(M.scenario_variables) ~= nil then
    config["scenarioVariables"] = M.scenario_variables
  end
  return config
end

local function save_config(config)
  local utils = require("ada_ls.utils")
  if M.project_file == "" then
    utils.notify("No Ada project file selected.", vim.log.levels.WARN)
    return
  end

  local project_file_path = get_abspath(M.project_file)
  save_new_configuration(project_file_path, config)

  return config
end

local function detect_project_files(root_dir)
  local find_downward = vim.fs.find(function(name)
    return name:match(".*%.gpr$")
  end, { path = root_dir, limit = 10, type = "file" })

  local find_upward = vim.fs.find(function(name)
    return name:match(".*%.gpr$")
  end, { upward = true, path = root_dir, limit = 10, type = "file" })

  for _, v in ipairs(find_upward) do
    if not vim.tbl_contains(find_downward, v) then
      table.insert(find_downward, v)
    end
  end

  return find_downward
end

local function update_project(prj_file, cfg)
  M.project_file = prj_file

  if cfg ~= nil then
    notify_configuration_change(cfg)
    return
  end

  local config = { projectFile = M.project_file }
  notify_configuration_change(config)

  set_scenario_var()
  config = create_config()
  save_config(config)

  notify_configuration_change(config)
  local folders = { get_abspath(M.project_file) }
  notify_workspace_folders_add(folders)

  vim.cmd("cd " .. vim.fs.dirname(folders[1]))
end

function M.pick_gpr_file()
  local utils = require("ada_ls.utils")
  local files =
    detect_project_files(als_root_dir(get_abspath(utils.get_bufpath())))
  local opts = {}
  local files_number = #files

  if files_number == 0 then
    utils.notify(
      "No Ada project files found in the current directory.",
      vim.log.levels.WARN
    )
    return
  elseif files_number == 1 then
    utils.notify(
      "Only one Ada project file found: " .. files[1],
      vim.log.levels.INFO
    )
    update_project(files[1])
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
            update_project(selection[1])
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

  local ada_ls_conf_path = als_root_dir(get_abspath(utils.get_bufpath()))

  local json_path = vim.fs.joinpath(ada_ls_conf_path, ".als.json")

  local group = vim.api.nvim_create_augroup("AdaLsConfigFile", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = json_path,
    callback = function()
      local _, _, json_config = M.decode_json_config(json_path)
      require("ada_ls.gprtools").makeprg_setup(json_config)
      require("ada_ls.utils").reset_als_client()
    end,
  })

  if vim.fn.filereadable(json_path) ~= 1 then
    return
  end

  local prj_file, _, json_config = M.decode_json_config(json_path)
  if not json_config then
    utils.notify(
      "Failed to decode Ada LSP configuration from " .. json_path,
      vim.log.levels.ERROR
    )
    return
  end

  if vim.bo.filetype == "gpr" then
    -- If the current buffer is a GPR file, use it as the project file
    prj_file = vim.fn.expand("%:p")
  end

  update_project(prj_file, json_config)
  require("ada_ls.gprtools").makeprg_setup(json_config)
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
