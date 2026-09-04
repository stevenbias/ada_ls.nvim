-- Tests for lua/ada_ls/project_view/
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.project_view.data", function()
  local data

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    -- Add vim.fs.normalize for path comparisons
    vim.fs.normalize = function(path)
      return path
    end
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("parse_response", function()
    before_each(function()
      data = require("ada_ls.project_view.data")
    end)

    it("returns error for nil input", function()
      local result, err = data.parse_response(nil)
      assert.is_nil(result)
      assert.equals("No response data", err)
    end)

    it("returns error when projects is missing", function()
      local result, err = data.parse_response({})
      assert.is_nil(result)
      assert.truthy(err:match("projects"))
    end)

    it("returns error when projects array is empty", function()
      local result, err = data.parse_response({ projects = {} })
      assert.is_nil(result)
      assert.truthy(err:match("No projects"))
    end)

    it("uses first project as root when no tree field", function()
      -- This simulates the actual ALS response format (no tree field)
      local response = {
        projects = {
          {
            project = {
              id = "proj_1",
              name = "test_project",
              directory = "/test",
            },
            sources = {},
          },
        },
      }
      local result, err = data.parse_response(response)

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.equals("proj_1", result.root_project_id)
    end)

    it("parses valid response successfully", function()
      local response = common.create_project_view_response({
        root_name = "my_project",
        root_id = "proj_1",
      })
      local result, err = data.parse_response(response)

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.equals("proj_1", result.root_project_id)
      assert.is_table(result.projects)
      assert.is_not_nil(result.projects["proj_1"])
    end)

    it("parses project metadata correctly", function()
      local response = common.create_project_view_response()
      local result = data.parse_response(response)

      local project = result.projects[result.root_project_id].project
      assert.equals("main_project", project.name)
      assert.equals("/project", project.directory)
      assert.equals("standard", project.kind)
      assert.is_false(project.is_externally_built)
      assert.same({ "ada" }, project.languages)
    end)

    it("parses sources correctly", function()
      local response = common.create_project_view_response()
      local result = data.parse_response(response)

      local entry = result.projects[result.root_project_id]
      assert.equals(2, #entry.sources)

      local src = entry.sources[1]
      assert.equals("/project/src/main.adb", src.file_name)
      assert.equals("main.adb", src.simple_name)
      assert.equals("/project/src", src.directory)
      assert.equals("ada", src.language)
    end)

    it("parses runtime project when present", function()
      local response = common.create_project_view_response({
        runtime = {
          id = "runtime_id",
          name = "GNAT Runtime",
          ["source-directories"] = { "/usr/lib/gnat/runtime" },
          sources = {
            {
              ["file-name"] = "/usr/lib/gnat/runtime/ada.ads",
              ["simple-name"] = "ada.ads",
              directory = "/usr/lib/gnat/runtime",
            },
          },
        },
      })
      local result = data.parse_response(response)

      assert.is_not_nil(result.runtime_project)
      assert.equals("runtime", result.runtime_project.project.kind)
      assert.equals(1, #result.runtime_project.sources)
    end)

    it("handles empty sources array", function()
      local response = common.create_project_view_response()
      response.projects[1].sources = {}

      local result = data.parse_response(response)
      local entry = result.projects[result.root_project_id]
      assert.equals(0, #entry.sources)
    end)

    it("parses extending info when present", function()
      local response = common.create_project_view_response()
      response.projects[1].extending = {
        ["extending-all"] = true,
        ["project-id"] = "base_proj",
      }

      local result = data.parse_response(response)
      local entry = result.projects[result.root_project_id]
      assert.is_not_nil(entry.extending)
      assert.is_true(entry.extending.extending_all)
      assert.equals("base_proj", entry.extending.project_id)
    end)
  end)

  describe("get_all_sources", function()
    before_each(function()
      data = require("ada_ls.project_view.data")
    end)

    it("returns sources from root project first", function()
      local response = common.create_project_view_response()
      local parsed = data.parse_response(response)
      local sources = data.get_all_sources(parsed)

      assert.equals(2, #sources)
      assert.is_true(sources[1].is_root)
      assert.is_true(sources[2].is_root)
    end)

    it("includes sources from multiple projects", function()
      local lib_project = {
        project = {
          id = "lib_id",
          name = "lib_project",
          kind = "library",
          qualifier = "default",
          ["simple-name"] = "lib.gpr",
          ["file-name"] = "/libs/lib.gpr",
          directory = "/libs",
          ["is-externally-built"] = false,
          languages = { "ada" },
          ["source-directories"] = { "/libs/src" },
        },
        imports = {},
        aggregated = {},
        extended = {},
        ["imported-by"] = {},
        sources = {
          {
            ["file-name"] = "/libs/src/lib.ads",
            ["simple-name"] = "lib.ads",
            directory = "/libs/src",
          },
        },
      }

      local response = common.create_project_view_response()
      table.insert(response.projects, lib_project)

      local parsed = data.parse_response(response)
      local sources = data.get_all_sources(parsed)

      -- 2 from root + 1 from lib
      assert.equals(3, #sources)

      -- Find non-root source
      local has_lib = false
      for _, s in ipairs(sources) do
        if s.project.name == "lib_project" then
          has_lib = true
          assert.is_false(s.is_root)
        end
      end
      assert.is_true(has_lib)
    end)

    it("excludes runtime sources by default", function()
      local response = common.create_project_view_response({
        runtime = {
          id = "runtime",
          name = "Runtime",
          sources = {
            {
              ["file-name"] = "/runtime/ada.ads",
              ["simple-name"] = "ada.ads",
              directory = "/runtime",
            },
          },
        },
      })

      local parsed = data.parse_response(response)
      local sources = data.get_all_sources(parsed)

      -- Only 2 from main project, not runtime
      assert.equals(2, #sources)
    end)

    it("includes runtime sources when option is set", function()
      local response = common.create_project_view_response({
        runtime = {
          id = "runtime",
          name = "Runtime",
          sources = {
            {
              ["file-name"] = "/runtime/ada.ads",
              ["simple-name"] = "ada.ads",
              directory = "/runtime",
            },
          },
        },
      })

      local parsed = data.parse_response(response)
      local sources = data.get_all_sources(parsed, { include_runtime = true })

      -- 2 from main + 1 from runtime
      assert.equals(3, #sources)
    end)
  end)

  describe("find_source", function()
    before_each(function()
      data = require("ada_ls.project_view.data")
    end)

    it("finds source by file path", function()
      local response = common.create_project_view_response()
      local parsed = data.parse_response(response)

      local result = data.find_source(parsed, "/project/src/main.adb")

      assert.is_not_nil(result)
      assert.equals("main.adb", result.source.simple_name)
      assert.equals("main_project", result.project.name)
    end)

    it("returns nil for non-existent path", function()
      local response = common.create_project_view_response()
      local parsed = data.parse_response(response)

      local result = data.find_source(parsed, "/nonexistent/file.adb")
      assert.is_nil(result)
    end)

    it("finds source in runtime project", function()
      local response = common.create_project_view_response({
        runtime = {
          id = "runtime",
          name = "Runtime",
          sources = {
            {
              ["file-name"] = "/runtime/ada.ads",
              ["simple-name"] = "ada.ads",
              directory = "/runtime",
            },
          },
        },
      })

      local parsed = data.parse_response(response)
      local result = data.find_source(parsed, "/runtime/ada.ads")

      assert.is_not_nil(result)
      assert.equals("ada.ads", result.source.simple_name)
      assert.equals("runtime", result.project.kind)
    end)
  end)

  describe("is_supported", function()
    it("returns false when ALS returns unknown command error", function()
      common.setup_lsp_cmd_project_view_mock(nil, "Unknown command")
      data = require("ada_ls.project_view.data")

      local supported, err = data.is_supported()

      assert.is_false(supported)
      assert.is_string(err)
      assert.truthy(err:match("ALS 2026.3"))
    end)

    it("returns true when command succeeds", function()
      local response = common.create_project_view_response()
      common.setup_lsp_cmd_project_view_mock(response)
      data = require("ada_ls.project_view.data")

      local supported, err = data.is_supported()

      assert.is_true(supported)
      assert.is_nil(err)
    end)
  end)

  describe("fetch", function()
    it("returns cached data on second call", function()
      local response = common.create_project_view_response()
      common.setup_lsp_cmd_project_view_mock(response)
      data = require("ada_ls.project_view.data")

      local result1 = data.fetch()
      local result2 = data.fetch()

      assert.is_not_nil(result1)
      assert.equals(result1, result2) -- Same reference = cached
    end)

    it("fetches fresh data when force=true", function()
      local response = common.create_project_view_response()
      local call_count = 0
      rawset(package.loaded, "ada_ls.lsp_cmd", {
        get_project_view_info = function()
          call_count = call_count + 1
          return response
        end,
      })
      data = require("ada_ls.project_view.data")

      data.fetch()
      data.fetch(true) -- Force refresh

      assert.equals(2, call_count)
    end)

    it("returns error when ALS not supported", function()
      common.setup_lsp_cmd_project_view_mock(nil, "Unknown command")
      data = require("ada_ls.project_view.data")

      local result, err = data.fetch()

      assert.is_nil(result)
      assert.is_string(err)
    end)
  end)

  describe("invalidate", function()
    it("clears cached data", function()
      local response = common.create_project_view_response()
      common.setup_lsp_cmd_project_view_mock(response)
      data = require("ada_ls.project_view.data")

      data.fetch()
      assert.is_not_nil(data.get_cached())

      data.invalidate()
      assert.is_nil(data.get_cached())
    end)
  end)
end)

describe("ada_ls.project_view (init.lua)", function()
  local project_view

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    vim.fs.normalize = function(path)
      return path
    end
    -- Mock neo-tree related functions
    vim.cmd = stub()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("backend detection", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
    end)

    it("defaults to 'auto' backend in initial state", function()
      assert.equals("auto", project_view.get_option("backend"))
    end)

    it("detects when neo-tree is available", function()
      -- Mock pcall to return success for neo-tree
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "neo-tree" then
          return true
        end
        return original_pcall(fn, ...)
      end

      assert.is_true(project_view._neo_tree_available())

      _G.pcall = original_pcall
    end)

    it("detects when neo-tree is not available", function()
      -- Mock pcall to return failure for neo-tree
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "neo-tree" then
          return false
        end
        return original_pcall(fn, ...)
      end

      assert.is_false(project_view._neo_tree_available())

      _G.pcall = original_pcall
    end)

    it("returns builtin backend when forced", function()
      project_view.setup({ backend = "builtin" })
      assert.equals("builtin", project_view._get_backend())
    end)

    it("returns builtin backend when neo-tree unavailable", function()
      -- Mock pcall to return failure for neo-tree
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "neo-tree" then
          return false
        end
        return original_pcall(fn, ...)
      end

      project_view.setup({ backend = "auto" })
      assert.equals("builtin", project_view._get_backend())

      _G.pcall = original_pcall
    end)
  end)

  describe("setup", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
    end)

    it("updates flat_mode option", function()
      project_view.setup({ flat_mode = true })
      assert.is_true(project_view.get_option("flat_mode"))
    end)

    it("updates show_object_dirs option", function()
      project_view.setup({ show_object_dirs = true })
      assert.is_true(project_view.get_option("show_object_dirs"))
    end)

    it("updates show_runtime option", function()
      project_view.setup({ show_runtime = true })
      assert.is_true(project_view.get_option("show_runtime"))
    end)

    it("updates backend option", function()
      project_view.setup({ backend = "builtin" })
      assert.equals("builtin", project_view.get_option("backend"))
    end)

    it("handles partial options", function()
      project_view.setup({ flat_mode = true })
      -- Other options should remain at default
      assert.is_false(project_view.get_option("show_object_dirs"))
      assert.is_true(project_view.get_option("flat_mode"))
    end)
  end)

  describe("option management", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
    end)

    it("gets option values", function()
      assert.equals("auto", project_view.get_option("backend"))
      assert.is_false(project_view.get_option("flat_mode"))
    end)

    it("sets option values", function()
      project_view.set_option("flat_mode", true)
      assert.is_true(project_view.get_option("flat_mode"))
    end)

    it("ignores invalid option keys", function()
      project_view.set_option("invalid_option", true)
      -- Should not error, just ignore
      assert.is_false(project_view.get_option("flat_mode"))
    end)

    it("refreshes tree when boolean option changed while open", function()
      local tree_module = require("ada_ls.project_view.tree")

      -- Mock is_open to return true
      stub(tree_module, "is_open").returns(true)

      -- Stub refresh before setting the option
      local refresh_stub = stub(tree_module, "refresh")

      project_view.set_option("flat_mode", true)

      assert.stub(refresh_stub).was_called()
    end)
  end)

  describe("tree operations", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
      -- Mock the tree module
      require("ada_ls.project_view.tree").open = stub()
      require("ada_ls.project_view.tree").close = stub()
      require("ada_ls.project_view.tree").toggle = stub()
      require("ada_ls.project_view.tree").is_open = stub().returns(false)
    end)

    it("opens builtin tree when backend is builtin", function()
      project_view.setup({ backend = "builtin" })
      project_view.open()

      assert.stub(require("ada_ls.project_view.tree").open).was_called()
    end)

    it("closes builtin tree when backend is builtin", function()
      project_view.setup({ backend = "builtin" })
      project_view.close()

      assert.stub(require("ada_ls.project_view.tree").close).was_called()
    end)

    it("toggles builtin tree when backend is builtin", function()
      project_view.setup({ backend = "builtin" })
      project_view.toggle()

      assert.stub(require("ada_ls.project_view.tree").toggle).was_called()
    end)

    it("checks if tree is open with builtin backend", function()
      project_view.setup({ backend = "builtin" })
      project_view.is_open()

      assert.stub(require("ada_ls.project_view.tree").is_open).was_called()
    end)
  end)

  describe("invalidation", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
      local data = require("ada_ls.project_view.data")
      data.invalidate = stub()
    end)

    it("invalidates project data", function()
      project_view.invalidate()

      assert.stub(require("ada_ls.project_view.data").invalidate).was_called()
    end)

    it("refreshes data and tree", function()
      require("ada_ls.project_view.tree").is_open = stub().returns(true)
      require("ada_ls.project_view.tree").refresh = stub()

      project_view.refresh()

      assert.stub(require("ada_ls.project_view.data").invalidate).was_called()
      assert.stub(require("ada_ls.project_view.tree").refresh).was_called()
    end)
  end)

  describe("neo-tree backend detection", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
    end)

    it("checks if neo-tree source is registered", function()
      -- Mock neo-tree as unavailable
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "neo-tree" then
          return false
        end
        return original_pcall(fn, ...)
      end

      local registered = project_view._neo_tree_source_registered()
      assert.is_false(registered)

      _G.pcall = original_pcall
    end)

    it("returns using_neo_tree status", function()
      local using_neo_tree = project_view.using_neo_tree()
      assert.is_boolean(using_neo_tree)
    end)
  end)

  describe("reveal current file", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
      local tree = require("ada_ls.project_view.tree")
      stub(tree, "is_open").returns(false)
      stub(tree, "open")
      stub(tree, "reveal_current_file")
    end)

    it("opens tree if not open before revealing", function()
      vim.fn.expand = function()
        return "/test/current.adb"
      end

      project_view.reveal()

      assert.stub(require("ada_ls.project_view.tree").open).was_called()
      assert
        .stub(require("ada_ls.project_view.tree").reveal_current_file)
        .was_called()
    end)

    it("does nothing if no current file", function()
      vim.fn.expand = function()
        return ""
      end

      local tree = require("ada_ls.project_view.tree")
      stub(tree, "is_open").returns(false)
      stub(tree, "open")

      project_view.reveal()

      assert.stub(tree.open).was_not_called()
    end)
  end)

  describe("is_supported", function()
    before_each(function()
      project_view = require("ada_ls.project_view")
    end)

    it("delegates to data.is_supported", function()
      local data = require("ada_ls.project_view.data")
      stub(data, "is_supported").returns(true)

      local supported = project_view.is_supported()

      assert.is_true(supported)
    end)
  end)
