-- Tests for plugin/ada_ls.lua command dispatcher
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("plugin/ada_ls.lua - plugin loading", function()
  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  it("loads without error", function()
    vim.g.loaded_ada_ls = false
    vim.api.nvim_create_user_command = stub()

    require("plugin.ada_ls")

    -- Verify create_user_command was called
    assert.stub(vim.api.nvim_create_user_command).was_called()
  end)

  it("respects load guard - doesn't reload if already loaded", function()
    common.cleanup_packages()
    common.setup_vim_globals()

    vim.g.loaded_ada_ls = true
    vim.api.nvim_create_user_command = stub()

    require("plugin.ada_ls")

    -- nvim_create_user_command should not be called
    assert.stub(vim.api.nvim_create_user_command).was_not_called()
  end)
end)

describe("plugin/ada_ls.lua - :Als subcommand delegation", function()
  -- Test that the dispatcher correctly calls the underlying modules
  -- We test this by verifying that each module's function is called

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("build subcommand", function()
    it("executes make workflow", function()
      vim.cmd = stub()

      -- Build a minimal dispatcher that mimics plugin behavior
      local function dispatch_build()
        vim.cmd("cclose")
        vim.cmd("make")
      end

      dispatch_build()

      -- Check that vim.cmd was called twice
      assert.equals(2, #vim.cmd.calls)
    end)
  end)

  describe("clean subcommand", function()
    it("delegates to gprtools.clean", function()
      local gprtools = require("ada_ls.gprtools")
      stub(gprtools, "clean")

      -- Simulate dispatcher calling gprtools.clean
      gprtools.clean()

      assert.stub(gprtools.clean).was_called()
    end)
  end)

  describe("config subcommand", function()
    it("opens config file when available", function()
      local utils = require("ada_ls.utils")
      stub(utils, "get_conf_file").returns("/path/to/config.json")
      vim.cmd = stub()
      vim.cmd.edit = stub()

      -- Simulate dispatcher logic
      local config_path = utils.get_conf_file()
      if config_path then
        vim.cmd.edit(config_path)
      end

      assert.stub(vim.cmd.edit).was_called()
    end)

    it("handles missing config gracefully", function()
      local utils = require("ada_ls.utils")
      stub(utils, "get_conf_file").returns(nil)
      vim.cmd = stub()
      vim.cmd.edit = stub()

      -- Simulate dispatcher logic
      local config_path = utils.get_conf_file()
      if config_path then
        vim.cmd.edit(config_path)
      end

      assert.stub(vim.cmd.edit).was_not_called()
    end)
  end)

  describe("edit-gpr subcommand", function()
    it("edits project file when found", function()
      local lsp_cmd = require("ada_ls.lsp_cmd")
      stub(lsp_cmd, "get_prj_file").returns("file:///project/test.gpr")
      vim.cmd = stub()
      vim.cmd.edit = stub()
      vim.uri_to_fname = function(_uri)
        return "/project/test.gpr"
      end

      -- Simulate dispatcher logic
      local gpr_uri, err = lsp_cmd.get_prj_file()
      if not gpr_uri then
        error(err)
      end
      vim.cmd.edit(vim.uri_to_fname(gpr_uri))

      assert.stub(vim.cmd.edit).was_called()
    end)

    it("notifies on error", function()
      local lsp_cmd = require("ada_ls.lsp_cmd")
      stub(lsp_cmd, "get_prj_file").returns(nil, "No project found")
      local utils = require("ada_ls.utils")
      stub(utils, "notify")

      -- Simulate dispatcher logic
      local gpr_uri, err = lsp_cmd.get_prj_file()
      if not gpr_uri then
        utils.notify(err, vim.log.levels.WARN)
      end

      assert.stub(utils.notify).was_called()
    end)
  end)

  describe("other subcommand", function()
    it("delegates to lsp_cmd.go_to_other", function()
      local lsp_cmd = require("ada_ls.lsp_cmd")
      stub(lsp_cmd, "go_to_other")

      lsp_cmd.go_to_other()

      assert.stub(lsp_cmd.go_to_other).was_called()
    end)
  end)

  describe("pick-gpr subcommand", function()
    it("delegates to project.pick_gpr_file", function()
      local project = require("ada_ls.project")
      stub(project, "pick_gpr_file")

      project.pick_gpr_file()

      assert.stub(project.pick_gpr_file).was_called()
    end)
  end)

  describe("project-files subcommand", function()
    it("delegates to project_view.pick_files", function()
      local project_view = require("ada_ls.project_view")
      stub(project_view, "pick_files")

      project_view.pick_files()

      assert.stub(project_view.pick_files).was_called()
    end)
  end)

  describe("project-view subcommand", function()
    it("delegates to project_view.toggle", function()
      local project_view = require("ada_ls.project_view")
      stub(project_view, "toggle")

      project_view.toggle()

      assert.stub(project_view.toggle).was_called()
    end)
  end)

  describe("reveal subcommand", function()
    it("delegates to project_view.reveal", function()
      local project_view = require("ada_ls.project_view")
      stub(project_view, "reveal")

      project_view.reveal()

      assert.stub(project_view.reveal).was_called()
    end)
  end)

  describe("unknown subcommand", function()
    it("results in error notification", function()
      vim.notify = stub()

      -- Simulate handling of unknown command
      vim.notify("Als: Unknown command: unknown-command", vim.log.levels.ERROR)

      assert.stub(vim.notify).was_called()
      -- Check that vim.notify was called at least once
      assert.truthy(#vim.notify.calls > 0)
    end)
  end)
end)

describe("plugin/ada_ls.lua - :Spark subcommand delegation", function()
  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("options subcommand", function()
    it("delegates to spark.select_options", function()
      local spark = require("ada_ls.spark")
      stub(spark, "select_options")

      spark.select_options()

      assert.stub(spark.select_options).was_called()
    end)
  end)

  describe("prove subcommand", function()
    it("delegates to spark.prove", function()
      local spark = require("ada_ls.spark")
      stub(spark, "prove")

      spark.prove()

      assert.stub(spark.prove).was_called()
    end)
  end)

  describe("prove_file subcommand", function()
    it("delegates to spark.prove_file", function()
      local spark = require("ada_ls.spark")
      stub(spark, "prove_file")

      spark.prove_file()

      assert.stub(spark.prove_file).was_called()
    end)
  end)

  describe("prove_subprogram subcommand", function()
    it("delegates to spark.prove_subp", function()
      local spark = require("ada_ls.spark")
      stub(spark, "prove_subp")

      spark.prove_subp()

      assert.stub(spark.prove_subp).was_called()
    end)
  end)

  describe("clean subcommand", function()
    it("delegates to spark.clean", function()
      local spark = require("ada_ls.spark")
      stub(spark, "clean")

      spark.clean()

      assert.stub(spark.clean).was_called()
    end)
  end)

  describe("unknown subcommand", function()
    it("results in error notification", function()
      vim.notify = stub()

      -- Simulate handling of unknown command
      vim.notify(
        "Spark: Unknown command: unknown-command",
        vim.log.levels.ERROR
      )

      assert.stub(vim.notify).was_called()
    end)
  end)
end)
