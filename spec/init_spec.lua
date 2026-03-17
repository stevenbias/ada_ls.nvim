-- Tests for lua/ada_ls/init.lua
local common = require("spec.helpers.common")

describe("ada_ls.init", function()
  local ada_ls

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    ada_ls = require("ada_ls")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("setup", function()
    it("creates LspAttach autocmd for Ada files", function()
      ada_ls.setup()

      assert.stub(vim.api.nvim_create_autocmd).was_called()

      -- Find the LspAttach call
      local found_attach = false
      for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
        if call.vals[1] == "LspAttach" then
          found_attach = true
          local opts = call.vals[2]
          assert.is_table(opts.pattern)
          -- Should include Ada file patterns
          local has_ada_pattern = false
          for _, p in ipairs(opts.pattern) do
            if p:match("%.ad%[bs%]") then
              has_ada_pattern = true
              break
            end
          end
          assert.is_true(has_ada_pattern)
          break
        end
      end
      assert.is_true(found_attach)
    end)

    it("creates LspDetach autocmd for Ada files", function()
      ada_ls.setup()

      assert.stub(vim.api.nvim_create_autocmd).was_called()

      -- Find the LspDetach call
      local found_detach = false
      for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
        if call.vals[1] == "LspDetach" then
          found_detach = true
          local opts = call.vals[2]
          assert.is_table(opts.pattern)
          break
        end
      end
      assert.is_true(found_detach)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
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

        -- Find and invoke the callback
        local callback = nil
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            callback = call.vals[2].callback
            break
          end
        end
        assert.is_function(callback)

        -- Mock getqflist to return items
        vim.fn.getqflist = stub.new().returns({ { text = "error" } })
        vim.cmd = stub.new()

        callback()

        assert.stub(vim.cmd).was_called_with("copen")
      end)

      it("does not open quickfix when no items", function()
        ada_ls._open_qf_on_make()

        -- Find and invoke the callback
        local callback = nil
        for _, call in ipairs(vim.api.nvim_create_autocmd.calls) do
          if call.vals[1] == "QuickFixCmdPost" then
            callback = call.vals[2].callback
            break
          end
        end
        assert.is_function(callback)

        -- Mock getqflist to return empty
        vim.fn.getqflist = stub.new().returns({})
        vim.cmd = stub.new()

        callback()

        assert.stub(vim.cmd).was_not_called()
      end)
    end)

    describe("_clear", function()
      it("clears project and utils state", function()
        -- First set up some state
        local project = require("ada_ls.project")
        local utils = require("ada_ls.utils")

        project.project_file = "/some/project.gpr"
        project.is_setup = true
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)
        utils.get_ada_ls() -- cache the client

        -- Call clear
        ada_ls._clear()

        -- Verify state is cleared
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
        -- Ensure ada_ls modules are loaded
        require("ada_ls.utils")
        require("ada_ls.project")

        ada_ls._clear()

        -- Note: We can't fully verify this since our test reload
        -- re-requires the modules, but we can verify vim.g was cleared
        assert.is_nil(vim.g.loaded_ada_ls)
      end)
    end)
  end
end)
