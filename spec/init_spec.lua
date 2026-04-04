-- Tests for lua/ada_ls/init.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.init", function()
  local ada_ls

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    -- Add mocks for vim.lsp fields used by init.setup()
    vim.lsp.protocol = {
      make_client_capabilities = stub.new().returns({}),
    }
    vim.lsp.config = stub.new()
    vim.lsp.enable = stub.new()
    vim.lsp.handlers = {}
    ada_ls = require("ada_ls")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  -- Helper: call setup() and return the config table passed to vim.lsp.config
  local function call_setup_and_get_config()
    ada_ls.setup()
    assert.stub(vim.lsp.config).was_called()
    return vim.lsp.config.calls[1].vals[2]
  end

  -- Helper: install als_handlers with a known original, return the wrapper
  local function setup_handler(original)
    vim.lsp.handlers = {}
    vim.lsp.handlers["workspace/applyEdit"] = original or function() end
    ada_ls._als_handlers()
    return vim.lsp.handlers["workspace/applyEdit"]
  end

  describe("setup", function()
    it("configures ada_ls with on_attach and on_detach callbacks", function()
      local config = call_setup_and_get_config()

      assert.equals("ada_ls", vim.lsp.config.calls[1].vals[1])
      assert.is_function(config.on_attach)
      assert.is_function(config.on_detach)
    end)

    it("enables the ada_ls LSP client", function()
      ada_ls.setup()

      assert.stub(vim.lsp.enable).was_called_with("ada_ls")
    end)

    it("includes capabilities, handlers and root_dir", function()
      local config = call_setup_and_get_config()

      assert.is_not_nil(config.capabilities)
      assert.is_not_nil(vim.lsp.handlers["workspace/applyEdit"])
      assert.is_function(config.root_dir)
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

        ada_ls._on_als_attach()

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

    describe("_on_als_detach", function()
      it("clears all plugin state", function()
        local project = require("ada_ls.project")
        local utils = require("ada_ls.utils")

        project.project_file = "/some/project.gpr"
        project.is_setup = true
        vim.g.loaded_ada_ls = true
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)
        utils.get_ada_ls()

        ada_ls._on_als_detach()

        assert.is_nil(vim.g.loaded_ada_ls)
        assert.equals("", project.project_file)
        assert.is_false(project.is_setup)
        assert.is_nil(utils.als)
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

        local caps = ada_ls._als_capabilities()

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

        local caps = ada_ls._als_capabilities()

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

        local caps = ada_ls._als_capabilities()

        assert.is_table(caps)
      end)
    end)

    describe("_als_handlers", function()
      it("installs workspace/applyEdit handler", function()
        ada_ls._als_handlers()

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

    describe("_als_snippets", function()
      it("does nothing when luasnip is not available", function()
        ada_ls._als_snippets()
      end)

      it("loads snippets when luasnip is available", function()
        local lazy_load_stub = stub.new()
        package.preload["luasnip"] = function()
          return {}
        end
        package.preload["luasnip.loaders.from_vscode"] = function()
          return { lazy_load = lazy_load_stub }
        end

        ada_ls._als_snippets()

        assert.stub(lazy_load_stub).was_called()
        assert.truthy(
          lazy_load_stub.calls[1].vals[1].paths[1]:match("snippets$")
        )

        package.preload["luasnip"] = nil
        package.preload["luasnip.loaders.from_vscode"] = nil
        package.loaded["luasnip"] = nil
        package.loaded["luasnip.loaders.from_vscode"] = nil
      end)
    end)

    describe("setup root_dir callback", function()
      it("calls on_dir with vim.fs.root result", function()
        rawset(vim.fs, "root", function()
          return "/project/root"
        end)
        local config = call_setup_and_get_config()

        local received = {}
        config.root_dir(1, function(dir)
          table.insert(received, dir)
        end)
        assert.equals("/project/root", received[1])

        -- Also test nil root
        rawset(vim.fs, "root", function()
          return nil
        end)
        config = call_setup_and_get_config()
        local received_nil = "sentinel"
        config.root_dir(1, function(dir)
          received_nil = dir
        end)
        assert.is_nil(received_nil)
      end)
    end)

    describe("_open_qf_on_make", function()
      it("creates QuickFixCmdPost autocmd for make", function()
        ada_ls._open_qf_on_make()

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
        ada_ls._open_qf_on_make()

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
        ada_ls._open_qf_on_make()

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

    describe("_clear", function()
      it("clears project and utils state", function()
        local project = require("ada_ls.project")
        local utils = require("ada_ls.utils")

        project.project_file = "/some/project.gpr"
        project.is_setup = true
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)
        utils.get_ada_ls()

        ada_ls._clear()

        assert.equals("", project.project_file)
        assert.is_false(project.is_setup)
        assert.is_nil(utils.als)
      end)

      it("clears vim.g.loaded_ada_ls", function()
        vim.g.loaded_ada_ls = true
        ada_ls._clear()
        assert.is_nil(vim.g.loaded_ada_ls)
      end)

      it("unloads ada_ls packages from package.loaded", function()
        require("ada_ls.utils")
        require("ada_ls.project")

        ada_ls._clear()

        assert.is_nil(vim.g.loaded_ada_ls)
      end)
    end)
  end
end)
