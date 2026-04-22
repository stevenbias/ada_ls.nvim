-- Tests for lua/ada_ls/gpr.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.gpr", function()
  local gpr
  local project_mock

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals(nil, {
      getcwd = function()
        return "/project/root"
      end,
    })
    rawset(vim, "system", stub.new())
    rawset(vim, "schedule", function(fn)
      fn()
    end)

    project_mock = {
      decode_json_config = function()
        return nil
      end,
    }
    package.preload["ada_ls.project"] = function()
      return project_mock
    end
    package.loaded["ada_ls.project"] = nil

    gpr = require("ada_ls.gpr")
  end)

  after_each(function()
    common.cleanup_packages()
    package.preload["ada_ls.project"] = nil
    package.loaded["ada_ls.project"] = nil
  end)

  describe("clean", function()
    it("notifies warning when no config file found", function()
      vim.lsp.get_clients = stub.new().returns({})

      gpr.clean()

      assert.stub(vim.notify).was_called()
      local call_args = vim.notify.calls[1]
      assert.matches("No configuration file found", call_args.vals[1])
    end)

    it("notifies warning when no project file in config", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

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

    it("calls vim.system with gprclean when config valid", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", ""
      end

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
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", ""
      end

      local captured_callback
      rawset(vim, "system", function(_cmd, _opts, callback)
        captured_callback = callback
      end)

      gpr.clean()

      assert.is_function(captured_callback)
      captured_callback({ code = 0 })

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
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", ""
      end

      local captured_callback
      rawset(vim, "system", function(_cmd, _opts, callback)
        captured_callback = callback
      end)

      gpr.clean()

      assert.is_function(captured_callback)
      captured_callback({ code = 1, stderr = "gprclean: error message" })

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

  describe("makeprg_setup", function()
    it("sets vim.o.makeprg when config is valid", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", " -XMODE=debug"
      end

      gpr.makeprg_setup()

      assert.is_string(vim.o.makeprg)
      assert.matches("gprbuild", vim.o.makeprg)
      assert.matches("-P", vim.o.makeprg)
      assert.matches("my_project.gpr", vim.o.makeprg)
    end)

    it("sets vim.o.errorformat with all gprbuild patterns", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", ""
      end

      gpr.makeprg_setup()

      assert.is_string(vim.o.errorformat)
      assert.matches("%%f:%%l:%%c:", vim.o.errorformat)
      assert.matches("%%f:%%l:", vim.o.errorformat)
      assert.matches("%%*", vim.o.errorformat)
      assert.matches("%-G", vim.o.errorformat)
    end)

    it("returns early when gprbuild_cmd returns nil", function()
      vim.lsp.get_clients = stub.new().returns({})
      vim.o.makeprg = nil

      gpr.makeprg_setup()

      assert.is_nil(vim.o.makeprg)
    end)

    it("uses json_config parameter directly when provided", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      local json_config = {
        projectFile = "/test/my_project.gpr",
        scenarioVariables = {
          MODE = "debug",
          ARCH = "x86_64",
        },
      }
      gpr.makeprg_setup(json_config)

      assert.is_string(vim.o.makeprg)
      assert.matches("gprbuild", vim.o.makeprg)
      assert.matches("-P", vim.o.makeprg)
      assert.matches("my_project.gpr", vim.o.makeprg)
      assert.matches("-XMODE=debug", vim.o.makeprg)
      assert.matches("-XARCH=x86_64", vim.o.makeprg)
    end)

    it("excludes -X vars when scenarioVariables is empty", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      local json_config = {
        projectFile = "/test/my_project.gpr",
        scenarioVariables = {},
      }
      gpr.makeprg_setup(json_config)

      assert.is_string(vim.o.makeprg)
      assert.matches("gprbuild", vim.o.makeprg)
      assert.not_matches("%-X", vim.o.makeprg)
    end)
  end)

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

        local result = gpr._gprbuild_cmd()
        assert.is_nil(result)
      end)

      it("returns gprbuild command string when config valid", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)
        project_mock.decode_json_config = function()
          return "/project/root/my_project.gpr", " -XMODE=debug"
        end

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
        project_mock.decode_json_config = function()
          return "/project/root/test.gpr", " -XARCH=x86_64 -XDEBUG=true"
        end

        local result = gpr._gprbuild_cmd()
        assert.matches("-XARCH=x86_64", result)
        assert.matches("-XDEBUG=true", result)
      end)

      it("uses json_config parameter directly", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        local json_config = {
          projectFile = "/test/direct.gpr",
          scenarioVariables = {
            TEST = "yes",
          },
        }
        local result = gpr._gprbuild_cmd(json_config)
        assert.is_string(result)
        assert.matches("direct.gpr", result)
        assert.matches("-XTEST=yes", result)
      end)
    end)
  end
end)
