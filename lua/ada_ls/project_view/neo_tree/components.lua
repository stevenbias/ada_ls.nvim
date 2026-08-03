-- Components for Ada project neo-tree source
-- Defines icon and name rendering for project, runtime, and object directory nodes
local M = {}

-- Icons for different node types (nerdfont)
local ICONS = {
  project = " ",
  runtime = " ",
  object_dir = " ",
}

--- Highlight group names (exported for user customization)
--- Users can customize these groups in their config:
---   vim.api.nvim_set_hl(0, require("ada_ls.project_view.neo_tree.components").highlights.project, { fg = "#E0A526" })
M.highlights = {
  project = "NeoTreeAdaProject",
  runtime = "NeoTreeAdaRuntime",
  object_dir = "NeoTreeAdaObjectDir",
}

-- Lazy-loaded common components cache
local _common

--- Get common components (lazy-loaded and cached)
---@return table
local function get_common()
  if not _common then
    _common = require("neo-tree.sources.common.components")
  end
  return _common
end

local highlights_setup = false

--- Setup custom highlight groups (called once, uses default=true for user override)
local function setup_highlights()
  if highlights_setup then
    return
  end
  highlights_setup = true

  -- Project nodes: bold directory-like
  vim.api.nvim_set_hl(0, M.highlights.project, {
    default = true,
    link = "Directory",
    bold = true,
  })
  -- Runtime project: dimmed
  vim.api.nvim_set_hl(0, M.highlights.runtime, {
    default = true,
    link = "NeoTreeDimText",
  })
  -- Object directory: dimmed
  vim.api.nvim_set_hl(0, M.highlights.object_dir, {
    default = true,
    link = "NeoTreeDimText",
  })
end

--- Icon component - handles project/runtime/object_dir node types
---@param config table Component configuration from renderer
---@param node table NuiNode for the current node
---@param state table Current state of the source
---@return table Component result with text and highlight
M.icon = function(config, node, state)
  setup_highlights()

  -- Object directory: gear icon
  if node.extra and node.extra.is_object_dir then
    return { text = ICONS.object_dir, highlight = M.highlights.object_dir }
  end

  -- Project nodes
  if node.type == "project" then
    if node.extra and node.extra.is_runtime then
      return { text = ICONS.runtime, highlight = M.highlights.runtime }
    end
    return { text = ICONS.project, highlight = M.highlights.project }
  end

  -- Delegate file/directory to common components
  return get_common().icon(config, node, state)
end

--- Name component - applies appropriate highlights for project nodes
---@param config table Component configuration from renderer
---@param node table NuiNode for the current node
---@param state table Current state of the source
---@return table Component result with text and highlight
M.name = function(config, node, state)
  setup_highlights()

  -- Object directory
  if node.extra and node.extra.is_object_dir then
    return { text = node.name, highlight = M.highlights.object_dir }
  end

  -- Project nodes
  if node.type == "project" then
    if node.extra and node.extra.is_runtime then
      return { text = node.name, highlight = M.highlights.runtime }
    end
    return { text = node.name, highlight = M.highlights.project }
  end

  -- Delegate to common components
  return get_common().name(config, node, state)
end

-- Export internals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._setup_highlights = setup_highlights
  M._reset_highlights_flag = function()
    highlights_setup = false
  end
  M._reset_common_cache = function()
    _common = nil
  end
  M._icons = ICONS
end

-- Merge with common components (inherits indent, git_status, diagnostics, etc.)
local ok, common = pcall(require, "neo-tree.sources.common.components")
if ok then
  _common = common -- cache it since we loaded it
  return vim.tbl_deep_extend("force", common, M)
end
return M
