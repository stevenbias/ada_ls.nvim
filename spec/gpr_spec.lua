-- Tests for lua/ada_ls/gprtools.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.gprtools", function()
  local gprtools
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

    gprtools = require("ada_ls.gprtools")
  end)

  after_each(function()
    common.cleanup_packages()
    package.preload["ada_ls.project"] = nil
    package.loaded["ada_ls.project"] = nil
  end)

  describe("clean", function()
    it("notifies warning when no config file found", function()
      vim.lsp.get_clients = stub.new().returns({})

      gprtools.clean()

      assert.stub(vim.notify).was_called()
      local call_args = vim.notify.calls[1]
      assert.matches("No configuration file found", call_args.vals[1])
    end)

    it("notifies warning when no project file in config", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      gprtools.clean()

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

      gprtools.clean()

      assert.stub(vim.system).was_called()
      local call_args = vim.system.calls[1].vals
      assert.same(
        { "gprclean", "-r", "-P", "/project/root/my_project.gpr" },
        call_args[1]
      )
    end)

    it("passes scenario values as individual clean arguments", function()
      common.setup_lsp_client(
        common.create_lsp_client({ root_dir = "/project/root" })
      )
      project_mock.decode_json_config = function()
        return "/project/my project.gpr",
          "unused legacy string",
          {
            scenarioVariables = {
              MODE = "release",
              OUTPUT = "a directory's $value; #%!",
              COUNT = 2,
              EMPTY = "",
            },
          }
      end

      gprtools.clean()

      assert.same({
        "gprclean",
        "-r",
        "-P",
        "/project/my project.gpr",
        "-XCOUNT=2",
        "-XEMPTY=",
        "-XMODE=release",
        "-XOUTPUT=a directory's $value; #%!",
      }, vim.system.calls[1].vals[1])
    end)

    it("omits scenario arguments for an empty variable table", function()
      common.setup_lsp_client(
        common.create_lsp_client({ root_dir = "/project/root" })
      )
      project_mock.decode_json_config = function()
        return "/project/root/test.gpr", "", { scenarioVariables = {} }
      end

      gprtools.clean()

      assert.same(
        { "gprclean", "-r", "-P", "/project/root/test.gpr" },
        vim.system.calls[1].vals[1]
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

      gprtools.clean()

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

      gprtools.clean()

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
    local function check_build_arguments(from_file)
      local directory = os.tmpname()
      os.remove(directory)
      vim.call("mkdir", directory, "p")
      local output = directory .. "/arguments"
      local original_path = vim.call("getenv", "PATH")
      local original_output = vim.call("getenv", "ADA_LS_TEST_ARGS")
      local bufnr = vim.call("bufnr", "%")
      local original_makeprg = vim.call("getbufvar", bufnr, "&makeprg")
      local original_errorformat = vim.call("getbufvar", bufnr, "&errorformat")
      local ok, err = pcall(function()
        vim.call("writefile", {
          "#!/bin/sh",
          'printf "%s\\n" "$@" > "$ADA_LS_TEST_ARGS"',
        }, directory .. "/gprbuild")
        vim.call("setfperm", directory .. "/gprbuild", "rwx------")
        vim.call("setenv", "PATH", directory .. ":" .. original_path)
        vim.call("setenv", "ADA_LS_TEST_ARGS", output)

        local config = {
          projectFile = "/project/my project's #%!.gpr",
          scenarioVariables = {
            OUTPUT = "a directory's $value; `printf expanded` $(printf expanded) #%! <cword>",
            EMPTY = "",
          },
        }
        if from_file then
          common.setup_lsp_client(
            common.create_lsp_client({ root_dir = "/project/root" })
          )
          project_mock.decode_json_config = function()
            return config.projectFile, "unused legacy string", config
          end
          gprtools.makeprg_setup()
        else
          gprtools.makeprg_setup(config)
        end

        -- Run Neovim's real :make so both Ex expansion and shell parsing apply.
        vim.call("setbufvar", bufnr, "&makeprg", vim.bo.makeprg)
        vim.call("setbufvar", bufnr, "&errorformat", vim.bo.errorformat)
        local make_output = vim.call("execute", "silent make!")
        assert.equals(1, vim.call("filereadable", output), make_output)
        assert.same({
          "-d",
          "-p",
          "-gnatef",
          "-XEMPTY=",
          "-XOUTPUT=" .. config.scenarioVariables.OUTPUT,
          "-P",
          config.projectFile,
        }, vim.call("readfile", output))
      end)

      vim.call("setenv", "PATH", original_path)
      vim.call("setenv", "ADA_LS_TEST_ARGS", original_output)
      vim.call("setbufvar", bufnr, "&makeprg", original_makeprg)
      vim.call("setbufvar", bufnr, "&errorformat", original_errorformat)
      vim.call("delete", directory, "rf")
      assert(ok, err)
    end

    it(
      "preserves direct-config arguments through :make and the shell",
      function()
        check_build_arguments(false)
      end
    )

    it("preserves file-config arguments through :make and the shell", function()
      check_build_arguments(true)
    end)

    it("sets vim.bo.makeprg when config is valid", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr",
          " -XMODE=debug",
          { scenarioVariables = { MODE = "debug" } }
      end

      gprtools.makeprg_setup()

      assert.is_string(vim.bo.makeprg)
      assert.matches("gprbuild", vim.bo.makeprg)
      assert.matches("-P", vim.bo.makeprg)
      assert.matches("my_project.gpr", vim.bo.makeprg)
    end)

    it("sets vim.bo.errorformat with all gprbuild patterns", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      project_mock.decode_json_config = function()
        return "/project/root/my_project.gpr", ""
      end

      gprtools.makeprg_setup()

      assert.is_string(vim.bo.errorformat)
      assert.matches("%%f:%%l:%%c:", vim.bo.errorformat)
      assert.matches("%%f:%%l:", vim.bo.errorformat)
      assert.matches("%%*", vim.bo.errorformat)
      assert.matches("%-G", vim.bo.errorformat)
    end)

    it("returns early when gprbuild_cmd returns nil", function()
      vim.lsp.get_clients = stub.new().returns({})
      vim.bo.makeprg = nil

      gprtools.makeprg_setup()

      assert.is_nil(vim.bo.makeprg)
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
      gprtools.makeprg_setup(json_config)

      assert.is_string(vim.bo.makeprg)
      assert.matches("gprbuild", vim.bo.makeprg)
      assert.matches("-P", vim.bo.makeprg)
      assert.matches("my_project.gpr", vim.bo.makeprg)
      assert.matches("-XMODE=debug", vim.bo.makeprg)
      assert.matches("-XARCH=x86_64", vim.bo.makeprg)
    end)

    it("excludes -X vars when scenarioVariables is empty", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      local json_config = {
        projectFile = "/test/my_project.gpr",
        scenarioVariables = {},
      }
      gprtools.makeprg_setup(json_config)

      assert.is_string(vim.bo.makeprg)
      assert.matches("gprbuild", vim.bo.makeprg)
      assert.not_matches("%-X", vim.bo.makeprg)
    end)
  end)

  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_gprbuild_cmd", function()
      it("returns nil when no config file found", function()
        vim.lsp.get_clients = stub.new().returns({})

        local result = gprtools._gprbuild_cmd()
        assert.is_nil(result)
      end)

      it("returns nil when no project file in config", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        local result = gprtools._gprbuild_cmd()
        assert.is_nil(result)
      end)

      it("returns gprbuild command string when config valid", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)
        project_mock.decode_json_config = function()
          return "/project/root/my_project.gpr",
            " -XMODE=debug",
            { scenarioVariables = { MODE = "debug" } }
        end

        local result = gprtools._gprbuild_cmd()
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
          return "/project/root/test.gpr",
            " -XARCH=x86_64 -XDEBUG=true",
            { scenarioVariables = { ARCH = "x86_64", DEBUG = true } }
        end

        local result = gprtools._gprbuild_cmd()
        assert.matches("-XARCH=x86_64", result)
        assert.matches("-XDEBUG=true", result)
      end)

      it("reads from config file when json_config not provided", function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)
        project_mock.decode_json_config = function()
          return "/project/test.gpr",
            " -XMODE=release",
            { scenarioVariables = { MODE = "release" } }
        end

        local result = gprtools._gprbuild_cmd(nil)

        assert.is_string(result)
        assert.matches("/project/test.gpr", result)
        assert.matches("-XMODE=release", result)
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
        local result = gprtools._gprbuild_cmd(json_config)
        assert.is_string(result)
        assert.matches("direct.gpr", result)
        assert.matches("-XTEST=yes", result)
      end)
    end)
  end
end)
