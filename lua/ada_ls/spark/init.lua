local M = {}

-- Get the JSON file path for persistence
local function get_state_file()
  return vim.fn.stdpath("data") .. "/ada_ls_spark.json"
end

local function get_project_key()
  local root = require("ada_ls.lsp_cmd").get_root_dir()
  return root or vim.fn.getcwd()
end

-- Convert state to CLI arguments
local function state_to_args(state)
  local args = {}

  -- Add proof level
  local level = state.proof_level or 0
  if level >= 0 and level < #require("ada_ls.spark.config").PROOF_LEVELS then
    table.insert(
      args,
      require("ada_ls.spark.config").PROOF_LEVELS[level + 1].value
    )
  end

  -- Add selected additional options
  for _, idx in ipairs(state.options or {}) do
    if idx >= 1 and idx <= #require("ada_ls.spark.config").SPARK_OPTIONS then
      table.insert(
        args,
        require("ada_ls.spark.config").SPARK_OPTIONS[idx].value
      )
    end
  end

  return args
end

-- Build gnatprove arguments for a specific kind of operation
local function build_args(kind, state)
  local args = { "--output=oneline" }

  -- Add options from state (except for clean)
  if kind ~= "clean" and state then
    local option_args = state_to_args(state)
    vim.list_extend(args, option_args)
  end

  -- Add kind-specific arguments
  local filename = vim.fn.expand("%:t")

  if kind == "clean" then
    args = { "--clean" }
  elseif kind == "prove_file" then
    table.insert(args, "-u")
    table.insert(args, filename)
  end

  return args
end

-- Parse gnatprove output and populate quickfix
local function populate_quickfix(output, cwd)
  local qf_items = {}

  -- gnatprove --output=oneline format:
  -- filename:line:col: severity: message
  -- e.g., main.adb:10:5: medium: overflow check might fail
  for line in output:gmatch("[^\r\n]+") do
    local file, lnum, col, severity, msg =
      line:match("^([^:]+):(%d+):(%d+): ([^:]+): (.+)$")

    if file and lnum then
      -- Determine quickfix type from severity
      local qf_type = "W" -- Default to warning
      if severity:match("error") then
        qf_type = "E"
      elseif severity:match("info") then
        qf_type = "I"
      end

      -- Make path absolute if relative
      local filepath = file
      if not file:match("^/") then
        filepath = cwd .. "/" .. file
      end

      table.insert(qf_items, {
        filename = filepath,
        lnum = tonumber(lnum),
        col = tonumber(col) or 1,
        text = "[" .. severity .. "] " .. msg,
        type = qf_type,
      })
    end
  end

  -- Set quickfix list
  vim.fn.setqflist({}, "r", {
    title = "GNATprove",
    items = qf_items,
  })

  -- Open quickfix if there are items
  if #qf_items > 0 then
    vim.cmd("copen")
  else
    vim.cmd("cclose")
  end
end

-- Run gnatprove asynchronously
local function run_gnatprove(kind, state)
  local notify = require("ada_ls.utils").notify
  local lsp_cmd = require("ada_ls.lsp_cmd")

  -- Get project file
  local prj_uri = lsp_cmd.get_prj_file()
  if not prj_uri then
    notify("No project file found", vim.log.levels.ERROR)
    return
  end
  local prj_file = vim.uri_to_fname(prj_uri)

  -- Build command
  local args = build_args(kind, state)
  table.insert(args, "-P")
  table.insert(args, prj_file)

  -- Add -cargs -gnatef for better error messages (except for clean)
  if kind ~= "clean" then
    table.insert(args, "-cargs")
    table.insert(args, "-gnatef")
  end

  local cmd = vim.list_extend({ "gnatprove" }, args)

  -- Notify start
  local kind_display = kind:gsub("_", " "):gsub("^%l", string.upper)
  notify("Running: " .. kind_display .. "...", vim.log.levels.INFO)
  vim.notify_once(
    "Running: " .. vim.inspect(table.concat(cmd, " ")),
    vim.log.levels.INFO
  )

  -- Get working directory
  local cwd = lsp_cmd.get_root_dir() or vim.fn.getcwd()

  -- Run asynchronously
  vim.system(cmd, {
    cwd = cwd,
    text = true,
    detach = true,
    stdout = function()
      vim.schedule(function()
        vim.notify(kind_display .. " running...")
      end)
    end,
  }, function(result)
    vim.schedule(function()
      vim.notify(kind_display .. " done")
      if result.code == 0 then
        notify(kind_display .. " completed successfully", vim.log.levels.INFO)
      else
        notify(kind_display .. " completed with errors", vim.log.levels.WARN)
      end

      -- Parse output to quickfix
      local output = (result.stdout or "") .. (result.stderr or "")
      populate_quickfix(output, cwd)
    end)
  end)
end

-- Run a SPARK operation with saved options
local function run_with_saved_options(kind)
  local state = M.load_state()
  run_gnatprove(kind, state)
end

-- Load state for current project
function M.load_state()
  local file = io.open(get_state_file(), "r")
  if not file then
    return vim.deepcopy(M.opts)
  end

  local content = file:read("*a")
  file:close()

  local ok, all = pcall(vim.json.decode, content)
  if not ok or type(all) ~= "table" then
    return vim.deepcopy(M.opts)
  end

  local key = get_project_key()
  local state = all[key]
  if not state then
    return vim.deepcopy(M.opts)
  end

  -- Validate state structure
  if type(state.proof_level) ~= "number" or not vim.islist(state.options) then
    return vim.deepcopy(M.opts)
  end

  return state
end

-- Save state for current project
function M.save_state(state)
  local file_path = get_state_file()

  -- Read existing data
  local all = {}
  local file = io.open(file_path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.json.decode, content)
    if ok and type(decoded) == "table" then
      all = decoded
    end
  end

  -- Update with new state
  local key = get_project_key()
  all[key] = state

  -- Write back
  file = io.open(file_path, "w")
  if file then
    file:write(vim.json.encode(all))
    file:close()
  end
end

-- Open the options picker and save selection
function M.select_options()
  require("ada_ls.spark.ui").ask_spark_options(function(state)
    if state then
      require("ada_ls.utils").notify(
        "SPARK Level saved: " .. state.proof_level,
        vim.log.levels.INFO
      )
      local opts_id = {}
      for opt in ipairs(state.options) do
        table.insert(
          opts_id,
          require("ada_ls.spark.config").SPARK_OPTIONS[opt].id
        )
      end
      require("ada_ls.utils").notify(
        "SPARK options saved: " .. table.concat(opts_id, ", "),
        vim.log.levels.INFO
      )
    end
  end)
end

-- Prove entire project
function M.prove()
  run_with_saved_options("prove_project")
end

-- Prove current file
function M.prove_file()
  run_with_saved_options("prove_file")
end

-- Clean project for proof
function M.clean()
  run_gnatprove("clean", nil)
end

function M.setup(opts)
  if opts and opts.spark ~= nil then
    require("ada_ls.spark.config").setup(opts.spark)
  end
  M.opts = require("ada_ls.spark.config").get()
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._state_to_args = state_to_args
  M._build_args = build_args
  M._populate_quickfix = populate_quickfix
end

return M
