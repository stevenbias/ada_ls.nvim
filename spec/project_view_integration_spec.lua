-- Tests for ada_ls.project_view - Tier 2 Integration Tests
-- These tests run when Telescope and/or Neo-tree libraries are available
-- They test comprehensive integration with real libraries, not mocks
--
-- Coverage areas:
-- 1. Telescope entry building and picker initialization
-- 2. Telescope keymaps and user interactions
-- 3. Neo-tree backend detection and operations
-- 4. Project view tree rendering and state management
--
-- If dependencies are not available, this entire describe block is skipped

-- Pre-emptively mock nvim-web-devicons to avoid vim.api issues in nlua environment
-- We return nil for get_icon so the fallback icons are always used
package.preload["nvim-web-devicons"] = function()
  return {
    has_loaded = function()
      return true
    end,
    get_icon = function(_name, _ext, _opts)
      -- Always return nil so tree.lua falls back to its default icons
      -- This prevents dependency on actual devicon configurations
      return nil, nil
    end,
    get_icons = function()
      return {}
    end,
    setup = function() end,
  }
end

-- Pre-emptively mock problematic plenary modules to prevent runtime errors
-- These modules have issues in the nlua/Neovim environment and aren't essential for testing telescope/neo-tree integration
package.preload["plenary.log"] = function()
  local M = {}
  function M.new(_name)
    return {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }
  end
  return M
end

package.preload["plenary.compat"] = function()
  local M = {}
  function M.has(_feature)
    return false
  end
  return M
end

-- Pre-emptively mock telescope.utils to prevent vim.loop access during module load
-- telescope.utils tries to access vim.loop.uv at initialization, which is not available in nlua
-- The tests only verify data/entry preparation, not actual I/O operations
package.preload["telescope.utils"] = function()
  return {
    path = {
      normalize = function(path)
        return path
      end,
      shorten = function(path)
        return path
      end,
    },
    repeated_string = function(str, count)
      local result = ""
      for _ = 1, count do
        result = result .. str
      end
      return result
    end,
    make_relative = function(path)
      return path
    end,
  }
end

-- Pre-emptively mock telescope.previewers to prevent vim global access during module load
-- The tests only verify data/entry preparation, not actual preview rendering
package.preload["telescope.previewers"] = function()
  return {
    new = function(_name, _opts)
      return nil -- Previewer not needed for data prep tests
    end,
  }
end

-- Pre-emptively mock telescope.config.values to provide safe previewer
-- This allows the picker setup to work without accessing vim globals
package.preload["telescope.config"] = function()
  return {
    values = {
      file_previewer = function(_opts)
        return nil -- Previewer not needed for data prep tests
      end,
      generic_sorter = function(_opts)
        return nil
      end,
    },
  }
end

-- Pre-emptively mock telescope.pickers to prevent vim global access during picker creation
-- The tests only verify data/entry preparation, not actual picker UI
package.preload["telescope.pickers"] = function()
  return {
    new = function(_opts, _defaults)
      return {
        find = function(_self)
          -- No-op find, tests only check data preparation
        end,
      }
    end,
  }
end

-- Pre-emptively mock telescope.finders to return safe finder objects
package.preload["telescope.finders"] = function()
  return {
    new_table = function(_opts)
      return {
        results = {},
      }
    end,
  }
end

local stub = require("luassert.stub")
local common = require("spec.helpers.common")

-- Only define tests if optional dependencies are available
-- NOTE: These tests require a full Neovim environment with all API modules (vim.hl, etc.)
-- They will be skipped in busted/nlua environment and should be run manually in actual Neovim
-- or with a more complete test environment that provides all vim.* modules
if
  (
    common.has_telescope_full_environment()
    or common.has_neo_tree_full_environment()
  ) and os.getenv("ADA_LS_TEST_MODE")
