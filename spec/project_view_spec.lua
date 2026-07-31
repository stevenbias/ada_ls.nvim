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
      assert.is_false(project_view.get_option("invalid_key"))
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

    describe("_get_relative_path", function()
      it("returns relative path when inside base directory", function()
        local result = tree._get_relative_path("/project/src", "/project")
        assert.equals("src", result)
      end)

      it("returns nested relative path", function()
        local result =
          tree._get_relative_path("/project/src/engine", "/project")
        assert.equals("src/engine", result)
      end)

      it("returns '.' when path equals base directory", function()
        local result = tree._get_relative_path("/project", "/project")
        assert.equals(".", result)
      end)

      it("returns basename when path is outside base directory", function()
        local result =
          tree._get_relative_path("/usr/share/gnat/adalib", "/project")
        assert.equals("adalib", result)
      end)

      it("handles trailing slashes in path", function()
        local result = tree._get_relative_path("/project/src/", "/project")
        assert.equals("src", result)
      end)

      it("handles trailing slashes in base directory", function()
        local result = tree._get_relative_path("/project/src", "/project/")
        assert.equals("src", result)
      end)

      it("handles empty path", function()
        local result = tree._get_relative_path("", "/project")
        assert.equals("", result)
      end)

      it("handles empty base directory", function()
        local result = tree._get_relative_path("/project/src", "")
        assert.equals("src", result)
      end)

      it("handles nil values", function()
        local result = tree._get_relative_path(nil, "/project")
        assert.equals("", result)
      end)
    end)
  end)
end
