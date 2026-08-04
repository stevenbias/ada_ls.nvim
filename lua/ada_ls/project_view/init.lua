-- Project View - main module and public API
local M = {}

-- View options state
local state = {
  flat_mode = false,
  show_object_dirs = false,
  show_runtime = false,
  backend = "auto", -- "auto" | "neo-tree" | "builtin"
}

-- Neo-tree source require path (for registration check in sources list)
local NEO_TREE_SOURCE = "ada_ls.project_view.neo_tree"
-- Neo-tree source name (for Neotree commands and manager calls)
local NEO_TREE_SOURCE_NAME = "ada_project"

--- Check if neo-tree is available (installed and loaded)
---@return boolean
local function neo_tree_available()
  local ok = pcall(require, "neo-tree")
  return ok
end

--- Check if ada_project source is registered with neo-tree
---@return boolean
local function neo_tree_source_registered()
  if not neo_tree_available() then
    return false
  end

  local neo_tree = require("neo-tree")
  local sources = neo_tree.config and neo_tree.config.sources
  if not sources then
    return false
  end

  for _, source in ipairs(sources) do
    if source == NEO_TREE_SOURCE then
      return true
    end
  end
  return false
end

--- Determine which backend to use based on config and availability
---@return "neo-tree"|"builtin"
local function get_backend()
  if state.backend == "builtin" then
    return "builtin"
  end
  -- For "neo-tree" or "auto", try neo-tree if available
  if neo_tree_available() then
    return "neo-tree"
  end
  return "builtin"
end

--- Check if using neo-tree backend
---@return boolean
function M.using_neo_tree()
  return get_backend() == "neo-tree"
end

--- Pick a source file from the project using Telescope
---@param opts? { include_runtime?: boolean }
function M.pick_files(opts)
  opts = opts or {}
  opts.include_runtime = opts.include_runtime or state.show_runtime
  require("ada_ls.project_view.telescope").pick_file(opts)
end

--- Pick a project using Telescope
---@param opts? { on_select?: fun(project: table) }
function M.pick_project(opts)
  require("ada_ls.project_view.telescope").pick_project(opts)
end

--- Open the project view tree
function M.open()
  if get_backend() == "neo-tree" then
    local ok = pcall(
      vim.cmd,
      "Neotree source=" .. NEO_TREE_SOURCE_NAME .. " position=left"
    )
    if ok then
      return
    end
  end
  require("ada_ls.project_view.tree").open({
    flat_mode = state.flat_mode,
    show_object_dirs = state.show_object_dirs,
    show_runtime = state.show_runtime,
  })
end

--- Close the project view tree
function M.close()
  if get_backend() == "neo-tree" then
    local ok = pcall(vim.cmd, "Neotree close source=" .. NEO_TREE_SOURCE_NAME)
    if ok then
      return
    end
  end
  require("ada_ls.project_view.tree").close()
end

--- Toggle the project view tree
function M.toggle()
  if get_backend() == "neo-tree" then
    local ok = pcall(
      vim.cmd,
      "Neotree toggle source=" .. NEO_TREE_SOURCE_NAME .. " position=left"
    )
    if ok then
      return
    end
  end
  require("ada_ls.project_view.tree").toggle({
    flat_mode = state.flat_mode,
    show_object_dirs = state.show_object_dirs,
    show_runtime = state.show_runtime,
  })
end

--- Check if tree is currently open
---@return boolean
function M.is_open()
  if get_backend() == "neo-tree" then
    -- Check if neo-tree window with our source is open
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local state_ok, source_state =
        pcall(manager.get_state, NEO_TREE_SOURCE_NAME)
      if state_ok and source_state then
        return source_state.winid
          and vim.api.nvim_win_is_valid(source_state.winid)
      end
    end
    return false
  end
  return require("ada_ls.project_view.tree").is_open()
end

--- Reveal the current file in the project view tree
function M.reveal()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    return
  end

  if get_backend() == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      -- Use manager.navigate with path_to_reveal parameter
      local nav_ok =
        pcall(manager.navigate, NEO_TREE_SOURCE_NAME, nil, current_file)
      if nav_ok then
        return
      end
    end
  end
  local tree = require("ada_ls.project_view.tree")
  -- First make sure tree is open
  if not tree.is_open() then
    tree.open({
      flat_mode = state.flat_mode,
      show_object_dirs = state.show_object_dirs,
      show_runtime = state.show_runtime,
    })
  end
  tree.reveal_current_file(current_file)
end

--- Refresh the project view data and tree
function M.refresh()
  require("ada_ls.project_view.data").invalidate()
  if get_backend() == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local refresh_ok = pcall(manager.refresh, NEO_TREE_SOURCE_NAME)
      if refresh_ok then
        return
      end
    end
  end
  local tree = require("ada_ls.project_view.tree")
  if tree.is_open() then
    tree.refresh()
  end
end

--- Invalidate cached data (call when project changes)
function M.invalidate()
  require("ada_ls.project_view.data").invalidate()
end

--- Check if ALS supports the project view feature
---@return boolean
---@return string? error_message
function M.is_supported()
  return require("ada_ls.project_view.data").is_supported()
end

--- Get a view option
---@param key "flat_mode"|"show_object_dirs"|"show_runtime"|"backend"
---@return boolean|string
function M.get_option(key)
  return state[key]
end

--- Set a view option
---@param key "flat_mode"|"show_object_dirs"|"show_runtime"|"backend"
---@param value boolean|string
function M.set_option(key, value)
  if state[key] ~= nil then
    state[key] = value
    -- Refresh tree if open (for boolean options)
    if type(value) == "boolean" and M.is_open() then
      M.refresh()
    end
  end
end

--- Configure the project view
---@param opts? { backend?: "auto"|"neo-tree"|"builtin", flat_mode?: boolean, show_object_dirs?: boolean, show_runtime?: boolean }
function M.setup(opts)
  opts = opts or {}
  if opts.backend ~= nil then
    state.backend = opts.backend
  end
  if opts.flat_mode ~= nil then
    state.flat_mode = opts.flat_mode
  end
  if opts.show_object_dirs ~= nil then
    state.show_object_dirs = opts.show_object_dirs
  end
  if opts.show_runtime ~= nil then
    state.show_runtime = opts.show_runtime
  end
end

--- Get the neo-tree source module path
--- Users should add this to their neo-tree sources config:
---   require("neo-tree").setup({
---     sources = { "filesystem", "buffers", "git_status", "ada_ls.project_view.neo_tree" },
---   })
---@return string source_path The module path to add to neo-tree sources
function M.get_neo_tree_source()
  return NEO_TREE_SOURCE
end

--- Check if neo-tree integration is properly configured
---@return boolean registered Whether the ada_project source is registered with neo-tree
---@return string? message Help message if not registered
function M.check_neo_tree_setup()
  if not neo_tree_available() then
    return false, "neo-tree is not installed"
  end

  if neo_tree_source_registered() then
    return true, nil
  end

  return false,
    "Add '" .. M.get_neo_tree_source() .. "' to your neo-tree sources config"
end

-- Export state for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._state = state
  M._get_backend = get_backend
  M._neo_tree_available = neo_tree_available
  M._neo_tree_source_registered = neo_tree_source_registered
end

return M
