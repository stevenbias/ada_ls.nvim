local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.health", function()
  local health

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    common.setup_vim_health()
    rawset(vim, "version", function()
      return { major = 0, minor = 11, patch = 0 }
    end)
    health = require("ada_ls.health")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("check", function()
    before_each(function()
      vim.fn.has = stub.new().returns(1)
      vim.fn.executable = stub.new().returns(1)
      vim.fn.system = stub.new().returns("gprbuild 24.0.0\n")
      vim.lsp.get_clients = stub.new().returns({})
      rawset(vim.api, "nvim_buf_get_name", stub.new().returns(""))
      vim.g.loaded_ada_ls = nil
      rawset(package.loaded, "ada_ls.spark.config", {
        get = function()
          return { proof_level = 0, options = { 1 } }
        end,
      })
      rawset(package.loaded, "ada_ls.utils", {
        get_conf_file = function()
          return nil
        end,
        get_server_project_name = function()
          return nil
        end,
      })
      rawset(package.loaded, "ada_ls.project", {
        decode_json_config = function()
          return nil, nil, nil
        end,
      })
    end)

    it("runs all health checks", function()
      health.check()
      assert.is_true(#vim.health.start.calls >= 5)
    end)

    it("reports Neovim >= 0.11 as ok", function()
      vim.fn.has = stub.new().returns(1)
      health.check()
      assert.is_true(common.find_stub_call(vim.health.ok, "Neovim"))
    end)

    it("reports Neovim < 0.11 as error", function()
      vim.fn.has = stub.new().returns(0)
      health.check()
      assert.is_true(common.find_stub_call(vim.health.error, "0.11"))
    end)

    it("reports plugin loaded when flag is set", function()
      vim.g.loaded_ada_ls = true
      health.check()
      assert.is_true(common.find_stub_call(vim.health.ok, "Plugin loaded"))
    end)

    it("reports plugin not loaded when flag is nil", function()
      vim.g.loaded_ada_ls = nil
      health.check()
      assert.is_true(
        common.find_stub_call(vim.health.warn, "Plugin not loaded")
      )
    end)

    it("reports ok when server project is configured", function()
      common.setup_utils_mock({ server_project = "my_project.gpr" })
      health.check()
      assert.is_true(common.find_stub_call(vim.health.ok, "ALS project:"))
    end)

    it("reports info when no server project configured", function()
      common.setup_utils_mock()
      health.check()
      assert.is_true(
        common.find_stub_call(vim.health.info, "No ALS project configured")
      )
    end)
  end)

  if os.getenv("ADA_LS_TEST_MODE") then
    describe("_check_executable", function()
      it("returns true and reports ok when found", function()
        vim.fn.executable = stub.new().returns(1)
        vim.fn.system = stub.new().returns("gprbuild 24.0.0\n")

        local result = health._check_executable("gprbuild")

        assert.is_true(result)
        assert.stub(vim.health.ok).was_called()
        local call_args = vim.health.ok.calls[1].vals
        assert.matches("gprbuild", call_args[1])
        assert.matches("24.0.0", call_args[1])
      end)

      it(
        "returns false and errors when required executable not found",
        function()
          vim.fn.executable = stub.new().returns(0)

          local result = health._check_executable("gprbuild")

          assert.is_false(result)
          assert.stub(vim.health.error).was_called()
          local call_args = vim.health.error.calls[1].vals
          assert.matches("gprbuild", call_args[1])
        end
      )

      it(
        "returns false and warns when optional executable not found",
        function()
          vim.fn.executable = stub.new().returns(0)

          local result =
            health._check_executable("gnatprove", { optional = true })

          assert.is_false(result)
          assert.stub(vim.health.warn).was_called()
          local call_args = vim.health.warn.calls[1].vals
          assert.matches("gnatprove", call_args[1])
        end
      )

      it("uses custom version_arg when provided", function()
        vim.fn.executable = stub.new().returns(1)
        vim.fn.system = stub.new().returns("custom version 1.0\n")

        health._check_executable("my_tool", { version_arg = "-v" })

        assert.stub(vim.fn.system).was_called()
        local call_args = vim.fn.system.calls[1].vals
        assert.matches("-v", call_args[1])
      end)

      it("uses default advice when not provided", function()
        vim.fn.executable = stub.new().returns(0)

        health._check_executable("missing_tool")

        local call_args = vim.health.error.calls[1]
        local advice = call_args.vals[2]
        assert.is_table(advice)
        assert.matches("package manager", advice[1])
      end)
    end)

    describe("_check_lsp_client", function()
      it("returns true and client when ada_ls is running", function()
        local mock_client = {
          name = "ada_ls",
          config = { root_dir = "/project/root" },
        }
        vim.lsp.get_clients = stub.new().returns({ mock_client })

        local ok, client = health._check_lsp_client()

        assert.is_true(ok)
        assert.equals(mock_client, client)
        assert.stub(vim.health.ok).was_called()
      end)

      it("reports 'unknown' when root_dir is nil", function()
        local mock_client = { name = "ada_ls", config = {} }
        vim.lsp.get_clients = stub.new().returns({ mock_client })

        health._check_lsp_client()

        local call_args = vim.health.ok.calls[1].vals
        assert.matches("unknown", call_args[1])
      end)

      it("returns false when no ada_ls client", function()
        vim.lsp.get_clients = stub.new().returns({})

        local ok, client = health._check_lsp_client()

        assert.is_false(ok)
        assert.is_nil(client)
        assert.stub(vim.health.error).was_called()
      end)
    end)

    describe("_check_project_file", function()
      it("reports info when no buffer loaded", function()
        rawset(vim.api, "nvim_buf_get_name", stub.new().returns(""))

        health._check_project_file()

        assert.stub(vim.health.info).was_called()
        local call_args = vim.health.info.calls[1].vals
        assert.matches("No file loaded", call_args[1])
      end)

      it("reports ok when .als.json found with project file", function()
        rawset(
          vim.api,
          "nvim_buf_get_name",
          stub.new().returns("/project/main.adb")
        )
        common.setup_utils_mock({ conf_file = "/project/.als.json" })
        rawset(package.loaded, "ada_ls.project", {
          decode_json_config = function()
            return "/project/test.gpr", "", {}
          end,
        })

        health._check_project_file()

        assert.is_true(
          common.find_stub_call(vim.health.ok, "Configuration file found")
        )
        assert.is_true(
          common.find_stub_call(vim.health.ok, "Project file found")
        )
      end)

      it("reports warn when .als.json not found", function()
        rawset(
          vim.api,
          "nvim_buf_get_name",
          stub.new().returns("/project/main.adb")
        )
        common.setup_utils_mock()

        health._check_project_file()

        assert.is_true(
          common.find_stub_call(vim.health.warn, "Configuration file not found")
        )
      end)

      it("reports warn when project file not in config", function()
        rawset(
          vim.api,
          "nvim_buf_get_name",
          stub.new().returns("/project/main.adb")
        )
        common.setup_utils_mock({ conf_file = "/project/.als.json" })
        rawset(package.loaded, "ada_ls.project", {
          decode_json_config = function()
            return nil, nil, nil
          end,
        })

        health._check_project_file()

        assert.is_true(common.find_stub_call(vim.health.warn, "not configured"))
      end)
    end)

    describe("_check_config", function()
      it("reports info when spark.config fails to load", function()
        rawset(package.loaded, "ada_ls.spark.config", nil)
        rawset(package.preload, "ada_ls.spark.config", function()
          error("module not found")
        end)

        health._check_config()

        assert.stub(vim.health.info).was_called()
        local call_args = vim.health.info.calls[1].vals
        assert.matches("Using default configuration", call_args[1])
      end)

      it("reports ok when proof_level is valid", function()
        rawset(package.loaded, "ada_ls.spark.config", {
          get = function()
            return { proof_level = 2, options = { 1, 3 } }
          end,
        })

        health._check_config()

        assert.is_true(
          common.find_stub_call(vim.health.ok, "Configuration is valid")
        )
      end)

      it("reports error when proof_level is invalid", function()
        rawset(package.loaded, "ada_ls.spark.config", {
          get = function()
            return { proof_level = "bad", options = {} }
          end,
        })

        health._check_config()

        assert.is_true(
          common.find_stub_call(vim.health.error, "invalid proof_level")
        )
      end)
    end)
  end
end)
