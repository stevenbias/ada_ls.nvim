-- Tests for plugin/ada_ls.lua command dispatcher
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

local function load_plugin_and_capture_commands()
  local commands = {}
  package.loaded["plugin.ada_ls"] = nil
  package.preload["plugin.ada_ls"] = nil
  vim.g.loaded_ada_ls = false
  vim.api.nvim_create_user_command = function(name, callback, opts)
    commands[name] = {
      callback = callback,
      opts = opts,
    }
  end

  require("plugin.ada_ls")
  return commands
end

local function execute_subcommand(commands, cmd_name, subcmd, extra_args)
  local entry = commands[cmd_name]
  assert.is_not_nil(entry)

  local fargs = { subcmd }
  for _, arg in ipairs(extra_args or {}) do
    table.insert(fargs, arg)
  end

  entry.callback({
    name = cmd_name,
    fargs = fargs,
  })
end

describe("plugin/ada_ls.lua", function()
  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("plugin loading", function()
    it("registers :Als and :Spark commands", function()
      local commands = load_plugin_and_capture_commands()

      assert.is_not_nil(commands.Als)
      assert.is_not_nil(commands.Spark)
      assert.equals("+", commands.Als.opts.nargs)
      assert.equals("+", commands.Spark.opts.nargs)
      assert.is_true(commands.Als.opts.bang)
      assert.is_true(commands.Spark.opts.bang)
    end)

    it("respects load guard and does not register commands twice", function()
      vim.g.loaded_ada_ls = true
      vim.api.nvim_create_user_command = stub.new()

      require("plugin.ada_ls")

      assert.stub(vim.api.nvim_create_user_command).was_not_called()
    end)
  end)

  describe(":Als subcommand delegation", function()
    local commands

    before_each(function()
      commands = load_plugin_and_capture_commands()
    end)

    it("executes build workflow", function()
      vim.cmd = stub.new()

      execute_subcommand(commands, "Als", "build")

      assert.equals(2, #vim.cmd.calls)
      assert.equals("cclose", vim.cmd.calls[1].vals[1])
      assert.equals("make", vim.cmd.calls[2].vals[1])
    end)

    it("delegates clean to gprtools.clean", function()
      local clean_stub = stub.new()
      package.loaded["ada_ls.gprtools"] = {
        clean = clean_stub,
      }

      execute_subcommand(commands, "Als", "clean")

      assert.stub(clean_stub).was_called()
    end)

    it("opens config file when available", function()
      local cmd_stub = stub.new()
      cmd_stub.edit = stub.new()
      vim.cmd = cmd_stub

      package.loaded["ada_ls.utils"] = {
        get_conf_file = function()
          return "/path/to/config.json"
        end,
      }

      execute_subcommand(commands, "Als", "config")

      assert.stub(cmd_stub.edit).was_called_with("/path/to/config.json")
    end)

    it("does not open config when file is unavailable", function()
      local cmd_stub = stub.new()
      cmd_stub.edit = stub.new()
      vim.cmd = cmd_stub

      package.loaded["ada_ls.utils"] = {
        get_conf_file = function()
          return nil
        end,
      }

      execute_subcommand(commands, "Als", "config")

      assert.stub(cmd_stub.edit).was_not_called()
    end)

    it("opens project file for edit_gpr when available", function()
      local cmd_stub = stub.new()
      cmd_stub.edit = stub.new()
      vim.cmd = cmd_stub
      vim.uri_to_fname = function(_uri)
        return "/project/test.gpr"
      end

      local notify_stub = stub.new()
      package.loaded["ada_ls.utils"] = {
        notify = notify_stub,
      }
      package.loaded["ada_ls.lsp_cmd"] = {
        get_prj_file = function()
          return "file:///project/test.gpr"
        end,
      }

      execute_subcommand(commands, "Als", "edit_gpr")

      assert.stub(cmd_stub.edit).was_called_with("/project/test.gpr")
      assert.stub(notify_stub).was_not_called()
    end)

    it("notifies when edit_gpr cannot get a project file", function()
      local cmd_stub = stub.new()
      cmd_stub.edit = stub.new()
      vim.cmd = cmd_stub

      local notify_stub = stub.new()
      package.loaded["ada_ls.utils"] = {
        notify = notify_stub,
      }
      package.loaded["ada_ls.lsp_cmd"] = {
        get_prj_file = function()
          return nil, "No project found"
        end,
      }

      execute_subcommand(commands, "Als", "edit_gpr")

      assert
        .stub(notify_stub)
        .was_called_with("No project found", vim.log.levels.WARN)
      assert.stub(cmd_stub.edit).was_not_called()
    end)

    it("delegates other to lsp_cmd.go_to_other", function()
      local go_to_other_stub = stub.new()
      package.loaded["ada_ls.lsp_cmd"] = {
        go_to_other = go_to_other_stub,
      }

      execute_subcommand(commands, "Als", "other")

      assert.stub(go_to_other_stub).was_called()
    end)

    it("delegates pick_gpr to project.pick_gpr_file", function()
      local pick_gpr_stub = stub.new()
      package.loaded["ada_ls.project"] = {
        pick_gpr_file = pick_gpr_stub,
      }

      execute_subcommand(commands, "Als", "pick_gpr")

      assert.stub(pick_gpr_stub).was_called()
    end)

    it("delegates project_files to project_view.pick_files", function()
      local pick_files_stub = stub.new()
      package.loaded["ada_ls.project_view"] = {
        pick_files = pick_files_stub,
      }

      execute_subcommand(commands, "Als", "project_files")

      assert.stub(pick_files_stub).was_called()
    end)

    it("delegates project_view to project_view.toggle", function()
      local toggle_stub = stub.new()
      package.loaded["ada_ls.project_view"] = {
        toggle = toggle_stub,
      }

      execute_subcommand(commands, "Als", "project_view")

      assert.stub(toggle_stub).was_called()
    end)

    it("notifies for unknown subcommand", function()
      vim.notify = stub.new()

      execute_subcommand(commands, "Als", "unknown_command")

      assert
        .stub(vim.notify)
        .was_called_with("Als: Unknown command: unknown_command", vim.log.levels.ERROR)
    end)
  end)

  describe(":Spark subcommand delegation", function()
    local commands

    before_each(function()
      commands = load_plugin_and_capture_commands()
    end)

    it("delegates options to spark.select_options", function()
      local select_options_stub = stub.new()
      package.loaded["ada_ls.spark"] = {
        select_options = select_options_stub,
      }

      execute_subcommand(commands, "Spark", "options")

      assert.stub(select_options_stub).was_called()
    end)

    it("delegates prove to spark.prove", function()
      local prove_stub = stub.new()
      package.loaded["ada_ls.spark"] = {
        prove = prove_stub,
      }

      execute_subcommand(commands, "Spark", "prove")

      assert.stub(prove_stub).was_called()
    end)

    it("delegates prove_file to spark.prove_file", function()
      local prove_file_stub = stub.new()
      package.loaded["ada_ls.spark"] = {
        prove_file = prove_file_stub,
      }

      execute_subcommand(commands, "Spark", "prove_file")

      assert.stub(prove_file_stub).was_called()
    end)

    it("delegates prove_subprogram to spark.prove_subp", function()
      local prove_subp_stub = stub.new()
      package.loaded["ada_ls.spark"] = {
        prove_subp = prove_subp_stub,
      }

      execute_subcommand(commands, "Spark", "prove_subprogram")

      assert.stub(prove_subp_stub).was_called()
    end)

    it("delegates clean to spark.clean", function()
      local clean_stub = stub.new()
      package.loaded["ada_ls.spark"] = {
        clean = clean_stub,
      }

      execute_subcommand(commands, "Spark", "clean")

      assert.stub(clean_stub).was_called()
    end)

    it("notifies for unknown subcommand", function()
      vim.notify = stub.new()

      execute_subcommand(commands, "Spark", "unknown_command")

      assert
        .stub(vim.notify)
        .was_called_with("Spark: Unknown command: unknown_command", vim.log.levels.ERROR)
    end)
  end)
end)
