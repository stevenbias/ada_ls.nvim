local M = {
  is_setup = false,
  project_file = "",
  scenario_variables = {},
}

local function get_abspath(str)
  local abspath = vim.fs.abspath(str)
  if not abspath then
    return nil
  end
  return abspath:match("(.*[/\\])")
end

local function normalize_path(path)
  return require("ada_ls.utils").normalize_path(path)
end

local function is_absolute_path(path)
  return type(path) == "string"
    and (path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil)
end

local function normalize_abspath(path)
  if is_absolute_path(path) then
    return normalize_path(path)
  end
  local abspath = vim.fs.abspath(path)
  if not abspath then
    return nil
  end
  return normalize_path(abspath)
end

local function get_config_dir(path)
  local dir = vim.fs.dirname(path)
  return dir and normalize_path(dir) or nil
end

local function resolve_project_file(project_file, json_config_path)
  if not project_file or project_file == "" then
    return nil
  end

  if is_absolute_path(project_file) then
    return normalize_abspath(project_file) or normalize_path(project_file)
  end

  local config_dir = get_config_dir(json_config_path)
  if not config_dir then
    return normalize_abspath(project_file) or normalize_path(project_file)
  end

  return normalize_abspath(vim.fs.joinpath(config_dir, project_file))
    or normalize_path(vim.fs.joinpath(config_dir, project_file))
end

local function encode_project_file(project_file, json_config_path)
  if not project_file or project_file == "" then
    return project_file
  end

  local config_dir = get_config_dir(json_config_path)
  if not config_dir then
    return project_file
  end

  local normalized_project = normalize_path(project_file)
  if normalized_project == config_dir then
    return "."
  end

  if normalized_project:sub(1, #config_dir + 1) == config_dir .. "/" then
    return normalized_project:sub(#config_dir + 2)
  end

  return normalized_project
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
  if folders == nil or #folders == 0 then
    return
  end
  local params = { event = { added = {}, removed = {} } }

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

  local cfg = vim.deepcopy(config)
  cfg.projectFile = encode_project_file(M.project_file, json_path)
  file:write(vim.json.encode(cfg))
  file:close()

  require("ada_ls.gprtools").makeprg_setup(config)
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
      for key, value in
        line:gmatch('external%s*%(%s*"([^"]+)"%s*,%s*"([^"]+)"%s*%)')
      do
        M.scenario_variables[key] = value
      end
    end
  end
end

local function create_config(base_config)
  local config = vim.deepcopy(base_config or {})
  config["projectFile"] = M.project_file
  if next(M.scenario_variables) ~= nil then
    config["scenarioVariables"] = vim.deepcopy(M.scenario_variables)
  else
    config["scenarioVariables"] = nil
  end
  return config
end

local function save_config(config, json_path)
  local utils = require("ada_ls.utils")
  if M.project_file == "" then
    utils.notify("No Ada project file selected.", vim.log.levels.WARN)
    return
  end

  local config_dir = json_path and get_config_dir(json_path)
    or get_abspath(M.project_file)
  save_new_configuration(config_dir, config)

  return config
end

local function apply_project_state(prj_file, opts)
  opts = opts or {}
  if not prj_file or prj_file == "" then
    require("ada_ls.utils").notify(
      "No Ada project file selected.",
      vim.log.levels.WARN
    )
    return nil
  end

  local config = opts.config and vim.deepcopy(opts.config)
    or { projectFile = prj_file }
  local recompute_scenario = opts.recompute_scenario == true

  M.project_file = prj_file

  if recompute_scenario then
    config.projectFile = M.project_file
    notify_configuration_change(config)
    set_scenario_var()
    config = create_config(config)
    save_config(config, opts.json_path)
    notify_configuration_change(config)
  else
    config.projectFile = M.project_file
    notify_configuration_change(config)
  end

  local folder = get_abspath(M.project_file)
  notify_workspace_folders_add({ folder })

  if folder and folder ~= "" then
    vim.api.nvim_set_current_dir(folder)
  end

  require("ada_ls.project_view").invalidate()
  require("ada_ls.gprtools").makeprg_setup(config)
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
    apply_project_state(files[1], { recompute_scenario = true })
  else
    local ok_telescope, pickers = pcall(require, "telescope.pickers")
    if ok_telescope then
      pickers
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
              apply_project_state(selection[1], { recompute_scenario = true })
            end)
            return true
          end,
        })
        :find()
      return
    end

    if vim.ui and type(vim.ui.select) == "function" then
      vim.ui.select(
        files,
        { prompt = "Ada project files picker" },
        function(choice)
          if choice then
            apply_project_state(choice, { recompute_scenario = true })
          end
        end
      )
      return
    end

    utils.notify(
      "Telescope is required for project picker",
      vim.log.levels.WARN
    )
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
    M.project_file =
      resolve_project_file(json_config["projectFile"], json_config_path)
    json_config["projectFile"] = M.project_file
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
    prj_file = normalize_abspath(vim.fn.expand("%:p"))
    json_config.projectFile = prj_file
  end

  if not prj_file or prj_file == "" then
    return
  end

  M.project_file = prj_file
  json_config.projectFile = M.project_file

  if json_config.scenarioVariables == nil then
    notify_configuration_change(json_config)
    set_scenario_var()
    json_config = create_config(json_config)
    save_config(json_config, json_path)
  end

  notify_configuration_change(json_config)
  require("ada_ls.project_view").invalidate()
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
  M._normalize_abspath = normalize_abspath
  M._resolve_project_file = resolve_project_file
  M._encode_project_file = encode_project_file
  M._als_root_dir = als_root_dir
  M._detect_project_files = detect_project_files
  M._notify_configuration_change = notify_configuration_change
  M._save_new_configuration = save_new_configuration
  M._create_config = create_config
  M._save_config = save_config
  M._set_scenario_var = set_scenario_var
  M._apply_project_state = apply_project_state
end

return M
