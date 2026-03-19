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
  package.preload["ada_ls.gpr"] = nil
  package.preload["ada_ls.spark"] = nil
  package.preload["ada_ls.spark.config"] = nil
  -- Then clear loaded modules
  package.loaded["ada_ls"] = nil
  package.loaded["ada_ls.utils"] = nil
  package.loaded["ada_ls.lsp_cmd"] = nil
  package.loaded["ada_ls.project"] = nil
  package.loaded["ada_ls.gpr"] = nil
  package.loaded["ada_ls.spark"] = nil
  package.loaded["ada_ls.spark.config"] = nil
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
    name = "ada",
    root_dir = "/project/root",
    offset_encoding = "utf-8",
    request_sync = stub.new().returns(nil),
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
function M.fixture_path(filename)
  -- Use pwd-relative path that works with busted
  return "spec/fixtures/" .. filename
end

return M
