-- Tests for lua/ada_ls/lsp_cmd.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.lsp_cmd", function()
  local lsp_cmd
  local utils

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    utils = require("ada_ls.utils")
    lsp_cmd = require("ada_ls.lsp_cmd")
  end)

  after_each(function()
    utils.clear()
    common.cleanup_packages()
  end)

  describe("get_root_dir", function()
    it("returns nil when no Ada LSP client exists", function()
      vim.lsp.get_clients = stub.new().returns({})

      local result = lsp_cmd.get_root_dir()
      assert.is_nil(result)
    end)

    it("returns client root_dir when Ada LSP client exists", function()
      local mock_client = common.create_lsp_client({ root_dir = "/my/project" })
      common.setup_lsp_client(mock_client)

      local result = lsp_cmd.get_root_dir()
      assert.equals("/my/project", result)
    end)
  end)

  describe("get_symbols", function()
    it("returns symbols list on success", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, { { name = "Main" }, { name = "Test" } })
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_symbols()
      assert.is_nil(err)
      assert.same({ { name = "Main" }, { name = "Test" } }, result)
    end)
  end)

  describe("get_declarations", function()
    it("returns declarations list on success", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, { { uri = "file:///test.ads", range = {} } })
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_declarations()
      assert.is_nil(err)
      assert.is_table(result)
    end)
  end)

  describe("get_prj_file", function()
    it("returns nil and error when no project file", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, nil)
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_file()
      assert.is_nil(result)
      assert.equals("No project file found", err)
    end)

    it("returns project file path on success", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, "/project/test.gpr")
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_file()
      assert.is_nil(err)
      assert.equals("/project/test.gpr", result)
    end)
  end)

  describe("get_prj_dependencies", function()
    it("returns nil when no project file", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, nil)
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_dependencies()
      assert.is_nil(result)
      assert.matches("No project file", err)
    end)

    it("returns dependencies when project file exists", function()
      local call_count = 0
      local mock_client = common.create_lsp_client({
        request = function(_self, method, _params, callback)
          call_count = call_count + 1
          if method == "workspace/executeCommand" then
            if call_count == 1 then
              -- First call: als-project-file
              callback(nil, "/project/main.gpr")
            else
              -- Second call: als-gpr-dependencies
              callback(nil, {
                { uri = "file:///project/lib1.gpr" },
                { uri = "file:///project/lib2.gpr" },
              })
            end
          end
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_dependencies()
      assert.is_nil(err)
      assert.is_table(result)
      assert.equals(2, #result)
    end)
  end)

  describe("go_to_other", function()
    it("sends als-other-file command with current buffer URI", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, "file:///test.ads")
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.go_to_other()
      assert.is_nil(err)
      assert.is_not_nil(result)
    end)
  end)

  describe("get_src_dirs", function()
    it("returns source directories on success", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, { "/src", "/lib/src" })
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_src_dirs()
      assert.is_nil(err)
      assert.same({ "/src", "/lib/src" }, result)
    end)
  end)

  describe("get_obj_dir", function()
    it("returns object directory on success", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, "/obj")
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_obj_dir()
      assert.is_nil(err)
      assert.equals("/obj", result)
    end)
  end)

  describe("send_request", function()
    it("returns nil and error when no Ada LSP client", function()
      vim.lsp.get_clients = stub.new().returns({})

      local result, err = lsp_cmd.send_request("textDocument/documentSymbol")
      assert.is_nil(result)
      assert.equals("Ada LSP client not found", err)
    end)

    it("returns result as list for successful request", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, { "symbol1", "symbol2" })
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_request("textDocument/documentSymbol")
      assert.is_nil(err)
      assert.same({ "symbol1", "symbol2" }, result)
    end)

    it("returns error when request fails", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback("Request timed out", nil)
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_request("textDocument/documentSymbol")
      assert.is_nil(result)
      assert.equals("Request timed out", err)
    end)
  end)

  describe("send_command", function()
    it("returns nil and error when no Ada LSP client", function()
      vim.lsp.get_clients = stub.new().returns({})

      local result, err = lsp_cmd.send_command("als-project-file")
      assert.is_nil(result)
      assert.equals("Ada LSP client not found", err)
    end)

    it("returns result for successful command", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback(nil, "/path/to/project.gpr")
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_command("als-project-file")
      assert.is_nil(err)
      assert.equals("/path/to/project.gpr", result)
    end)

    it("returns error when command fails", function()
      local mock_client = common.create_lsp_client({
        request = function(_self, _method, _params, callback)
          callback("Command not found", nil)
        end,
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_command("als-invalid-command")
      assert.is_nil(result)
      assert.equals("Command not found", err)
    end)
  end)
end)