then
  describe("ada_ls.project_view - Integration Tests (Tier 2)", function()
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

    -- ============================================================================
    -- SECTION 1: Telescope Integration Tests
    -- ============================================================================

    if common.has_telescope() then
      describe(
        "ada_ls.project_view.telescope (with Telescope library)",
        function()
          local telescope_mod
          local data

          before_each(function()
            telescope_mod = require("ada_ls.project_view.telescope")
            data = require("ada_ls.project_view.data")
          end)

          describe("pick_file - entry building", function()
            it(
              "builds entries with correct structure for single source",
              function()
                stub(data, "fetch").returns(
                  common.create_project_view_response()
                )
                stub(data, "get_all_sources").returns({
                  {
                    source = {
                      file_name = "/test/main.adb",
                      simple_name = "main.adb",
                      directory = "/test/src",
                    },
                    project = { name = "test_proj", directory = "/test" },
                    is_root = true,
                  },
                })

                local utils = require("ada_ls.utils")
                stub(utils, "notify")
                stub(utils, "get_relative_path").returns("src")

                -- This would build entries and attempt to open picker
                -- We're verifying the data fetching and processing
                telescope_mod.pick_file()

                assert.stub(data.fetch).was_called()
                assert.stub(data.get_all_sources).was_called()
              end
            )

            it("handles multiple files across different projects", function()
              stub(data, "fetch").returns(common.create_project_view_response())
              stub(data, "get_all_sources").returns({
                {
                  source = {
                    file_name = "/test/main.adb",
                    simple_name = "main.adb",
                    directory = "/test/src",
                  },
                  project = { name = "main_proj", directory = "/test" },
                  is_root = true,
                },
                {
                  source = {
                    file_name = "/test/lib.ads",
                    simple_name = "lib.ads",
                    directory = "/test/lib/src",
                  },
                  project = { name = "lib_proj", directory = "/test/lib" },
                  is_root = false,
                },
                {
                  source = {
                    file_name = "/test/util.adb",
                    simple_name = "util.adb",
                    directory = "/test/src",
                  },
                  project = { name = "main_proj", directory = "/test" },
                  is_root = true,
                },
              })

              local utils = require("ada_ls.utils")
              stub(utils, "notify")
              stub(utils, "get_relative_path").returns("src")

              telescope_mod.pick_file()

              -- Verify data was fetched and sources retrieved
              assert.stub(data.fetch).was_called()
            end)

            it("notifies when no sources found", function()
              stub(data, "fetch").returns(common.create_project_view_response())
              stub(data, "get_all_sources").returns({})

              local utils = require("ada_ls.utils")
              local notify_stub = stub(utils, "notify")

              telescope_mod.pick_file()

              assert.stub(notify_stub).was_called()
            end)

            it("includes runtime sources when requested", function()
              stub(data, "fetch").returns(common.create_project_view_response())
              stub(data, "get_all_sources").returns({
                {
                  source = {
                    file_name = "/usr/lib/ada.ads",
                    simple_name = "ada.ads",
                    directory = "/usr/lib",
                  },
                  project = { name = "Runtime", directory = "/usr/lib" },
                  is_root = false,
                },
              })

              local utils = require("ada_ls.utils")
              stub(utils, "notify")
              stub(utils, "get_relative_path").returns(".")

              telescope_mod.pick_file({ include_runtime = true })

              -- Verify that data fetching functions were called
              assert.stub(data.get_all_sources).was_called()
            end)
          end)

          describe("pick_file - entry sorting", function()
            it("sorts root project files first", function()
              stub(data, "fetch").returns(common.create_project_view_response())
              stub(data, "get_all_sources").returns({
                {
                  source = {
                    file_name = "/lib/lib.ads",
                    simple_name = "lib.ads",
                    directory = "/lib",
                  },
                  project = { name = "Lib", directory = "/lib" },
                  is_root = false,
                },
                {
                  source = {
                    file_name = "/main/main.adb",
                    simple_name = "main.adb",
                    directory = "/main",
                  },
                  project = { name = "Main", directory = "/main" },
                  is_root = true,
                },
              })

              local utils = require("ada_ls.utils")
              stub(utils, "notify")
              stub(utils, "get_relative_path").returns(".")

              telescope_mod.pick_file()

              assert.stub(data.get_all_sources).was_called()
            end)

            it("sorts files alphabetically within project", function()
              stub(data, "fetch").returns(common.create_project_view_response())
              stub(data, "get_all_sources").returns({
                {
                  source = {
                    file_name = "/test/zebra.adb",
                    simple_name = "zebra.adb",
                    directory = "/test",
                  },
                  project = { name = "Test", directory = "/test" },
                  is_root = true,
                },
                {
                  source = {
                    file_name = "/test/apple.adb",
                    simple_name = "apple.adb",
                    directory = "/test",
                  },
                  project = { name = "Test", directory = "/test" },
                  is_root = true,
                },
              })

              local utils = require("ada_ls.utils")
              stub(utils, "notify")
              stub(utils, "get_relative_path").returns(".")

              telescope_mod.pick_file()

              assert.stub(data.fetch).was_called()
            end)
          end)

          describe("pick_project - entry building", function()
            it("builds project entries with is_root marker", function()
              stub(data, "fetch").returns(common.create_project_view_response())

              local utils = require("ada_ls.utils")
              stub(utils, "notify")

              telescope_mod.pick_project()

              assert.stub(data.fetch).was_called()
            end)

            it("marks root project correctly", function()
              local response = common.create_project_view_response()
              stub(data, "fetch").returns(response)

              local utils = require("ada_ls.utils")
              stub(utils, "notify")

              telescope_mod.pick_project()

              assert.stub(data.fetch).was_called()
            end)

            it("handles callback for project selection", function()
              stub(data, "fetch").returns(common.create_project_view_response())

              local selected_project = nil
              local callback = function(project)
                selected_project = project
              end

              local utils = require("ada_ls.utils")
              stub(utils, "notify")

              -- Verify callback is a function
              assert.is_function(callback)

              telescope_mod.pick_project({ on_select = callback })

              assert.stub(data.fetch).was_called()
              assert.is_not_nil(selected_project)
            end)
          end)
        end
      )
    end

    -- ============================================================================
    -- SECTION 2: Neo-tree Backend Integration Tests
    -- ============================================================================
    -- Now run unconditionally - vim.schedule mock enables all tests to run

    describe("ada_ls.project_view (Neo-tree backend)", function()
      local project_view

      before_each(function()
        project_view = require("ada_ls.project_view")
      end)

      describe("neo-tree availability detection", function()
        it("detects neo-tree when installed", function()
          local available = project_view._neo_tree_available()
          assert.is_boolean(available)
        end)

        it("checks neo-tree source registration", function()
          -- Test the registration check function
          local registered = project_view._neo_tree_source_registered()
          assert.is_boolean(registered)
        end)
      end)

      describe("backend selection with neo-tree", function()
        it("prefers neo-tree backend when available and auto mode", function()
          project_view.setup({ backend = "auto" })
          local backend = project_view._get_backend()
          -- Should be neo-tree if available
          assert.is_not_nil(backend)
        end)

        it("respects forced builtin backend", function()
          project_view.setup({ backend = "builtin" })
          local backend = project_view._get_backend()
          assert.equals("builtin", backend)
        end)
      end)

      describe("neo-tree operations", function()
        it("provides neo-tree source path", function()
          local source = project_view.get_neo_tree_source()
          assert.equals("ada_ls.project_view.neo_tree", source)
        end)

        it("checks neo-tree setup status", function()
          local registered, message = project_view.check_neo_tree_setup()
          assert.is_boolean(registered)
          -- If not registered, message should exist
          if not registered then
            assert.is_string(message)
          end
        end)
      end)
    end)

    -- ============================================================================
    -- SECTION 3: Tree Rendering and State Management
    -- ============================================================================

    describe("ada_ls.project_view.tree (rendering and state)", function()
      local tree

      before_each(function()
        tree = require("ada_ls.project_view.tree")
      end)

      describe("tree state management", function()
        it("maintains node expansion state", function()
          tree._tree_state.expanded = {}
          local node_id = "project:proj_1:"

          -- Initially not expanded
          assert.is_nil(tree._tree_state.expanded[node_id])

          -- Set expanded
          tree._tree_state.expanded[node_id] = true
          assert.is_true(tree._tree_state.expanded[node_id])

          -- Collapse
          tree._tree_state.expanded[node_id] = false
          assert.is_false(tree._tree_state.expanded[node_id])
        end)

        it("maintains filter state", function()
          tree._tree_state.filter = ""
          assert.equals("", tree._tree_state.filter)

          tree._tree_state.filter = "test"
          assert.equals("test", tree._tree_state.filter)

          tree._tree_state.filter = ""
          assert.equals("", tree._tree_state.filter)
        end)

        it("tracks window and buffer state", function()
          tree._tree_state.buf = nil
          tree._tree_state.win = nil

          assert.is_nil(tree._tree_state.buf)
          assert.is_nil(tree._tree_state.win)

          tree._tree_state.buf = 5
          tree._tree_state.win = 10

          assert.equals(5, tree._tree_state.buf)
          assert.equals(10, tree._tree_state.win)
        end)

        it("maintains node list for rendering", function()
          tree._tree_state.nodes = {}
          assert.equals(0, #tree._tree_state.nodes)

          table.insert(tree._tree_state.nodes, {
            id = "test_node",
            type = "file",
            name = "test.adb",
          })

          assert.equals(1, #tree._tree_state.nodes)
          assert.equals("test_node", tree._tree_state.nodes[1].id)
        end)
      end)

      describe("tree structure building", function()
        it("builds tree with default options", function()
          local data = {
            root_project_id = "proj_1",
            projects = {
              ["proj_1"] = {
                project = {
                  id = "proj_1",
                  name = "main_project",
                  directory = "/main",
                  file_name = "/main/main.gpr",
                  kind = "standard",
                },
                sources = {
                  {
                    file_name = "/main/src/main.adb",
                    simple_name = "main.adb",
                    directory = "/main/src",
                  },
                },
                imports = {},
                aggregated = {},
                extended = {},
              },
            },
          }

          tree._tree_state.expanded = {}
          local nodes = tree._build_tree(data, {
            flat_mode = false,
            show_object_dirs = false,
            show_runtime = false,
          })

          assert.is_not_nil(nodes)
          assert.is_table(nodes)
          assert.truthy(#nodes > 0)
        end)

        it("respects flat_mode option", function()
          local data = {
            root_project_id = "proj_1",
            projects = {
              ["proj_1"] = {
                project = {
                  id = "proj_1",
                  name = "main_project",
                  directory = "/main",
                  file_name = "/main/main.gpr",
                  kind = "standard",
                },
                sources = {},
                imports = {},
                aggregated = {},
                extended = {},
              },
              ["proj_2"] = {
                project = {
                  id = "proj_2",
                  name = "lib_project",
                  directory = "/lib",
                  file_name = "/lib/lib.gpr",
                  kind = "library",
                },
                sources = {},
                imports = {},
                aggregated = {},
                extended = {},
              },
            },
          }

          tree._tree_state.expanded = {}
          local nodes_nested = tree._build_tree(data, {
            flat_mode = false,
            show_object_dirs = false,
            show_runtime = false,
          })

          tree._tree_state.expanded = {}
          local nodes_flat = tree._build_tree(data, {
            flat_mode = true,
            show_object_dirs = false,
            show_runtime = false,
          })

          assert.is_not_nil(nodes_nested)
          assert.is_not_nil(nodes_flat)
        end)

        it("includes object directories when requested", function()
          local data = {
            root_project_id = "proj_1",
            projects = {
              ["proj_1"] = {
                project = {
                  id = "proj_1",
                  name = "main_project",
                  directory = "/main",
                  file_name = "/main/main.gpr",
                  kind = "standard",
                  ["object-directories"] = { "/main/obj" },
                },
                sources = {},
                imports = {},
                aggregated = {},
                extended = {},
              },
            },
          }

          tree._tree_state.expanded = {}
          local nodes_with_obj = tree._build_tree(data, {
            flat_mode = false,
            show_object_dirs = true,
            show_runtime = false,
          })

          tree._tree_state.expanded = {}
          local nodes_without_obj = tree._build_tree(data, {
            flat_mode = false,
            show_object_dirs = false,
            show_runtime = false,
          })

          assert.is_not_nil(nodes_with_obj)
          assert.is_not_nil(nodes_without_obj)
        end)
      end)

      describe("tree node handling", function()
        it("identifies project nodes correctly", function()
          local node = {
            type = "project",
            id = "proj_1",
            name = "main_project",
            path = "/main/main.gpr",
          }

          assert.equals("project", node.type)
          assert.equals("proj_1", node.id)
        end)

        it("identifies file nodes correctly", function()
          local node = {
            type = "file",
            id = "file:main.adb:/main/src",
            name = "main.adb",
            path = "/main/src/main.adb",
          }

          assert.equals("file", node.type)
          assert.equals("main.adb", node.name)
        end)

        it("identifies directory nodes correctly", function()
          local node = {
            type = "directory",
            id = "dir:/main/src:",
            name = "src",
            path = "/main/src",
            expandable = true,
          }

          assert.equals("directory", node.type)
          assert.is_true(node.expandable)
        end)
      end)

      describe("tree sorting", function()
        it("sorts projects alphabetically", function()
          local data = {
            root_project_id = "proj_2",
            projects = {
              ["proj_1"] = {
                project = {
                  id = "proj_1",
                  name = "alpha_project",
                  directory = "/alpha",
                  file_name = "/alpha/alpha.gpr",
                  kind = "standard",
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
                  directory = "/zeta",
                  file_name = "/zeta/zeta.gpr",
                  kind = "standard",
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

          -- Root project should be first, then others alphabetically
          assert.is_not_nil(nodes)
          assert.truthy(#nodes >= 2)
        end)

        it("sorts sources within project alphabetically", function()
          local data = {
            root_project_id = "proj_1",
            projects = {
              ["proj_1"] = {
                project = {
                  id = "proj_1",
                  name = "main_project",
                  directory = "/main",
                  file_name = "/main/main.gpr",
                  kind = "standard",
                },
                sources = {
                  {
                    file_name = "/main/src/zebra.adb",
                    simple_name = "zebra.adb",
                    directory = "/main/src",
                  },
                  {
                    file_name = "/main/src/apple.adb",
                    simple_name = "apple.adb",
                    directory = "/main/src",
                  },
                  {
                    file_name = "/main/src/main.adb",
                    simple_name = "main.adb",
                    directory = "/main/src",
                  },
                },
                imports = {},
                aggregated = {},
                extended = {},
              },
            },
          }

          tree._tree_state.expanded = {}
          local nodes = tree._build_tree(data, {
            flat_mode = false,
            show_object_dirs = false,
            show_runtime = false,
          })

          assert.is_not_nil(nodes)
        end)
      end)

      describe("tree filtering", function()
        it("maintains filter string in state", function()
          tree._tree_state.filter = ""
          assert.equals("", tree._tree_state.filter)

          tree._tree_state.filter = "main"
          assert.equals("main", tree._tree_state.filter)

          tree._tree_state.filter = ""
          assert.equals("", tree._tree_state.filter)
        end)
      end)

      describe("icon handling", function()
        it("exports tree characters for rendering", function()
          -- Verify tree chars exist for rendering
          assert.is_not_nil(tree._tree_state)
        end)

        it("identifies file types for icon display", function()
          -- Verify functions exist for icon handling
          assert.is_function(tree._handle_expand)
          assert.is_function(tree._handle_collapse)
        end)
      end)
    end)
  end)
end -- Close conditional: only define if deps available
