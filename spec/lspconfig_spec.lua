-- Tests for lua/ada_ls/lspconfig.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.lspconfig", function()
  local lspconfig

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    -- Add mocks for vim.lsp fields used by lspconfig
    vim.lsp.protocol = {
      make_client_capabilities = stub.new().returns({}),
    }
    vim.lsp.config = stub.new()
    vim.lsp.enable = stub.new()
    vim.lsp.handlers = {}
    lspconfig = require("ada_ls.lspconfig")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  -- Helper: call get() and return the config table
  local function call_get_config()
    return lspconfig.get()
  end

  -- Helper: install als_handlers with a known original, return the wrapper
  local function setup_handler(original)
    vim.lsp.handlers = {}
    vim.lsp.handlers["workspace/applyEdit"] = original or function() end
    lspconfig._als_handlers()
    return vim.lsp.handlers["workspace/applyEdit"]
  end

  describe("get", function()
    it(
      "returns config with capabilities, handlers, on_attach and root_dir",
      function()
        local config = call_get_config()

        assert.is_not_nil(config.capabilities)
        assert.is_not_nil(vim.lsp.handlers["workspace/applyEdit"])
        assert.is_function(config.root_dir)
        assert.is_function(config.on_attach)
      end
    )

    it("returns cached config on subsequent calls", function()
      local config1 = call_get_config()
      local config2 = call_get_config()

      assert.equals(config1, config2)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_on_als_attach", function()
      it("sets loaded flag and creates QuickFixCmdPost autocmd", function()
        rawset(vim, "opt", {
          diff = {
            get = function()
              return true
            end,
          },
        })

        lspconfig._on_als_attach()

        assert.is_true(vim.g.loaded_ada_ls)
        local found_qf = false
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            found_qf = true
            break
          end
        end
        assert.is_true(found_qf)
      end)
    end)

    describe("_als_capabilities", function()
      local original_open

      before_each(function()
        original_open = io.open
      end)

      after_each(function()
        rawset(io, "open", original_open)
      end)

      it("returns base capabilities when json file not found", function()
        rawset(io, "open", function(path, ...)
          if path and path:match("vscode_capabilities%.json$") then
            return nil
          end
          return original_open(path, ...)
        end)

        local caps = lspconfig._als_capabilities()

        assert.is_table(caps)
      end)

      it("returns base capabilities when json decode fails", function()
        rawset(io, "open", function(path, ...)
          if path and path:match("vscode_capabilities%.json$") then
            return {
              read = function()
                return "invalid json{{"
              end,
              close = function() end,
            }
          end
          return original_open(path, ...)
        end)
        rawset(vim.json, "decode", function()
          error("decode error")
        end)

        local caps = lspconfig._als_capabilities()

        assert.is_table(caps)
      end)

      it("merges vscode capabilities on success", function()
        rawset(io, "open", function(path, ...)
          if path and path:match("vscode_capabilities%.json$") then
            return {
              read = function()
                return '{"textDocument":{"test":true}}'
              end,
              close = function() end,
            }
          end
          return original_open(path, ...)
        end)
        rawset(vim.json, "decode", function()
          return { textDocument = { test = true } }
        end)
        rawset(vim, "tbl_deep_extend", function(_, a, b)
          for k, v in pairs(b) do
            a[k] = v
          end
          return a
        end)

        local caps = lspconfig._als_capabilities()

        assert.is_table(caps)
      end)
    end)

    describe("_als_handlers", function()
      it("installs workspace/applyEdit handler", function()
        lspconfig._als_handlers()

        assert.is_function(vim.lsp.handlers["workspace/applyEdit"])
      end)

      it("strips annotationId when changeAnnotations missing", function()
        local handler = setup_handler(function() end)

        local result = {
          edit = {
            documentChanges = {
              {
                edits = {
                  { newText = "test", annotationId = "ann1" },
                  { newText = "test2", annotationId = "ann2" },
                },
              },
            },
          },
        }

        handler(nil, result, {}, {})

        assert.is_nil(result.edit.documentChanges[1].edits[1].annotationId)
        assert.is_nil(result.edit.documentChanges[1].edits[2].annotationId)
      end)

      it("handles create kind and executes scheduled callback", function()
        local scheduled_fns = {}
        rawset(vim, "schedule", function(fn)
          table.insert(scheduled_fns, fn)
        end)
        rawset(vim, "uri_to_fname", function(uri)
          return uri:gsub("file://", "")
        end)

        local original_called = false
        local handler = setup_handler(function()
          original_called = true
        end)

        package.loaded["ada_ls.utils"] = {
          reset_als_client = stub.new(),
          try_require = function()
            return false
          end,
          notify = stub.new(),
          clear = stub.new(),
        }

        handler(nil, {
          edit = {
            changeAnnotations = { ann1 = {} },
            documentChanges = {
              { kind = "create", uri = "file:///test/new_file.adb" },
            },
          },
        }, {}, {})

        assert.is_true(original_called)
        assert.equals(1, #scheduled_fns)

        -- Execute scheduled callback - empty last line triggers normal cmds
        vim.cmd = { edit = stub.new(), normal = stub.new() }
        vim.fn.getline = stub.new().returns("")
        scheduled_fns[1]()
        assert.stub(vim.cmd.edit).was_called_with("/test/new_file.adb")
        assert.stub(vim.cmd.normal).was_called()
      end)

      it("skips normal commands when last line not empty", function()
        local scheduled_fns = {}
        rawset(vim, "schedule", function(fn)
          table.insert(scheduled_fns, fn)
        end)
        rawset(vim, "uri_to_fname", function(uri)
          return uri:gsub("file://", "")
        end)

        local handler = setup_handler(function() end)

        package.loaded["ada_ls.utils"] = {
          reset_als_client = stub.new(),
          try_require = function()
            return false
          end,
          notify = stub.new(),
          clear = stub.new(),
        }

        handler(nil, {
          edit = {
            changeAnnotations = { ann1 = {} },
            documentChanges = {
              { kind = "create", uri = "file:///test/new_file.adb" },
            },
          },
        }, {}, {})

        vim.cmd = { edit = stub.new(), normal = stub.new() }
        vim.fn.getline = stub.new().returns("end My_Package;")
        scheduled_fns[1]()
        assert.stub(vim.cmd.edit).was_called()
        assert.stub(vim.cmd.normal).was_not_called()
      end)

      it("handles textDocument and executes scheduled callback", function()
        local scheduled_fns = {}
        rawset(vim, "schedule", function(fn)
          table.insert(scheduled_fns, fn)
        end)
        rawset(vim, "uri_to_fname", function(uri)
          return uri:gsub("file://", "")
        end)

        local handler = setup_handler(function() end)

        handler(nil, {
          edit = {
            changeAnnotations = { ann1 = {} },
            documentChanges = {
              { textDocument = { uri = "file:///test/existing.adb" } },
            },
          },
        }, {}, {})

        assert.equals(1, #scheduled_fns)
        vim.cmd = { edit = stub.new() }
        scheduled_fns[1]()
        assert.stub(vim.cmd.edit).was_called()
        local call_args = vim.cmd.edit.calls[1].vals
        assert.equals("/test/existing.adb", call_args[1])
      end)

      it("passes through to original handler and returns response", function()
        local handler = setup_handler(function()
          return { applied = true }
        end)

        -- nil result - no edit processing
        local r1 = handler(nil, nil, {}, {})
        assert.same({ applied = true }, r1)

        -- result without edit field - no edit processing
        local r2 = handler(nil, { something = "else" }, {}, {})
        assert.same({ applied = true }, r2)
      end)
    end)

    describe("root_dir callback", function()
      it("calls on_dir with vim.fs.root result", function()
        rawset(vim.fs, "root", function()
          return "/project/root"
        end)
        local config = call_get_config()

        local received = {}
        config.root_dir(1, function(dir)
          table.insert(received, dir)
        end)
        assert.equals("/project/root", received[1])
      end)

      it("passes nil when vim.fs.root returns nil", function()
        rawset(vim.fs, "root", function()
          return nil
        end)
        local config = call_get_config()

        local received_nil = "sentinel"
        config.root_dir(1, function(dir)
          received_nil = dir
        end)
        assert.is_nil(received_nil)
      end)
    end)

    describe("_open_qf_on_make", function()
      it("creates QuickFixCmdPost autocmd for make", function()
        lspconfig._open_qf_on_make()

        assert.stub(vim.api.nvim_create_autocmd).was_called()

        local found_qf = false
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            found_qf = true
            local opts = call.vals[2]
            assert.equals("make", opts.pattern)
            assert.is_function(opts.callback)
            break
          end
        end
        assert.is_true(found_qf)
      end)

      it("opens quickfix when items exist", function()
        lspconfig._open_qf_on_make()

        local callback = nil
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            callback = call.vals[2].callback
            break
          end
        end
        assert.is_function(callback)

        vim.fn.getqflist = stub.new().returns({ { text = "error" } })
        vim.cmd = stub.new()
        callback()
        assert.stub(vim.cmd).was_called_with("copen")
      end)

      it("does not open quickfix when no items", function()
        lspconfig._open_qf_on_make()

        local callback = nil
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            callback = call.vals[2].callback
            break
          end
        end
        assert.is_function(callback)

        vim.fn.getqflist = stub.new().returns({})
        vim.cmd = stub.new()
        callback()
        assert.stub(vim.cmd).was_not_called()
      end)
    end)
  end
end)
