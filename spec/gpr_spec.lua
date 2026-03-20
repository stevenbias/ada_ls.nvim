-- Tests for lua/ada_ls/gpr.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.gpr", function()
  local gpr

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals(nil, {
      getcwd = function()
        return "/project/root"
      end,
    })
    -- Mock vim.system for async operations
    rawset(vim, "system", stub.new())
    rawset(vim, "schedule", function(fn)
      fn()
    end)
    gpr = require("ada_ls.gpr")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("clean", function()
    it("notifies warning when no config file found", function()
      -- Setup: get_conf_file returns nil (no LSP client)
      vim.lsp.get_clients = stub.new().returns({})

      gpr.clean()

      assert.stub(vim.notify).was_called()
      local call_args = vim.notify.calls[1]
      assert.matches("No configuration file found", call_args.vals[1])
    end)

    it("notifies warning when no project file in config", function()
      -- Setup: get_conf_file returns a path, but decode_json_config returns nil
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      -- Mock project.decode_json_config to return nil
      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return nil
          end,
        }
      end
      -- Force reload of gpr to pick up the mock
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      gpr.clean()

      assert.stub(vim.notify).was_called()
      local found_msg = false
      for _, call in ipairs(vim.notify.calls) do
        if call.vals[1] and call.vals[1]:match("No Ada project file") then
          found_msg = true
          break
        end
      end
      assert.is_true(found_msg)
    end)
  end)

  describe("makeprg_setup", function()
    it("sets vim.o.makeprg when config is valid", function()
      -- Setup: mock get_conf_file and decode_json_config
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return "/project/root/my_project.gpr", " -XMODE=debug"
          end,
        }
      end
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      gpr.makeprg_setup()

      assert.is_string(vim.o.makeprg)
      assert.matches("gprbuild", vim.o.makeprg)
      assert.matches("-P", vim.o.makeprg)
      assert.matches("my_project.gpr", vim.o.makeprg)
    end)

    it("sets vim.o.errorformat to gprbuild format", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return "/project/root/my_project.gpr", ""
          end,
        }
      end
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      gpr.makeprg_setup()

      assert.is_string(vim.o.errorformat)
      -- Should contain line:column patterns for gprbuild
      assert.matches("%%f:%%l:%%c:", vim.o.errorformat)
    end)

    it("returns early when gprbuild_cmd returns nil", function()
      -- Setup: no LSP client, so gprbuild_cmd returns nil
      vim.lsp.get_clients = stub.new().returns({})
      vim.o.makeprg = nil

      gpr.makeprg_setup()

      -- makeprg should not be set
      assert.is_nil(vim.o.makeprg)
    end)
  end)

  describe("clean", function()
    it("calls vim.system with gprclean when config valid", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return "/project/root/my_project.gpr", ""
          end,
        }
      end
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      gpr.clean()

      assert.stub(vim.system).was_called()
      local call_args = vim.system.calls[1].vals
      assert.same(
        { "gprclean", "-r", "-P", "/project/root/my_project.gpr" },
        call_args[1]
      )
    end)

    it("notifies success when gprclean succeeds", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return "/project/root/my_project.gpr", ""
          end,
        }
      end
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      -- Capture the callback passed to vim.system
      local captured_callback
      rawset(vim, "system", function(_cmd, _opts, callback)
        captured_callback = callback
      end)

      gpr.clean()

      -- Invoke the callback with success result
      assert.is_function(captured_callback)
      captured_callback({ code = 0 })

      -- Check that success notification was sent
      local found_success = false
      for _, call in ipairs(vim.notify.calls) do
        if call.vals[1] and call.vals[1]:match("Clean successful") then
          found_success = true
          break
        end
      end
      assert.is_true(found_success)
    end)

    it("notifies error when gprclean fails", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      package.preload["ada_ls.project"] = function()
        return {
          decode_json_config = function()
            return "/project/root/my_project.gpr", ""
          end,
        }
      end
      package.loaded["ada_ls.gpr"] = nil
      gpr = require("ada_ls.gpr")

      -- Capture the callback passed to vim.system
      local captured_callback
      rawset(vim, "system", function(_cmd, _opts, callback)
        captured_callback = callback
      end)

      gpr.clean()

      -- Invoke the callback with failure result
      assert.is_function(captured_callback)
      captured_callback({ code = 1, stderr = "gprclean: error message" })

      -- Check that error notification was sent
      local found_error = false
      for _, call in ipairs(vim.notify.calls) do
        if call.vals[1] and call.vals[1]:match("Clean failed") then
          found_error = true
          break
        end
      end
      assert.is_true(found_error)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_gprbuild_cmd", function()
      it("returns nil when no config file found", function()
        vim.lsp.get_clients = stub.new().returns({})

        local result = gpr._gprbuild_cmd()
        assert.is_nil(result)
      end)

      it("returns nil when no project file in config", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        package.preload["ada_ls.project"] = function()
          return {
            decode_json_config = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.gpr"] = nil
        gpr = require("ada_ls.gpr")

        local result = gpr._gprbuild_cmd()
        assert.is_nil(result)
      end)

      it("returns gprbuild command string when config valid", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        package.preload["ada_ls.project"] = function()
          return {
            decode_json_config = function()
              return "/project/root/my_project.gpr", " -XMODE=debug"
            end,
          }
        end
        package.loaded["ada_ls.gpr"] = nil
        gpr = require("ada_ls.gpr")

        local result = gpr._gprbuild_cmd()
        assert.is_string(result)
        assert.matches("gprbuild", result)
        assert.matches("-d", result)
        assert.matches("-p", result)
        assert.matches("-gnatef", result)
        assert.matches("-XMODE=debug", result)
        assert.matches("-P", result)
        assert.matches("my_project.gpr", result)
      end)

      it("includes scenario variables in command", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        package.preload["ada_ls.project"] = function()
          return {
            decode_json_config = function()
              return "/project/root/test.gpr", " -XARCH=x86_64 -XDEBUG=true"
            end,
          }
        end
        package.loaded["ada_ls.gpr"] = nil
        gpr = require("ada_ls.gpr")

        local result = gpr._gprbuild_cmd()
        assert.matches("-XARCH=x86_64", result)
        assert.matches("-XDEBUG=true", result)
      end)
    end)
  end
end)
