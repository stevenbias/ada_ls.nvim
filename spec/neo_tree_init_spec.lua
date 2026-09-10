local common = require("spec.helpers.common")
local stub = require("luassert.stub")

describe("ada_ls.project_view.neo_tree", function()
  local source
  local mock_renderer
  local mock_items
  local mock_utils

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals(nil, {
      getcwd = function()
        return "/current/cwd"
      end,
    })

    mock_renderer = {
      show_nodes = stub.new(),
      focus_node = stub.new(),
    }
    rawset(package.loaded, "neo-tree.ui.renderer", mock_renderer)

    mock_items = {
      get_items = stub.new(),
      find_node_by_path = stub.new(),
    }
    rawset(package.loaded, "ada_ls.project_view.neo_tree.items", mock_items)

    mock_utils = {
      notify = stub.new(),
    }
    rawset(package.loaded, "ada_ls.utils", mock_utils)

    source = require("ada_ls.project_view.neo_tree")
  end)

  after_each(function()
    common.cleanup_packages()
    package.loaded["neo-tree.ui.renderer"] = nil
  end)

  describe("default_config", function()
    it("defines a project renderer", function()
      assert.is_table(source.default_config.renderers)
      assert.is_table(source.default_config.renderers.project)
    end)

    it("renders project nodes with indent, icon, and name", function()
      local renderer = source.default_config.renderers.project

      assert.equals("indent", renderer[1][1])
      assert.equals("icon", renderer[2][1])
      assert.equals("container", renderer[3][1])
      assert.equals("name", renderer[3].content[1][1])
    end)
  end)

  describe("setup", function()
    it("stores config and global_config", function()
      local config = {
        show_runtime = true,
        show_object_dirs = true,
        flat_mode = true,
      }
      local global_config = { use_git_status = false }

      source.setup(config, global_config)

      assert.equals(config, source.config)
      assert.equals(global_config, source.global_config)
    end)
  end)

  describe("navigate", function()
    it("uses explicit path and configured options", function()
      local state = {}
      local items = {
        { id = "project:root", name = "root", type = "project" },
      }
      local captured_opts

      mock_items.get_items = function(opts, callback)
        captured_opts = opts
        callback(items)
      end

      source.setup({
        show_runtime = true,
        show_object_dirs = true,
        flat_mode = true,
      }, {})

      source.navigate(state, "/explicit/path", nil, nil)

      assert.equals("/explicit/path", state.path)
      assert.same({
        show_runtime = true,
        show_object_dirs = true,
        flat_mode = true,
      }, captured_opts)
      assert.stub(mock_renderer.show_nodes).was_called_with(items, state)
      assert.stub(mock_items.find_node_by_path).was_not_called()
      assert.stub(mock_renderer.focus_node).was_not_called()
    end)

    it("falls back to cwd and default options before setup", function()
      local state = {}
      local captured_opts

      mock_items.get_items = function(opts, callback)
        captured_opts = opts
        callback({})
      end

      source.navigate(state, nil, nil, nil)

      assert.equals("/current/cwd", state.path)
      assert.same({
        show_runtime = false,
        show_object_dirs = false,
        flat_mode = false,
      }, captured_opts)
    end)

    it(
      "notifies and renders an empty tree when get_items returns an error",
      function()
        local state = {}

        mock_items.get_items = function(_opts, callback)
          callback(nil, "Project view failed")
        end

        source.navigate(state, "/explicit/path", nil, nil)

        assert
          .stub(mock_utils.notify)
          .was_called_with("Project view failed", vim.log.levels.WARN)

        local call = mock_renderer.show_nodes.calls[1].vals
        assert.same({}, call[1])
        assert.equals("/explicit/path", call[2].path)
      end
    )

    it("reveals and focuses a matching node when requested", function()
      local state = {}
      local items = {
        { id = "project:root", name = "root", type = "project" },
      }
      local callback = stub.new()

      mock_items.get_items = function(_opts, done)
        done(items)
      end

      mock_items.find_node_by_path = function(found_items, reveal_path)
        assert.equals(items, found_items)
        assert.equals("/explicit/path/main.adb", reveal_path)
        return { id = "file:main" }
      end

      source.navigate(
        state,
        "/explicit/path",
        "/explicit/path/main.adb",
        callback
      )

      assert.stub(mock_renderer.show_nodes).was_called_with(items, state)
      assert.stub(mock_renderer.focus_node).was_called_with(state, "file:main")
      assert.stub(callback).was_called()
    end)

    it("skips focusing when the reveal target is not found", function()
      local state = {}
      local items = {
        { id = "project:root", name = "root", type = "project" },
      }
      local callback = stub.new()

      mock_items.get_items = function(_opts, done)
        done(items)
      end

      mock_items.find_node_by_path = function(_items, _reveal_path)
        return nil
      end

      source.navigate(
        state,
        "/explicit/path",
        "/explicit/path/missing.adb",
        callback
      )

      assert.stub(mock_renderer.focus_node).was_not_called()
      assert.stub(callback).was_called()
    end)
  end)
end)
