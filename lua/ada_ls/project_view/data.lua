-- Project View data fetching, parsing, and caching
local M = {}

-- Cached project view data
local cache = {
  data = nil,
  supported = nil, -- nil = unknown, true/false = checked
}

---@class ProjectSource
---@field file_name string Full path to source file
---@field simple_name string Base name of source file
---@field directory string Directory containing the source
---@field language? string Language of the source (e.g., "ada", "c")

---@class ProjectInfo
---@field id string Unique project identifier
---@field name string Project name
---@field kind string Project kind
---@field qualifier string Project qualifier
---@field simple_name string Base name of project file
---@field file_name string Full path to project file
---@field directory string Project directory
---@field is_externally_built boolean Whether project is externally built
---@field languages string[] Languages used in project
---@field source_directories string[] Source directories
---@field object_dir? string Object directory path

---@class ProjectEntry
---@field project ProjectInfo Project metadata
---@field imports string[] IDs of imported projects
---@field aggregated string[] IDs of aggregated projects
---@field extended string[] IDs of extended projects
---@field extending? { extending_all: boolean, project_id: string }
---@field imported_by string[] IDs of projects importing this one
---@field sources ProjectSource[] Source files

---@class ProjectViewData
---@field root_project_id string ID of the root project
---@field projects table<string, ProjectEntry> Map of project ID to entry
---@field runtime_project? ProjectEntry Optional runtime project

--- Get a value from a table, trying multiple key formats
---@param tbl table
---@param key string Base key name (e.g., "file_name")
---@param default? any Default value if not found
---@return any
local function get_flexible(tbl, key, default)
  if not tbl then
    return default
  end
  -- Try the key as-is first
  if tbl[key] ~= nil then
    return tbl[key]
  end
  -- Try kebab-case (file-name)
  local kebab = key:gsub("_", "-")
  if tbl[kebab] ~= nil then
    return tbl[kebab]
  end
  -- Try camelCase (fileName)
  local camel = key:gsub("_(%l)", function(c)
    return c:upper()
  end)
  if tbl[camel] ~= nil then
    return tbl[camel]
  end
  -- Try with common prefixes removed
  if tbl[key:gsub("^is_", "")] ~= nil then
    return tbl[key:gsub("^is_", "")]
  end
  return default
end

--- Normalize a path by stripping trailing slashes
---@param path string
---@return string
local function normalize_path(path)
  if not path or path == "" then
    return ""
  end
  -- Strip trailing slashes (but keep root "/" intact)
  return path:gsub("/+$", "")
end

--- Parse a raw source info from ALS response
---@param raw table Raw source info
---@return ProjectSource
local function parse_source(raw)
  -- Try to extract directory from file path if not provided
  local file_name = get_flexible(raw, "file_name", "")
  local directory = get_flexible(raw, "directory", "")

  -- Normalize paths (strip trailing slashes)
  file_name = normalize_path(file_name)
  directory = normalize_path(directory)

  -- If directory is empty but we have a file path, extract it
  if directory == "" and file_name ~= "" then
    directory = vim.fs.dirname(file_name) or ""
  end

  -- Get simple name - if not provided, extract from file_name
  local simple_name = get_flexible(raw, "simple_name", "")
  if simple_name == "" and file_name ~= "" then
    simple_name = vim.fs.basename(file_name) or ""
  end

  return {
    file_name = file_name,
    simple_name = simple_name,
    directory = directory,
    language = get_flexible(raw, "language"),
  }
end

--- Parse a raw project info from ALS response
---@param raw table Raw project info
---@return ProjectInfo
local function parse_project_info(raw)
  local file_name = get_flexible(raw, "file_name", "")
  local directory = get_flexible(raw, "directory", "")

  -- Normalize paths (strip trailing slashes)
  file_name = normalize_path(file_name)
  directory = normalize_path(directory)

  -- Extract directory from file path if not provided
  if directory == "" and file_name ~= "" then
    directory = vim.fs.dirname(file_name) or ""
  end

  local object_dir = get_flexible(raw, "object_directory")
  if object_dir then
    object_dir = normalize_path(object_dir)
  end

  return {
    id = get_flexible(raw, "id", ""),
    name = get_flexible(raw, "name", ""),
    kind = get_flexible(raw, "kind", ""),
    qualifier = get_flexible(raw, "qualifier", ""),
    simple_name = get_flexible(raw, "simple_name", ""),
    file_name = file_name,
    directory = directory,
    is_externally_built = get_flexible(raw, "is_externally_built", false),
    languages = get_flexible(raw, "languages", {}),
    source_directories = get_flexible(raw, "source_directories", {}),
    object_dir = object_dir,
  }
