-- Neo-tree source for Ada project view
-- Usage: Add "ada_ls.project_view.neo_tree" to your neo-tree sources config,
-- then use :Neotree source=ada_project
local M = {
  name = "ada_project",
  display_name = " Ada Project",
}

M.default_config = {
  renderers = {
    project = {
      { "indent" },
      { "icon" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
        },
      },
    },
  },
  window = {
    position = "left",
    width = 40,
    mappings = {
      ["<cr>"] = "open",
      ["o"] = "open",
      ["s"] = "open_split",
      ["v"] = "open_vsplit",
      ["t"] = "open_tabnew",
      ["P"] = { "toggle_preview", config = { use_float = true } },
      ["R"] = "refresh",
      ["a"] = "none",
      ["d"] = "none",
      ["r"] = "none",
    },
  },
  follow_current_file = { enabled = true },
  bind_to_cwd = false,
  show_runtime = false,
  show_object_dirs = false,
  flat_mode = false,
}

local project_view_opts = nil

---@param opts? { show_runtime?: boolean, show_object_dirs?: boolean, flat_mode?: boolean }
function M.set_project_view_opts(opts)
  if opts == nil then
    project_view_opts = nil
    return
  end

  project_view_opts = vim.deepcopy(opts)
end

---@return { show_runtime: boolean, show_object_dirs: boolean, flat_mode: boolean }
local function get_effective_opts()
  local config = M.config or M.default_config
  local opts = {
    show_runtime = config.show_runtime,
    show_object_dirs = config.show_object_dirs,
    flat_mode = config.flat_mode,
  }

  if project_view_opts then
    if project_view_opts.show_runtime ~= nil then
      opts.show_runtime = project_view_opts.show_runtime
    end
    if project_view_opts.show_object_dirs ~= nil then
      opts.show_object_dirs = project_view_opts.show_object_dirs
    end
    if project_view_opts.flat_mode ~= nil then
      opts.flat_mode = project_view_opts.flat_mode
    end
  end

  return opts
end

function M.setup(config, global_config)
  M.config = config
  M.global_config = global_config
end

function M.navigate(state, path, path_to_reveal, callback)
  state.path = path or vim.fn.getcwd()

  local renderer = require("neo-tree.ui.renderer")
  local items_mod = require("ada_ls.project_view.neo_tree.items")
  local opts = get_effective_opts()

  items_mod.get_items({
    show_runtime = opts.show_runtime,
    show_object_dirs = opts.show_object_dirs,
    flat_mode = opts.flat_mode,
  }, function(items, err)
    if err then
      require("ada_ls.utils").notify(err, vim.log.levels.WARN)
      renderer.show_nodes({}, state)
      return
    end
    renderer.show_nodes(items or {}, state)

    -- If path_to_reveal is set, find and focus the node
    if path_to_reveal and path_to_reveal ~= "" then
      local node = items_mod.find_node_by_path(items or {}, path_to_reveal)
      if node then
        -- Schedule focus to allow tree to render first
        vim.schedule(function()
          renderer.focus_node(state, node.id)
        end)
      end
    end

    if callback then
      callback()
    end
  end)
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._get_effective_opts = get_effective_opts
end

return M
