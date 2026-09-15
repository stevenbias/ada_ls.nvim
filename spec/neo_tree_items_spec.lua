-- Tests for lua/ada_ls/project_view/neo_tree/items.lua
local common = require("spec.helpers.common")

describe("ada_ls.project_view.neo_tree.items", function()
  local items

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

  describe("get_items", function()
    local object_dir_cleanup = nil

    after_each(function()
      if object_dir_cleanup then
        object_dir_cleanup()
        object_dir_cleanup = nil
      end
    end)

    it("returns error when ALS not supported", function()
      common.setup_lsp_cmd_project_view_mock(nil, "Unknown command")
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items, result_err
      items.get_items({}, function(i, e)
        result_items = i
        result_err = e
      end)

      assert.is_table(result_items)
      assert.equals(0, #result_items)
      assert.is_string(result_err)
    end)

    it("returns items when ALS is supported", function()
      local response = common.create_project_view_response()
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items, result_err
      items.get_items({}, function(i, e)
        result_items = i
        result_err = e
      end)

      assert.is_nil(result_err)
      assert.is_table(result_items)
      assert.is_true(#result_items > 0)
    end)

    it("returns project nodes with correct structure", function()
      local response = common.create_project_view_response({
        root_name = "test_project",
      })
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items
      items.get_items({}, function(i)
        result_items = i
      end)

      assert.equals(1, #result_items)
      local project_node = result_items[1]
      assert.equals("project", project_node.type)
      assert.truthy(project_node.name:find("test_project"))
      assert.truthy(project_node.name:find("Root"))
      assert.is_table(project_node.children)
      assert.is_string(project_node.id)
    end)

    it("creates directory nodes with file children", function()
      local response = common.create_project_view_response()
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items
      items.get_items({}, function(i)
        result_items = i
      end)

      -- Find a directory node
      local project_node = result_items[1]
      assert.is_table(project_node.children)
      assert.is_true(#project_node.children > 0)

      local dir_node = project_node.children[1]
      assert.equals("directory", dir_node.type)
      assert.is_table(dir_node.children)
    end)

    it("includes runtime project when show_runtime is true", function()
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
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items
      items.get_items({ show_runtime = true }, function(i)
        result_items = i
      end)

      -- Should have main project + runtime
      assert.equals(2, #result_items)

      -- Find runtime node
      local runtime_node = nil
      for _, node in ipairs(result_items) do
        if node.extra and node.extra.is_runtime then
          runtime_node = node
          break
        end
      end
      assert.is_not_nil(runtime_node)
      assert.equals("Runtime", runtime_node.name)
    end)

    it("respects flat_mode option", function()
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
        sources = {},
      }

      local response = common.create_project_view_response()
      response.projects[1].imports = { "lib_id" }
      table.insert(response.projects, lib_project)
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items
      items.get_items({ flat_mode = true }, function(i)
        result_items = i
      end)

      -- In flat mode, both projects at root level
      assert.equals(2, #result_items)
      -- Root project should be first
      assert.truthy(result_items[1].extra.is_root)
    end)

    it("nests sub-project nodes under the root project", function()
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
        sources = {},
      }

      local response = common.create_project_view_response()
      response.projects[1].imports = { "lib_id" }
      table.insert(response.projects, lib_project)
      common.setup_lsp_cmd_project_view_mock(response)
      items = require("ada_ls.project_view.neo_tree.items")

      local result_items
      items.get_items({ flat_mode = false }, function(i)
        result_items = i
      end)

      assert.equals(1, #result_items)
      local root_node = result_items[1]
      local subproject_node = root_node.children[#root_node.children]
      assert.equals("project", subproject_node.type)
      assert.equals("lib_project", subproject_node.name)
      assert.is_false(subproject_node.extra.is_root)
    end)

    it(
      "adds object directory with direct file children when enabled",
      function()
        local temp_root = os.tmpname()
        os.remove(temp_root)
        local obj_dir = vim.fs.joinpath(temp_root, "obj")
        assert.equals(true, vim.fn.mkdir(obj_dir, "p") == 1)
        local obj_file = vim.fs.joinpath(obj_dir, "main.ali")
        local file = io.open(obj_file, "w")
        assert.is_not_nil(file)
        file:write("")
        file:close()

        object_dir_cleanup = function()
          os.remove(obj_file)
          os.remove(obj_dir)
          os.remove(temp_root)
        end

        local response = common.create_project_view_response()
        response.projects[1].project["object-directory"] = obj_dir
        common.setup_lsp_cmd_project_view_mock(response)
        items = require("ada_ls.project_view.neo_tree.items")

        local result_items
        items.get_items({ show_object_dirs = true }, function(i)
          result_items = i
        end)

        local project_node = result_items[1]
        local obj_node = project_node.children[2]
        assert.equals("directory", obj_node.type)
        assert.equals("obj (obj)", obj_node.name)
        assert.is_true(obj_node.extra.is_object_dir)
        assert.equals(1, #obj_node.children)
        assert.equals("file", obj_node.children[1].type)
        assert.equals("main.ali", obj_node.children[1].name)
      end
    )
  end)

  describe("find_node_by_path", function()
    before_each(function()
      items = require("ada_ls.project_view.neo_tree.items")
    end)

    it("finds node by exact path match", function()
      local test_items = {
        {
          id = "project:1",
          name = "project",
          type = "project",
          children = {
            {
              id = "dir:1",
              name = "src",
              type = "directory",
              path = "/project/src",
              children = {
                {
                  id = "file:1",
                  name = "main.adb",
                  type = "file",
                  path = "/project/src/main.adb",
                },
              },
            },
          },
        },
      }

      local result =
        items.find_node_by_path(test_items, "/project/src/main.adb")

      assert.is_not_nil(result)
      assert.equals("main.adb", result.name)
      assert.equals("file", result.type)
    end)

    it("returns nil for non-existent path", function()
      local test_items = {
        {
          id = "project:1",
          name = "project",
          type = "project",
          path = "/project.gpr",
        },
      }

      local result = items.find_node_by_path(test_items, "/nonexistent.adb")

      assert.is_nil(result)
    end)

    it("searches nested children recursively", function()
      local test_items = {
        {
          id = "project:1",
          children = {
            {
              id = "dir:1",
              children = {
                {
                  id = "dir:2",
                  children = {
                    {
                      id = "file:1",
                      path = "/deep/nested/file.adb",
                      name = "file.adb",
                    },
                  },
                },
              },
            },
          },
        },
      }

      local result =
        items.find_node_by_path(test_items, "/deep/nested/file.adb")

      assert.is_not_nil(result)
      assert.equals("file.adb", result.name)
    end)
  end)
end)

-- Test internals when ADA_LS_TEST_MODE is set
if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.neo_tree.items (internals)", function()
    local items

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals()
      items = require("ada_ls.project_view.neo_tree.items")
    end)

    after_each(function()
      common.cleanup_packages()
    end)

    describe("_make_id", function()
      it("generates correct format type:project_id:path", function()
        local result = items._make_id("file", "/src/main.adb", "proj_1")
        assert.equals("file:proj_1:/src/main.adb", result)
      end)

      it("handles nil project_id", function()
        local result = items._make_id("directory", "/src", nil)
        assert.equals("directory::/src", result)
      end)
    end)

    describe("_group_by_directory", function()
      it("groups sources by directory", function()
        local sources = {
          { directory = "/src", simple_name = "main.adb" },
          { directory = "/src", simple_name = "utils.adb" },
          { directory = "/tests", simple_name = "test.adb" },
        }
        local dirs, sorted = items._group_by_directory(sources)

        assert.equals(2, #sorted)
        assert.equals(2, #dirs["/src"])
        assert.equals(1, #dirs["/tests"])
      end)

      it("returns sorted directory list", function()
        local sources = {
          { directory = "/zeta", simple_name = "z.adb" },
          { directory = "/alpha", simple_name = "a.adb" },
        }
        local _, sorted = items._group_by_directory(sources)

        assert.equals("/alpha", sorted[1])
        assert.equals("/zeta", sorted[2])
      end)
    end)

    describe("_create_file_node", function()
      it("creates file node with correct structure", function()
        local source = {
          file_name = "/src/main.adb",
          simple_name = "main.adb",
          directory = "/src",
          language = "ada",
        }
        local project = { id = "proj_1", name = "test_project" }

        local node = items._create_file_node(source, project)

        assert.equals("file", node.type)
        assert.equals("main.adb", node.name)
        assert.equals("/src/main.adb", node.path)
        assert.equals("adb", node.ext)
        assert.equals("proj_1", node.extra.project_id)
        assert.equals("ada", node.extra.language)
      end)

      it("extracts extension correctly", function()
        local source = {
          file_name = "/src/package.ads",
          simple_name = "package.ads",
        }
        local project = { id = "proj_1" }

        local node = items._create_file_node(source, project)

        assert.equals("ads", node.ext)
      end)
    end)

    describe("_create_object_dir_node", function()
      local cleanup = nil

      after_each(function()
        if cleanup then
          cleanup()
          cleanup = nil
        end
      end)

      it("creates direct file children from the filesystem", function()
        local temp_root = os.tmpname()
        os.remove(temp_root)
        local obj_dir = vim.fs.joinpath(temp_root, "obj")
        assert.equals(true, vim.fn.mkdir(obj_dir, "p") == 1)
        local obj_file = vim.fs.joinpath(obj_dir, "main.ali")
        local file = io.open(obj_file, "w")
        assert.is_not_nil(file)
        file:write("")
        file:close()

        cleanup = function()
          os.remove(obj_file)
          os.remove(obj_dir)
          os.remove(temp_root)
        end

        local node = items._create_object_dir_node(obj_dir, {
          id = "proj_1",
          name = "test_project",
        })

        assert.equals("directory", node.type)
        assert.equals("obj (obj)", node.name)
        assert.is_true(node.extra.is_object_dir)
        assert.equals(1, #node.children)
        assert.equals("file", node.children[1].type)
        assert.equals("main.ali", node.children[1].name)
      end)
    end)
  end)
end
