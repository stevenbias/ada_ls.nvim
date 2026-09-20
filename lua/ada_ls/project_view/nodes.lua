-- Shared project-view node shaping helpers
local M = {}

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

return M
