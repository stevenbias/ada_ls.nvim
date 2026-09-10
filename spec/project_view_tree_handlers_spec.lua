-- Tests for ada_ls.project_view.tree handler integration
-- Verifies tree state (expansion, filter) persists correctly through refresh cycles
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.tree integration", function()
    local tree
    local mock_data

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals({
        nvim_create_autocmd = function() end,
        nvim_create_augroup = stub().returns(1),
        nvim_create_buf = stub().returns(1),
        nvim_buf_set_lines = stub(),
        nvim_buf_set_option = function() end,
        nvim_buf_set_name = function() end,
        nvim_buf_set_keymap = function() end,
        nvim_open_win = stub().returns(1),
        nvim_win_set_option = function() end,
        nvim_set_current_win = function() end,
        nvim_buf_is_valid = stub().returns(true),
        nvim_win_is_valid = stub().returns(true),
        nvim_create_namespace = stub().returns(1),
        nvim_buf_clear_namespace = stub(),
        nvim_buf_add_highlight = stub(),
        nvim_get_current_win = stub().returns(1),
        nvim_win_set_buf = stub(),
        nvim_win_close = stub(),
      })
      vim.fn = { line = stub().returns(1) }
      vim.ui = { input = stub() }

      -- Setup tree-specific mocks (vim.bo, vim.wo, data module)
      mock_data = common.setup_tree_integration_mocks()
    end)

    after_each(function()
      common.cleanup_packages()
    end)

    describe("tree initialization", function()
      it("exposes required public functions", function()
        tree = require("ada_ls.project_view.tree")
        assert.is_function(tree.open)
        assert.is_function(tree.close)
        assert.is_function(tree.toggle)
        assert.is_function(tree.refresh)
        assert.is_function(tree.is_open)
      end)

      it("exposes test-only state for verification", function()
        tree = require("ada_ls.project_view.tree")
        assert.is_table(tree._tree_state)
        assert.is_not_nil(tree._tree_state.expanded)
        assert.is_not_nil(tree._tree_state.nodes)
        assert.is_string(tree._tree_state.filter)
      end)
    end)

    describe("expansion state persistence", function()
      it("preserves directory expansion through refresh", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Verify tree is open and has nodes
        assert.is_true(tree.is_open())
        assert.is_true(#tree._tree_state.nodes > 0)

        -- Find first expandable directory node
        local dir_node = nil
        for _, node in ipairs(tree._tree_state.nodes) do
          if node.expandable and node.type == "directory" then
            dir_node = node
            break
          end
        end
        assert.is_not_nil(dir_node)

        -- Expand the directory
        tree._tree_state.expanded[dir_node.id] = true
        assert.is_true(tree._tree_state.expanded[dir_node.id])

        -- Refresh tree with same data
        tree.refresh()

        -- Verify expansion persisted
        assert.is_true(tree._tree_state.expanded[dir_node.id])
      end)

      it("preserves project expansion through refresh", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Find first expandable project node
        local proj_node = nil
        for _, node in ipairs(tree._tree_state.nodes) do
          if node.expandable and node.type == "project" then
            proj_node = node
            break
          end
        end
        assert.is_not_nil(proj_node)

        -- Expand the project
        tree._tree_state.expanded[proj_node.id] = true
        assert.is_true(tree._tree_state.expanded[proj_node.id])

        -- Refresh
        tree.refresh()

        -- Verify expansion persisted
        assert.is_true(tree._tree_state.expanded[proj_node.id])
      end)

      it("preserves multiple simultaneous expansions", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Expand first 2 expandable nodes
        local expanded_ids = {}
        local count = 0
        for _, node in ipairs(tree._tree_state.nodes) do
          if node.expandable and count < 2 then
            tree._tree_state.expanded[node.id] = true
            table.insert(expanded_ids, node.id)
            count = count + 1
          end
        end
        assert.equals(2, #expanded_ids)

        -- Refresh tree
        tree.refresh()

        -- Verify all expansions persisted
        for _, id in ipairs(expanded_ids) do
          assert.is_true(tree._tree_state.expanded[id])
        end
      end)
    end)

    describe("filter state persistence", function()
      it("preserves filter string through refresh", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Apply filter
        tree._tree_state.filter = "main"
        assert.equals("main", tree._tree_state.filter)

        -- Refresh tree
        tree.refresh()

        -- Verify filter persisted
        assert.equals("main", tree._tree_state.filter)

        -- Verify nodes are still filtered (contain matching text)
        local has_main = false
        for _, node in ipairs(tree._tree_state.nodes) do
          if node.name:lower():find("main") then
            has_main = true
            break
          end
        end
        assert.is_true(has_main)
      end)

      it("preserves empty filter through refresh", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        local nodes_before = #tree._tree_state.nodes
        tree._tree_state.filter = ""

        -- Refresh
        tree.refresh()

        -- Verify filter stays empty and all nodes shown
        assert.equals("", tree._tree_state.filter)
        assert.equals(nodes_before, #tree._tree_state.nodes)
      end)

      it("preserves custom filter through multiple refreshes", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Apply filter
        tree._tree_state.filter = "utils"

        -- Refresh multiple times
        tree.refresh()
        tree.refresh()
        tree.refresh()

        -- Verify filter persisted through all refreshes
        assert.equals("utils", tree._tree_state.filter)
      end)
    end)

    describe("error handling", function()
      it("handles data.fetch() returning nil gracefully", function()
        mock_data.fetch.returns(nil, "Connection lost")

        tree = require("ada_ls.project_view.tree")

        -- tree.open() should handle error gracefully
        -- (will not crash, tree stays closed)
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Tree should exist but not be open
        assert.is_not_nil(tree)
        assert.is_false(tree.is_open())
      end)

      it("handles refresh when tree is closed gracefully", function()
        mock_data.fetch.returns(nil)

        tree = require("ada_ls.project_view.tree")

        -- Calling refresh on unopened tree should not crash
        assert.has_no_error(function()
          tree.refresh()
        end)
      end)
    end)

    describe("state transitions", function()
      it("maintains expansion state when opening then closing", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Find and expand a node
        local node_to_expand = nil
        for _, node in ipairs(tree._tree_state.nodes) do
          if node.expandable then
            node_to_expand = node
            break
          end
        end
        assert.is_not_nil(node_to_expand)

        tree._tree_state.expanded[node_to_expand.id] = true
        local expanded_id = node_to_expand.id

        -- Close the tree
        tree.close()
        assert.is_false(tree.is_open())

        -- Expansion state should still be in memory
        assert.is_true(tree._tree_state.expanded[expanded_id])
      end)

      it("maintains filter state when opening then closing", function()
        -- Create realistic project data
        local project_data = common.create_project_view_response()
        local parsed_data =
          require("ada_ls.project_view.data").parse_response(project_data)
        mock_data.fetch.returns(parsed_data)

        tree = require("ada_ls.project_view.tree")
        tree.open({
          flat_mode = false,
          show_object_dirs = false,
          show_runtime = false,
        })

        -- Apply filter
        tree._tree_state.filter = "src"

        -- Close the tree
        tree.close()
        assert.is_false(tree.is_open())

        -- Filter state should still be in memory
        assert.equals("src", tree._tree_state.filter)
      end)
    end)
  end)
end
