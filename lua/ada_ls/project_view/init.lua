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
  elseif state.backend == "neo-tree" then
    if neo_tree_source_registered() then
      return "neo-tree"
    else
      if neo_tree_available() then
        require("ada_ls.utils").notify(
          "ada_project source not registered with neo-tree. "
            .. "Add 'ada_ls.project_view.neo_tree' to your neo-tree sources config. "
            .. "Falling back to builtin tree.",
          vim.log.levels.WARN
        )
      else
        require("ada_ls.utils").notify(
          "neo-tree not available, falling back to builtin",
          vim.log.levels.WARN
        )
      end
      return "builtin"
    end
  else
    -- auto: prefer neo-tree if source is registered
    if neo_tree_source_registered() then
      return "neo-tree"
    end
    return "builtin"
  end
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
    vim.cmd("Neotree source=" .. NEO_TREE_SOURCE_NAME .. " position=left")
  else
    require("ada_ls.project_view.tree").open({
      flat_mode = state.flat_mode,
      show_object_dirs = state.show_object_dirs,
      show_runtime = state.show_runtime,
    })
  end
end

--- Close the project view tree
function M.close()
  if get_backend() == "neo-tree" then
    vim.cmd("Neotree close source=" .. NEO_TREE_SOURCE_NAME)
  else
    require("ada_ls.project_view.tree").close()
  end
end

--- Toggle the project view tree
function M.toggle()
  if get_backend() == "neo-tree" then
    vim.cmd(
      "Neotree toggle source=" .. NEO_TREE_SOURCE_NAME .. " position=left"
    )
  else
    require("ada_ls.project_view.tree").toggle({
      flat_mode = state.flat_mode,
      show_object_dirs = state.show_object_dirs,
      show_runtime = state.show_runtime,
    })
  end
end

--- Check if tree is currently open
---@return boolean
function M.is_open()
  if get_backend() == "neo-tree" then
    -- Check if neo-tree window with our source is open
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local source_state = manager.get_state(NEO_TREE_SOURCE_NAME)
      return source_state
        and source_state.winid
        and vim.api.nvim_win_is_valid(source_state.winid)
    end
    return false
  else
    return require("ada_ls.project_view.tree").is_open()
  end
end

--- Reveal the current file in the project view tree
function M.reveal()
  if get_backend() == "neo-tree" then
    vim.cmd(
      "Neotree reveal source=" .. NEO_TREE_SOURCE_NAME .. " position=left"
    )
  else
    local tree = require("ada_ls.project_view.tree")
    -- First make sure tree is open
    if not tree.is_open() then
      tree.open({
        flat_mode = state.flat_mode,
        show_object_dirs = state.show_object_dirs,
        show_runtime = state.show_runtime,
      })
    end
    tree.reveal_current_file()
  end
end

--- Refresh the project view data and tree
function M.refresh()
  require("ada_ls.project_view.data").invalidate()
  if get_backend() == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      manager.refresh(NEO_TREE_SOURCE_NAME)
    end
  else
    local tree = require("ada_ls.project_view.tree")
    if tree.is_open() then
      tree.refresh()
    end
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

--- Show options picker (floating window)
function M.select_options()
  local options = {
    {
      key = "flat_mode",
      label = "Flat Mode",
      desc = "Show all projects at root level",
    },
    {
      key = "show_object_dirs",
      label = "Object Directories",
      desc = "Show object directory nodes",
    },
    {
      key = "show_runtime",
      label = "Runtime Files",
      desc = "Show runtime project sources",
    },
  }

  -- Build lines for display
  local lines = { "Project View Options", string.rep("─", 40) }
  for i, opt in ipairs(options) do
    local checked = state[opt.key] and "[x]" or "[ ]"
    table.insert(lines, string.format(" %d. %s %s", i, checked, opt.label))
    table.insert(lines, string.format("    %s", opt.desc))
  end
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, " Press 1-3 to toggle, q to close")

  -- Create floating window
  local width = 44
  local height = #lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Options ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set up keymaps
  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function toggle_option(idx)
    local opt = options[idx]
    if opt then
      state[opt.key] = not state[opt.key]
      -- Update display
      local checked = state[opt.key] and "[x]" or "[ ]"
      local line_idx = 2 + (idx - 1) * 2 -- Account for header lines
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(
        buf,
        line_idx,
        line_idx + 1,
        false,
        { string.format(" %d. %s %s", idx, checked, opt.label) }
      )
      vim.bo[buf].modifiable = false
      -- Refresh tree if open
      if M.is_open() then
        M.refresh()
      end
    end
  end

  vim.keymap.set("n", "q", close_win, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, nowait = true })
  vim.keymap.set("n", "1", function()
    toggle_option(1)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "2", function()
    toggle_option(2)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "3", function()
    toggle_option(3)
  end, { buffer = buf, nowait = true })

  -- Close on leaving buffer
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = close_win,
  })
end

-- Export state for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._state = state
  M._get_backend = get_backend
  M._neo_tree_available = neo_tree_available
  M._neo_tree_source_registered = neo_tree_source_registered
end

return M
