-- Project View - main module and public API
local M = {}

-- View options state
local state = {
  flat_mode = false,
  show_object_dirs = false,
  show_runtime = false,
}

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

--- Open the project view tree buffer
function M.open()
  require("ada_ls.project_view.tree").open({
    flat_mode = state.flat_mode,
    show_object_dirs = state.show_object_dirs,
    show_runtime = state.show_runtime,
  })
end

--- Close the project view tree buffer
function M.close()
  require("ada_ls.project_view.tree").close()
end

--- Toggle the project view tree buffer
function M.toggle()
  require("ada_ls.project_view.tree").toggle({
    flat_mode = state.flat_mode,
    show_object_dirs = state.show_object_dirs,
    show_runtime = state.show_runtime,
  })
end

--- Reveal the current file in the project view tree
function M.reveal()
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

--- Refresh the project view data and tree
function M.refresh()
  require("ada_ls.project_view.data").invalidate()
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
---@param key "flat_mode"|"show_object_dirs"|"show_runtime"
---@return boolean
function M.get_option(key)
  return state[key] or false
end

--- Set a view option
---@param key "flat_mode"|"show_object_dirs"|"show_runtime"
---@param value boolean
function M.set_option(key, value)
  if state[key] ~= nil then
    state[key] = value
    -- Refresh tree if open
    local tree = require("ada_ls.project_view.tree")
    if tree.is_open() then
      tree.refresh()
    end
  end
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
      local tree = require("ada_ls.project_view.tree")
      if tree.is_open() then
        tree.refresh()
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
end

return M
