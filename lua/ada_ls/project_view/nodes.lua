-- Shared project-view node shaping helpers
local M = {}

local function merge_tables(base, extra)
  local merged = {}
  for k, v in pairs(base or {}) do
    merged[k] = v
  end
  for k, v in pairs(extra or {}) do
    merged[k] = v
  end
  return merged
end

local function build_id(type, path, project_id)
  return string.format("%s:%s:%s", type, project_id or "", path)
end

local function create_file_node(source, project, extra)
  extra = extra or {}
  return {
    id = build_id("file", source.file_name, project.id),
    type = "file",
    name = source.simple_name,
    path = source.file_name,
    project_id = project.id,
    extra = merge_tables({
      project_id = project.id,
      project_name = project.name,
      language = source.language,
    }, extra),
  }
end

local function create_directory_node(dir_path, project, extra)
  local utils = require("ada_ls.utils")
  extra = extra or {}
  return {
    id = build_id("directory", dir_path, project.id),
    type = "directory",
    name = utils.get_relative_path(dir_path, project.directory),
    path = dir_path,
    project_id = project.id,
    children = {},
    extra = merge_tables({
      project_id = project.id,
      project_name = project.name,
    }, extra),
  }
end

local function create_object_dir_node(object_dir, project)
  local utils = require("ada_ls.utils")
  local children = {}

  for _, file_name in ipairs(M.get_directory_files(object_dir)) do
    table.insert(children, {
      id = build_id("file", vim.fs.joinpath(object_dir, file_name), project.id),
      type = "file",
      name = file_name,
      path = vim.fs.joinpath(object_dir, file_name),
      project_id = project.id,
      extra = {
        project_id = project.id,
        project_name = project.name,
      },
    })
  end

  return {
    id = build_id("object_dir", object_dir, project.id),
    type = "object_dir",
    name = utils.safe_basename(object_dir) .. " (obj)",
    path = object_dir,
    project_id = project.id,
    children = children,
    extra = {
      project_id = project.id,
      project_name = project.name,
      is_object_dir = true,
    },
  }
end

local function create_project_node(project, is_root)
  return {
    id = build_id("project", project.file_name, project.id),
    type = "project",
    name = project.name .. (is_root and " (Root)" or ""),
    path = project.file_name,
    project_id = project.id,
    is_root = is_root,
    children = {},
    extra = {
      project_id = project.id,
      project_name = project.name,
      is_root = is_root,
      kind = project.kind,
      languages = project.languages,
    },
  }
end

local function create_runtime_node(_runtime)
  return {
    id = build_id("runtime", "runtime", "runtime"),
    type = "runtime",
    name = "Runtime",
    project_id = "runtime",
    children = {},
    extra = {
      project_id = "runtime",
      project_name = "Runtime",
      is_runtime = true,
    },
  }
end

--- Group sources by their directory.
---@param sources table[]
---@return table<string, table[]> dirs
---@return string[] sorted_dirs
function M.group_sources_by_dir(sources)
  local dirs = {}
  for _, source in ipairs(sources or {}) do
    local dir = source.directory or ""
    if not dirs[dir] then
      dirs[dir] = {}
    end
    table.insert(dirs[dir], source)
  end

  local sorted_dirs = vim.tbl_keys(dirs)
  table.sort(sorted_dirs)
  return dirs, sorted_dirs
end

--- Sort sources by simple file name, in place.
---@param sources table[]
function M.sort_sources_by_simple_name(sources)
  table.sort(sources, function(a, b)
    return a.simple_name < b.simple_name
  end)
end

--- Get direct file entries from a directory, sorted alphabetically.
---@param dir_path string
---@return string[]
function M.get_directory_files(dir_path)
  local fs_dir = vim.fs.dir
  if type(fs_dir) ~= "function" then
    return {}
  end

  local files = {}
  local ok, iter = pcall(fs_dir, dir_path)
  if not ok or type(iter) ~= "function" then
    return files
  end

  for name, entry_type in iter do
    if entry_type == "file" then
      table.insert(files, name)
    end
  end

  table.sort(files)
  return files
end