end

--- Parse a raw project entry from ALS response
---@param raw table Raw project entry
---@return ProjectEntry
local function parse_project_entry(raw)
  local sources = {}
  local raw_sources = get_flexible(raw, "sources", {})
  if raw_sources and type(raw_sources) == "table" then
    for _, s in ipairs(raw_sources) do
      table.insert(sources, parse_source(s))
    end
  end

  local extending = nil
  local raw_extending = get_flexible(raw, "extending")
  if raw_extending then
    extending = {
      extending_all = get_flexible(raw_extending, "extending_all", false),
      project_id = get_flexible(raw_extending, "project_id", ""),
    }
  end

  return {
    project = parse_project_info(get_flexible(raw, "project", {})),
    imports = get_flexible(raw, "imports", {}),
    aggregated = get_flexible(raw, "aggregated", {}),
    extended = get_flexible(raw, "extended", {}),
    extending = extending,
    imported_by = get_flexible(raw, "imported_by", {}),
    sources = sources,
  }
end

--- Parse runtime project from ALS response
---@param raw table Raw runtime project info
---@return ProjectEntry
local function parse_runtime_project(raw)
  local sources = {}
  local raw_sources = get_flexible(raw, "sources", {})
  if raw_sources and type(raw_sources) == "table" then
    for _, s in ipairs(raw_sources) do
      table.insert(sources, parse_source(s))
    end
  end

  return {
    project = {
      id = get_flexible(raw, "id", "runtime"),
      name = get_flexible(raw, "name", "Runtime"),
      kind = "runtime",
      qualifier = "runtime",
      simple_name = get_flexible(raw, "name", "Runtime"),
      file_name = "",
      directory = "",
      is_externally_built = true,
      languages = {},
      source_directories = get_flexible(raw, "source_directories", {}),
      object_dir = get_flexible(raw, "object_directory"),
    },
    imports = {},
    aggregated = {},
    extended = {},
    imported_by = {},
    sources = sources,
  }
end

--- Parse the full ALS project view response
---@param raw table Raw ALS response
---@return ProjectViewData?
---@return string? error
function M.parse_response(raw)
  if not raw then
    return nil, "No response data"
  end

  -- Get projects array
  local raw_projects = get_flexible(raw, "projects")
  if not raw_projects then
    return nil,
      string.format(
        "Response missing projects field. Keys: %s",
        vim.inspect(vim.tbl_keys(raw))
      )
  end

  -- Handle both array and object formats for projects
  if not vim.islist(raw_projects) then
    -- Convert object to array if needed
    local projects_array = {}
    for _, v in pairs(raw_projects) do
      table.insert(projects_array, v)
    end
    raw_projects = projects_array
  end

  if #raw_projects == 0 then
    return nil, "No projects in response"
  end

  -- Determine root project ID
  -- Option 1: Check for tree.root-project.id (newer ALS format)
  -- Option 2: Use first project in array (older/simpler format)
  local root_id = nil
  local tree = get_flexible(raw, "tree")
  if tree then
    local root_project = get_flexible(tree, "root_project")
    if root_project then
      root_id = get_flexible(root_project, "id")
    end
  end

  -- Parse all project entries
  local projects = {}
  local first_project_id = nil

  for _, raw_entry in ipairs(raw_projects) do
    local raw_project = get_flexible(raw_entry, "project", {})
    local project_id = get_flexible(raw_project, "id")
    if project_id then
      local entry = parse_project_entry(raw_entry)
      projects[entry.project.id] = entry

      -- Track first project as potential root
      if not first_project_id then
        first_project_id = entry.project.id
      end
    end
  end

  -- Use first project as root if no tree.root-project specified
  if not root_id then
    root_id = first_project_id
  end

  if not root_id then
    return nil, "Could not determine root project"
  end

  -- Parse optional runtime project
  local runtime_project = nil
  local raw_runtime = get_flexible(raw, "runtime_project")
  if raw_runtime then
    runtime_project = parse_runtime_project(raw_runtime)
  end

  return {
    root_project_id = root_id,
    projects = projects,
    runtime_project = runtime_project,
  }
