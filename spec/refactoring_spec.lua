-- Tests for lua/ada_ls/refactoring.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.refactoring", function()
  local refactoring
  local mock_client
  local utils_notify_stub

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()

    -- Mock ada_ls.utils
    utils_notify_stub = stub.new()
    package.loaded["ada_ls.utils"] = { notify = utils_notify_stub }

    -- Create mock client
    mock_client = {
      name = "ada_ls",
      request = stub.new(),
    }

    -- Mock vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = stub.new().returns(mock_client)

    -- Add vim.ui.input mock
    rawset(vim, "ui", { input = stub.new() })

    refactoring = require("ada_ls.refactoring")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_make_handler", function()
      it("shows error when client not found", function()
        vim.lsp.get_client_by_id = stub.new().returns(nil)

        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command = { command = "test-command", arguments = { {} } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(utils_notify_stub).was_called()
        local call = utils_notify_stub.calls[1]
        assert.truthy(call.vals[1]:match("Als client not found"))
        assert.equals(vim.log.levels.ERROR, call.vals[2])
      end)

      it("shows error when client is not ada_ls", function()
        vim.lsp.get_client_by_id = stub.new().returns({ name = "other_ls" })

        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command = { command = "test-command", arguments = { {} } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(utils_notify_stub).was_called()
        local call = utils_notify_stub.calls[1]
        assert.truthy(call.vals[1]:match("Als client not found"))
      end)

      it("shows error when command.arguments is nil", function()
        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command = { command = "test-command", arguments = nil }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.equals("Refactoring: missing command arguments", call.vals[1])
        assert.equals(vim.log.levels.ERROR, call.vals[2])
      end)

      it("shows error when command.arguments is empty", function()
        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command = { command = "test-command", arguments = {} }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.equals("Refactoring: missing command arguments", call.vals[1])
      end)

      it("prompts user with vim.ui.input", function()
        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command =
          { command = "test-command", arguments = { { existing = "data" } } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.ui.input).was_called()
        local call = vim.ui.input.calls[1]
        assert.equals("Test prompt: ", call.vals[1].prompt)
      end)

      it("shows warning when user provides empty input", function()
        vim.ui.input = function(_opts, callback)
          callback("")
        end

        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command =
          { command = "test-command", arguments = { { existing = "data" } } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.equals("Refactoring cancelled: no input provided", call.vals[1])
        assert.equals(vim.log.levels.WARN, call.vals[2])
        assert.stub(mock_client.request).was_not_called()
      end)

      it("shows warning when user cancels input (nil)", function()
        vim.ui.input = function(_opts, callback)
          callback(nil)
        end

        local handler = refactoring._make_handler("testField", "Test prompt: ")
        local command =
          { command = "test-command", arguments = { { existing = "data" } } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.equals("Refactoring cancelled: no input provided", call.vals[1])
        assert.stub(mock_client.request).was_not_called()
      end)

      it("sets field and calls client:request on valid input", function()
        vim.ui.input = function(_opts, callback)
          callback("New_Param : Integer")
        end

        local handler =
          refactoring._make_handler("newParameter", "New parameter: ")
        local args = { existingField = "value" }
        local command =
          { command = "als-refactor-add-parameters", arguments = { args } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        -- Verify field was set
        assert.equals("New_Param : Integer", args.newParameter)

        -- Verify client:request was called with correct params
        assert.stub(mock_client.request).was_called()
        local call = mock_client.request.calls[1]
        assert.equals("workspace/executeCommand", call.vals[2])
        assert.same(command, call.vals[3])
      end)

      it("shows error notification on server error", function()
        vim.ui.input = function(_opts, callback)
          callback("valid input")
        end
        -- Mock client:request to immediately call callback with error
        mock_client.request = function(_self, _method, _cmd, callback)
          callback({ message = "Server error message" }, nil)
        end

        local handler = refactoring._make_handler("testField", "Test: ")
        local command = { command = "test-command", arguments = { {} } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.truthy(
          call.vals[1]:match("Refactoring failed: Server error message")
        )
        assert.equals(vim.log.levels.ERROR, call.vals[2])
      end)

      it("shows generic error when error.message is nil", function()
        vim.ui.input = function(_opts, callback)
          callback("valid input")
        end
        -- Mock client:request to immediately call callback with error without message
        mock_client.request = function(_self, _method, _cmd, callback)
          callback({}, nil)
        end

        local handler = refactoring._make_handler("testField", "Test: ")
        local command = { command = "test-command", arguments = { {} } }
        local ctx = { client_id = 1 }

        handler(command, ctx)

        assert.stub(vim.notify).was_called()
        local call = vim.notify.calls[1]
        assert.truthy(call.vals[1]:match("unknown error"))
      end)
    end)
  end

  describe("exported handlers", function()
    it("add_parameter is a function", function()
      assert.is_function(refactoring.add_parameter)
    end)

    it("change_parameter_type is a function", function()
      assert.is_function(refactoring.change_parameter_type)
    end)

    it("change_parameter_default is a function", function()
      assert.is_function(refactoring.change_parameter_default)
    end)

    it("replace_type is a function", function()
      assert.is_function(refactoring.replace_type)
    end)
  end)
end)