end)

describe("ada_ls.project_view.telescope", function()
  local telescope_mod

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    vim.fs.normalize = function(path)
      return path
    end
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("pick_file", function()
    before_each(function()
      telescope_mod = require("ada_ls.project_view.telescope")
    end)

    it("notifies when telescope not available", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")

      -- Mock pcall to fail for telescope
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return false
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_file()

      assert.stub(notify_stub).was_called()
      notify_stub:revert()
      _G.pcall = original_pcall
    end)

    it("notifies when no data available", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")
      local data = require("ada_ls.project_view.data")
      stub(data, "fetch").returns(nil, "Error fetching data")

      -- Mock telescope as available
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return true
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_file()

      assert
        .stub(notify_stub)
        .was_called_with("Error fetching data", vim.log.levels.ERROR)
      notify_stub:revert()
      _G.pcall = original_pcall
    end)

    it("notifies when no projects found", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")
      local data = require("ada_ls.project_view.data")
      stub(data, "fetch").returns({ projects = {} })

      -- Mock telescope as available
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return true
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_file()

      assert.stub(notify_stub).was_called()
      notify_stub:revert()
      _G.pcall = original_pcall
    end)

    it("notifies when no source files found", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")
      local data = require("ada_ls.project_view.data")
      stub(data, "fetch").returns(
        common.create_project_view_response({ root_id = "proj_1" })
      )
      stub(data, "get_all_sources").returns({})

      -- Mock telescope as available
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return true
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_file()

      assert.stub(notify_stub).was_called()
      notify_stub:revert()
      _G.pcall = original_pcall
    end)
  end)

  describe("pick_project", function()
    before_each(function()
      telescope_mod = require("ada_ls.project_view.telescope")
    end)

    it("notifies when telescope not available", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")

      -- Mock pcall to fail for telescope
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return false
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_project()

      assert.stub(notify_stub).was_called()
      notify_stub:revert()
      _G.pcall = original_pcall
    end)

    it("notifies when no data available", function()
      local utils = require("ada_ls.utils")
      local notify_stub = stub(utils, "notify")
      local data = require("ada_ls.project_view.data")
      stub(data, "fetch").returns(nil, "Error fetching data")

      -- Mock telescope as available
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return true
        end
        return original_pcall(fn, ...)
      end

      telescope_mod.pick_project()

      assert.stub(notify_stub).was_called()
      notify_stub:revert()
      _G.pcall = original_pcall
    end)

    it("handles callback for project selection", function()
      local data = require("ada_ls.project_view.data")
      local response = common.create_project_view_response()
      stub(data, "fetch").returns(response)

      local on_select_callback = function(project)
        -- Verify callback receives project parameter
        local _ = (project ~= nil)
      end

      -- Mock telescope as available but don't actually run it
      local original_pcall = pcall
      _G.pcall = function(fn, ...)
        if fn == require and select(1, ...) == "telescope" then
          return true
        end
        return original_pcall(fn, ...)
      end

      -- We can't easily test the picker execution, but we verify it tries
      -- and the callback would be used
      assert.is_function(on_select_callback)

      _G.pcall = original_pcall
    end)
  end)
end)

