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

    it(
      "resolves relative project file paths against the config file",
      function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '"')
        local config_path = temp_dir .. "/.als.json"
        local file = io.open(config_path, "w")
        assert.is_not_nil(file)
        file:write('{"projectFile":"nested/test.gpr"}')
        file:close()

        rawset(vim.fs, "abspath", function(path)
          if path:match("^/") then
            return path
          end
          return "/absolute" .. path
        end)
        rawset(vim.json, "decode", function()
          return { projectFile = "nested/test.gpr" }
        end)

        local prj, _, config = project.decode_json_config(config_path)

        assert.equals(temp_dir .. "/nested/test.gpr", prj)
        assert.equals(temp_dir .. "/nested/test.gpr", config.projectFile)

        os.remove(config_path)
        os.execute('rmdir "' .. temp_dir .. '"')
      end
    )

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

    it("builds scenario variables string from multiple variables", function()
      local fixture_path = common.fixture_path("als_config.json")
      rawset(vim.json, "decode", function(_raw)
        return {
          projectFile = "/project/test.gpr",
          scenarioVariables = {
            MODE = "release",
            PLATFORM = "windows",
            ARCH = "x86_64",
            DEBUG = "false",
          },
        }
      end)

      local _, vars, _ = project.decode_json_config(fixture_path)

      assert.matches("-XMODE=release", vars)
      assert.matches("-XPLATFORM=windows", vars)
      assert.matches("-XARCH=x86_64", vars)
      assert.matches("-XDEBUG=false", vars)
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

      assert.stub(vim.notify).was_called()
      local call_args = vim.notify.calls[1]
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
      assert
        .stub(vim.api.nvim_set_current_dir)
        .was_called_with("/absolute/project/")
    end)

    it("falls back to vim.ui.select when telescope is unavailable", function()
      local gpr1, cleanup_gpr1 =
        common.create_temp_file("project A is\nend A;\n", ".gpr")
      local gpr2, cleanup_gpr2 =
        common.create_temp_file("project B is\nend B;\n", ".gpr")

      vim.fs.find = function(_, opts)
        if opts and opts.type == "file" and not opts.upward then
          return { gpr1, gpr2 }
        end
        return {}
      end

      vim.fn.isdirectory = stub.new().returns(0)
      vim.fn.filereadable = stub.new().returns(1)

      package.preload["ada_ls.lsp_cmd"] = function()
        return {
          get_prj_dependencies = function()
            return nil
          end,
          get_root_dir = function()
            return "/project"
          end,
        }
      end
      package.loaded["ada_ls.lsp_cmd"] = nil

      local original_require = _G.require
      _G.require = function(name)
        if name == "telescope.pickers" then
          error("module not found")
        end
        return original_require(name)
      end

      local selected
      rawset(vim, "ui", {
        select = function(items, _, callback)
          selected = items[2]
          callback(items[2])
        end,
      })

      project.pick_gpr_file()

      assert.equals(gpr2, selected)
      assert.equals(gpr2, project.project_file)

      cleanup_gpr1()
      cleanup_gpr2()
      _G.require = original_require
    end)

    it(
      "recomputes inherited scenario variables after notifying the server about the new project",
      function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '/dep"')

        local selected_gpr = temp_dir .. "/othello_stm32f746disco.gpr"
        local selected_file = io.open(selected_gpr, "w")
        assert.is_not_nil(selected_file)
        selected_file:write(
          "project Othello_Stm32f746disco is\nend Othello_Stm32f746disco;\n"
        )
        selected_file:close()

        local dep_gpr = temp_dir .. "/dep/inherited.gpr"
        local dep_file = io.open(dep_gpr, "w")
        assert.is_not_nil(dep_file)
        dep_file:write('Mode : String := external("MODE", "debug");\n')
        dep_file:close()

        vim.fs.find = function(_, opts)
          if opts and opts.type == "file" and not opts.upward then
            return { selected_gpr }
          end
          return {}
        end
        rawset(vim.fs, "abspath", function(path)
          if path:match("^/") then
            return path
          end
          return "/absolute" .. path
        end)
        vim.fn.isdirectory = stub.new().returns(0)
        vim.fn.filereadable = stub.new().returns(1)

        local current_project
        local config_notifications = {}
        local mock_client = common.create_lsp_client()
        mock_client.notify = function(_, method, params)
          if
            method == "workspace/didChangeConfiguration"
            and params
            and params.settings
            and params.settings.ada
          then
            current_project = params.settings.ada.projectFile
            table.insert(
              config_notifications,
              vim.deepcopy(params.settings.ada)
            )
          end
          return true
        end
        common.setup_lsp_client(mock_client)

        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function(prj_file)
              if
                prj_file == selected_gpr and current_project == selected_gpr
              then
                return { { uri = "file://" .. dep_gpr } }
              end
              return nil
            end,
            get_root_dir = function()
              return temp_dir
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil
        package.loaded["ada_ls.project"] = nil
        project = require("ada_ls.project")

        project.pick_gpr_file()

        assert.equals(selected_gpr, project.project_file)
        assert.equals("debug", project.scenario_variables.MODE)
        assert.equals(2, #config_notifications)
        assert.equals(selected_gpr, config_notifications[1].projectFile)
        assert.is_nil(config_notifications[1].scenarioVariables)
        assert.equals(selected_gpr, config_notifications[2].projectFile)
        assert.same(
          { MODE = "debug" },
          config_notifications[2].scenarioVariables
        )

        local saved_cfg = io.open(temp_dir .. "/.als.json", "r")
        assert.is_not_nil(saved_cfg)
        if saved_cfg then
          local content = saved_cfg:read("*a")
          saved_cfg:close()
          assert.matches('"projectFile":"othello_stm32f746disco.gpr"', content)
          assert.matches('"scenarioVariables":%{"MODE":"debug"%}', content)
        end

        os.execute("rm -rf " .. temp_dir)
      end
    )
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

      -- Create a temp GPR file (needed because io.lines reads the actual file)
      local temp_gpr = os.tmpname() .. ".gpr"
      local gpr_file = io.open(temp_gpr, "w")
      gpr_file:write("project Test is\nend Test;\n")
      gpr_file:close()

      rawset(vim.fs, "joinpath", function(dir, file)
        return dir .. "/" .. file
      end)
      vim.fn.filereadable = stub.new().returns(1)
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fs.find = stub.new().returns({ temp_gpr })

      -- Create a temp config file
      local temp_file = os.tmpname()
      local file = io.open(temp_file, "w")
      file:write('{"projectFile": "' .. temp_gpr .. '"}')
      file:close()

      rawset(vim.json, "decode", function(_raw)
        return { projectFile = temp_gpr }
      end)

      -- Mock the decode_json_config to use our temp file
      local orig_decode = project.decode_json_config
      project.decode_json_config = function(_path)
        return orig_decode(temp_file)
      end

      project.setup()

      assert.is_true(project.is_setup)

      os.remove(temp_file)
      os.remove(temp_gpr)
    end)

    it(
      "does not change cwd or workspace folders when loading config",
      function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        local temp_gpr, cleanup_gpr =
          common.create_temp_file("project Test is\nend Test;\n", ".gpr")
        local temp_cfg, cleanup_cfg =
          common.create_temp_file('{"projectFile": "nested/test.gpr"}')

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)
        vim.fn.filereadable = stub.new().returns(1)
        vim.fn.isdirectory = stub.new().returns(0)
        vim.fs.find = stub.new().returns({ temp_gpr })
        rawset(vim.json, "decode", function()
          return { projectFile = temp_gpr }
        end)

        local orig_decode = project.decode_json_config
        project.decode_json_config = function()
          return orig_decode(temp_cfg)
        end

        project.setup()

        assert.stub(vim.api.nvim_set_current_dir).was_not_called()
        assert
          .stub(mock_client.notify)
          .was_not_called_with("workspace/didChangeWorkspaceFolders")

        cleanup_cfg()
        cleanup_gpr()
      end
    )

    it(
      "saves recomputed scenario variables back to the loaded config path",
      function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '/nested"')

        local root_gpr = temp_dir .. "/root.gpr"
        local root_gpr_file = io.open(root_gpr, "w")
        assert.is_not_nil(root_gpr_file)
        root_gpr_file:write("project Root is\nend Root;\n")
        root_gpr_file:close()

        local temp_gpr = temp_dir .. "/nested/test.gpr"
        local gpr_file = io.open(temp_gpr, "w")
        assert.is_not_nil(gpr_file)
        gpr_file:write('Mode : String := external("MODE", "debug");\n')
        gpr_file:close()

        local temp_cfg = temp_dir .. "/.als.json"
        local cfg_file = io.open(temp_cfg, "w")
        assert.is_not_nil(cfg_file)
        cfg_file:write('{"projectFile":"nested/test.gpr"}')
        cfg_file:close()

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)
        rawset(vim.fs, "abspath", function(path)
          if path:match("^/") then
            return path
          end
          return "/absolute" .. path
        end)
        vim.fn.filereadable = stub.new().returns(1)
        vim.fn.isdirectory = stub.new().returns(0)
        vim.fs.find = stub.new().returns({ root_gpr })
        rawset(vim.json, "decode", function()
          return { projectFile = "nested/test.gpr" }
        end)

        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        local orig_decode = project.decode_json_config
        project.decode_json_config = function()
          return orig_decode(temp_cfg)
        end

        project.setup()

        local file = io.open(temp_cfg, "r")
        assert.is_not_nil(file)
        if file then
          local content = file:read("*a")
          file:close()
          assert.matches('"projectFile":"nested/test.gpr"', content)
          assert.matches('"scenarioVariables":%{"MODE":"debug"%}', content)
        end

        local nested_cfg = io.open(temp_dir .. "/nested/.als.json", "r")
        assert.is_nil(nested_cfg)

        os.remove(temp_cfg)
        os.remove(temp_gpr)
        os.remove(root_gpr)
        os.execute("rm -rf " .. temp_dir)
      end
    )

    it(
      "preserves extra config keys when recomputing missing scenario variables",
      function()
        local mock_client =
          common.create_lsp_client({ root_dir = "/project/root" })
        common.setup_lsp_client(mock_client)

        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '/nested"')

        local root_gpr = temp_dir .. "/root.gpr"
        local root_gpr_file = io.open(root_gpr, "w")
        assert.is_not_nil(root_gpr_file)
        root_gpr_file:write("project Root is\nend Root;\n")
        root_gpr_file:close()

        local temp_gpr = temp_dir .. "/nested/test.gpr"
        local gpr_file = io.open(temp_gpr, "w")
        assert.is_not_nil(gpr_file)
        gpr_file:write('Mode : String := external("MODE", "debug");\n')
        gpr_file:close()

        local temp_cfg = temp_dir .. "/.als.json"
        local cfg_file = io.open(temp_cfg, "w")
        assert.is_not_nil(cfg_file)
        local config_json = table.concat({
          '{"projectFile":"nested/test.gpr"',
          '"defaultCharset":"UTF-8"',
          '"rootDir":"/workspace/root"',
          '"relocateBuildTree":"/workspace/build"}',
        }, ",")
        cfg_file:write(config_json)
        cfg_file:close()

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)
        rawset(vim.fs, "abspath", function(path)
          if path:match("^/") then
            return path
          end
          return "/absolute" .. path
        end)
        vim.fn.filereadable = stub.new().returns(1)
        vim.fn.isdirectory = stub.new().returns(0)
        vim.fs.find = stub.new().returns({ root_gpr })
        rawset(vim.json, "decode", function()
          return {
            projectFile = "nested/test.gpr",
            defaultCharset = "UTF-8",
            rootDir = "/workspace/root",
            relocateBuildTree = "/workspace/build",
          }
        end)

        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        local orig_decode = project.decode_json_config
        project.decode_json_config = function()
          return orig_decode(temp_cfg)
        end

        project.setup()

        local file = io.open(temp_cfg, "r")
        assert.is_not_nil(file)
        if file then
          local content = file:read("*a")
          file:close()
          assert.matches('"projectFile":"nested/test.gpr"', content)
          assert.matches('"scenarioVariables":%{"MODE":"debug"%}', content)
          assert.matches('"defaultCharset":"UTF%-8"', content)
          assert.matches('"rootDir":"/workspace/root"', content)
          assert.matches('"relocateBuildTree":"/workspace/build"', content)
        end

        os.remove(temp_cfg)
        os.remove(temp_gpr)
        os.remove(root_gpr)
        os.execute("rm -rf " .. temp_dir)
      end
    )

    it(
      "notifies ALS before recomputing inherited scenario variables during setup",
      function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '/dep"')

        local root_gpr = temp_dir .. "/root.gpr"
        local root_gpr_file = io.open(root_gpr, "w")
        assert.is_not_nil(root_gpr_file)
        root_gpr_file:write("project Root is\nend Root;\n")
        root_gpr_file:close()

        local selected_gpr = temp_dir .. "/target.gpr"
        local selected_file = io.open(selected_gpr, "w")
        assert.is_not_nil(selected_file)
        selected_file:write("project Target is\nend Target;\n")
        selected_file:close()

        local dep_gpr = temp_dir .. "/dep/inherited.gpr"
        local dep_file = io.open(dep_gpr, "w")
        assert.is_not_nil(dep_file)
        dep_file:write('Mode : String := external("MODE", "release");\n')
        dep_file:close()

        local temp_cfg = temp_dir .. "/.als.json"
        local cfg_file = io.open(temp_cfg, "w")
        assert.is_not_nil(cfg_file)
        cfg_file:write('{"projectFile":"target.gpr"}')
        cfg_file:close()

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)
        rawset(vim.fs, "abspath", function(path)
          if path:match("^/") then
            return path
          end
          return "/absolute" .. path
        end)
        vim.fn.filereadable = stub.new().returns(1)
        vim.fn.isdirectory = stub.new().returns(0)
        vim.fs.find = stub.new().returns({ root_gpr })
        rawset(vim.json, "decode", function()
          return { projectFile = "target.gpr" }
        end)

        local current_project
        local config_notifications = {}
        local mock_client = common.create_lsp_client({ root_dir = temp_dir })
        mock_client.notify = function(_, method, params)
          if
            method == "workspace/didChangeConfiguration"
            and params
            and params.settings
            and params.settings.ada
          then
            current_project = params.settings.ada.projectFile
            table.insert(
              config_notifications,
              vim.deepcopy(params.settings.ada)
            )
          end
          return true
        end
        common.setup_lsp_client(mock_client)

        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function(prj_file)
              if
                prj_file == selected_gpr and current_project == selected_gpr
              then
                return { { uri = "file://" .. dep_gpr } }
              end
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil

        local orig_decode = project.decode_json_config
        project.decode_json_config = function()
          return orig_decode(temp_cfg)
        end

        project.setup()

        assert.equals(selected_gpr, project.project_file)
        assert.equals("release", project.scenario_variables.MODE)
        assert.equals(2, #config_notifications)
        assert.equals(selected_gpr, config_notifications[1].projectFile)
        assert.is_nil(config_notifications[1].scenarioVariables)
        assert.same(
          { MODE = "release" },
          config_notifications[2].scenarioVariables
        )

        local file = io.open(temp_cfg, "r")
        assert.is_not_nil(file)
        if file then
          local content = file:read("*a")
          file:close()
          assert.matches('"scenarioVariables":%{"MODE":"release"%}', content)
        end

        os.remove(temp_cfg)
        os.remove(selected_gpr)
        os.remove(root_gpr)
        os.execute("rm -rf " .. temp_dir)
      end
    )

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
      assert.is_true(common.find_stub_call(vim.notify, "Failed to decode"))
    end)

    it("uses current GPR file when buffer filetype is gpr", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      local temp_gpr, cleanup_gpr =
        common.create_temp_file("project Test is\nend Test;\n", ".gpr")
      local temp_cfg, cleanup_cfg =
        common.create_temp_file('{"projectFile": "other.gpr"}')

      rawset(vim.fs, "joinpath", function(dir, file)
        return dir .. "/" .. file
      end)
      vim.fn.filereadable = stub.new().returns(1)
      vim.fn.isdirectory = stub.new().returns(0)
      vim.fs.find = stub.new().returns({ temp_gpr })
      rawset(vim, "bo", { filetype = "gpr" })
      vim.fn.expand = function(arg)
        if arg == "%:p" or arg == "%" then
          return temp_gpr
        end
        return "/test/path/file.adb"
      end
      rawset(vim.json, "decode", function()
        return { projectFile = "other.gpr" }
      end)

      local orig_decode = project.decode_json_config
      project.decode_json_config = function()
        return orig_decode(temp_cfg)
      end

      project.setup()

      assert.equals(temp_gpr, project.project_file)
      assert.is_true(project.is_setup)

      cleanup_cfg()
      cleanup_gpr()
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

        local config = project._create_config()

        assert.equals("/project/my.gpr", config.projectFile)
        assert.is_nil(config.scenarioVariables)
      end)

      it("adds scenario variables when present", function()
        project.project_file = "/project/my.gpr"
        project.scenario_variables = { MODE = "debug", ARCH = "x86" }

        local config = project._create_config()

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

      it("writes projectFile relative to the config directory", function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute("mkdir -p " .. temp_dir)

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)

        project.project_file = temp_dir .. "/nested/test.gpr"
        local config = { projectFile = "/project/test.gpr" }
        os.execute('mkdir -p "' .. temp_dir .. '/nested"')
        project._save_new_configuration(temp_dir, config)

        -- Verify file was created
        local file = io.open(temp_dir .. "/.als.json", "r")
        assert.is_not_nil(file)
        if file then
          local content = file:read("*a")
          file:close()
          assert.matches('"projectFile":"nested/test.gpr"', content)
        end

        os.execute("rm -rf " .. temp_dir)
      end)

      it(
        "keeps absolute projectFile when project is outside config directory",
        function()
          local temp_dir = os.tmpname()
          os.remove(temp_dir)
          os.execute("mkdir -p " .. temp_dir)

          rawset(vim.fs, "joinpath", function(dir, file)
            return dir .. "/" .. file
          end)

          project.project_file = "/external/project/test.gpr"
          project._save_new_configuration(temp_dir, {
            projectFile = "/external/project/test.gpr",
          })

          local file = io.open(temp_dir .. "/.als.json", "r")
          assert.is_not_nil(file)
          if file then
            local content = file:read("*a")
            file:close()
            assert.matches(
              '"projectFile":"/external/project/test.gpr"',
              content
            )
          end

          os.execute("rm -rf " .. temp_dir)
        end
      )

      it("notifies error when file cannot be opened", function()
        rawset(vim.fs, "joinpath", function(_, _)
          return "/nonexistent/readonly/path/.als.json"
        end)

        local config = { projectFile = "/project/test.gpr" }
        project._save_new_configuration("/nonexistent/readonly/path", config)

        assert.stub(vim.notify).was_called()
        local call_args = vim.notify.calls[1]
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

        assert.is_true(common.find_stub_call(vim.notify, "No Ada project file"))
      end)

      it("writes to the provided config path when supplied", function()
        local temp_dir = os.tmpname()
        os.remove(temp_dir)
        os.execute('mkdir -p "' .. temp_dir .. '/nested"')

        rawset(vim.fs, "joinpath", function(dir, file)
          return dir .. "/" .. file
        end)

        project.project_file = temp_dir .. "/nested/test.gpr"
        project._save_config(
          { projectFile = project.project_file },
          temp_dir .. "/.als.json"
        )

        local root_cfg = io.open(temp_dir .. "/.als.json", "r")
        assert.is_not_nil(root_cfg)
        if root_cfg then
          local content = root_cfg:read("*a")
          root_cfg:close()
          assert.matches('"projectFile":"nested/test.gpr"', content)
        end

        local nested_cfg = io.open(temp_dir .. "/nested/.als.json", "r")
        assert.is_nil(nested_cfg)

        os.execute("rm -rf " .. temp_dir)
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
        local gpr_content = 'Mode : String := external("MODE", "debug");\n'
          .. 'Arch : String := external("ARCH", "x86_64");\n'
        local temp_gpr, cleanup = common.create_temp_file(gpr_content, ".gpr")

        project.project_file = temp_gpr
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
        vim.fn.filereadable = stub.new().returns(1)
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        assert.equals("debug", project.scenario_variables["MODE"])
        assert.equals("x86_64", project.scenario_variables["ARCH"])
        cleanup()
      end)

      it("parses dependencies and their external variables", function()
        local temp_gpr, cleanup_gpr = common.create_temp_file(
          'Mode : String := external("MODE", "release");\n',
          ".gpr"
        )
        local dep_gpr, cleanup_dep = common.create_temp_file(
          'Platform : String := external("PLATFORM", "linux");\n',
          ".gpr"
        )

        project.project_file = temp_gpr
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
        vim.fn.filereadable = stub.new().returns(1)
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        assert.equals("release", project.scenario_variables["MODE"])
        assert.equals("linux", project.scenario_variables["PLATFORM"])
        cleanup_gpr()
        cleanup_dep()
      end)

      it("parses external variables without spaces after comma", function()
        local gpr_content = 'Mode : String := external("MODE","debug");\n'
          .. 'Arch : String := external("ARCH","x86_64");\n'
        local temp_gpr, cleanup = common.create_temp_file(gpr_content, ".gpr")

        project.project_file = temp_gpr
        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil
        vim.fn.filereadable = stub.new().returns(1)

        project._set_scenario_var()

        assert.equals("debug", project.scenario_variables["MODE"])
        assert.equals("x86_64", project.scenario_variables["ARCH"])
        cleanup()
      end)

      it("ignores malformed external calls without crashing", function()
        local gpr_content = 'Mode : String := external("MODE");\n'
          .. 'Arch : String := external("ARCH", "x86_64");\n'
        local temp_gpr, cleanup = common.create_temp_file(gpr_content, ".gpr")

        project.project_file = temp_gpr
        package.preload["ada_ls.lsp_cmd"] = function()
          return {
            get_prj_dependencies = function()
              return nil
            end,
          }
        end
        package.loaded["ada_ls.lsp_cmd"] = nil
        vim.fn.filereadable = stub.new().returns(1)

        local ok = pcall(project._set_scenario_var)

        assert.is_true(ok)
        assert.is_nil(project.scenario_variables["MODE"])
        assert.equals("x86_64", project.scenario_variables["ARCH"])
        cleanup()
      end)

      it("warns when GPR file is not readable", function()
        project.project_file = "/nonexistent/project.gpr"
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
        vim.fn.filereadable = stub.new().returns(0)
        local mock_client = common.create_lsp_client()
        common.setup_lsp_client(mock_client)

        project._set_scenario_var()

        assert.is_true(common.find_stub_call(vim.notify, "Could not read"))
      end)
    end)
  end
end)
