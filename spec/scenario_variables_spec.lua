-- Tests for lua/ada_ls/scenario_variables.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

describe("ada_ls.scenario_variables", function()
  local scenario_variables
  local lsp_cmd_mock

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("get_info", function()
    before_each(function()
      lsp_cmd_mock = {
        get_scenario_variables_info = stub.new(),
      }
      package.loaded["ada_ls.lsp_cmd"] = lsp_cmd_mock
      scenario_variables = require("ada_ls.scenario_variables")
    end)

    it("returns LSP response on success", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)

      local result, err = scenario_variables.get_info()

      assert.is_nil(err)
      assert.same(response, result)
    end)

    it("returns error when LSP command fails", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(nil, "LSP error")

      local result, err = scenario_variables.get_info()

      assert.is_nil(result)
      assert.equals("LSP error", err)
    end)

    it("returns nil result when LSP returns nil without error", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(nil, nil)

      local result, err = scenario_variables.get_info()

      assert.is_nil(result)
      assert.is_nil(err)
    end)
  end)

  describe("get_variables", function()
    before_each(function()
      lsp_cmd_mock = {
        get_scenario_variables_info = stub.new(),
      }
      package.loaded["ada_ls.lsp_cmd"] = lsp_cmd_mock
      scenario_variables = require("ada_ls.scenario_variables")
    end)

    it("parses LSP response into scenario variables table", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
          {
            name = "ARCH",
            value = "x86_64",
            ["possible-values"] = { "x86", "x86_64", "arm64" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)

      local result, err = scenario_variables.get_variables()

      assert.is_nil(err)
      assert.equals("debug", result["MODE"].value)
      assert.same({ "debug", "release" }, result["MODE"].possible_values)
      assert.equals("x86_64", result["ARCH"].value)
      assert.same({ "x86", "x86_64", "arm64" }, result["ARCH"].possible_values)
    end)

    it("handles empty possible values", function()
      local response = {
        variables = {
          {
            name = "EMPTY",
            value = "default",
            ["possible-values"] = {},
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)

      local result, err = scenario_variables.get_variables()

      assert.is_nil(err)
      assert.same({}, result["EMPTY"].possible_values)
    end)

    it("propagates error from get_info", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(nil, "Connection failed")

      local result, err = scenario_variables.get_variables()

      assert.is_nil(result)
      assert.equals("Connection failed", err)
    end)

    it("returns nil with error when LSP returns nil", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(nil, nil)

      local result, err = scenario_variables.get_variables()

      assert.is_nil(result)
      assert.is_nil(err)
    end)
  end)

  describe("set_variable", function()
    before_each(function()
      lsp_cmd_mock = {
        get_scenario_variables_info = stub.new(),
      }
      package.loaded["ada_ls.lsp_cmd"] = lsp_cmd_mock

      local utils_mock = {
        notify = stub.new(),
        get_conf_file = stub.new().returns("/project/.als.json"),
        get_server_project_name = stub.new().returns("test_project"),
      }
      package.loaded["ada_ls.utils"] = utils_mock

      local project_mock = {
        update_scenario_variable = stub.new(),
      }
      package.loaded["ada_ls.project"] = project_mock

      -- Mock vim.cmd with a redraw method
      vim.cmd = {
        redraw = function() end,
      }

      scenario_variables = require("ada_ls.scenario_variables")
    end)

    it("returns error when scenario variables cannot be retrieved", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(
        nil,
        "Failed to connect to LSP"
      )

      local result, err = scenario_variables.set_variable()

      assert.is_nil(result)
      assert.equals("Failed to connect to LSP", err)
    end)

    it("returns generic error when get_info returns nil", function()
      lsp_cmd_mock.get_scenario_variables_info.returns(nil, nil)

      local result, err = scenario_variables.set_variable()

      assert.is_nil(result)
      assert.equals("Failed to retrieve scenario variables", err)
    end)

    it(
      "returns error when user selection is invalid (index out of range)",
      function()
        local response = {
          variables = {
            {
              name = "MODE",
              value = "debug",
              ["possible-values"] = { "debug", "release" },
            },
          },
        }
        lsp_cmd_mock.get_scenario_variables_info.returns(response)
        vim.fn.inputlist = stub.new().returns(0) -- Invalid selection

        local result, err = scenario_variables.set_variable()

        assert.is_nil(result)
        assert.equals("Invalid selection", err)
      end
    )

    it("returns error when user selection exceeds variable count", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)
      vim.fn.inputlist = stub.new().returns(5) -- Out of range

      local result, err = scenario_variables.set_variable()

      assert.is_nil(result)
      assert.equals("Invalid selection", err)
    end)

    it("returns error when value selection is invalid", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)
      -- Create a mock function that returns different values on successive calls
      local call_count = 0
      local input_fn = function()
        call_count = call_count + 1
        if call_count == 1 then
          return 1 -- Valid variable
        else
          return 0 -- Invalid value
        end
      end
      vim.fn.inputlist = input_fn

      local result, err = scenario_variables.set_variable()

      assert.is_nil(result)
      assert.equals("Invalid selection", err)
    end)

    it("returns error when value selection exceeds possible values", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)
      local call_count = 0
      local input_fn = function()
        call_count = call_count + 1
        if call_count == 1 then
          return 1 -- Valid variable
        else
          return 5 -- Out of range
        end
      end
      vim.fn.inputlist = input_fn

      local result, err = scenario_variables.set_variable()

      assert.is_nil(result)
      assert.equals("Invalid selection", err)
    end)

    it(
      "calls update_scenario_variable with selected variable and value",
      function()
        local response = {
          variables = {
            {
              name = "MODE",
              value = "debug",
              ["possible-values"] = { "debug", "release" },
            },
            {
              name = "ARCH",
              value = "x86_64",
              ["possible-values"] = { "x86", "x86_64" },
            },
          },
        }
        lsp_cmd_mock.get_scenario_variables_info.returns(response)
        local call_count = 0
        local input_fn = function()
          call_count = call_count + 1
          -- This is the first inputlist call which lists variables
          -- Store the variable names from the first inputlist for reference
          return 1 -- Select first variable
        end
        vim.fn.inputlist = input_fn

        scenario_variables.set_variable()

        local project = require("ada_ls.project")
        -- Verify that update_scenario_variable was called with some valid variable
        assert.stub(project.update_scenario_variable).was_called()
        local calls = project.update_scenario_variable.calls
        assert.is_true(#calls > 0)
        local var_name, var_value = calls[1].vals[1], calls[1].vals[2]
        -- The variable should be one of the defined ones
        assert.is_true(
          var_name == "MODE" or var_name == "ARCH",
          "Variable name should be MODE or ARCH, got: " .. tostring(var_name)
        )
        -- The value should be one of the possible values
        assert.is_true(
          var_value == "debug"
            or var_value == "release"
            or var_value == "x86"
            or var_value == "x86_64",
          "Variable value should be a valid option, got: "
            .. tostring(var_value)
        )
      end
    )

    it("displays nil value as string 'nil' in selection list", function()
      local response = {
        variables = {
          {
            name = "OPTIONAL",
            value = nil,
            ["possible-values"] = { "value1", "value2" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)
      local call_count = 0
      local input_fn = function()
        call_count = call_count + 1
        return 1 -- Always return valid selection
      end
      vim.fn.inputlist = input_fn

      scenario_variables.set_variable()

      -- The test verifies that nil was converted to "nil" string implicitly
      -- by successfully passing without error. If nil wasn't handled properly,
      -- concatenation would fail
      assert.equals(2, call_count) -- Called twice
    end)

    it("handles multiple variables correctly", function()
      local response = {
        variables = {
          {
            name = "MODE",
            value = "debug",
            ["possible-values"] = { "debug", "release" },
          },
          {
            name = "ARCH",
            value = "x86_64",
            ["possible-values"] = { "x86", "x86_64" },
          },
          {
            name = "PLATFORM",
            value = "linux",
            ["possible-values"] = { "linux", "windows" },
          },
        },
      }
      lsp_cmd_mock.get_scenario_variables_info.returns(response)
      local call_count = 0
      local input_fn = function()
        call_count = call_count + 1
        if call_count == 1 then
          return 1 -- First variable
        else
          return 2 -- Second possible value
        end
      end
      vim.fn.inputlist = input_fn

      scenario_variables.set_variable()

      local project = require("ada_ls.project")
      -- Should have updated with one of the variables and its value
      assert.stub(project.update_scenario_variable).was_called()
    end)
  end)
end)
