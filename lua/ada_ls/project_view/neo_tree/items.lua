-- Transform ALS project view data into neo-tree node format
local M = {}

--- Generate a unique node ID
---@param type string Node type
---@param path string Path or identifier
---@param project_id? string Project ID
---@return string
local function make_id(type, path, project_id)
  return string.format("%s:%s:%s", type, project_id or "", path)
end

--- Group sources by their directory
---@param sources table[] List of source objects
---@return table<string, table[]> Map of directory path to sources
---@return string[] Sorted list of directory paths
local function group_by_directory(sources)
  local dirs = {}
  for _, source in ipairs(sources) do
    local dir = source.directory or ""
    if not dirs[dir] then
      dirs[dir] = {}
    end
    table.insert(dirs[dir], source)
  end

  local sorted = vim.tbl_keys(dirs)
  table.sort(sorted)
  return dirs, sorted
end

--- Create a file node
---@param source table Source info from ALS
---@param project table Project info
---@return table Neo-tree node
local function create_file_node(source, project)
  return {
    id = make_id("file", source.file_name, project.id),
    name = source.simple_name,
    type = "file",
    path = source.file_name,
    ext = source.simple_name:match("%.([^%.]+)$") or "",
    extra = {
      project_id = project.id,
      project_name = project.name,
      language = source.language,
    },
  }
end

--- Create a directory node with file children
---@param dir_path string Directory path
---@param sources table[] Sources in this directory
---@param project table Project info
---@return table Neo-tree node
local function create_directory_node(dir_path, sources, project)
  local utils = require("ada_ls.utils")
  local dir_name = utils.get_relative_path(dir_path, project.directory)

  -- Sort files
  table.sort(sources, function(a, b)
    return a.simple_name < b.simple_name
  end)

  local children = {}
  for _, source in ipairs(sources) do
    table.insert(children, create_file_node(source, project))
  end

  return {
    id = make_id("directory", dir_path, project.id),
    name = dir_name,
    type = "directory",
    path = dir_path,
    children = children,
    extra = {
      project_id = project.id,
      project_name = project.name,
    },
  }
end

--- Create an object directory node
---@param object_dir string Object directory path
---@param project table Project info
---@return table Neo-tree node
local function create_object_dir_node(object_dir, project)
  local utils = require("ada_ls.utils")
  return {
    id = make_id("object_dir", object_dir, project.id),
    name = utils.safe_basename(object_dir) .. " (obj)",
    type = "directory",
    path = object_dir,
    -- No children - object directory is a leaf
    extra = {
      project_id = project.id,
      project_name = project.name,
      is_object_dir = true,
    },
  }
end

--- Create a project node with all its contents
---@param entry table ProjectEntry from ALS
---@param data table Full ProjectViewData
---@param opts table Options (flat_mode, show_object_dirs)
---@param is_root boolean Whether this is the root project
---@return table Neo-tree node
local function create_project_node(entry, data, opts, is_root)
  local project = entry.project
  local children = {}

  -- Add source directories
  local dirs, dir_list = group_by_directory(entry.sources)
  for _, dir_path in ipairs(dir_list) do
    local dir_sources = dirs[dir_path]
    table.insert(
      children,
      create_directory_node(dir_path, dir_sources, project)
    )
  end

  -- Add object directory if enabled
  if opts.show_object_dirs and project.object_dir then
    table.insert(children, create_object_dir_node(project.object_dir, project))
  end

  -- Add sub-projects if not in flat mode
  if not opts.flat_mode then
    local sub_entries = {}

    -- Collect all sub-project IDs
    for _, id in ipairs(entry.imports or {}) do
      local sub = data.projects[id]
      if sub then
        table.insert(sub_entries, sub)
      end
    end
    for _, id in ipairs(entry.aggregated or {}) do
      local sub = data.projects[id]
      if sub then
        table.insert(sub_entries, sub)
      end
    end
    for _, id in ipairs(entry.extended or {}) do
      local sub = data.projects[id]
      if sub then
        table.insert(sub_entries, sub)
      end
    end

    -- Sort sub-projects by name
    table.sort(sub_entries, function(a, b)
      return a.project.name < b.project.name
    end)

    -- Create sub-project nodes
    for _, sub_entry in ipairs(sub_entries) do
      table.insert(children, create_project_node(sub_entry, data, opts, false))
    end
  end

  local display_name = project.name
  if is_root then
    display_name = display_name .. " (Root)"
  end

  return {
    id = make_id("project", project.file_name, project.id),
    name = display_name,
    type = "project", -- Custom type for projects
    path = project.file_name,
    children = children,
    extra = {
      project_id = project.id,
      project_name = project.name,
      is_root = is_root,
      kind = project.kind,
      languages = project.languages,
    },
  }