end

--- Check if ALS supports the project view command
---@return boolean supported
---@return string? error_message
function M.is_supported()
  if cache.supported ~= nil then
    return cache.supported,
      cache.supported and nil or "Project View requires ALS 2026.3 or later"
  end

  -- Try fetching to check support
  local raw, err = require("ada_ls.lsp_cmd").get_project_view_info()

  if err then
    local err_str = type(err) == "string" and err or vim.inspect(err)
    if err_str:match("[Uu]nknown command") then
      cache.supported = false
      return false, "Project View requires ALS 2026.3 or later"
    end
    -- Other errors might be transient, don't cache
    return false, err_str
  end

  cache.supported = true
  -- Cache the data we just fetched
  if raw then
    local data, _ = M.parse_response(raw)
    if data then
      cache.data = data
    end
  end

  return true
end

--- Fetch project view data from ALS
---@param force? boolean Force refresh even if cached
---@return ProjectViewData?
---@return string? error
function M.fetch(force)
  -- Return cached data if available and not forcing refresh
  if not force and cache.data then
    return cache.data
  end

  -- Check support first
  local supported, support_err = M.is_supported()
  if not supported then
    return nil, support_err
  end

  -- If we already have data from the support check, return it
  if cache.data and not force then
    return cache.data
  end

  -- Fetch fresh data
  local raw, err = require("ada_ls.lsp_cmd").get_project_view_info()
  if err then
    return nil, type(err) == "string" and err or vim.inspect(err)
  end

  if not raw then
    return nil, "No data returned from ALS"
  end

  local data, parse_err = M.parse_response(raw)
  if not data then
    return nil, parse_err
  end

  cache.data = data
  return data
end

--- Get cached data without fetching
---@return ProjectViewData?
function M.get_cached()
  return cache.data
end

--- Invalidate the cache
function M.invalidate()
  cache.data = nil
  -- Don't reset cache.supported - that shouldn't change during session
end

--- Get all source files from the project view data
--- Returns a flat list of all sources with project context
---@param data ProjectViewData
---@param opts? { include_runtime: boolean }
---@return { source: ProjectSource, project: ProjectInfo, is_root: boolean }[]
function M.get_all_sources(data, opts)
  opts = opts or {}
  local results = {}

  -- Process regular projects, root first
  local root_entry = data.projects[data.root_project_id]
  if root_entry then
    for _, source in ipairs(root_entry.sources) do
      table.insert(results, {
        source = source,
        project = root_entry.project,
        is_root = true,
      })
    end
  end

  -- Process other projects
  for id, entry in pairs(data.projects) do
    if id ~= data.root_project_id then
      for _, source in ipairs(entry.sources) do
        table.insert(results, {
          source = source,
          project = entry.project,
          is_root = false,
        })
      end
    end
  end

  -- Include runtime project sources if requested
  if opts.include_runtime and data.runtime_project then
    for _, source in ipairs(data.runtime_project.sources) do
      table.insert(results, {
        source = source,
        project = data.runtime_project.project,
        is_root = false,
      })
    end
  end

  return results
end

--- Find a source file in the project data by path
---@param data ProjectViewData
---@param file_path string Absolute path to the file
---@return { source: ProjectSource, project: ProjectInfo }?
function M.find_source(data, file_path)
  -- Normalize path for comparison
  local normalized = vim.fs.normalize(file_path)

  for _, entry in pairs(data.projects) do
    for _, source in ipairs(entry.sources) do
      if vim.fs.normalize(source.file_name) == normalized then
        return { source = source, project = entry.project }
      end
    end
  end

  -- Check runtime project
  if data.runtime_project then
    for _, source in ipairs(data.runtime_project.sources) do
      if vim.fs.normalize(source.file_name) == normalized then
        return { source = source, project = data.runtime_project.project }
      end
    end
  end

  return nil
end

-- Export internals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._cache = cache
  M._parse_source = parse_source
  M._parse_project_info = parse_project_info
  M._parse_project_entry = parse_project_entry
  M._parse_runtime_project = parse_runtime_project
end

return M
