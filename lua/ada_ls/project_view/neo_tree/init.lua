-- Neo-tree source for Ada project view
-- Usage: Add "ada_ls.project_view.neo_tree" to your neo-tree sources config,
-- then use :Neotree source=ada_project
local M = {
  name = "ada_project",
  display_name = " Ada Project",
}

M.default_config = {
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

function M.setup(config, global_config)
  M.config = config
  M.global_config = global_config
end

function M.navigate(state, path, path_to_reveal, callback)
  state.path = path or vim.fn.getcwd()

  local renderer = require("neo-tree.ui.renderer")
  local items_mod = require("ada_ls.project_view.neo_tree.items")
  local config = M.config or M.default_config

  items_mod.get_items({
    show_runtime = config.show_runtime,
    show_object_dirs = config.show_object_dirs,
    flat_mode = config.flat_mode,
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

return M