end

--- Create a runtime project node
---@param runtime table Runtime project entry
---@return table Neo-tree node
local function create_runtime_node(runtime)
  local children = {}

  -- Group runtime sources by directory
  local dirs, dir_list = group_by_directory(runtime.sources)

  for _, dir_path in ipairs(dir_list) do
    local dir_sources = dirs[dir_path]
    local project = runtime.project
      or { id = "runtime", name = "Runtime", directory = "" }

    -- Sort files
    table.sort(dir_sources, function(a, b)
      return a.simple_name < b.simple_name
    end)

    local file_children = {}
    for _, source in ipairs(dir_sources) do
      table.insert(file_children, create_file_node(source, project))
    end

    local utils = require("ada_ls.utils")
    table.insert(children, {
      id = make_id("directory", dir_path, "runtime"),
      name = utils.get_relative_path(dir_path, project.directory or ""),
      type = "directory",
      path = dir_path,
      children = file_children,
      extra = {
        project_id = "runtime",
        project_name = "Runtime",
      },
    })
  end

  return {
    id = make_id("runtime", "runtime", "runtime"),
    name = "Runtime",
    type = "project",
    children = children,
    extra = {
      project_id = "runtime",
      is_runtime = true,
    },
  }
end

--- Get all items (nodes) for the neo-tree
---@param opts table Options { show_runtime, show_object_dirs, flat_mode }
---@param callback fun(items: table[], err?: string) Callback with items or error
function M.get_items(opts, callback)
  local data_mod = require("ada_ls.project_view.data")

  -- Check if ALS supports project view
  local supported, support_err = data_mod.is_supported()
  if not supported then
    callback({}, support_err or "Project View not supported")
    return
  end

  -- Fetch project data
  local data, fetch_err = data_mod.fetch()
  if not data then
    callback({}, fetch_err or "Failed to fetch project data")
    return
  end

  local items = {}

  if opts.flat_mode then
    -- Flat mode: all projects at root level
    local project_list = {}
    for _, entry in pairs(data.projects) do
      table.insert(project_list, entry)
    end

    -- Sort: root first, then alphabetically
    table.sort(project_list, function(a, b)
      local a_root = a.project.id == data.root_project_id
      local b_root = b.project.id == data.root_project_id
      if a_root ~= b_root then
        return a_root
      end
      return a.project.name < b.project.name
    end)

    for _, entry in ipairs(project_list) do
      local is_root = entry.project.id == data.root_project_id
      table.insert(items, create_project_node(entry, data, opts, is_root))
    end
  else
    -- Hierarchical mode: start from root
    local root_entry = data.projects[data.root_project_id]
    if root_entry then
      table.insert(items, create_project_node(root_entry, data, opts, true))
    end
  end

  -- Add runtime project if enabled
  if opts.show_runtime and data.runtime_project then
    table.insert(items, create_runtime_node(data.runtime_project))
  end

  callback(items)
end

--- Find a node by file path
---@param items table[] List of nodes
---@param path string File path to find
---@return table? node The found node or nil
function M.find_node_by_path(items, path)
  local normalized = vim.fs.normalize(path)

  local function search(nodes)
    for _, node in ipairs(nodes) do
      if node.path and vim.fs.normalize(node.path) == normalized then
        return node
      end
      if node.children then
        local found = search(node.children)
        if found then
          return found
        end
      end
    end
    return nil
  end

  return search(items)
end

-- Export internals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._make_id = make_id
  M._group_by_directory = group_by_directory
  M._create_file_node = create_file_node
  M._create_directory_node = create_directory_node
  M._create_project_node = create_project_node
  M._create_runtime_node = create_runtime_node
end

return M
