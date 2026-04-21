-- Tests for lua/ada_ls/lsp_cmd.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.lsp_cmd", function()
  local lsp_cmd
  local utils

  -- Test data builders
  local function create_lsp_result(data)
    return { result = data }
  end

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
        request_sync = stub.new().returns(
          create_lsp_result({ { name = "Main" }, { name = "Test" } })
        ),
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
        request_sync = stub.new().returns(create_lsp_result({
          { uri = "file:///test.ads", range = {} },
        })),
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
        request_sync = stub.new().returns(create_lsp_result({})),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_file()
      assert.is_nil(result)
      assert.equals("No project file found", err)
    end)

    it("returns project file path on success", function()
      local mock_client = common.create_lsp_client({
        request_sync = stub
          .new()
          .returns(create_lsp_result({ "/project/test.gpr" })),
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
        request_sync = stub.new().returns(create_lsp_result({})),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_prj_dependencies()
      assert.is_nil(result)
      assert.matches("No project file", err)
    end)

    it("returns dependencies when project file exists", function()
      local call_count = 0
      local mock_client = common.create_lsp_client({
        request_sync = function(_self, method, _params, _timeout)
          call_count = call_count + 1
          if method == "workspace/executeCommand" then
            if call_count == 1 then
              -- First call: als-project-file
              return { result = { "/project/main.gpr" } }
            else
              -- Second call: als-gpr-dependencies
              return {
                result = {
                  { uri = "file:///project/lib1.gpr" },
                  { uri = "file:///project/lib2.gpr" },
                },
              }
            end
          end
          return nil
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
        request_sync = stub
          .new()
          .returns(create_lsp_result("file:///test.ads")),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.go_to_other()
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.stub(mock_client.request_sync).was_called()
    end)
  end)

  describe("get_src_dirs", function()
    it("returns source directories on success", function()
      local mock_client = common.create_lsp_client({
        request_sync = stub
          .new()
          .returns(create_lsp_result({ "/src", "/lib/src" })),
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
        request_sync = stub.new().returns(create_lsp_result("/obj")),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.get_obj_dir()
      assert.is_nil(err)
      assert.same({ "/obj" }, result)
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
        request_sync = stub
          .new()
          .returns(create_lsp_result({ "symbol1", "symbol2" })),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_request("textDocument/documentSymbol")
      assert.is_nil(err)
      assert.same({ "symbol1", "symbol2" }, result)
    end)

    it("returns error when request fails", function()
      local mock_client = common.create_lsp_client({
        request_sync = stub.new().returns(nil, "Request timed out"),
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
        request_sync = stub
          .new()
          .returns(create_lsp_result("/path/to/project.gpr")),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_command("als-project-file")
      assert.is_nil(err)
      assert.same({ "/path/to/project.gpr" }, result)
    end)

    it("returns error when command fails", function()
      local mock_client = common.create_lsp_client({
        request_sync = stub.new().returns(nil, "Command not found"),
      })
      common.setup_lsp_client(mock_client)

      local result, err = lsp_cmd.send_command("als-invalid-command")
      assert.is_nil(result)
      assert.equals("Command not found", err)
    end)
  end)
end)
