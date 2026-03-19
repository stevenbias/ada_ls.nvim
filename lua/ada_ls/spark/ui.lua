local M = {}

--============================================================================--
local function pick_proof_level(current_level, callback)
  local items = {}
  for i, level in ipairs(require("ada_ls.spark.config").PROOF_LEVELS) do
    local prefix = (i - 1 == current_level) and "● " or "○ "
    table.insert(items, prefix .. level.label)
  end

  local idx =
    vim.fn.inputlist({ "Select proof level:", table.concat(items, "\n") })
  if
    idx < 0 or idx >= vim.fn.len(require("ada_ls.spark.config").PROOF_LEVELS)
  then
    idx = current_level
  end
  callback(idx)
end

-- Step 2: Pick additional options using floating toggle buffer
local function pick_additional_options(current_options, callback)
  local opts = require("ada_ls.spark.config").SPARK_OPTIONS

  -- Track selected state (1-based indices)
  local selected = {}
  for _, idx in ipairs(current_options) do
    selected[idx] = true
  end

  -- Calculate window size and position
  local win_width = 50
  local win_height = #opts + 4
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

  -- Create buffer content
  local function build_lines(width)
    local lines = { "GNATprove Additional Options", string.rep("─", width) }
    for i, opt in ipairs(opts) do
      local checkbox = selected[i] and "[x]" or "[ ]"
      table.insert(lines, checkbox .. " " .. opt.label)
    end
    table.insert(lines, string.rep("─", width))
    table.insert(lines, "<Tab> toggle  <CR> confirm  q cancel")
    return lines
  end

  -- Create scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, build_lines(win_width))
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " SPARK Options ",
    title_pos = "center",
  })

  -- Position cursor on first option
  vim.api.nvim_win_set_cursor(win, { 3, 1 })

  -- Helper to get current option index from cursor position
  local function get_option_index()
    local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
    local option_idx = cursor_row - 2 -- Account for header lines
    if option_idx >= 1 and option_idx <= #opts then
      return option_idx
    end
    return nil
  end

  -- Helper to update display
  local function refresh()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, build_lines(win_width))
    vim.bo[buf].modifiable = false
  end

  -- Helper to close and return result
  local function close_with_result(confirmed)
    vim.api.nvim_win_close(win, true)
    if not confirmed then
      callback(nil)
    else
      local result = {}
      for i = 1, #opts do
        if selected[i] then
          table.insert(result, i)
        end
      end
      callback(result)
    end
  end

  -- Keymaps
  local kopts = { buffer = buf, nowait = true }

  -- Toggle option with Tab
  vim.keymap.set("n", "<Tab>", function()
    local idx = get_option_index()
    if idx then
      selected[idx] = not selected[idx]
      refresh()
    end
  end, kopts)

  for _, key in ipairs({ "<CR>", "q", "<Esc>" }) do
    local confirmed = false
    if key == "<CR>" then
      confirmed = true
    end
    vim.keymap.set("n", key, function()
      close_with_result(confirmed)
    end, kopts)
  end
end

-- Full two-step picker flow
function M.ask_spark_options(callback)
  local current = require("ada_ls.spark").load_state()

  pick_proof_level(current.proof_level, function(level)
    if level == nil then
      callback(nil)
      return
    end

    pick_additional_options(current.options, function(opts)
      if opts == nil then
        callback(nil)
        return
      end

      local state = { proof_level = level, options = opts }
      require("ada_ls.spark").save_state(state)
      callback(state)
    end)
  end)
end

return M
