-- Tests for lua/ada_ls/utils.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.utils", function()
  local utils

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    utils = require("ada_ls.utils")
  end)

  after_each(function()
    utils.clear()
    common.cleanup_packages()
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_log_lvl_tostring", function()
      it("returns TRACE for level 0", function()
        assert.equals("TRACE", utils._log_lvl_tostring(0))
      end)

      it("returns DEBUG for level 1", function()
        assert.equals("DEBUG", utils._log_lvl_tostring(1))
      end)

      it("returns INFO for level 2", function()
        assert.equals("INFO", utils._log_lvl_tostring(2))
      end)

      it("returns WARN for level 3", function()
        assert.equals("WARN", utils._log_lvl_tostring(3))
      end)

      it("returns ERROR for level 4", function()
        assert.equals("ERROR", utils._log_lvl_tostring(4))
      end)

      it("returns ERROR for unknown level", function()
        assert.equals("ERROR", utils._log_lvl_tostring(99))
      end)
    end)
  end

  describe("get_ada_ls", function()
    it("returns nil when no Ada LSP client exists", function()
      vim.lsp.get_clients = stub.new().returns({})

      local client, err = utils.get_ada_ls()
      assert.is_nil(client)
      assert.equals("Ada LSP client not found", err)
    end)

    it("returns cached client on subsequent calls", function()
      local mock_client = common.create_lsp_client()
      common.setup_lsp_client(mock_client)

      local client1 = utils.get_ada_ls()
      local client2 = utils.get_ada_ls()

      assert.equals(mock_client, client1)
      assert.equals(client1, client2)
      -- get_clients should only be called once due to caching
      assert.stub(vim.lsp.get_clients).was_called(1)
    end)
  end)

  describe("clear", function()
    it("clears the cached ALS client", function()
      local mock_client = common.create_lsp_client()
      common.setup_lsp_client(mock_client)

      utils.get_ada_ls() -- cache the client
      utils.clear()

      -- After clear, als should be nil
      assert.is_nil(utils.als)
    end)
  end)

  describe("notify", function()
    it("uses vim.notify when nvim-notify not available", function()
      -- Simulate notify not being available
      package.loaded["notify"] = nil
      package.preload["notify"] = function()
        error("module not found")
      end

      utils.notify("Test message", vim.log.levels.INFO)

      assert.stub(vim.notify).was_called()
      local call_args = vim.notify.calls[1].vals
      assert.matches("Test message", call_args[1])
    end)
  end)

  describe("try_require", function()
    it("returns true for available modules", function()
      local result = utils.try_require("string")
      assert.is_true(result)
    end)

    it("returns false for unavailable modules", function()
      local result = utils.try_require("nonexistent_module_xyz")
      assert.is_false(result)
    end)
  end)

  describe("get_filename", function()
    it("returns basename of current buffer path", function()
      vim.fn.expand = stub.new().returns("/path/to/file.adb")

      local result = utils.get_filename()
      assert.equals("file.adb", result)
    end)
  end)

  describe("get_bufdir", function()
    it("returns directory of current buffer path", function()
      vim.fn.expand = stub.new().returns("/path/to/file.adb")

      local result = utils.get_bufdir()
      assert.equals("/path/to/", result)
    end)
  end)

  describe("get_conf_file", function()
    it("returns nil when no LSP client", function()
      vim.lsp.get_clients = stub.new().returns({})

      local result = utils.get_conf_file()
      assert.is_nil(result)
    end)

    it("returns .als.json path when LSP client exists", function()
      local mock_client =
        common.create_lsp_client({ root_dir = "/project/root" })
      common.setup_lsp_client(mock_client)

      local result = utils.get_conf_file()
      assert.equals("/project/root/.als.json", result)
    end)
  end)

  describe("notify_server", function()
    it("returns false when no LSP client", function()
      vim.lsp.get_clients = stub.new().returns({})

      local result = utils.notify_server("test/method", {})
      assert.is_false(result)
    end)

    it("calls client:notify when LSP client exists", function()
      local mock_client = common.create_lsp_client()
      common.setup_lsp_client(mock_client)

      utils.notify_server("test/method", { key = "value" })

      assert.stub(mock_client.notify).was_called()
    end)
  end)

  describe("get_bufid", function()
    it("returns current buffer id", function()
      vim.api.nvim_get_current_buf = stub.new().returns(42)

      local result = utils.get_bufid()
      assert.equals(42, result)
    end)
  end)

  describe("notify", function()
    it("uses nvim-notify when available", function()
      -- Create a mock notify function
      local mock_notify = stub.new()
      package.loaded["notify"] = mock_notify

      utils.notify("Test message", vim.log.levels.WARN)

      assert.stub(mock_notify).was_called()
      local call_args = mock_notify.calls[1].vals
      assert.equals("Test message", call_args[1])
      assert.equals(vim.log.levels.WARN, call_args[2])
      assert.is_table(call_args[3])
      assert.matches("WARN", call_args[3].title)

      -- Cleanup
      package.loaded["notify"] = nil
    end)
  end)
end)
