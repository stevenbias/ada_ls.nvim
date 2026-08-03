-- Common test utilities for ada_ls.nvim
local stub = require("luassert.stub")

local M = {}

-- Package cleanup (reset module state between tests)
function M.cleanup_packages()
  -- Clear preloads first
  package.preload["ada_ls"] = nil
  package.preload["ada_ls.utils"] = nil
  package.preload["ada_ls.lsp_cmd"] = nil
  package.preload["ada_ls.project"] = nil
  package.preload["ada_ls.gprtools"] = nil
  package.preload["ada_ls.spark"] = nil
  package.preload["ada_ls.spark.config"] = nil
  package.preload["ada_ls.lspconfig"] = nil
  package.preload["ada_ls.refactoring"] = nil
  package.preload["ada_ls.project_view"] = nil
  package.preload["ada_ls.project_view.data"] = nil
  package.preload["ada_ls.project_view.telescope"] = nil
  package.preload["ada_ls.project_view.tree"] = nil
  package.preload["ada_ls.project_view.neo_tree"] = nil
  package.preload["ada_ls.project_view.neo_tree.items"] = nil
  package.preload["ada_ls.project_view.neo_tree.commands"] = nil
  package.preload["ada_ls.project_view.neo_tree.components"] = nil
  -- Then clear loaded modules
  package.loaded["ada_ls"] = nil
  package.loaded["ada_ls.utils"] = nil
  package.loaded["ada_ls.lsp_cmd"] = nil
  package.loaded["ada_ls.project"] = nil
  package.loaded["ada_ls.gprtools"] = nil
  package.loaded["ada_ls.spark"] = nil
  package.loaded["ada_ls.spark.config"] = nil
  package.loaded["ada_ls.lspconfig"] = nil
  package.loaded["ada_ls.refactoring"] = nil
  package.loaded["ada_ls.project_view"] = nil
  package.loaded["ada_ls.project_view.data"] = nil
  package.loaded["ada_ls.project_view.telescope"] = nil
  package.loaded["ada_ls.project_view.tree"] = nil
  package.loaded["ada_ls.project_view.neo_tree"] = nil
  package.loaded["ada_ls.project_view.neo_tree.items"] = nil
  package.loaded["ada_ls.project_view.neo_tree.commands"] = nil
  package.loaded["ada_ls.project_view.neo_tree.components"] = nil
end

-- Vim API mocking
function M.create_basic_vim_api(custom_api)
  local base_api = {
    nvim_echo = function(msg)
      return msg
    end,
    nvim_get_current_buf = function()
      return 1
    end,
    nvim_buf_get_lines = function()
      return {}
    end,
    nvim_buf_set_lines = stub.new(),
    nvim_create_autocmd = stub.new().returns(1),
    nvim_create_augroup = function()
      return 1
    end,
    nvim_buf_set_option = stub.new(),
    nvim_set_option_value = stub.new(),
    nvim__get_runtime = function()
      return {}
    end,
  }

  if custom_api then
    for k, v in pairs(custom_api) do
      base_api[k] = v
    end
  end

  return base_api
end

-- Vim function mocking
function M.create_vim_fn_mock(overrides)
  local base_fn = {
    expand = function()
      return "/test/path/file.adb"
    end,
    readfile = function()
      return {}
    end,
    getpos = function()
      return { 0, 5, 10 }
    end,
    filereadable = function()
      return 1
    end,
    isdirectory = function()
      return 0
    end,
  }

  if overrides then
    for k, v in pairs(overrides) do
      base_fn[k] = v
    end
  end

  return base_fn
end

