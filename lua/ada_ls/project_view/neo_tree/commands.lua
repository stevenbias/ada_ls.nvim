-- Neo-tree commands for Ada project source
local ok, cc = pcall(require, "neo-tree.sources.common.commands")
if not ok then
  return {} -- Module loaded outside neo-tree context
end

local M = {}

function M.open(state, toggle_directory)
  local node = state.tree:get_node()
  if not node then
    return
  end

  if node.type == "directory" or node.type == "project" then
    if toggle_directory ~= false then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      require("neo-tree.ui.renderer").redraw(state)
    end
  elseif node.path then
    cc.open(state, function() end)
  end
end

function M.open_split(state)
  cc.open_split(state, function() end)
end

function M.open_vsplit(state)
  cc.open_vsplit(state, function() end)
end

function M.open_tabnew(state)
  cc.open_tabnew(state, function() end)
end

function M.toggle_preview(state, config)
  cc.toggle_preview(state, config)
end

function M.refresh(state)
  require("ada_ls.project_view.data").invalidate()
  require("neo-tree.sources.manager").refresh("ada_project", state)
end

function M.none(_state)
  -- No-op for disabled mappings
end

cc._add_common_commands(M)

return M
