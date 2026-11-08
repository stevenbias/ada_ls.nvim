-- Tests for lua/ada_ls/project_view/neo_tree/components.lua
local common = require("spec.helpers.common")
local stub = require("luassert.stub")

---@param calls table Stub calls array
---@param name string Highlight group name
---@return table|nil opts The highlight options if found
local function find_hl_call(calls, name)
  for _, call in ipairs(calls) do
    if call.vals[2] == name then
      return call.vals[3]
    end
  end
  return nil
end

describe("ada_ls.project_view.neo_tree.components", function()
  local components
  local mock_common_components

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()

    vim.api.nvim_set_hl = stub.new()

    mock_common_components = {
      icon = stub.new().returns({ text = " ", highlight = "NeoTreeFileIcon" }),
      name = stub
        .new()
        .returns({ text = "test.adb", highlight = "NeoTreeFileName" }),
      indent = function()
        return {}
      end,
      git_status = function()
        return {}
      end,
    }
    package.loaded["neo-tree.sources.common.components"] =
      mock_common_components
  end)

  after_each(function()
    common.cleanup_packages()
    package.loaded["neo-tree.sources.common.components"] = nil
  end)

  describe("icon", function()
    before_each(function()
      components = require("ada_ls.project_view.neo_tree.components")
    end)

    it("returns folder icon for collapsed project nodes", function()
      local node = {
        type = "project",
        extra = {},
        is_expanded = function()
          return false
        end,
      }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaProjectSubproject", result.highlight)
    end)

    it("returns open folder icon for expanded project nodes", function()
      local node = {
        type = "project",
        extra = {},
        is_expanded = function()
          return true
        end,
      }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaProjectSubproject", result.highlight)
    end)

    it("uses root highlight for root project nodes", function()
      local node = {
        type = "project",
        extra = { is_root = true },
        is_expanded = function()
          return false
        end,
      }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaProjectRoot", result.highlight)
    end)

    it("returns runtime icon for runtime project nodes", function()
      local node = { type = "project", extra = { is_runtime = true } }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaRuntime", result.highlight)
    end)

    it("returns object-dir icon for object directory nodes", function()
      local node = { type = "directory", extra = { is_object_dir = true } }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaObjectDir", result.highlight)
    end)

    it("delegates to common for file nodes", function()
      local node = { type = "file", name = "test.adb" }
      local config = { default = " " }
      local state = {}

      components.icon(config, node, state)

      assert
        .stub(mock_common_components.icon)
        .was_called_with(config, node, state)
    end)

    it("delegates to common for plain directory nodes", function()
      local node = { type = "directory", name = "src", extra = {} }
      local config = {}
      local state = {}

      components.icon(config, node, state)

      assert
        .stub(mock_common_components.icon)
        .was_called_with(config, node, state)
    end)
  end)

  describe("name", function()
    before_each(function()
      components = require("ada_ls.project_view.neo_tree.components")
    end)

    it("uses subproject highlight for project nodes", function()
      local node = { type = "project", name = "my_project", extra = {} }
      local result = components.name({}, node, {})

      assert.equals("my_project", result.text)
      assert.equals("NeoTreeAdaProjectSubproject", result.highlight)
    end)

    it("uses root highlight for root project nodes", function()
      local node = {
        type = "project",
        name = "root_project",
        extra = { is_root = true },
      }
      local result = components.name({}, node, {})

      assert.equals("root_project", result.text)
      assert.equals("NeoTreeAdaProjectRoot", result.highlight)
    end)

    it("uses runtime highlight for runtime nodes", function()
      local node =
        { type = "project", name = "Runtime", extra = { is_runtime = true } }
      local result = components.name({}, node, {})

      assert.equals("Runtime", result.text)
      assert.equals("NeoTreeAdaRuntime", result.highlight)
    end)

    it("uses object-dir highlight for object dirs", function()
      local node = {
        type = "directory",
        name = "obj (obj)",
        extra = { is_object_dir = true },
      }
      local result = components.name({}, node, {})

      assert.equals("obj (obj)", result.text)
      assert.equals("NeoTreeAdaObjectDir", result.highlight)
    end)

    it("delegates to common for file nodes", function()
      local node = { type = "file", name = "main.adb" }
      local config = {}
      local state = {}

      components.name(config, node, state)

      assert
        .stub(mock_common_components.name)
        .was_called_with(config, node, state)
    end)

    it("delegates to common for regular directory nodes", function()
      local node = { type = "directory", name = "src", extra = {} }
      local config = {}
      local state = {}

      components.name(config, node, state)

      assert
        .stub(mock_common_components.name)
        .was_called_with(config, node, state)
    end)
  end)

  describe("highlight setup", function()
    it("creates NeoTreeAdaProjectRoot highlight group", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})

      local opts =
        find_hl_call(vim.api.nvim_set_hl.calls, "NeoTreeAdaProjectRoot")
      assert.is_not_nil(opts, "NeoTreeAdaProjectRoot highlight not created")
      assert.is_true(opts.default)
      assert.equals("Title", opts.link)
      assert.is_true(opts.bold)
    end)

    it("creates NeoTreeAdaProjectSubproject highlight group", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})

      local opts =
        find_hl_call(vim.api.nvim_set_hl.calls, "NeoTreeAdaProjectSubproject")
      assert.is_not_nil(
        opts,
        "NeoTreeAdaProjectSubproject highlight not created"
      )
      assert.equals("Type", opts.link)
    end)

    it("creates NeoTreeAdaRuntime highlight group", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})

      local opts = find_hl_call(vim.api.nvim_set_hl.calls, "NeoTreeAdaRuntime")
      assert.is_not_nil(opts, "NeoTreeAdaRuntime highlight not created")
      assert.equals("NeoTreeDimText", opts.link)
    end)

    it("creates NeoTreeAdaObjectDir highlight group", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})

      local opts =
        find_hl_call(vim.api.nvim_set_hl.calls, "NeoTreeAdaObjectDir")
      assert.is_not_nil(opts, "NeoTreeAdaObjectDir highlight not created")
      assert.equals("NeoTreeDimText", opts.link)
    end)

    it("only sets up project highlights once", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})
      components.icon({}, { type = "project", extra = {} }, {})
      components.icon({}, { type = "project", extra = {} }, {})

      local count = 0
      for _, call in ipairs(vim.api.nvim_set_hl.calls) do
        if call.vals[2] == "NeoTreeAdaProjectRoot" then
          count = count + 1
        end
      end
      assert.equals(1, count)
    end)
  end)

  describe("exported highlights", function()
    it("exposes highlight group names for user customization", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_table(components.highlights)
      assert.equals(
        "NeoTreeAdaProjectSubproject",
        components.highlights.project
      )
      assert.equals("NeoTreeAdaProjectRoot", components.highlights.project_root)
      assert.equals(
        "NeoTreeAdaProjectSubproject",
        components.highlights.project_subproject
      )
      assert.equals("NeoTreeAdaRuntime", components.highlights.runtime)
      assert.equals("NeoTreeAdaObjectDir", components.highlights.object_dir)
    end)

    it("uses exported names in icon results", function()
      components = require("ada_ls.project_view.neo_tree.components")

      local result = components.icon({}, {
        type = "project",
        extra = {},
        is_expanded = function()
          return false
        end,
      }, {})
      assert.equals(components.highlights.project_subproject, result.highlight)
    end)

    it("uses exported names in name results", function()
      components = require("ada_ls.project_view.neo_tree.components")

      local result = components.name(
        {},
        { type = "project", name = "test", extra = {} },
        {}
      )
      assert.equals(components.highlights.project_subproject, result.highlight)
    end)
  end)

  describe("module exports", function()
    it("includes common components via tbl_deep_extend", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_function(components.indent)
      assert.is_function(components.git_status)
    end)

    it("overrides icon from common", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_function(components.icon)
      local result = components.icon({}, {
        type = "project",
        extra = {},
        is_expanded = function()
          return false
        end,
      }, {})
      assert.equals(" ", result.text)
    end)

    it("overrides name from common", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_function(components.name)
      local result = components.name(
        {},
        { type = "project", name = "test", extra = {} },
        {}
      )
      assert.equals("NeoTreeAdaProjectSubproject", result.highlight)
    end)
  end)