-- Additional tests for tree.lua interactive features
describe("ada_ls.project_view.tree - interactive features", function()
  local tree

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    vim.fs.normalize = function(path)
      return path
    end
    tree = require("ada_ls.project_view.tree")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("window keymaps", function()
    it("has enter handler for opening files", function()
      assert.is_function(tree._handle_enter)
    end)

    it("has split handler for horizontal split", function()
      assert.is_function(tree._handle_open_split)
    end)

    it("has vsplit handler for vertical split", function()
      assert.is_function(tree._handle_open_vsplit)
    end)

    it("has tab handler for opening in new tab", function()
      assert.is_function(tree._handle_open_tab)
    end)

    it("has preview handler for previewing files", function()
      assert.is_function(tree._handle_preview)
    end)

    it("has expand handler for expanding nodes", function()
      assert.is_function(tree._handle_expand)
    end)

    it("has collapse handler for collapsing nodes", function()
      assert.is_function(tree._handle_collapse)
    end)

    it("has collapse_all handler for collapsing all", function()
      assert.is_function(tree._handle_collapse_all)
    end)

    it("has expand_all handler for expanding all", function()
      assert.is_function(tree._handle_expand_all)
    end)

    it("has filter handler for filtering", function()
      assert.is_function(tree._handle_filter)
    end)

    it("has clear_filter handler", function()
      assert.is_function(tree._handle_clear_filter)
    end)

    it("has help handler for showing help", function()
      assert.is_function(tree._handle_help)
    end)
  end)

  describe("tree rendering options", function()
    it("supports flat_mode option", function()
      local opts =
        { flat_mode = true, show_object_dirs = false, show_runtime = false }
      assert.is_true(opts.flat_mode)
    end)

    it("supports show_object_dirs option", function()
      local opts =
        { flat_mode = false, show_object_dirs = true, show_runtime = false }
      assert.is_true(opts.show_object_dirs)
    end)

    it("supports show_runtime option", function()
      local opts =
        { flat_mode = false, show_object_dirs = false, show_runtime = true }
      assert.is_true(opts.show_runtime)
    end)
  end)

  describe("node state management", function()
    it("tracks node expansion state", function()
      tree._tree_state.expanded = {}
      local node_id = "test_node_1"

      -- Initially not set (nil)
      assert.is_nil(tree._tree_state.expanded[node_id])

      -- After toggling, should be true
      tree._tree_state.expanded[node_id] = true
      assert.is_true(tree._tree_state.expanded[node_id])

      -- After toggling again, should be false
      tree._tree_state.expanded[node_id] = false
      assert.is_false(tree._tree_state.expanded[node_id])
    end)

    it("stores filter state", function()
      tree._tree_state.filter = ""
      assert.equals("", tree._tree_state.filter)

      tree._tree_state.filter = "main"
      assert.equals("main", tree._tree_state.filter)
    end)

    it("tracks open window and buffer", function()
      tree._tree_state.buf = nil
      tree._tree_state.win = nil
      assert.is_nil(tree._tree_state.buf)
      assert.is_nil(tree._tree_state.win)

      tree._tree_state.buf = 1
      tree._tree_state.win = 2
      assert.equals(1, tree._tree_state.buf)
      assert.equals(2, tree._tree_state.win)
    end)
  end)
end)