-- Complete vim globals setup
function M.setup_vim_globals(custom_api, custom_fn, custom_other)
  -- Set up vim.lsp first using rawset to avoid triggering metamethods
  -- that would try to lazy load vim.lsp module
  rawset(vim, "lsp", {
    get_clients = stub.new().returns({}),
    util = {
      make_position_params = stub.new().returns({}),
    },
  })

  -- Set up vim.api
  rawset(vim, "api", M.create_basic_vim_api(custom_api))

  -- Set up vim.fn
  rawset(vim, "fn", M.create_vim_fn_mock(custom_fn))

  -- Set up other vim globals using rawset
  rawset(vim, "log", {
    levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, OFF = 5 },
  })
  rawset(vim, "notify", stub.new())
  rawset(vim, "notify_once", stub.new())
  rawset(vim, "cmd", stub.new())
  rawset(vim, "o", {})
  rawset(vim, "bo", {})
  rawset(vim, "g", {})
  rawset(vim, "defer_fn", stub.new())
  rawset(vim, "uri_from_bufnr", function(_bufnr)
    return "file:///test/path/file.adb"
  end)
  rawset(vim, "uri_to_fname", function(uri)
    if not uri then
      return nil
    end
    return uri:gsub("^file://", "")
  end)
  rawset(vim, "uri_from_fname", function(fname)
    if not fname then
      return nil
    end
    return "file://" .. fname
  end)

  -- Set up vim.deepcopy
  rawset(vim, "deepcopy", function(t)
    if type(t) ~= "table" then
      return t
    end
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end)

  -- Set up vim.islist
  rawset(vim, "islist", function(t)
    if type(t) ~= "table" then
      return false
    end
    local count = 0
    for k in pairs(t) do
      if type(k) ~= "number" then
        return false
      end
      count = count + 1
    end
    return count == #t
  end)

  -- Set up vim.fs
  rawset(vim, "fs", {
    basename = function(path)
      return path:match("[^/]+$")
    end,
    dirname = function(path)
      return path:match("(.*/)")
    end,
    find = stub.new().returns({}),
    joinpath = function(...)
      return table.concat({ ... }, "/")
    end,
  })

  -- Set up vim.json
  rawset(vim, "json", {
    encode = function(val)
      -- Simple JSON encode for testing
      if type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
          local key = type(k) == "string" and ('"' .. k .. '"') or k
          local value
          if type(v) == "string" then
            value = '"' .. v .. '"'
          elseif type(v) == "table" then
            value = vim.json.encode(v)
          else
            value = tostring(v)
          end
          table.insert(parts, key .. ":" .. value)
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
      return tostring(val)
    end,
    decode = function()
      return {}
    end,
  })

  if custom_other then
    for k, v in pairs(custom_other) do
      rawset(vim, k, v)
    end
  end
end

-- LSP client mocking
function M.create_lsp_client(overrides)
  local base_client = {
    name = "ada_ls",
    root_dir = "/project/root",
    offset_encoding = "utf-8",
    request_sync = stub.new().returns(nil),
    request = function(self, method, params, callback)
      local result = self.request_sync(self, method, params)
      if result and result.result ~= nil then
        callback(nil, result.result)
      else
        callback(nil, result)
      end
    end,
    notify = stub.new(),
    stop = stub.new(),
  }

  if overrides then
    for k, v in pairs(overrides) do
      base_client[k] = v
    end
  end

  return base_client
end

-- Setup LSP client with automatic vim.lsp.get_clients mock
function M.setup_lsp_client(client)
  _G.vim.lsp.get_clients = stub.new().returns({ client })
  return client
end

-- Get path to fixture files
function M.setup_vim_health()
  rawset(vim, "health", {
    start = stub.new(),
    ok = stub.new(),
    warn = stub.new(),
    error = stub.new(),
    info = stub.new(),
  })
end

function M.fixture_path(filename)
  -- Use pwd-relative path that works with busted
  return "spec/fixtures/" .. filename
end

function M.symbol(name, start_line, end_line, start_char)
  return {
    name = name,
    range = {
      start = { line = start_line, character = start_char or 0 },
      ["end"] = { line = end_line, character = 0 },
    },
    selectionRange = {
      start = { line = start_line, character = start_char or 0 },
      ["end"] = { line = end_line, character = 0 },
    },
  }
end

function M.mock_symbols(children)
  return { { children = children } }
end

-- Mock ada_ls.utils with configurable options
---@param opts? { conf_file?: string, server_project?: string }
function M.setup_utils_mock(opts)
  opts = opts or {}
  rawset(package.loaded, "ada_ls.utils", {
    get_conf_file = function()
      return opts.conf_file
    end,
    get_server_project_name = function()
      return opts.server_project
    end,
    notify = stub.new(),
  })
end