end)

if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.neo_tree.components (internals)", function()
    local components

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals()
      vim.api.nvim_set_hl = stub.new()

      package.loaded["neo-tree.sources.common.components"] = {
        icon = function()
          return {}
        end,
        name = function()
          return {}
        end,
      }

      components = require("ada_ls.project_view.neo_tree.components")
    end)

    after_each(function()
      common.cleanup_packages()
      package.loaded["neo-tree.sources.common.components"] = nil
    end)

    describe("_icons", function()
      it("exposes icon constants for testing", function()
        assert.is_table(components._icons)
        assert.equals(" ", components._icons.project_closed)
        assert.equals(" ", components._icons.project_open)
        assert.equals(" ", components._icons.runtime)
        assert.equals(" ", components._icons.object_dir)
      end)
    end)

    describe("_get_project_highlight", function()
      it("returns root highlight for root nodes", function()
        local result =
          components._get_project_highlight({ extra = { is_root = true } })

        assert.equals("NeoTreeAdaProjectRoot", result)
      end)

      it("returns subproject highlight for non-root nodes", function()
        local result = components._get_project_highlight({ extra = {} })

        assert.equals("NeoTreeAdaProjectSubproject", result)
      end)
    end)

    describe("_get_project_icon", function()
      it("returns closed folder for collapsed nodes", function()
        local result = components._get_project_icon({
          is_expanded = function()
            return false
          end,
        })

        assert.equals(" ", result)
      end)

      it("returns open folder for expanded nodes", function()
        local result = components._get_project_icon({
          is_expanded = function()
            return true
          end,
        })

        assert.equals(" ", result)
      end)
    end)

    describe("_reset_highlights_flag", function()
      it("allows highlights to be set up again", function()
        components.icon({}, { type = "project", extra = {} }, {})
        local initial_count = #vim.api.nvim_set_hl.calls

        components._reset_highlights_flag()
        components.icon({}, { type = "project", extra = {} }, {})

        assert.is_true(#vim.api.nvim_set_hl.calls > initial_count)
      end)
    end)

    describe("_setup_highlights", function()
      it("is exposed for testing", function()
        assert.is_function(components._setup_highlights)
      end)

      it("can be called directly", function()
        components._reset_highlights_flag()
        vim.api.nvim_set_hl:clear()

        components._setup_highlights()

        assert.stub(vim.api.nvim_set_hl).was_called()
      end)
    end)

    describe("_reset_common_cache", function()
      it("forces lazy-load on next icon call", function()
        components._reset_common_cache()

        local result = components.icon({}, { type = "file" }, {})

        assert.is_table(result)
      end)

      it("forces lazy-load on next name call", function()
        components._reset_common_cache()

        local result = components.name({}, { type = "file", name = "test" }, {})

        assert.is_table(result)
      end)
    end)
  end)
end