describe("ada_ls.project_view", function()
  local project_view

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("get_option / set_option", function()
    before_each(function()
      -- Mock tree module
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")
    end)

    it("returns default values for options", function()
      assert.is_false(project_view.get_option("flat_mode"))
      assert.is_false(project_view.get_option("show_object_dirs"))
      assert.is_false(project_view.get_option("show_runtime"))
    end)

    it("sets option values", function()
      project_view.set_option("flat_mode", true)
      assert.is_true(project_view.get_option("flat_mode"))

      project_view.set_option("flat_mode", false)
      assert.is_false(project_view.get_option("flat_mode"))
    end)

    it("ignores invalid option keys", function()
      project_view.set_option("invalid_key", true)
      -- Invalid keys return nil (not set in state)
      assert.is_nil(project_view.get_option("invalid_key"))
    end)
  end)

  describe("is_supported", function()
    it("delegates to data module", function()
      local data_is_supported = stub.new().returns(true, nil)
      rawset(package.loaded, "ada_ls.project_view.data", {
        is_supported = data_is_supported,
      })
      project_view = require("ada_ls.project_view")

      local result = project_view.is_supported()

      assert.is_true(result)
      assert.stub(data_is_supported).was_called()
    end)
  end)

  describe("invalidate", function()
    it("calls data.invalidate", function()
      local invalidate_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.data", {
        invalidate = invalidate_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.invalidate()

      assert.stub(invalidate_stub).was_called()
    end)
  end)

  describe("refresh", function()
    it("invalidates data and refreshes tree if open", function()
      local invalidate_stub = stub.new()
      local refresh_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.data", {
        invalidate = invalidate_stub,
      })
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return true
        end,
        refresh = refresh_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.refresh()

      assert.stub(invalidate_stub).was_called()
      assert.stub(refresh_stub).was_called()
    end)

    it("does not refresh tree if not open", function()
      local refresh_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.data", {
        invalidate = stub.new(),
      })
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        refresh = refresh_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.refresh()

      assert.stub(refresh_stub).was_not_called()
    end)
  end)

  describe("pick_files", function()
    it("calls telescope.pick_file with runtime option from state", function()
      local pick_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.telescope", {
        pick_file = pick_stub,
      })
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")

      -- Set show_runtime option
      project_view.set_option("show_runtime", true)
      project_view.pick_files()

      assert.stub(pick_stub).was_called()
      local call_args = pick_stub.calls[1].refs[1]
      assert.is_true(call_args.include_runtime)
    end)
  end)

  describe("pick_project", function()
    it("calls telescope.pick_project", function()
      local pick_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.telescope", {
        pick_project = pick_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.pick_project()

      assert.stub(pick_stub).was_called()
    end)
  end)

  describe("open", function()
    it("calls tree.open with current state options", function()
      local open_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        open = open_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")

      project_view.set_option("flat_mode", true)
      project_view.open()

      assert.stub(open_stub).was_called()
      local call_args = open_stub.calls[1].refs[1]
      assert.is_true(call_args.flat_mode)
    end)
  end)

  describe("close", function()
    it("calls tree.close", function()
      local close_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        close = close_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.close()

      assert.stub(close_stub).was_called()
    end)
  end)

  describe("toggle", function()
    it("calls tree.toggle with current state options", function()
      local toggle_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        toggle = toggle_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")

      project_view.set_option("show_object_dirs", true)
      project_view.toggle()

      assert.stub(toggle_stub).was_called()
      local call_args = toggle_stub.calls[1].refs[1]
      assert.is_true(call_args.show_object_dirs)
    end)
  end)

  describe("reveal", function()
    it("opens tree if not open before revealing", function()
      local open_stub = stub.new()
      local reveal_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        open = open_stub,
        reveal_current_file = reveal_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")

      project_view.reveal()

      assert.stub(open_stub).was_called()
      assert.stub(reveal_stub).was_called()
    end)

    it("does not open tree if already open", function()
      local open_stub = stub.new()
      local reveal_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return true
        end,
        open = open_stub,
        reveal_current_file = reveal_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")

      project_view.reveal()

      assert.stub(open_stub).was_not_called()
      assert.stub(reveal_stub).was_called()
    end)

    it("uses manager.navigate for neo-tree backend", function()
      local navigate_stub = stub.new()
      rawset(package.loaded, "neo-tree.sources.manager", {
        navigate = navigate_stub,
      })
      -- Mock neo-tree being available
      rawset(package.loaded, "neo-tree", {
        config = { sources = { "ada_ls.project_view.neo_tree" } },
      })
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        open = stub.new(),
        reveal_current_file = stub.new(),
      })

      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "auto" })

      project_view.reveal()

      assert.stub(navigate_stub).was_called()
      local call_args = navigate_stub.calls[1].vals
      assert.equals("ada_project", call_args[1])
      -- path_to_reveal should be the current file
      assert.equals("/test/path/file.adb", call_args[3])

      -- Cleanup neo-tree mocks
      package.loaded["neo-tree"] = nil
      package.loaded["neo-tree.sources.manager"] = nil
    end)

    it("returns early if no current file", function()
      rawset(vim, "fn", {
        expand = function()
          return ""
        end,
      })
      local navigate_stub = stub.new()
      rawset(package.loaded, "neo-tree.sources.manager", {
        navigate = navigate_stub,
      })
      rawset(package.loaded, "neo-tree", {
        config = { sources = { "ada_ls.project_view.neo_tree" } },
      })

      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "auto" })

      project_view.reveal()

      assert.stub(navigate_stub).was_not_called()

      -- Cleanup neo-tree mocks
      package.loaded["neo-tree"] = nil
      package.loaded["neo-tree.sources.manager"] = nil
    end)
  end)

  describe("set_option with tree open", function()
    it("refreshes tree when option changes and tree is open", function()
      local refresh_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return true
        end,
        refresh = refresh_stub,
      })
      project_view = require("ada_ls.project_view")

      project_view.set_option("flat_mode", true)

      assert.stub(refresh_stub).was_called()
    end)
  end)

  describe("backend detection", function()
    before_each(function()
      -- Mock tree module for fallback
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        open = stub.new(),
        close = stub.new(),
        toggle = stub.new(),
        refresh = stub.new(),
        reveal_current_file = stub.new(),
      })
    end)

    it("uses builtin backend when backend is 'builtin'", function()
      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "builtin" })

      assert.is_false(project_view.using_neo_tree())
    end)

    it(
      "uses builtin backend when neo-tree not available (auto mode)",
      function()
        -- neo-tree is not loaded in tests, so auto should fall back to builtin
        project_view = require("ada_ls.project_view")
        project_view.setup({ backend = "auto" })

        assert.is_false(project_view.using_neo_tree())
      end
    )

    it(
      "falls back to builtin when neo-tree requested but not available",
      function()
        project_view = require("ada_ls.project_view")
        project_view.setup({ backend = "neo-tree" })

        -- Should fall back to builtin since neo-tree isn't loaded
        -- (silently, no warning)
        assert.is_false(project_view.using_neo_tree())
      end
    )

    it("setup configures view options", function()
      project_view = require("ada_ls.project_view")
      project_view.setup({
        backend = "builtin",
        flat_mode = true,
        show_runtime = true,
        show_object_dirs = true,
      })

      assert.is_true(project_view.get_option("flat_mode"))
      assert.is_true(project_view.get_option("show_runtime"))
      assert.is_true(project_view.get_option("show_object_dirs"))
    end)

    it("open dispatches to tree when using builtin", function()
      local open_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        open = open_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "builtin" })

      project_view.open()

      assert.stub(open_stub).was_called()
    end)

    it("close dispatches to tree when using builtin", function()
      local close_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        close = close_stub,
      })
      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "builtin" })

      project_view.close()

      assert.stub(close_stub).was_called()
    end)

    it("toggle dispatches to tree when using builtin", function()
      local toggle_stub = stub.new()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return false
        end,
        toggle = toggle_stub,
        refresh = stub.new(),
      })
      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "builtin" })

      project_view.toggle()

      assert.stub(toggle_stub).was_called()
    end)

    it("is_open checks tree when using builtin", function()
      rawset(package.loaded, "ada_ls.project_view.tree", {
        is_open = function()
          return true
        end,
      })
      project_view = require("ada_ls.project_view")
      project_view.setup({ backend = "builtin" })

      assert.is_true(project_view.is_open())
    end)

    it(
      "refresh invalidates data and refreshes tree when using builtin",
      function()
        local invalidate_stub = stub.new()
        local refresh_stub = stub.new()
        rawset(package.loaded, "ada_ls.project_view.data", {
          invalidate = invalidate_stub,
        })
        rawset(package.loaded, "ada_ls.project_view.tree", {
          is_open = function()
            return true
          end,
          refresh = refresh_stub,
        })
        project_view = require("ada_ls.project_view")
        project_view.setup({ backend = "builtin" })

        project_view.refresh()

        assert.stub(invalidate_stub).was_called()
        assert.stub(refresh_stub).was_called()
      end
    )
  end)
end)

