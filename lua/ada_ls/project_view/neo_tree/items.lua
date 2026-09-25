-- Transform ALS project view data into neo-tree node format
local M = {}
local node_utils = require("ada_ls.project_view.nodes")

local function decorate_for_neo_tree(nodes)
  for _, node in ipairs(nodes or {}) do
    if node.type == "object_dir" then
      node.type = "directory"
    elseif node.type == "runtime" then
      node.type = "project"
    end

    if node.type == "file" then
      node.ext = node.name:match("%.([^%.]+)$") or ""
    end

    if node.children then
      decorate_for_neo_tree(node.children)
    end
  end

  return nodes
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

  callback(decorate_for_neo_tree(node_utils.build_hierarchy(data, opts)))
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
  M._decorate_for_neo_tree = decorate_for_neo_tree
  M._make_id = node_utils.make_node_id
  M._group_by_directory = node_utils.group_sources_by_dir
  M._create_file_node = node_utils._create_file_node
  M._create_object_dir_node = node_utils._create_object_dir_node
end

return M
