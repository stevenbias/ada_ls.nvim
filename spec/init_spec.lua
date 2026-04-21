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

  describe("setup", function()
    it("configures ada_ls with on_attach callback", function()
      local config = call_setup_and_get_config()

      assert.equals("ada_ls", vim.lsp.config.calls[1].vals[1])
      assert.is_function(config.on_attach)
    end)

    it("creates LspDetach autocmd for Ada files", function()
      ada_ls.setup()

      local found_detach = false
      for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
        if call.vals[1] == "LspDetach" then
          found_detach = true
          local opts = call.vals[2]
          assert.is_function(opts.callback)
          assert.same({ "*.ad[bs]" }, opts.pattern)
          break
        end
      end
      assert.is_true(found_detach)
    end)

    it("enables the ada_ls LSP client", function()
      ada_ls.setup()

      assert.stub(vim.lsp.enable).was_called_with("ada_ls")
    end)

    it("includes capabilities, on_attach and root_dir", function()
      local config = call_setup_and_get_config()

      assert.is_not_nil(config.capabilities)
      assert.is_function(config.on_attach)
      assert.is_function(config.root_dir)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
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