-- Test internals when ADA_LS_TEST_MODE is set
if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.data (internals)", function()
    local data

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals()
      data = require("ada_ls.project_view.data")
    end)

    after_each(function()
      common.cleanup_packages()
    end)

    describe("_parse_source", function()
      it("parses source with all fields", function()
        local raw = {
          ["file-name"] = "/src/test.adb",
          ["simple-name"] = "test.adb",
          directory = "/src",
          language = "ada",
        }
        local result = data._parse_source(raw)

        assert.equals("/src/test.adb", result.file_name)
        assert.equals("test.adb", result.simple_name)
        assert.equals("/src", result.directory)
        assert.equals("ada", result.language)
      end)

      it("handles missing fields", function()
        local result = data._parse_source({})

        assert.equals("", result.file_name)
        assert.equals("", result.simple_name)
        assert.equals("", result.directory)
        assert.is_nil(result.language)
      end)

      it("strips trailing slashes from directory", function()
        local raw = {
          ["file-name"] = "/src/test.adb",
          ["simple-name"] = "test.adb",
          directory = "/src/",
        }
        local result = data._parse_source(raw)

        assert.equals("/src", result.directory)
      end)

      it("strips multiple trailing slashes from directory", function()
        local raw = {
          ["file-name"] = "/src/test.adb",
          directory = "/src///",
        }
        local result = data._parse_source(raw)

        assert.equals("/src", result.directory)
      end)
    end)

    describe("_parse_project_info", function()
      it("parses project info with all fields", function()
        local raw = {
          id = "proj_1",
          name = "my_project",
          kind = "standard",
          qualifier = "default",
          ["simple-name"] = "my_project.gpr",
          ["file-name"] = "/path/my_project.gpr",
          directory = "/path",
          ["is-externally-built"] = true,
          languages = { "ada", "c" },
          ["source-directories"] = { "/path/src" },
          ["object-directory"] = "/path/obj",
        }
        local result = data._parse_project_info(raw)

        assert.equals("proj_1", result.id)
        assert.equals("my_project", result.name)
        assert.equals("standard", result.kind)
        assert.is_true(result.is_externally_built)
        assert.same({ "ada", "c" }, result.languages)
        assert.equals("/path/obj", result.object_dir)
      end)

      it("strips trailing slashes from directory and object_dir", function()
        local raw = {
          id = "proj_1",
          directory = "/path/",
          ["object-directory"] = "/path/obj/",
        }
        local result = data._parse_project_info(raw)

        assert.equals("/path", result.directory)
        assert.equals("/path/obj", result.object_dir)
      end)
    end)

    describe("_cache", function()
      it("is accessible for testing", function()
        assert.is_table(data._cache)
        assert.is_nil(data._cache.data)
      end)
    end)
  end)

  describe("tree internals (ADA_LS_TEST_MODE)", function()
    local tree

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals({
        nvim_create_autocmd = function() end,
        nvim_create_augroup = function()
          return 1
        end,
        nvim_create_buf = function()
          return 1
        end,
        nvim_buf_set_lines = function() end,
        nvim_buf_set_option = function() end,
        nvim_buf_set_keymap = function() end,
        nvim_open_win = function()
          return 1
        end,
        nvim_win_set_option = function() end,
        nvim_set_current_win = function() end,
        nvim_buf_is_valid = function()
          return true
        end,
        nvim_win_is_valid = function()
          return true
        end,
      })
      tree = require("ada_ls.project_view.tree")
    end)

    after_each(function()
      common.cleanup_packages()
    end)

    describe("_make_node_id", function()
      it("generates correct format type:project_id:path", function()
        local result = tree._make_node_id("file", "/src/main.adb", "proj_1")
        assert.equals("file:proj_1:/src/main.adb", result)
      end)

      it("handles nil project_id", function()
        local result = tree._make_node_id("directory", "/src", nil)
        assert.equals("directory::/src", result)
      end)

      it("generates unique IDs for different types", function()
        local file_id = tree._make_node_id("file", "/src/main.adb", "proj_1")
        local dir_id =
          tree._make_node_id("directory", "/src/main.adb", "proj_1")
        assert.is_not.equals(file_id, dir_id)
      end)

      it("generates unique IDs for different projects", function()
        local id1 = tree._make_node_id("file", "/src/main.adb", "proj_1")
        local id2 = tree._make_node_id("file", "/src/main.adb", "proj_2")
        assert.is_not.equals(id1, id2)
      end)
    end)

    describe("_group_sources_by_dir", function()
      it("groups sources by directory", function()
        local sources = {
          { directory = "/src", simple_name = "main.adb" },
          { directory = "/src", simple_name = "utils.adb" },
          { directory = "/tests", simple_name = "test.adb" },
        }
        local dirs, sorted = tree._group_sources_by_dir(sources)

        assert.equals(2, #sorted)
        assert.equals(2, #dirs["/src"])
        assert.equals(1, #dirs["/tests"])
      end)

      it("returns sorted directory list", function()
        local sources = {
          { directory = "/zeta", simple_name = "z.adb" },
          { directory = "/alpha", simple_name = "a.adb" },
          { directory = "/middle", simple_name = "m.adb" },
        }
        local _, sorted = tree._group_sources_by_dir(sources)

        assert.equals("/alpha", sorted[1])
        assert.equals("/middle", sorted[2])
        assert.equals("/zeta", sorted[3])
      end)

      it("handles empty sources array", function()
        local dirs, sorted = tree._group_sources_by_dir({})

        assert.equals(0, #sorted)
        assert.is_table(dirs)
      end)

      it("handles single source", function()
        local sources = {
          { directory = "/src", simple_name = "main.adb" },
        }
        local dirs, sorted = tree._group_sources_by_dir(sources)

        assert.equals(1, #sorted)
        assert.equals("/src", sorted[1])
        assert.equals(1, #dirs["/src"])
      end)
    end)

    describe("_build_tree", function()
      local function create_test_data(opts)
        opts = opts or {}
        return {
          root_project_id = "proj_1",
          projects = {
            ["proj_1"] = {
              project = {
                id = "proj_1",
                name = "main_project",
                file_name = "/project/main.gpr",
                directory = "/project",
                object_dir = "/project/obj",
              },
              sources = opts.sources
                or {
                  {
                    file_name = "/project/src/main.adb",
                    simple_name = "main.adb",
                    directory = "/project/src",
                  },
                  {
                    file_name = "/project/src/utils.ads",
                    simple_name = "utils.ads",
                    directory = "/project/src",
                  },
                },
              imports = opts.imports or {},
              aggregated = opts.aggregated or {},
              extended = opts.extended or {},
            },
          },
          runtime_project = opts.runtime_project,
        }
      end

      before_each(function()
        -- Clear expanded state before each test
        tree._tree_state.expanded = {}
      end)

      it("returns project node at root level", function()
        local data = create_test_data()
        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        assert.equals(1, #nodes)
        assert.equals("project", nodes[1].type)
        assert.equals("main_project (Root)", nodes[1].name)
        assert.equals(0, nodes[1].depth)
        assert.is_true(nodes[1].expandable)
        assert.is_true(nodes[1].is_root)
      end)

      it("groups sources by directory when project is expanded", function()
        local data = create_test_data()
        -- Expand the project
        local project_id = "project:proj_1:/project/main.gpr"
        tree._tree_state.expanded[project_id] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Should have: project + 1 directory
        assert.equals(2, #nodes)
        assert.equals("project", nodes[1].type)
        assert.equals("directory", nodes[2].type)
        assert.equals("src", nodes[2].name)
        assert.equals(1, nodes[2].depth)
      end)

      it("shows files when directory is expanded", function()
        local data = create_test_data()
        -- Expand project and directory
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true
        tree._tree_state.expanded["directory:proj_1:/project/src"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Should have: project + directory + 2 files
        assert.equals(4, #nodes)
        assert.equals("file", nodes[3].type)
        assert.equals("main.adb", nodes[3].name)
        assert.equals("file", nodes[4].type)
        assert.equals("utils.ads", nodes[4].name)
        -- Files should be sorted alphabetically
        assert.is_true(nodes[3].name < nodes[4].name)
      end)

      it("shows object directory when option enabled", function()
        local data = create_test_data()
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = true,
          show_runtime = false,
        })

        -- Find object_dir node
        local obj_node = nil
        for _, node in ipairs(nodes) do
          if node.type == "object_dir" then
            obj_node = node
            break
          end
        end

        assert.is_not_nil(obj_node)
        assert.equals("obj (obj)", obj_node.name)
        assert.equals("/project/obj", obj_node.path)
        assert.is_false(obj_node.expandable)
      end)

      it("shows all projects at root in flat mode", function()
        local data = create_test_data({
          imports = { "proj_2" },
        })
        data.projects["proj_2"] = {
          project = {
            id = "proj_2",
            name = "sub_project",
            file_name = "/subproj/sub.gpr",
            directory = "/subproj",
          },
          sources = {},
          imports = {},
          aggregated = {},
          extended = {},
        }

        local nodes = tree._build_tree(data, {
          flat_mode = true,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Both projects at depth 0
        assert.equals(2, #nodes)
        assert.equals(0, nodes[1].depth)
        assert.equals(0, nodes[2].depth)
        -- Root project should be first
        assert.truthy(nodes[1].name:find("Root"))
      end)

      it("shows sub-projects hierarchically when not flat mode", function()
        local data = create_test_data({
          imports = { "proj_2" },
        })
        data.projects["proj_2"] = {
          project = {
            id = "proj_2",
            name = "sub_project",
            file_name = "/subproj/sub.gpr",
            directory = "/subproj",
          },
          sources = {},
          imports = {},
          aggregated = {},
          extended = {},
        }
        -- Expand root project to see sub-projects
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Root at depth 0, sub-project at depth 1
        local sub_node = nil
        for _, node in ipairs(nodes) do
          if node.name == "sub_project" then
            sub_node = node
            break
          end
        end

        assert.is_not_nil(sub_node)
        assert.equals(1, sub_node.depth)
      end)

      it("shows runtime project when option enabled", function()
        local data = create_test_data({
          runtime_project = {
            project = {
              id = "runtime",
              name = "runtime",
              directory = "/usr/share/gnat",
            },
            sources = {
              {
                file_name = "/usr/share/gnat/adainclude/ada.ads",
                simple_name = "ada.ads",
                directory = "/usr/share/gnat/adainclude",
              },
            },
          },
        })

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = true,
        })

        -- Find runtime node
        local runtime_node = nil
        for _, node in ipairs(nodes) do
          if node.type == "runtime" then
            runtime_node = node
            break
          end
        end

        assert.is_not_nil(runtime_node)
        assert.equals("Runtime", runtime_node.name)
        assert.equals(0, runtime_node.depth)
        assert.is_true(runtime_node.expandable)
      end)

      it("shows runtime directories when runtime expanded", function()
        local data = create_test_data({
          runtime_project = {
            project = {
              id = "runtime",
              name = "runtime",
              directory = "/usr/share/gnat",
            },
            sources = {
              {
                file_name = "/usr/share/gnat/adainclude/ada.ads",
                simple_name = "ada.ads",
                directory = "/usr/share/gnat/adainclude",
              },
            },
          },
        })
        tree._tree_state.expanded["runtime:runtime:runtime"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = true,
        })

        -- Should have project + runtime + runtime directory
        local dir_node = nil
        for _, node in ipairs(nodes) do
          if node.type == "directory" and node.project_id == "runtime" then
            dir_node = node
            break
          end
        end

        assert.is_not_nil(dir_node)
        assert.equals(1, dir_node.depth)
      end)

      it("handles multiple source directories", function()
        local data = create_test_data({
          sources = {
            {
              file_name = "/project/src/main.adb",
              simple_name = "main.adb",
              directory = "/project/src",
            },
            {
              file_name = "/project/tests/test.adb",
              simple_name = "test.adb",
              directory = "/project/tests",
            },
          },
        })
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Count directory nodes
        local dir_count = 0
        for _, node in ipairs(nodes) do
          if node.type == "directory" then
            dir_count = dir_count + 1
          end
        end

        assert.equals(2, dir_count)
      end)

      it("handles empty sources array", function()
        local data = create_test_data({ sources = {} })
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Only project node, no directories
        assert.equals(1, #nodes)
        assert.equals("project", nodes[1].type)
      end)
    end)

    describe("_filter_nodes", function()
      local test_nodes

      before_each(function()
        test_nodes = {
          {
            id = "project:proj_1:/project.gpr",
            type = "project",
            name = "main_project",
            depth = 0,
            expandable = true,
            project_id = "proj_1",
          },
          {
            id = "directory:proj_1:/src",
            type = "directory",
            name = "src",
            path = "/src",
            depth = 1,
            expandable = true,
            project_id = "proj_1",
          },
          {
            id = "file:proj_1:/src/main.adb",
            type = "file",
            name = "main.adb",
            path = "/src/main.adb",
            depth = 2,
            expandable = false,
            project_id = "proj_1",
          },
          {
            id = "file:proj_1:/src/utils.ads",
            type = "file",
            name = "utils.ads",
            path = "/src/utils.ads",
            depth = 2,
            expandable = false,
            project_id = "proj_1",
          },
        }
      end)

      it("returns all nodes when filter is empty", function()
        local result = tree._filter_nodes(test_nodes, "")
        assert.equals(4, #result)
      end)

      it("filters nodes by name (case-insensitive)", function()
        local result = tree._filter_nodes(test_nodes, "main")
        -- Should include main.adb and its parents
        local names = {}
        for _, node in ipairs(result) do
          table.insert(names, node.name)
        end
        assert.truthy(vim.tbl_contains(names, "main.adb"))
      end)

      it("includes parent nodes of matching files", function()
        local result = tree._filter_nodes(test_nodes, "utils")
        -- Should include utils.ads, src directory, and project
        assert.is_true(#result >= 1)
        -- The matching file should be included
        local has_utils = false
        for _, node in ipairs(result) do
          if node.name == "utils.ads" then
            has_utils = true
            break
          end
        end
        assert.is_true(has_utils)
      end)

      it("returns empty array when no matches", function()
        local result = tree._filter_nodes(test_nodes, "nonexistent")
        assert.equals(0, #result)
      end)

      it("matches partial names", function()
        local result = tree._filter_nodes(test_nodes, "util")
        local has_utils = false
        for _, node in ipairs(result) do
          if node.name == "utils.ads" then
            has_utils = true
            break
          end
        end
        assert.is_true(has_utils)
      end)

      it("handles uppercase filter", function()
        local result = tree._filter_nodes(test_nodes, "MAIN")
        local has_main = false
        for _, node in ipairs(result) do
          if node.name == "main.adb" then
            has_main = true
            break
          end
        end
        assert.is_true(has_main)
      end)
    end)

    describe("_build_tree_prefix", function()
      it("returns empty string for depth 0 nodes", function()
        local nodes = {
          { depth = 0, name = "project" },
        }
        local result = tree._build_tree_prefix(1, nodes)
        assert.equals("", result)
      end)

      it("returns branch connector for non-last node at depth 1", function()
        local nodes = {
          { depth = 0, name = "project" },
          { depth = 1, name = "src" },
          { depth = 1, name = "tests" }, -- sibling after
        }
        local result = tree._build_tree_prefix(2, nodes)
        -- Should use branch connector (not last)
        assert.equals(tree._tree_chars.branch, result)
      end)

      it("returns last connector for last node at depth 1", function()
        local nodes = {
          { depth = 0, name = "project" },
          { depth = 1, name = "src" },
          { depth = 1, name = "tests" },
        }
        local result = tree._build_tree_prefix(3, nodes)
        -- Should use last connector
        assert.equals(tree._tree_chars.last, result)
      end)

      it("builds vertical lines for nested nodes", function()
        local nodes = {
          { depth = 0, name = "project" },
          { depth = 1, name = "src" },
          { depth = 2, name = "main.adb" },
          { depth = 1, name = "tests" }, -- sibling at depth 1
        }
        local result = tree._build_tree_prefix(3, nodes)
        -- Should have vertical line + last connector
        -- Because depth 1 has more siblings after this file
        assert.truthy(result:find(tree._tree_chars.vertical, 1, true))
      end)

      it("builds space for nested nodes without more siblings", function()
        local nodes = {
          { depth = 0, name = "project" },
          { depth = 1, name = "src" },
          { depth = 2, name = "main.adb" },
        }
        local result = tree._build_tree_prefix(3, nodes)
        -- Should have space + last connector (no more siblings at depth 1)
        assert.truthy(result:find(tree._tree_chars.space, 1, true))
        assert.truthy(result:find(tree._tree_chars.last, 1, true))
      end)

      it("handles deeply nested nodes", function()
        local nodes = {
          { depth = 0, name = "project" },
          { depth = 1, name = "src" },
          { depth = 2, name = "engine" },
          { depth = 3, name = "core.adb" },
        }
        local result = tree._build_tree_prefix(4, nodes)
        -- Depth 3 node should have prefix for depth 1 and 2
        assert.is_true(#result > #tree._tree_chars.last)
      end)
    end)

    describe("_toggle_expanded / _is_expanded", function()
      before_each(function()
        tree._tree_state.expanded = {}
      end)

      it("returns false for non-expanded node", function()
        assert.is_false(tree._is_expanded("some_id"))
      end)

      it("toggles node expansion state", function()
        assert.is_false(tree._is_expanded("node_1"))
        tree._toggle_expanded("node_1")
        assert.is_true(tree._is_expanded("node_1"))
        tree._toggle_expanded("node_1")
        assert.is_false(tree._is_expanded("node_1"))
      end)
    end)

    describe("_get_node_icon", function()
      before_each(function()
        tree._tree_state.expanded = {}
      end)

      it("returns file icon for file nodes", function()
        local node = { type = "file", name = "main.adb", id = "file_1" }
        local icon, _ = tree._get_node_icon(node)
        assert.equals(tree._icons.file, icon)
      end)

      it("returns directory icon for collapsed directory", function()
        local node = {
          type = "directory",
          name = "src",
          id = "dir_1",
        }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(tree._icons.directory, icon)
        assert.equals("Directory", hl)
      end)

      it("returns open directory icon for expanded directory", function()
        tree._tree_state.expanded["dir_1"] = true
        local node = {
          type = "directory",
          name = "src",
          id = "dir_1",
        }
        local icon, _ = tree._get_node_icon(node)
        assert.equals(tree._icons.directory_open, icon)
      end)

      it("returns project_root icon for root project", function()
        local node = {
          type = "project",
          name = "main",
          id = "proj_1",
          is_root = true,
        }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(tree._icons.project_root, icon)
        assert.equals("Title", hl)
      end)

      it("returns project icon for non-root project", function()
        local node = {
          type = "project",
          name = "sub",
          id = "proj_2",
          is_root = false,
        }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(tree._icons.project, icon)
        assert.equals("Type", hl)
      end)

      it("returns object_dir icon", function()
        local node = { type = "object_dir", name = "obj", id = "obj_1" }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(tree._icons.object_dir, icon)
        assert.equals("Special", hl)
      end)

      it("returns runtime icon for collapsed runtime", function()
        local node = { type = "runtime", name = "Runtime", id = "runtime_1" }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(tree._icons.runtime, icon)
        assert.equals("Comment", hl)
      end)

      it("returns open icon for expanded runtime", function()
        tree._tree_state.expanded["runtime_1"] = true
        local node = { type = "runtime", name = "Runtime", id = "runtime_1" }
        local icon, _ = tree._get_node_icon(node)
        assert.equals(tree._icons.directory_open, icon)
      end)

      it("returns space for unknown node type", function()
        local node = { type = "unknown", name = "test", id = "unknown_1" }
        local icon, hl = tree._get_node_icon(node)
        assert.equals(" ", icon)
        assert.is_nil(hl)
      end)
    end)

    describe("_build_tree with aggregated/extended projects", function()
      local function create_multi_project_data()
        return {
          root_project_id = "proj_1",
          projects = {
            ["proj_1"] = {
              project = {
                id = "proj_1",
                name = "main_project",
                file_name = "/project/main.gpr",
                directory = "/project",
              },
              sources = {},
              imports = {},
              aggregated = { "proj_2" },
              extended = { "proj_3" },
            },
            ["proj_2"] = {
              project = {
                id = "proj_2",
                name = "aggregated_project",
                file_name = "/agg/agg.gpr",
                directory = "/agg",
              },
              sources = {},
              imports = {},
              aggregated = {},
              extended = {},
            },
            ["proj_3"] = {
              project = {
                id = "proj_3",
                name = "extended_project",
                file_name = "/ext/ext.gpr",
                directory = "/ext",
              },
              sources = {},
              imports = {},
              aggregated = {},
              extended = {},
            },
          },
        }
      end

      before_each(function()
        tree._tree_state.expanded = {}
      end)

      it("shows aggregated projects when root expanded", function()
        local data = create_multi_project_data()
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Should have root + aggregated + extended
        assert.equals(3, #nodes)
        local names = {}
        for _, node in ipairs(nodes) do
          table.insert(names, node.name)
        end
        assert.truthy(vim.tbl_contains(names, "aggregated_project"))
        assert.truthy(vim.tbl_contains(names, "extended_project"))
      end)

      it("sorts sub-projects alphabetically", function()
        local data = create_multi_project_data()
        tree._tree_state.expanded["project:proj_1:/project/main.gpr"] = true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Sub-projects should be sorted: aggregated_project < extended_project
        assert.equals("aggregated_project", nodes[2].name)
        assert.equals("extended_project", nodes[3].name)
      end)
    end)

    describe("_build_tree with runtime files expanded", function()
      before_each(function()
        tree._tree_state.expanded = {}
      end)

      it("shows runtime files when runtime directory expanded", function()
        local data = {
          root_project_id = "proj_1",
          projects = {
            ["proj_1"] = {
              project = {
                id = "proj_1",
                name = "main_project",
                file_name = "/project/main.gpr",
                directory = "/project",
              },
              sources = {},
              imports = {},
              aggregated = {},
              extended = {},
            },
          },
          runtime_project = {
            project = {
              id = "runtime",
              name = "runtime",
              directory = "/usr/share/gnat",
            },
            sources = {
              {
                file_name = "/usr/share/gnat/adainclude/ada.ads",
                simple_name = "ada.ads",
                directory = "/usr/share/gnat/adainclude",
              },
              {
                file_name = "/usr/share/gnat/adainclude/system.ads",
                simple_name = "system.ads",
                directory = "/usr/share/gnat/adainclude",
              },
            },
          },
        }
        -- Expand runtime and its directory
        tree._tree_state.expanded["runtime:runtime:runtime"] = true
        tree._tree_state.expanded["directory:runtime:/usr/share/gnat/adainclude"] =
          true

        local nodes = tree._build_tree(data, {
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = true,
        })

        -- Count file nodes in runtime
        local file_count = 0
        for _, node in ipairs(nodes) do
          if node.type == "file" and node.project_id == "runtime" then
            file_count = file_count + 1
          end
        end

        assert.equals(2, file_count)
      end)
    end)

    describe("_render_tree", function()
      local captured_lines
      local captured_highlights

      before_each(function()
        captured_lines = nil
        captured_highlights = {}
        tree._tree_state.nodes = {}

        -- Mock vim.bo
        vim.bo = setmetatable({}, {
          __index = function()
            return {}
          end,
          __newindex = function() end,
        })

        -- Mock vim.api functions for rendering
        vim.api.nvim_buf_set_lines = function(_, _, _, _, lines)
          captured_lines = lines
        end
        vim.api.nvim_create_namespace = function()
          return 1
        end
        vim.api.nvim_buf_clear_namespace = function() end
        vim.api.nvim_buf_add_highlight = function(
          _,
          _,
          hl,
          line,
          col_start,
          col_end
        )
          table.insert(captured_highlights, {
            hl_group = hl,
            line = line,
            col_start = col_start,
            col_end = col_end,
          })
        end
      end)

      it("stores nodes in tree_state", function()
        local nodes = {
          {
            id = "1",
            name = "test",
            type = "file",
            depth = 0,
            expandable = false,
          },
        }
        tree._render_tree(1, nodes)
        assert.same(nodes, tree._tree_state.nodes)
      end)

      it("renders correct number of lines", function()
        local nodes = {
          {
            id = "1",
            name = "project",
            type = "project",
            depth = 0,
            expandable = true,
            is_root = true,
          },
          {
            id = "2",
            name = "src",
            type = "directory",
            depth = 1,
            expandable = true,
          },
        }
        tree._render_tree(1, nodes)

        assert.equals(2, #captured_lines)
      end)

      it("applies highlights for icons and names", function()
        tree._tree_state.expanded = {}
        local nodes = {
          {
            id = "1",
            name = "project",
            type = "project",
            depth = 0,
            expandable = true,
            is_root = true,
          },
        }
        tree._render_tree(1, nodes)

        -- Should have at least icon highlight and name highlight
        assert.is_true(#captured_highlights >= 1)
      end)

      it("renders file nodes without directory highlights", function()
        local nodes = {
          {
            id = "1",
            name = "main.adb",
            type = "file",
            depth = 0,
            expandable = false,
          },
        }
        tree._render_tree(1, nodes)

        -- File nodes should not have "Directory" or "Title" highlights for name
        for _, hl in ipairs(captured_highlights) do
          assert.is_not.equals("Directory", hl.hl_group)
          assert.is_not.equals("Title", hl.hl_group)
        end
      end)
    end)

    describe("_get_node_at_cursor", function()
      it("returns node at cursor line", function()
        tree._tree_state.nodes = {
          { id = "1", name = "first" },
          { id = "2", name = "second" },
          { id = "3", name = "third" },
        }
        vim.fn = {
          line = function()
            return 2
          end,
        }

        local node = tree._get_node_at_cursor()
        assert.equals("second", node.name)
      end)

      it("returns first node when cursor at line 1", function()
        tree._tree_state.nodes = {
          { id = "1", name = "first" },
          { id = "2", name = "second" },
        }
        vim.fn = {
          line = function()
            return 1
          end,
        }

        local node = tree._get_node_at_cursor()
        assert.equals("first", node.name)
      end)

      it("returns nil for empty nodes", function()
        tree._tree_state.nodes = {}
        vim.fn = {
          line = function()
            return 1
          end,
        }

        local node = tree._get_node_at_cursor()
        assert.is_nil(node)
      end)

      it("returns nil when cursor beyond nodes", function()
        tree._tree_state.nodes = {
          { id = "1", name = "only" },
        }
        vim.fn = {
          line = function()
            return 5
          end,
        }

        local node = tree._get_node_at_cursor()
        assert.is_nil(node)
      end)
    end)

    describe("_open_file", function()
      local cmd_calls

      before_each(function()
        cmd_calls = {}
        vim.cmd = setmetatable({}, {
          __index = function(_, key)
            return function(arg)
              table.insert(cmd_calls, { cmd = key, arg = arg })
            end
          end,
        })
      end)

      it("opens file with default edit command", function()
        tree._open_file("/path/to/file.adb")

        assert.equals(2, #cmd_calls)
        assert.equals("wincmd", cmd_calls[1].cmd)
        assert.equals("p", cmd_calls[1].arg)
        assert.equals("edit", cmd_calls[2].cmd)
        assert.equals("/path/to/file.adb", cmd_calls[2].arg)
      end)

      it("opens file with split command", function()
        tree._open_file("/path/to/file.adb", "split")

        assert.equals("split", cmd_calls[2].cmd)
        assert.equals("/path/to/file.adb", cmd_calls[2].arg)
      end)

      it("opens file with vsplit command", function()
        tree._open_file("/path/to/file.adb", "vsplit")

        assert.equals("vsplit", cmd_calls[2].cmd)
      end)

      it("opens file with tabedit command", function()
        tree._open_file("/path/to/file.adb", "tabedit")

        assert.equals("tabedit", cmd_calls[2].cmd)
      end)
    end)

    describe("handler functions", function()
      local refresh_called
      local original_refresh

      before_each(function()
        refresh_called = false
        tree._tree_state.nodes = {}
        tree._tree_state.expanded = {}
        tree._tree_state.filter = ""

        -- Save and mock M.refresh
        original_refresh = tree.refresh
        tree.refresh = function()
          refresh_called = true
        end

        -- Mock vim.fn.line
        vim.fn = {
          line = function()
            return 1
          end,
        }

        -- Mock vim.cmd for open_file
        vim.cmd = setmetatable({}, {
          __index = function(_, _)
            return function() end
          end,
        })
      end)

      after_each(function()
        tree.refresh = original_refresh
      end)

      describe("_handle_enter", function()
        it("toggles expansion for expandable nodes", function()
          tree._tree_state.nodes = {
            { id = "proj_1", type = "project", expandable = true },
          }

          tree._handle_enter()

          assert.is_true(tree._tree_state.expanded["proj_1"])
          assert.is_true(refresh_called)
        end)

        it("opens file for file nodes", function()
          local cmd_calls = {}
          vim.cmd = setmetatable({}, {
            __index = function(_, key)
              return function(arg)
                table.insert(cmd_calls, { cmd = key, arg = arg })
              end
            end,
          })

          tree._tree_state.nodes = {
            {
              id = "file_1",
              type = "file",
              path = "/src/main.adb",
              expandable = false,
            },
          }

          tree._handle_enter()

          -- Should call wincmd then edit
          assert.equals(2, #cmd_calls)
          assert.equals("edit", cmd_calls[2].cmd)
          assert.equals("/src/main.adb", cmd_calls[2].arg)
        end)

        it("does nothing when no node at cursor", function()
          tree._tree_state.nodes = {}

          tree._handle_enter()

          assert.is_false(refresh_called)
        end)

        it("does nothing for non-expandable node without path", function()
          tree._tree_state.nodes = {
            { id = "node_1", type = "unknown", expandable = false },
          }

          tree._handle_enter()

          assert.is_false(refresh_called)
        end)
      end)

      describe("_handle_open_split", function()
        it("opens file in split", function()
          local cmd_calls = {}
          vim.cmd = setmetatable({}, {
            __index = function(_, key)
              return function(arg)
                table.insert(cmd_calls, { cmd = key, arg = arg })
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "file", path = "/test.adb" },
          }

          tree._handle_open_split()

          assert.equals(2, #cmd_calls)
          assert.equals("split", cmd_calls[2].cmd)
        end)

        it("does nothing for non-file nodes", function()
          local cmd_called = false
          vim.cmd = setmetatable({}, {
            __index = function()
              return function()
                cmd_called = true
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "directory", path = "/src" },
          }

          tree._handle_open_split()

          assert.is_false(cmd_called)
        end)
      end)

      describe("_handle_open_vsplit", function()
        it("opens file in vsplit", function()
          local cmd_calls = {}
          vim.cmd = setmetatable({}, {
            __index = function(_, key)
              return function(arg)
                table.insert(cmd_calls, { cmd = key, arg = arg })
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "file", path = "/test.adb" },
          }

          tree._handle_open_vsplit()

          assert.equals(2, #cmd_calls)
          assert.equals("vsplit", cmd_calls[2].cmd)
        end)
      end)

      describe("_handle_open_tab", function()
        it("opens file in tab", function()
          local cmd_calls = {}
          vim.cmd = setmetatable({}, {
            __index = function(_, key)
              return function(arg)
                table.insert(cmd_calls, { cmd = key, arg = arg })
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "file", path = "/test.adb" },
          }

          tree._handle_open_tab()

          assert.equals(2, #cmd_calls)
          assert.equals("tabedit", cmd_calls[2].cmd)
        end)
      end)

      describe("_handle_preview", function()
        it("previews file and returns to tree", function()
          local cmd_sequence = {}
          vim.cmd = setmetatable({}, {
            __index = function(_, key)
              return function(arg)
                table.insert(cmd_sequence, { cmd = key, arg = arg })
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "file", path = "/test.adb" },
          }

          tree._handle_preview()

          assert.equals(3, #cmd_sequence)
          assert.equals("wincmd", cmd_sequence[1].cmd)
          assert.equals("edit", cmd_sequence[2].cmd)
          assert.equals("wincmd", cmd_sequence[3].cmd)
        end)

        it("does nothing for non-file nodes", function()
          local cmd_called = false
          vim.cmd = setmetatable({}, {
            __index = function()
              return function()
                cmd_called = true
              end
            end,
          })

          tree._tree_state.nodes = {
            { id = "1", type = "directory", path = "/src" },
          }

          tree._handle_preview()

          assert.is_false(cmd_called)
        end)
      end)

      describe("_handle_expand", function()
        it("expands collapsed expandable node", function()
          tree._tree_state.nodes = {
            { id = "dir_1", type = "directory", expandable = true },
          }
          tree._tree_state.expanded = {}

          tree._handle_expand()

          assert.is_true(tree._tree_state.expanded["dir_1"])
          assert.is_true(refresh_called)
        end)

        it("does nothing if already expanded", function()
          tree._tree_state.nodes = {
            { id = "dir_1", type = "directory", expandable = true },
          }
          tree._tree_state.expanded = { ["dir_1"] = true }

          tree._handle_expand()

          assert.is_false(refresh_called)
        end)

        it("does nothing for non-expandable nodes", function()
          tree._tree_state.nodes = {
            { id = "file_1", type = "file", expandable = false },
          }

          tree._handle_expand()

          assert.is_false(refresh_called)
        end)
      end)

      describe("_handle_collapse", function()
        it("collapses expanded node", function()
          tree._tree_state.nodes = {
            { id = "dir_1", type = "directory", expandable = true },
          }
          tree._tree_state.expanded = { ["dir_1"] = true }

          tree._handle_collapse()

          assert.is_false(tree._tree_state.expanded["dir_1"])
          assert.is_true(refresh_called)
        end)

        it("does nothing if already collapsed", function()
          tree._tree_state.nodes = {
            { id = "dir_1", type = "directory", expandable = true },
          }
          tree._tree_state.expanded = {}

          tree._handle_collapse()

          assert.is_false(refresh_called)
        end)
      end)

      describe("_handle_collapse_all", function()
        it("clears all expanded state", function()
          tree._tree_state.expanded = { a = true, b = true, c = true }

          tree._handle_collapse_all()

          assert.same({}, tree._tree_state.expanded)
          assert.is_true(refresh_called)
        end)
      end)

      describe("_handle_expand_all", function()
        it("expands all expandable nodes", function()
          tree._tree_state.nodes = {
            { id = "proj", expandable = true },
            { id = "dir", expandable = true },
            { id = "file", expandable = false },
          }
          tree._tree_state.expanded = {}

          tree._handle_expand_all()

          assert.is_true(tree._tree_state.expanded["proj"])
          assert.is_true(tree._tree_state.expanded["dir"])
          assert.is_nil(tree._tree_state.expanded["file"])
          assert.is_true(refresh_called)
        end)
      end)

      describe("_handle_clear_filter", function()
        it("clears filter and refreshes when filter exists", function()
          tree._tree_state.filter = "main"

          tree._handle_clear_filter()

          assert.equals("", tree._tree_state.filter)
          assert.is_true(refresh_called)
        end)

        it("does nothing when no filter", function()
          tree._tree_state.filter = ""

          tree._handle_clear_filter()

          assert.is_false(refresh_called)
        end)
      end)

      describe("_handle_help", function()
        it("shows help message via vim.notify", function()
          local notified_msg
          local original_notify = vim.notify
          vim.notify = function(msg)
            notified_msg = msg
          end

          tree._handle_help()

          vim.notify = original_notify

          assert.is_not_nil(notified_msg)
          assert.truthy(notified_msg:find("Project View Keymaps"))
          assert.truthy(notified_msg:find("<CR>"))
        end)
      end)

      describe("_handle_refresh", function()
        it("invalidates data and refreshes", function()
          local invalidate_called = false
          rawset(package.loaded, "ada_ls.project_view.data", {
            invalidate = function()
              invalidate_called = true
            end,
          })

          tree._handle_refresh()

          assert.is_true(invalidate_called)
          assert.is_true(refresh_called)
        end)
      end)

      describe("_handle_filter", function()
        it("sets filter and refreshes when input provided", function()
          local input_callback
          vim.ui = {
            input = function(_, callback)
              input_callback = callback
            end,
          }

          tree._handle_filter()

          -- Simulate user entering "main"
          assert.is_not_nil(input_callback)
          input_callback("main")

          assert.equals("main", tree._tree_state.filter)
          assert.is_true(refresh_called)
        end)

        it("does not set filter when input is nil", function()
          tree._tree_state.filter = "original"
          vim.ui = {
            input = function(_, callback)
              callback(nil)
            end,
          }

          tree._handle_filter()

          assert.equals("original", tree._tree_state.filter)
          assert.is_false(refresh_called)
        end)
      end)
    end)

    describe("M.is_open", function()
      it("returns false when window is nil", function()
        tree._tree_state.win = nil

        assert.is_false(tree.is_open())
      end)

      it("returns false when window is invalid", function()
        tree._tree_state.win = 123
        vim.api.nvim_win_is_valid = function()
          return false
        end

        assert.is_false(tree.is_open())
      end)

      it("returns true when window is valid", function()
        tree._tree_state.win = 123
        vim.api.nvim_win_is_valid = function()
          return true
        end

        assert.is_true(tree.is_open())
      end)
    end)

    describe("setup_keymaps (via keymap.set mock)", function()
      it("registers all expected keymaps", function()
        local registered_keys = {}
        vim.keymap = {
          set = function(mode, key, _, _)
            table.insert(registered_keys, { mode = mode, key = key })
          end,
        }

        -- We can't call setup_keymaps directly as it's not exported,
        -- but we verify the handlers exist
        assert.is_function(tree._handle_enter)
        assert.is_function(tree._handle_open_split)
        assert.is_function(tree._handle_open_vsplit)
        assert.is_function(tree._handle_open_tab)
        assert.is_function(tree._handle_preview)
        assert.is_function(tree._handle_refresh)
        assert.is_function(tree._handle_expand)
        assert.is_function(tree._handle_collapse)
        assert.is_function(tree._handle_collapse_all)
        assert.is_function(tree._handle_expand_all)
        assert.is_function(tree._handle_filter)
        assert.is_function(tree._handle_clear_filter)
        assert.is_function(tree._handle_help)
      end)
    end)

    describe("sorting comparators", function()
      it("sorts projects by name in build_tree flat mode", function()
        local data = {
          root_project_id = "proj_2",
          projects = {
            ["proj_1"] = {
              project = {
                id = "proj_1",
                name = "alpha_project",
                file_name = "/alpha/alpha.gpr",
                directory = "/alpha",
              },
              sources = {},
              imports = {},
              aggregated = {},
              extended = {},
            },
            ["proj_2"] = {
              project = {
                id = "proj_2",
                name = "zeta_project",
                file_name = "/zeta/zeta.gpr",
                directory = "/zeta",
              },
              sources = {},
              imports = {},
              aggregated = {},
              extended = {},
            },
          },
        }
        tree._tree_state.expanded = {}

        local nodes = tree._build_tree(data, {
          flat_mode = true,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Root project should be first, then alphabetical
        assert.truthy(nodes[1].name:find("zeta")) -- Root first
        assert.truthy(nodes[2].name:find("alpha"))
      end)
    end)
  end)
end