-- Search through stub calls for a matching pattern
---@param stub_obj table The stub to search
---@param pattern string Lua pattern to match against first argument
---@return boolean found Whether a match was found
function M.find_stub_call(stub_obj, pattern)
  if not stub_obj.calls then
    return false
  end
  for _, call in ipairs(stub_obj.calls) do
    if call.vals[1] and call.vals[1]:match(pattern) then
      return true
    end
  end
  return false
end

-- Create a temporary file with content, returns path and cleanup function
---@param content string File content
---@param ext? string File extension (default: none)
---@return string path, function cleanup
function M.create_temp_file(content, ext)
  local path = os.tmpname() .. (ext or "")
  local file = io.open(path, "w")
  file:write(content)
  file:close()
  return path, function()
    os.remove(path)
  end
end

-- Setup all vim mocks needed for spark/ui tests
function M.setup_spark_ui_mocks()
  rawset(vim, "fn", {
    inputlist = function()
      return 2
    end,
    len = function(t)
      return #t
    end,
  })
  rawset(vim, "o", { lines = 100, columns = 200 })
  rawset(vim, "api", {
    nvim_create_buf = stub.new().returns(1),
    nvim_buf_set_lines = stub.new(),
    nvim_open_win = stub.new().returns(2),
    nvim_win_set_cursor = stub.new(),
    nvim_win_get_cursor = stub.new().returns({ 3, 0 }),
    nvim_win_close = stub.new(),
    nvim_create_autocmd = stub.new(),
    nvim__get_runtime = function()
      return {}
    end,
  })
  local bo = {}
  setmetatable(bo, {
    __index = function()
      return {}
    end,
    __newindex = function() end,
  })
  rawset(vim, "bo", bo)

  -- Return captured callbacks for test assertions
  local captured = { cr_callback = nil, q_callback = nil }
  rawset(vim, "keymap", {
    set = function(_, key, fn, _)
      if key == "<CR>" then
        captured.cr_callback = fn
      elseif key == "q" then
        captured.q_callback = fn
      end
    end,
  })
  return captured
end

-- Setup mock for ada_ls.spark module
---@param opts? { proof_level?: number, options?: table }
function M.setup_spark_mock(opts)
  opts = opts or {}
  local mock = {
    load_state = function()
      return {
        proof_level = opts.proof_level or 0,
        options = opts.options or {},
      }
    end,
    save_state = stub.new(),
  }
  rawset(package.loaded, "ada_ls.spark", mock)
  return mock
end

-- Create a mock ALS project view response
---@param opts? { root_name?: string, projects?: table[], runtime?: table }
---@return table
function M.create_project_view_response(opts)
  opts = opts or {}
  local root_name = opts.root_name or "main_project"
  local root_id = opts.root_id or "proj_" .. root_name

  -- Default project entry
  local default_project = {
    project = {
      id = root_id,
      name = root_name,
      kind = "standard",
      qualifier = "default",
      ["simple-name"] = root_name .. ".gpr",
      ["file-name"] = "/project/" .. root_name .. ".gpr",
      directory = "/project",
      ["is-externally-built"] = false,
      languages = { "ada" },
      ["source-directories"] = { "/project/src" },
      ["object-directory"] = "/project/obj",
    },
    imports = {},
    aggregated = {},
    extended = {},
    ["imported-by"] = {},
    sources = {
      {
        ["file-name"] = "/project/src/main.adb",
        ["simple-name"] = "main.adb",
        directory = "/project/src",
        language = "ada",
      },
      {
        ["file-name"] = "/project/src/utils.ads",
        ["simple-name"] = "utils.ads",
        directory = "/project/src",
        language = "ada",
      },
    },
  }

  local projects = opts.projects or { default_project }

  local response = {
    tree = {
      ["root-project"] = { id = root_id },
    },
    projects = projects,
  }

  if opts.runtime then
    response["runtime-project"] = opts.runtime
  end

  return response
end

-- Setup mock for lsp_cmd with project view support
---@param response? table ALS response (nil = command not supported)
---@param err? string Error message
function M.setup_lsp_cmd_project_view_mock(response, err)
  local mock = {
    get_project_view_info = function()
      if err then
        return nil, err
      end
      return response
    end,
    get_root_dir = function()
      return "/project"
    end,
  }
  rawset(package.loaded, "ada_ls.lsp_cmd", mock)
  return mock
end

return M
