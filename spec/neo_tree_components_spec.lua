-- Tests for lua/ada_ls/project_view/neo_tree/components.lua
local common = require("spec.helpers.common")
local stub = require("luassert.stub")

--- Find a highlight setup call by name
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

    -- Add nvim_set_hl mock
    vim.api.nvim_set_hl = stub.new()

    -- Mock neo-tree common components
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

    it("returns project icon for project nodes", function()
      local node = { type = "project", extra = {} }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaProject", result.highlight)
    end)

    it("returns runtime icon for runtime project nodes", function()
      local node = { type = "project", extra = { is_runtime = true } }
      local result = components.icon({}, node, {})

      assert.equals(" ", result.text)
      assert.equals("NeoTreeAdaRuntime", result.highlight)
    end)

    it("returns gear icon for object directory nodes", function()
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

    it("delegates to common for directory nodes without extra", function()
      local node = { type = "directory", name = "src" }
      local config = {}
      local state = {}

      components.icon(config, node, state)

      assert
        .stub(mock_common_components.icon)
        .was_called_with(config, node, state)
    end)

    it(
      "delegates to common for directory nodes without is_object_dir",
      function()
        local node = { type = "directory", name = "src", extra = {} }
        local config = {}
        local state = {}

        components.icon(config, node, state)

        assert
          .stub(mock_common_components.icon)
          .was_called_with(config, node, state)
      end
    )
  end)

  describe("name", function()
    before_each(function()
      components = require("ada_ls.project_view.neo_tree.components")
    end)

    it("uses NeoTreeAdaProject highlight for project nodes", function()
      local node = { type = "project", name = "my_project", extra = {} }
      local result = components.name({}, node, {})

      assert.equals("my_project", result.text)
      assert.equals("NeoTreeAdaProject", result.highlight)
    end)

    it("uses NeoTreeAdaRuntime highlight for runtime nodes", function()
      local node =
        { type = "project", name = "Runtime", extra = { is_runtime = true } }
      local result = components.name({}, node, {})

      assert.equals("Runtime", result.text)
      assert.equals("NeoTreeAdaRuntime", result.highlight)
    end)

    it("uses NeoTreeAdaObjectDir highlight for object dirs", function()
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
    it("creates NeoTreeAdaProject highlight group", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})

      local opts = find_hl_call(vim.api.nvim_set_hl.calls, "NeoTreeAdaProject")
      assert.is_not_nil(opts, "NeoTreeAdaProject highlight not created")
      assert.is_true(opts.default)
      assert.equals("Directory", opts.link)
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

    it("only sets up highlights once", function()
      components = require("ada_ls.project_view.neo_tree.components")
      components.icon({}, { type = "project", extra = {} }, {})
      components.icon({}, { type = "project", extra = {} }, {})
      components.icon({}, { type = "project", extra = {} }, {})

      -- Count NeoTreeAdaProject calls (should be exactly 1)
      local count = 0
      for _, call in ipairs(vim.api.nvim_set_hl.calls) do
        if call.vals[2] == "NeoTreeAdaProject" then
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
      assert.equals("NeoTreeAdaProject", components.highlights.project)
      assert.equals("NeoTreeAdaRuntime", components.highlights.runtime)
      assert.equals("NeoTreeAdaObjectDir", components.highlights.object_dir)
    end)

    it("uses exported names in icon results", function()
      components = require("ada_ls.project_view.neo_tree.components")

      local result = components.icon({}, { type = "project", extra = {} }, {})
      assert.equals(components.highlights.project, result.highlight)
    end)

    it("uses exported names in name results", function()
      components = require("ada_ls.project_view.neo_tree.components")

      local result = components.name(
        {},
        { type = "project", name = "test", extra = {} },
        {}
      )
      assert.equals(components.highlights.project, result.highlight)
    end)
  end)

  describe("module exports", function()
    it("includes common components via tbl_deep_extend", function()
      components = require("ada_ls.project_view.neo_tree.components")

      -- Should have inherited indent and git_status from mock
      assert.is_function(components.indent)
      assert.is_function(components.git_status)
    end)

    it("overrides icon from common", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_function(components.icon)
      local result = components.icon({}, { type = "project", extra = {} }, {})
      assert.equals(" ", result.text)
    end)

    it("overrides name from common", function()
      components = require("ada_ls.project_view.neo_tree.components")

      assert.is_function(components.name)
      local result = components.name(
        {},
        { type = "project", name = "test", extra = {} },
        {}
      )
      assert.equals("NeoTreeAdaProject", result.highlight)
    end)
  end)
end)

-- Test internals when ADA_LS_TEST_MODE is set
if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.neo_tree.components (internals)", function()
    local components

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals()
      vim.api.nvim_set_hl = stub.new()

      -- Mock neo-tree common components
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
        assert.equals(" ", components._icons.project)
        assert.equals(" ", components._icons.runtime)
        assert.equals(" ", components._icons.object_dir)
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
        -- Reset the cache
        components._reset_common_cache()

        -- Call icon for a file (triggers get_common)
        local result = components.icon({}, { type = "file" }, {})

        -- Should have delegated to mock common
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
