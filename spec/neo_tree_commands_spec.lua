-- Tests for lua/ada_ls/project_view/neo_tree/commands.lua
-- Comprehensive tests for neo-tree command handlers
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

if os.getenv("ADA_LS_TEST_MODE") then
  describe("ada_ls.project_view.neo_tree.commands", function()
    local commands
    local mock_cc -- mock common commands
    local mock_renderer
    local mock_sources_manager
    local mock_data_module

    before_each(function()
      common.cleanup_packages()
      common.setup_vim_globals()

      -- Setup mock common commands (neo-tree.sources.common.commands)
      mock_cc = {
        open = stub.new(),
        open_split = stub.new(),
        open_vsplit = stub.new(),
        open_tabnew = stub.new(),
        toggle_preview = stub.new(),
        _add_common_commands = stub.new(),
      }
      package.loaded["neo-tree.sources.common.commands"] = mock_cc

      -- Setup mock renderer
      mock_renderer = {
        redraw = stub.new(),
      }
      package.loaded["neo-tree.ui.renderer"] = mock_renderer

      -- Setup mock sources manager
      mock_sources_manager = {
        refresh = stub.new(),
      }
      package.loaded["neo-tree.sources.manager"] = mock_sources_manager

      -- Setup mock data module
      mock_data_module = {
        invalidate = stub.new(),
      }
      package.loaded["ada_ls.project_view.data"] = mock_data_module

      -- Require after all mocks are set up
      commands = require("ada_ls.project_view.neo_tree.commands")
    end)

    after_each(function()
      common.cleanup_packages()
      package.loaded["neo-tree.sources.common.commands"] = nil
      package.loaded["neo-tree.ui.renderer"] = nil
      package.loaded["neo-tree.sources.manager"] = nil
      package.loaded["ada_ls.project_view.data"] = nil
    end)

    describe("M.open", function()
      it("returns early when no node at cursor", function()
        local state = {
          tree = {
            get_node = stub.new().returns(nil),
          },
        }

        commands.open(state)

        assert.stub(state.tree.get_node).was_called()
        assert.stub(mock_renderer.redraw).was_not_called()
      end)

      it(
        "expands collapsed directory node when toggle_directory not false",
        function()
          local expanded = false
          local node = {
            type = "directory",
            is_expanded = function()
              return expanded
            end,
            expand = function()
              expanded = true
            end,
            collapse = stub.new(),
          }

          local state = {
            tree = {
              get_node = stub.new().returns(node),
            },
          }

          commands.open(state)

          assert.is_true(expanded)
          assert.stub(mock_renderer.redraw).was_called_with(state)
        end
      )

      it(
        "collapses expanded directory node when toggle_directory not false",
        function()
          local expanded = true
          local node = {
            type = "directory",
            is_expanded = function()
              return expanded
            end,
            expand = stub.new(),
            collapse = function()
              expanded = false
            end,
          }

          local state = {
            tree = {
              get_node = stub.new().returns(node),
            },
          }

          commands.open(state)

          assert.is_false(expanded)
          assert.stub(mock_renderer.redraw).was_called_with(state)
        end
      )

      it(
        "expands collapsed project node when toggle_directory not false",
        function()
          local expanded = false
          local node = {
            type = "project",
            is_expanded = function()
              return expanded
            end,
            expand = function()
              expanded = true
            end,
            collapse = stub.new(),
          }

          local state = {
            tree = {
              get_node = stub.new().returns(node),
            },
          }

          commands.open(state)

          assert.is_true(expanded)
          assert.stub(mock_renderer.redraw).was_called_with(state)
        end
      )

      it("skips toggle when toggle_directory is false on directory", function()
        local node = {
          type = "directory",
          is_expanded = stub.new(),
          expand = stub.new(),
          collapse = stub.new(),
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        commands.open(state, false)

        assert.stub(node.is_expanded).was_not_called()
        assert.stub(node.expand).was_not_called()
        assert.stub(node.collapse).was_not_called()
        assert.stub(mock_renderer.redraw).was_not_called()
      end)

      it("opens file node using common.open when has path", function()
        local node = {
          type = "file",
          path = "/project/main.adb",
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        commands.open(state)

        local calls = mock_cc.open.calls
        assert.equals(1, #calls)
        -- Verify state was passed (can't use == for tables)
        assert.is_not_nil(calls[1].vals[1])
        assert.is_function(calls[1].vals[2])
        assert.stub(mock_renderer.redraw).was_not_called()
      end)

      it("ignores directory without path", function()
        local node = {
          type = "directory",
          -- no path
          is_expanded = stub.new(),
          expand = stub.new(),
          collapse = stub.new(),
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        commands.open(state)

        -- Should still toggle directory
        assert.stub(node.is_expanded).was_called()
      end)

      it("does nothing for unknown node type without path", function()
        local node = {
          type = "unknown",
          -- no path
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        commands.open(state)

        assert.stub(mock_cc.open).was_not_called()
        assert.stub(mock_renderer.redraw).was_not_called()
      end)
    end)

    describe("M.open_split", function()
      it("delegates to common.open_split with empty callback", function()
        local state = { some = "state" }

        commands.open_split(state)

        local calls = mock_cc.open_split.calls
        assert.equals(1, #calls)
        assert.is_not_nil(calls[1].vals[1])
        assert.is_function(calls[1].vals[2])
      end)

      it("passes state unchanged to common.open_split", function()
        local state = {
          tree = { data = "test" },
          window = 123,
        }

        commands.open_split(state)

        local call_args = mock_cc.open_split.calls[1].vals
        assert.equals(state.window, call_args[1].window)
        assert.equals(state.tree.data, call_args[1].tree.data)
      end)
    end)

    describe("M.open_vsplit", function()
      it("delegates to common.open_vsplit with empty callback", function()
        local state = { some = "state" }

        commands.open_vsplit(state)

        local calls = mock_cc.open_vsplit.calls
        assert.equals(1, #calls)
        assert.is_not_nil(calls[1].vals[1])
        assert.is_function(calls[1].vals[2])
      end)

      it("passes state unchanged to common.open_vsplit", function()
        local state = {
          tree = { data = "test" },
          window = 456,
        }

        commands.open_vsplit(state)

        local call_args = mock_cc.open_vsplit.calls[1].vals
        assert.equals(state.window, call_args[1].window)
        assert.equals(state.tree.data, call_args[1].tree.data)
      end)
    end)

    describe("M.open_tabnew", function()
      it("delegates to common.open_tabnew with empty callback", function()
        local state = { some = "state" }

        commands.open_tabnew(state)

        local calls = mock_cc.open_tabnew.calls
        assert.equals(1, #calls)
        assert.is_not_nil(calls[1].vals[1])
        assert.is_function(calls[1].vals[2])
      end)

      it("passes state unchanged to common.open_tabnew", function()
        local state = {
          tree = { data = "test" },
          window = 789,
        }

        commands.open_tabnew(state)

        local call_args = mock_cc.open_tabnew.calls[1].vals
        assert.equals(state.window, call_args[1].window)
        assert.equals(state.tree.data, call_args[1].tree.data)
      end)
    end)

    describe("M.toggle_preview", function()
      it("delegates to common.toggle_preview with state and config", function()
        local state = { some = "state" }
        local config = { preview_enabled = false }

        commands.toggle_preview(state, config)

        assert.stub(mock_cc.toggle_preview).was_called_with(state, config)
      end)

      it("passes config unchanged", function()
        local state = { window = 1 }
        local config = { width = 40, height = 20 }

        commands.toggle_preview(state, config)

        local call_args = mock_cc.toggle_preview.calls[1].vals
        assert.equals(config.width, call_args[2].width)
        assert.equals(config.height, call_args[2].height)
      end)

      it("handles nil config", function()
        local state = { window = 1 }

        commands.toggle_preview(state, nil)

        assert.stub(mock_cc.toggle_preview).was_called_with(state, nil)
      end)
    end)

    describe("M.refresh", function()
      it("invalidates data cache", function()
        local state = {}

        commands.refresh(state)

        assert.stub(mock_data_module.invalidate).was_called()
      end)

      it("calls sources manager refresh with ada_project source", function()
        local state = { window = 1 }

        commands.refresh(state)

        assert
          .stub(mock_sources_manager.refresh)
          .was_called_with("ada_project", state)
      end)

      it("invalidates before refreshing", function()
        local call_order = {}
        mock_data_module.invalidate = function()
          table.insert(call_order, "invalidate")
        end
        mock_sources_manager.refresh = function()
          table.insert(call_order, "refresh")
        end

        local state = {}
        commands.refresh(state)

        assert.equals("invalidate", call_order[1])
        assert.equals("refresh", call_order[2])
      end)

      it("passes state to refresh unchanged", function()
        local state = {
          data = "test",
          bufnr = 42,
        }

        commands.refresh(state)

        local call_args = mock_sources_manager.refresh.calls[1].vals
        assert.equals(state.bufnr, call_args[2].bufnr)
        assert.equals(state.data, call_args[2].data)
      end)
    end)

    describe("M.none", function()
      it("is a no-op function that returns nothing", function()
        local result = commands.none({ some = "state" })

        assert.is_nil(result)
      end)

      it("accepts state parameter but does nothing", function()
        local state = { tree = {}, window = 1 }

        -- Should not raise any errors
        commands.none(state)

        assert.stub(mock_cc.open).was_not_called()
        assert.stub(mock_renderer.redraw).was_not_called()
      end)

      it("can be called with nil state", function()
        -- Should not raise any errors
        commands.none(nil)
      end)
    end)

    describe("command merging via _add_common_commands", function()
      it("calls common._add_common_commands with module table", function()
        -- Module was already loaded before this test, but we verify the call
        -- happened during require
        assert.stub(mock_cc._add_common_commands).was_called()
      end)

      it("passes module table to _add_common_commands", function()
        -- Verify that _add_common_commands is called
        local call_count = #mock_cc._add_common_commands.calls
        assert.is_true(call_count > 0)
      end)
    end)

    describe("error handling and edge cases", function()
      it("raises error when node:expand() fails during open", function()
        local node = {
          type = "directory",
          is_expanded = function()
            return false
          end,
          expand = function()
            error("Expand failed")
          end,
          collapse = stub.new(),
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        -- Should raise error (not silently handled)
        assert.has_error(function()
          commands.open(state)
        end)
      end)

      it("handles malformed state in open_split", function()
        -- Pass empty table as state
        local state = {}

        -- Should not raise, common.open_split handles it
        assert.has_no_error(function()
          commands.open_split(state)
        end)
      end)

      it("handles rapid successive refresh calls", function()
        local state = {}

        commands.refresh(state)
        commands.refresh(state)
        commands.refresh(state)

        -- Should call invalidate and refresh 3 times each
        assert.equals(3, #mock_data_module.invalidate.calls)
        assert.equals(3, #mock_sources_manager.refresh.calls)
      end)

      it("handles file node with nil path", function()
        local node = {
          type = "file",
          path = nil,
        }

        local state = {
          tree = {
            get_node = stub.new().returns(node),
          },
        }

        commands.open(state)

        -- Should not call common.open since path is nil
        assert.stub(mock_cc.open).was_not_called()
      end)
    end)

    describe("state management across multiple calls", function()
      it("maintains independent state for sequential open calls", function()
        local node1 = {
          type = "directory",
          is_expanded = function()
            return false
          end,
          expand = function() end,
          collapse = stub.new(),
        }

        local node2 = {
          type = "directory",
          is_expanded = function()
            return true
          end,
          expand = stub.new(),
          collapse = function() end,
        }

        local state1 = {
          tree = {
            get_node = stub.new().returns(node1),
          },
        }

        local state2 = {
          tree = {
            get_node = stub.new().returns(node2),
          },
        }

        commands.open(state1)
        commands.open(state2)

        -- Both should succeed independently
        assert.equals(2, #mock_renderer.redraw.calls)
      end)

      it("handles interleaved operations (open, refresh, open)", function()
        local state = { tree = { get_node = stub.new().returns(nil) } }

        commands.open(state)
        commands.refresh(state)
        commands.open(state)

        assert.equals(1, #mock_data_module.invalidate.calls)
        assert.equals(1, #mock_sources_manager.refresh.calls)
      end)
    end)
  end)
end