--- Collect sub-project entries from imports/aggregated/extended and sort by name.
---@param entry table
---@param data table
---@return table[]
function M.collect_subproject_entries(entry, data)
  local sub_entries = {}
  local seen_ids = {}

  local function add_subproject(id)
    if seen_ids[id] then
      return
    end

    local sub = data.projects[id]
    if sub then
      seen_ids[id] = true
      table.insert(sub_entries, sub)
    end
  end

  for _, id in ipairs(entry.imports or {}) do
    add_subproject(id)
  end
  for _, id in ipairs(entry.aggregated or {}) do
    add_subproject(id)
  end
  for _, id in ipairs(entry.extended or {}) do
    add_subproject(id)
  end

  table.sort(sub_entries, function(a, b)
    return a.project.name < b.project.name
  end)

  return sub_entries
end

--- List all projects sorted root-first, then by project name.
---@param data table
---@return table[]
function M.list_projects_flat(data)
  local project_list = {}
  for _, entry in pairs(data.projects) do
    table.insert(project_list, entry)
  end

  table.sort(project_list, function(a, b)
    local a_root = a.project.id == data.root_project_id
    local b_root = b.project.id == data.root_project_id
    if a_root ~= b_root then
      return a_root
    end
    return a.project.name < b.project.name
  end)

  return project_list
end

function M.make_node_id(type, path, project_id)
  return build_id(type, path, project_id)
end

function M.build_hierarchy(data, opts)
  opts = opts or {}
  local roots = {}
  local visited_projects = {}

  local function build_project_branch(entry, is_root)
    local project = entry.project
    if visited_projects[project.id] then
      return nil
    end
    visited_projects[project.id] = true

    local project_node = create_project_node(project, is_root)

    local dirs, dir_list = M.group_sources_by_dir(entry.sources)
    for _, dir_path in ipairs(dir_list) do
      local directory_node = create_directory_node(dir_path, project)
      local dir_sources = dirs[dir_path]
      M.sort_sources_by_simple_name(dir_sources)

      for _, source in ipairs(dir_sources) do
        table.insert(directory_node.children, create_file_node(source, project))
      end

      table.insert(project_node.children, directory_node)
    end

    if opts.show_object_dirs and project.object_dir then
      table.insert(
        project_node.children,
        create_object_dir_node(project.object_dir, project)
      )
    end

    if not opts.flat_mode then
      for _, sub_entry in ipairs(M.collect_subproject_entries(entry, data)) do
        local sub_node = build_project_branch(sub_entry, false)
        if sub_node then
          table.insert(project_node.children, sub_node)
        end
      end
    end

    return project_node
  end

  if opts.flat_mode then
    for _, entry in ipairs(M.list_projects_flat(data)) do
      local is_root = entry.project.id == data.root_project_id
      local root = build_project_branch(entry, is_root)
      if root then
        table.insert(roots, root)
      end
    end
  else
    local root_entry = data.projects[data.root_project_id]
    if root_entry then
      local root = build_project_branch(root_entry, true)
      if root then
        table.insert(roots, root)
      end
    end
  end

  if opts.show_runtime and data.runtime_project then
    local runtime = data.runtime_project
    local runtime_node = create_runtime_node(runtime)
    local runtime_project = runtime.project
      or { id = "runtime", name = "Runtime", directory = "" }
    local dirs, dir_list = M.group_sources_by_dir(runtime.sources)

    for _, dir_path in ipairs(dir_list) do
      local directory_node = create_directory_node(dir_path, runtime_project, {
        project_id = "runtime",
        project_name = "Runtime",
      })
      directory_node.id = build_id("directory", dir_path, "runtime")
      directory_node.project_id = "runtime"

      local dir_sources = dirs[dir_path]
      M.sort_sources_by_simple_name(dir_sources)
      for _, source in ipairs(dir_sources) do
        local file_node = create_file_node(source, runtime_project, {
          project_id = "runtime",
          project_name = "Runtime",
        })
        file_node.id = build_id("file", source.file_name, "runtime")
        file_node.project_id = "runtime"
        table.insert(directory_node.children, file_node)
      end

      table.insert(runtime_node.children, directory_node)
    end

    table.insert(roots, runtime_node)
  end

  return roots
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._create_file_node = create_file_node
  M._create_object_dir_node = create_object_dir_node
  M._merge_tables = merge_tables
end

return M
