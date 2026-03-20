-- Tests for lua/ada_ls/project.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.project", function()
  local function setup_base_mocks()
    common.setup_vim_globals(nil, nil, {
      opt = {
        diff = {
          get = function()
            return false
          end,
        },
      },
      uri_to_fname = function(uri)
        return (uri:gsub("file://", ""))
      end,
    })
    -- Mock vim.fs.abspath
    rawset(vim.fs, "abspath", function(path)
      return "/absolute" .. path
    end)
    -- Mock vim.fs.joinpath
    rawset(vim.fs, "joinpath", function(...)
      return table.concat({ ... }, "/")
    end)
    -- Mock vim.fs.dirname to handle nil
    rawset(vim.fs, "dirname", function(path)
      if path == nil then
        return nil
      end
      return path:match("(.*/)")
    end)
  end

  describe("decode_json_config", function()
    local project

    before_each(function()
      common.cleanup_packages()
      setup_base_mocks()
      -- Default json.decode returns empty table (simulates no valid config)
      rawset(vim.json, "decode", function()
        return {}
      end)
      project = require("ada_ls.project")
    end)

    after_each(function()
      if project and project.clear then
        project.clear()
      end
      common.cleanup_packages()
    end)

    it("returns nil values when file does not exist", function()
      local prj, vars, config =
        project.decode_json_config("/nonexistent/.als.json")
      assert.is_nil(prj)
      assert.is_nil(vars)
      assert.is_nil(config)
    end)

    it("returns nil values when JSON is invalid", function()
      -- Create a temp file with invalid JSON
      local temp_file = os.tmpname()
      local file = io.open(temp_file, "w")
      file:write("{ invalid json }")
      file:close()

      -- Override vim.json.decode to simulate real behavior (throws on invalid)
      rawset(vim.json, "decode", function(_raw)
        error("Invalid JSON")
      end)

      local prj, vars, config = project.decode_json_config(temp_file)
      assert.is_nil(prj)
      assert.is_nil(vars)
      assert.is_nil(config)

      os.remove(temp_file)
    end)

    it("parses valid JSON config and extracts project file", function()
      local fixture_path = common.fixture_path("als_config.json")
      -- Override vim.json.decode to parse our fixture
      rawset(vim.json, "decode", function(_raw)
        return {
          projectFile = "/project/root/my_project.gpr",
          scenarioVariables = {
            MODE = "debug",
            PLATFORM = "linux",
          },
          defaultCharset = "UTF-8",
          relocateBuildTree = "/project/build",
          rootDir = "/project/root",
        }
      end)

      local prj, vars, config = project.decode_json_config(fixture_path)

      assert.equals("/project/root/my_project.gpr", prj)
      assert.is_string(vars)
      assert.is_table(config)
      assert.equals("/project/root/my_project.gpr", config.projectFile)
    end)

    it("builds scenario variables string from config", function()
      local fixture_path = common.fixture_path("als_config.json")
      -- Override vim.json.decode to parse our fixture
      rawset(vim.json, "decode", function(_raw)
        return {
          projectFile = "/project/root/my_project.gpr",
          scenarioVariables = {
            MODE = "debug",
            PLATFORM = "linux",
          },
        }
      end)

      local _, vars, _ = project.decode_json_config(fixture_path)

      -- The fixture has MODE=debug and PLATFORM=linux
      assert.matches("-XMODE=debug", vars)
      assert.matches("-XPLATFORM=linux", vars)
    end)
  end)

  describe("pick_gpr_file", function()
    local project

    before_each(function()
      common.cleanup_packages()
      setup_base_mocks()
      rawset(vim.json, "decode", function()
        return {}
      end)
      project = require("ada_ls.project")
    end)

    after_each(function()
      if project and project.clear then
        project.clear()
      end
      common.cleanup_packages()
    end)

    it("notifies when no GPR files found", function()
      vim.fs.find = stub.new().returns({})
      vim.fn.isdirectory = stub.new().returns(0)

      project.pick_gpr_file()

      assert.stub(vim.notify_once).was_called()
      local call_args = vim.notify_once.calls[1]
      assert.matches("No Ada project files found", call_args.vals[1])
    end)

    it("sets project_file when single GPR file found", function()
      vim.fs.find = stub.new().returns({ "/project/only.gpr" })
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fn.filereadable = stub.new().returns(0) -- No gpr content to read
      rawset(vim, "system", stub.new()) -- For reset_als_client

      -- Mock lsp_cmd to avoid actual LSP calls
      package.preload["ada_ls.lsp_cmd"] = function()
        return {
          get_prj_file = function()
            return "/project/only.gpr"
          end,
          get_prj_dependencies = function()
            return nil
          end,
          get_root_dir = function()
            return "/project"
          end,
        }
      end
      package.loaded["ada_ls.lsp_cmd"] = nil
      package.loaded["ada_ls.project"] = nil
      project = require("ada_ls.project")

      project.pick_gpr_file()

      assert.equals("/project/only.gpr", project.project_file)
      assert.stub(vim.notify).was_called()
    end)
  end)

  describe("clear", function()
    local project

    before_each(function()
      common.cleanup_packages()
      setup_base_mocks()
      rawset(vim.json, "decode", function()
        return {}
      end)
      project = require("ada_ls.project")
    end)

    after_each(function()
      common.cleanup_packages()
    end)

    it("resets module state", function()
      project.project_file = "/some/project.gpr"
      project.scenario_variables = { MODE = "debug" }
      project.is_setup = true

      project.clear()

      assert.equals("", project.project_file)
      assert.same({}, project.scenario_variables)
      assert.is_false(project.is_setup)
    end)
  end)

  describe("setup", function()
    local project

    before_each(function()
      common.cleanup_packages()
      setup_base_mocks()
      rawset(vim.json, "decode", function()
        return {}
      end)
      project = require("ada_ls.project")
    end)

    after_each(function()
      if project and project.clear then
        project.clear()
      end
      common.cleanup_packages()
    end)

    it("returns early when in diff mode", function()
      rawset(vim, "opt", {
        diff = {
          get = function()
            return true
          end,
        },
      })

      project.setup()

      -- Should return early without setting is_setup
      assert.is_false(project.is_setup)
    end)

    it("returns early when already setup", function()
      project.is_setup = true

      project.setup()

      -- Should not have done anything since already setup
      assert.is_true(project.is_setup)
    end)

    it("returns early when no Ada LSP client", function()
      vim.lsp.get_clients = stub.new().returns({})

      project.setup()

      assert.is_false(project.is_setup)
    end)

    it("returns early when config file not readable", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)
      rawset(vim.fs, "joinpath", function(dir, file)
        return dir .. "/" .. file
      end)
      vim.fn.filereadable = stub.new().returns(0)
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fs.find = stub.new().returns({ "/project/root/test.gpr" })

      project.setup()

      assert.is_false(project.is_setup)
    end)

    it("completes setup when config is valid", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      rawset(vim.fs, "joinpath", function(dir, file)
        return dir .. "/" .. file
      end)
      vim.fn.filereadable = stub.new().returns(1)
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fs.find = stub.new().returns({ "/project/root/test.gpr" })

      -- Create a temp config file
      local temp_file = os.tmpname()
      local file = io.open(temp_file, "w")
      file:write('{"projectFile": "/project/root/test.gpr"}')
      file:close()

      rawset(vim.json, "decode", function(_raw)
        return { projectFile = "/project/root/test.gpr" }
      end)

      -- Mock the decode_json_config to use our temp file
      local orig_decode = project.decode_json_config
      project.decode_json_config = function(_path)
        return orig_decode(temp_file)
      end

      project.setup()

      assert.is_true(project.is_setup)
      assert.stub(vim.notify_once).was_called()

      os.remove(temp_file)
    end)

    it("notifies error when config decode fails", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      rawset(vim.fs, "joinpath", function(dir, file)
        return dir .. "/" .. file
      end)
      vim.fn.filereadable = stub.new().returns(1)
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fs.find = stub.new().returns({ "/project/root/test.gpr" })

      -- Mock decode_json_config to return nil (failure)
      project.decode_json_config = function(_path)
        return nil, nil, nil
      end

      project.setup()

      assert.is_false(project.is_setup)
      -- Check that notify was called with error message
      assert.stub(vim.notify).was_called()
      local found_error = false
      for _, call in ipairs(vim.notify.calls) do
        if call.vals[1] and call.vals[1]:match("Failed to decode") then
          found_error = true
          break
        end
      end
      assert.is_true(found_error)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_get_abspath", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("returns directory path with trailing slash", function()
        rawset(vim.fs, "abspath", function(path)
          return "/home/user/project/" .. path
        end)

        local result = project._get_abspath("src/main.adb")
        assert.equals("/home/user/project/src/", result)
      end)

      it("handles paths with backslashes", function()
        rawset(vim.fs, "abspath", function(_path)
          return "C:\\Users\\test\\project\\file.adb"
        end)

        local result = project._get_abspath("file.adb")
        assert.equals("C:\\Users\\test\\project\\", result)
      end)
    end)

    describe("_als_root_dir", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("returns gpr directory when gpr file found", function()
        vim.fs.find = stub.new().returns({ "/project/root/my_project.gpr" })
        rawset(vim.fs, "dirname", function(_path)
          return "/project/root/"
        end)

        local result = project._als_root_dir("/project/root/src/")
        assert.equals("/project/root/", result)
      end)

      it("returns startpath dirname when no gpr and not in git repo", function()
        vim.fs.find = stub.new().returns({})
        rawset(vim.fs, "dirname", function(path)
          if path == nil then
            return nil
          end
          return "/parent/dir/"
        end)
        vim.fn.isdirectory = stub.new().returns(0) -- not a git repo

        local result = project._als_root_dir("/parent/dir/subdir/")
        assert.equals("/parent/dir/", result)
      end)

      it("returns startpath when in git repo root", function()
        vim.fs.find = stub.new().returns({})
        rawset(vim.fs, "dirname", function(_path)
          return nil
        end)
        vim.fn.isdirectory = stub.new().returns(1) -- is a git repo

        local result = project._als_root_dir("/project/root/")
        assert.equals("/project/root/", result)
      end)
    end)

    describe("_detect_project_files", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("returns downward found files when present", function()
        vim.fs.find = stub.new().returns({
          "/project/root/main.gpr",
          "/project/root/lib/lib.gpr",
        })

        local result = project._detect_project_files("/project/root/")
        assert.same({
          "/project/root/main.gpr",
          "/project/root/lib/lib.gpr",
        }, result)
      end)

      it("searches upward when no downward files found", function()
        local call_count = 0
        rawset(vim.fs, "find", function(_fn, _opts)
          call_count = call_count + 1
          if call_count == 1 then
            return {} -- first call (downward) returns nothing
          else
            return { "/parent/project.gpr" } -- second call (upward)
          end
        end)

        local result = project._detect_project_files("/project/src/")
        assert.same({ "/parent/project.gpr" }, result)
        assert.equals(2, call_count)
      end)
    end)

    describe("_create_config", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("adds project file to config", function()
        project.project_file = "/project/my.gpr"
        project.scenario_variables = {}

        local config = {}
        project._create_config(config)

        assert.equals("/project/my.gpr", config.projectFile)
        assert.is_nil(config.scenarioVariables)
      end)

      it("adds scenario variables when present", function()
        project.project_file = "/project/my.gpr"
        project.scenario_variables = { MODE = "debug", ARCH = "x86" }

        local config = {}
        project._create_config(config)

        assert.equals("/project/my.gpr", config.projectFile)
        assert.same({ MODE = "debug", ARCH = "x86" }, config.scenarioVariables)
      end)
    end)

    describe("_notify_configuration_change", function()
      local project
      local utils

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        utils = require("ada_ls.utils")
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        utils.clear()
        common.cleanup_packages()
      end)

      it("sends workspace/didChangeConfiguration notification", function()
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        local config = { projectFile = "/project/my.gpr" }
        project._notify_configuration_change(config)

        assert.stub(mock_client.notify).was_called()
        local call_args = mock_client.notify.calls[1].vals
        assert.equals("workspace/didChangeConfiguration", call_args[2])
        assert.is_table(call_args[3].settings)
        assert.is_table(call_args[3].settings.ada)
      end)
    end)

    describe("_save_new_configuration", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("writes config to .als.json file", function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute("mkdir -p " .. temp_dir)

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)

        local config = { projectFile = "/project/test.gpr" }
        project._save_new_configuration(temp_dir, config)

        -- Verify file was created
        local file = io.open(temp_dir .. "/.als.json", "r")
        assert.is_not_nil(file)
        if file then
          local content = file:read("*a")
          file:close()
          assert.matches("projectFile", content)
        end

        os.execute("rm -rf " .. temp_dir)
      end)

      it("notifies error when file cannot be opened", function()
        rawset(vim.fs, "joinpath", function(_, _)
          return "/nonexistent/readonly/path/.als.json"
        end)

        local config = { projectFile = "/project/test.gpr" }
        project._save_new_configuration("/nonexistent/readonly/path", config)

        assert.stub(vim.notify_once).was_called()
        local call_args = vim.notify_once.calls[1]
        assert.matches("Could not save", call_args.vals[1])
      end)
    end)

    describe("_save_config", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("notifies warning when no project file selected", function()
        project.project_file = ""

        project._save_config()

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

    describe("_set_scenario_var", function()
      local project

      before_each(function()
        common.cleanup_packages()
        setup_base_mocks()
        project = require("ada_ls.project")
      end)

      after_each(function()
        project.clear()
        common.cleanup_packages()
      end)

      it("returns early when no project file", function()
        project.project_file = ""

        project._set_scenario_var()

        -- Should not have modified scenario_variables
        assert.same({}, project.scenario_variables)
      end)

      it("parses external variables from GPR file", function()
        -- Create temp GPR file with external variables
        local temp_gpr = os.tmpname() .. ".gpr"
        local file = io.open(temp_gpr, "w")
        file:write('Mode : String := external("MODE", "debug");\n')
        file:write('Arch : String := external("ARCH", "x86_64");\n')
        file:close()

        project.project_file = temp_gpr

        -- Mock lsp_cmd
        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_file = function()
              return temp_gpr
            end,
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        -- Mock filereadable to return 1
        vim.fn.filereadable = stub.new().returns(1)

        -- Mock notify (called by notify_configuration_change)
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        assert.equals("debug", project.scenario_variables["MODE"])
        assert.equals("x86_64", project.scenario_variables["ARCH"])

        os.remove(temp_gpr)
      end)

      it("parses dependencies and their external variables", function()
        -- Create main GPR file
        local temp_gpr = os.tmpname() .. ".gpr"
        local file = io.open(temp_gpr, "w")
        file:write('Mode : String := external("MODE", "release");\n')
        file:close()

        -- Create dependency GPR file
        local dep_gpr = os.tmpname() .. ".gpr"
        file = io.open(dep_gpr, "w")
        file:write('Platform : String := external("PLATFORM", "linux");\n')
        file:close()

        project.project_file = temp_gpr

        -- Mock lsp_cmd to return dependency
        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_file = function()
              return temp_gpr
            end,
            get_prj_dependencies = function()
              return { { uri = "file://" .. dep_gpr } }
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        -- Mock filereadable to return 1
        vim.fn.filereadable = stub.new().returns(1)

        -- Mock notify
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        assert.equals("release", project.scenario_variables["MODE"])
        assert.equals("linux", project.scenario_variables["PLATFORM"])

        os.remove(temp_gpr)
        os.remove(dep_gpr)
      end)

      it("warns when GPR file is not readable", function()
        project.project_file = "/nonexistent/project.gpr"

        -- Mock lsp_cmd
        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_file = function()
              return "/nonexistent/project.gpr"
            end,
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        -- Mock filereadable to return 0
        vim.fn.filereadable = stub.new().returns(0)

        -- Mock notify
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        -- Should have warned about unreadable file
        assert.stub(vim.notify).was_called()
        local found_warn = false
        for _, call in ipairs(vim.notify.calls) do
          if call.vals[1] and call.vals[1]:match("Could not read") then
            found_warn = true
            break
          end
        end
        assert.is_true(found_warn)
      end)
    end)
  end
end)
