local M = {
  -- Proof levels (single choice, matches VS Code extension)
  PROOF_LEVELS = {
    { label = "0 - Fast, one prover (default)", value = "--level=0" },
    { label = "1 - Fast, most provers", value = "--level=1" },
    { label = "2 - Most provers", value = "--level=2" },
    { label = "3 - Slower, most provers", value = "--level=3" },
    { label = "4 - Slowest, most provers", value = "--level=4" },
  },

  -- Additional SPARK options (multi-choice, matches VS Code extension)
  SPARK_OPTIONS = {
    {
      id = "multiprocessing",
      label = "Multiprocessing (-j0)",
      value = "-j0",
    },
    {
      id = "no_warnings",
      label = "Do not report warnings (--warnings=off)",
      value = "--warnings=off",
    },
    {
      id = "report_all",
      label = "Report checks proved (--report=all)",
      value = "--report=all",
    },
    {
      id = "info",
      label = "Output info messages (--info)",
      value = "--info",
    },
    {
      id = "proof_warnings",
      label = "Enable proof warnings (--proof-warnings=on)",
      value = "--proof-warnings=on",
    },
  },
  opts = { proof_level = 0, options = { 1 } },
}

-- Default state: level 0, multiprocessing enabled

local valid_keys = {
  "proof_level",
  "options",
}

local valid_options = {}

local function ids_to_opts(ids)
  local opts = {}

  for idx, key in ipairs(M.SPARK_OPTIONS) do
    if vim.tbl_contains(ids, key.id) then
      table.insert(opts, idx)
    end
  end
  return opts
end

local function is_valid(opts)
  if opts == nil or next(opts) == nil then
    return true
  end

  local notify = require("ada_ls.utils").notify

  for key in pairs(opts) do
    if not vim.tbl_contains(valid_keys, key) then
      notify("Unknown SPARK config field: " .. key, vim.log.levels.ERROR)
      return false
    end
  end

  if opts.options then
    for _, key in pairs(opts.options) do
      if not vim.tbl_contains(valid_options, key) then
        notify("Unknown SPARK option: " .. key, vim.log.levels.ERROR)
        return false
      end
    end
    opts.options = ids_to_opts(opts.options)
  end

  if opts.proof_level then
    if type(opts.proof_level) ~= "number" then
      notify("spark.proof_level must be a number", vim.log.levels.ERROR)
      return false
    end
  end

  return true
end

function M.get()
  return M.opts
end

function M.setup(opts)
  for _, opt in ipairs(M.SPARK_OPTIONS) do
    table.insert(valid_options, opt.id)
  end

  if is_valid(opts) then
    M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  end
end

if os.getenv("ADA_LS_TEST_MODE") then
  M._ids_to_opts = ids_to_opts
  M._is_valid = is_valid
end

return M
