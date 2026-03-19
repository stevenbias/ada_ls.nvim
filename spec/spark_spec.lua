-- Tests for lua/ada_ls/spark.lua
local stub = require("luassert.stub")
local common = require("spec.helpers.common")

-- Helper to setup spark module with mocked dependencies
local function setup_spark_module()
  -- Add spark to cleanup
  package.preload["ada_ls.spark"] = nil
  package.loaded["ada_ls.spark"] = nil
  return require("ada_ls.spark")
end

describe("ada_ls.spark", function()
  local spark
  local test_state_file

  before_each(function()
    common.cleanup_packages()
    package.preload["ada_ls.spark"] = nil
    package.loaded["ada_ls.spark"] = nil

    common.setup_vim_globals(nil, {
      getcwd = function()
        return "/project/root"
      end,
      expand = function(arg)
        if arg == "%:t" then
          return "main.adb"
        end
        return "/test/path/file.adb"
      end,
      line = function(arg)
        if arg == "." then
          return 10
        elseif arg == "'<" then
          return 5
        elseif arg == "'>" then
          return 15
        end
        return 1
      end,
      stdpath = function(what)
        if what == "data" then
          return "/tmp/nvim-test-data"
        end
        return "/tmp"
      end,
      setqflist = stub.new(),
      len = function(t)
        return #t
      end,
    })

    -- Mock vim.system for async operations
    rawset(vim, "system", stub.new())
    rawset(vim, "schedule", function(fn)
      fn()
    end)
    rawset(vim, "deepcopy", function(t)
      if type(t) ~= "table" then
        return t
      end
      local copy = {}
      for k, v in pairs(t) do
        copy[k] = vim.deepcopy(v)
      end
      return copy
    end)
    rawset(vim, "list_extend", function(dst, src)
      for _, v in ipairs(src) do
        table.insert(dst, v)
      end
      return dst
    end)
    rawset(vim, "uri_to_fname", function(uri)
      return uri:gsub("^file://", "")
    end)
    rawset(vim, "tbl_deep_extend", function(_, t1, t2)
      local result = {}
      for k, v in pairs(t1) do
        result[k] = v
      end
      for k, v in pairs(t2) do
        result[k] = v
      end
      return result
    end)
    rawset(vim, "tbl_contains", function(t, val)
      for _, v in ipairs(t) do
        if v == val then
          return true
        end
      end
      return false
    end)

    -- Create temp directory for test state file
    test_state_file = "/tmp/nvim-test-data/ada_ls_spark.json"

    spark = setup_spark_module()
    spark.config = require("ada_ls.spark.config")
    spark.setup()
  end)

  after_each(function()
    common.cleanup_packages()
    package.preload["ada_ls.spark"] = nil
    package.loaded["ada_ls.spark"] = nil
    -- Clean up test file
    os.remove(test_state_file)
  end)

  describe("option definitions", function()
    it("has 5 proof levels", function()
      assert.equals(5, #spark.config.PROOF_LEVELS)
    end)

    it("proof levels have correct structure", function()
      for i, level in ipairs(spark.config.PROOF_LEVELS) do
        assert.is_string(level.label)
        assert.is_string(level.value)
        assert.matches("--level=" .. (i - 1), level.value)
      end
    end)

    it("has 5 additional options", function()
      assert.equals(5, #spark.config.SPARK_OPTIONS)
    end)

    it("additional options have correct structure", function()
      for _, opt in ipairs(spark.config.SPARK_OPTIONS) do
        assert.is_string(opt.id)
        assert.is_string(opt.label)
        assert.is_string(opt.value)
        assert.is_nil(opt.default)
      end
    end)

    it("multiprocessing is first option", function()
      assert.equals("multiprocessing", spark.config.SPARK_OPTIONS[1].id)
    end)

    it("defaults has level 0 and multiprocessing", function()
      assert.equals(0, spark.opts.proof_level)
      assert.same({ 1 }, spark.opts.options)
    end)
  end)

  -- Private function tests - only run in test mode
  if os.getenv("ADA_LS_TEST_MODE") then
    describe("persistence", function()
      describe("_get_state_file", function()
        it("returns path in stdpath data directory", function()
          local path = spark._get_state_file()
          assert.matches("ada_ls_spark.json", path)
          assert.matches("/tmp/nvim%-test%-data", path)
        end)
      end)

      describe("_get_project_key", function()
        it("returns LSP root_dir when available", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          local key = spark._get_project_key()
          assert.equals("/my/project", key)
        end)

        it("falls back to getcwd when no LSP client", function()
          vim.lsp.get_clients = stub.new().returns({})
          package.loaded["ada_ls.utils"] = nil

          local key = spark._get_project_key()
          assert.equals("/project/root", key)
        end)
      end)

      describe("_load_state", function()
        it("returns defaults when no state file exists", function()
          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when state file is invalid JSON", function()
          -- Create invalid JSON file
          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write("not valid json {{{")
          f:close()

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when project key not in file", function()
          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write(
            '{ "/other/project": { "proof_level": 2, "options": [1, 2] } }'
          )
          f:close()

          -- Mock JSON decode to return the actual content
          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return {
                ["/other/project"] = { proof_level = 2, options = { 1, 2 } },
              }
            end,
          })

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns saved state for current project", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write(
            '{ "/my/project": { "proof_level": 3, "options": [1, 3, 5] } }'
          )
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return {
                ["/my/project"] = { proof_level = 3, options = { 1, 3, 5 } },
              }
            end,
          })

          local state = spark._load_state()
          assert.equals(3, state.proof_level)
          assert.same({ 1, 3, 5 }, state.options)
        end)
      end)

      describe("_save_state", function()
        it("creates state file if not exists", function()
          os.remove(test_state_file)
          os.execute("mkdir -p /tmp/nvim-test-data")

          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          spark._save_state({ proof_level = 2, options = { 1, 4 } })

          local f = io.open(test_state_file, "r")
          assert.is_not_nil(f)
          if f then
            f:close()
          end
        end)

        it("preserves other project settings when saving", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write('{ "/other/project": { "proof_level": 4, "options": [2] } }')
          f:close()

          -- Mock JSON decode/encode properly
          local stored_data =
            { ["/other/project"] = { proof_level = 4, options = { 2 } } }
          rawset(vim, "json", {
            decode = function()
              return stored_data
            end,
            encode = function(val)
              stored_data = val
              return "{}"
            end,
          })

          spark._save_state({ proof_level = 1, options = { 1 } })

          -- Verify other project still exists
          assert.is_not_nil(stored_data["/other/project"])
          assert.equals(4, stored_data["/other/project"].proof_level)
        end)
      end)
    end)

    describe("argument building", function()
      describe("_state_to_args", function()
        it("returns level argument for proof_level", function()
          local args = spark._state_to_args({ proof_level = 2, options = {} })
          assert.same({ "--level=2" }, args)
        end)

        it("returns option arguments for selected options", function()
          local args =
            spark._state_to_args({ proof_level = 0, options = { 1, 3 } })
          assert.equals(3, #args)
          assert.equals("--level=0", args[1])
          assert.equals("-j0", args[2])
          assert.equals("--report=all", args[3])
        end)

        it("handles all options selected", function()
          local args = spark._state_to_args({
            proof_level = 4,
            options = { 1, 2, 3, 4, 5 },
          })
          assert.equals(6, #args) -- 1 level + 5 options
          assert.equals("--level=4", args[1])
        end)

        it("handles empty options", function()
          local args = spark._state_to_args({ proof_level = 1, options = {} })
          assert.same({ "--level=1" }, args)
        end)
      end)

      describe("_build_args", function()
        it("includes --output=oneline for all prove kinds", function()
          local state = { proof_level = 0, options = { 1 } }
          local args = spark._build_args("prove_project", state)
          assert.equals("--output=oneline", args[1])
        end)

        it("builds correct args for prove_project", function()
          local state = { proof_level = 0, options = {} }
          local args = spark._build_args("prove_project", state)
          assert.equals(2, #args) -- output + level
        end)

        it("builds correct args for prove_file", function()
          local state = { proof_level = 1, options = {} }
          local args = spark._build_args("prove_file", state)
          -- output, level, -u, filename
          assert.equals(4, #args)
          assert.equals("-u", args[3])
          assert.equals("main.adb", args[4])
        end)

        it("builds correct args for clean", function()
          local args = spark._build_args("clean", nil)
          assert.same({ "--clean" }, args)
        end)
      end)
    end)

    describe("quickfix parsing", function()
      describe("_populate_quickfix", function()
        it("parses gnatprove output format", function()
          local output = [[
main.adb:10:5: medium: overflow check might fail
main.adb:20:10: info: assertion proved
other.ads:5:1: error: cannot prove precondition
]]
          spark._populate_quickfix(output, "/project")

          assert.stub(vim.fn.setqflist).was_called()
          local call_args = vim.fn.setqflist.calls[1].vals
          local qf_opts = call_args[3]

          assert.equals("GNATprove", qf_opts.title)
          assert.equals(3, #qf_opts.items)

          -- Check first item
          assert.equals("/project/main.adb", qf_opts.items[1].filename)
          assert.equals(10, qf_opts.items[1].lnum)
          assert.equals(5, qf_opts.items[1].col)
          assert.matches("%[medium%]", qf_opts.items[1].text)

          -- Check error type
          assert.equals("E", qf_opts.items[3].type)
        end)

        it("handles absolute paths in output", function()
          local output = "/abs/path/file.adb:1:1: info: proved\n"
          spark._populate_quickfix(output, "/project")

          local call_args = vim.fn.setqflist.calls[1].vals
          local qf_opts = call_args[3]

          assert.equals("/abs/path/file.adb", qf_opts.items[1].filename)
        end)

        it("opens quickfix when items present", function()
          local output = "main.adb:1:1: info: test\n"
          spark._populate_quickfix(output, "/project")

          assert.stub(vim.cmd).was_called_with("copen")
        end)

        it("closes quickfix when no items", function()
          spark._populate_quickfix("", "/project")

          assert.stub(vim.cmd).was_called_with("cclose")
        end)
      end)
    end)

    describe("ada_ls.spark.config", function()
      local config

      before_each(function()
        common.cleanup_packages()
        package.loaded["ada_ls.spark.config"] = nil
        config = require("ada_ls.spark.config")
      end)

      describe("M.setup", function()
        it("with nil preserves defaults", function()
          config.setup(nil)
          assert.same({ proof_level = 0, options = { 1 } }, config.get())
        end)

        it("with valid proof_level updates config", function()
          config.setup({ proof_level = 3 })
          assert.equals(3, config.get().proof_level)
        end)

        it("with non-numeric proof_level preserves defaults", function()
          config.setup({ proof_level = "invalid" })
          assert.same({ proof_level = 0, options = { 1 } }, config.get())
        end)

        it("with unknown field preserves defaults", function()
          config.setup({ unknown_field = true })
          assert.same({ proof_level = 0, options = { 1 } }, config.get())
        end)

        it("with valid options IDs converts to indices", function()
          config.setup({ options = { "multiprocessing", "no_warnings" } })
          assert.same({ 1, 2 }, config.get().options)
        end)

        it("with invalid option ID preserves defaults", function()
          config.setup({ options = { "invalid_option" } })
          assert.same({ proof_level = 0, options = { 1 } }, config.get())
        end)
      end)

      describe("M._ids_to_opts", function()
        it("converts option IDs to indices", function()
          local result =
            config._ids_to_opts({ "multiprocessing", "report_all" })
          assert.same({ 1, 3 }, result)
        end)

        it("returns empty table for empty input", function()
          local result = config._ids_to_opts({})
          assert.same({}, result)
        end)

        it("handles unknown IDs gracefully", function()
          local result = config._ids_to_opts({ "unknown_id" })
          assert.same({}, result)
        end)
      end)

      describe("M._is_valid", function()
        it("returns true for nil", function()
          assert.is_true(config._is_valid(nil))
        end)

        it("returns true for empty table", function()
          assert.is_true(config._is_valid({}))
        end)

        it("returns false for unknown field", function()
          assert.is_false(config._is_valid({ bad_field = true }))
        end)

        it("returns false for non-numeric proof_level", function()
          assert.is_false(config._is_valid({ proof_level = "bad" }))
        end)
      end)
    end)
  end

  describe("public API", function()
    describe("prove", function()
      it("notifies error when no project file", function()
        vim.lsp.get_clients = stub.new().returns({})

        spark.prove()

        assert.stub(vim.notify).was_called()
        local found_error = false
        for _, call in ipairs(vim.notify.calls) do
          if call.vals[1] and call.vals[1]:match("No project file") then
            found_error = true
            break
          end
        end
        assert.is_true(found_error)
      end)

      it("calls vim.system with gnatprove when project exists", function()
        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request_sync = stub.new().returns({
            result = { "file:///project/root/test.gpr" },
          }),
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.stub(vim.system).was_called()
        local call_args = vim.system.calls[1].vals
        assert.equals("gnatprove", call_args[1][1])
      end)
    end)

    describe("prove_file", function()
      it("includes -u flag and filename in args", function()
        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request_sync = stub.new().returns({
            result = { "file:///project/root/test.gpr" },
          }),
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove_file()

        assert.stub(vim.system).was_called()
        local call_args = vim.system.calls[1].vals
        local cmd = call_args[1]

        -- Find -u flag
        local found_u = false
        local found_filename = false
        for i, arg in ipairs(cmd) do
          if arg == "-u" then
            found_u = true
            if cmd[i + 1] == "main.adb" then
              found_filename = true
            end
          end
        end
        assert.is_true(found_u)
        assert.is_true(found_filename)
      end)
    end)

    describe("clean", function()
      it("calls gnatprove with --clean", function()
        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request_sync = stub.new().returns({
            result = { "file:///project/root/test.gpr" },
          }),
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.clean()

        assert.stub(vim.system).was_called()
        local call_args = vim.system.calls[1].vals
        local cmd = call_args[1]

        local found_clean = false
        for _, arg in ipairs(cmd) do
          if arg == "--clean" then
            found_clean = true
          end
        end
        assert.is_true(found_clean)
      end)
    end)

    describe("select_options", function()
      it("loads spark options via inputlist and floating window", function()
        rawset(vim, "fn", {
          inputlist = stub.new().returns(1),
          expand = function(arg)
            if arg == "%:t" then
              return "main.adb"
            end
            return "/test/path/file.adb"
          end,
          stdpath = function(what)
            if what == "data" then
              return "/tmp/nvim-test-data"
            end
            return "/tmp"
          end,
          len = function(t)
            return #t
          end,
        })
        rawset(vim, "o", {
          lines = 100,
          columns = 200,
        })
        rawset(vim, "api", {
          nvim_create_buf = stub.new().returns(1),
          nvim_buf_set_lines = stub.new(),
          nvim_open_win = stub.new().returns(1),
          nvim_win_set_cursor = stub.new(),
          nvim_create_autocmd = stub.new().returns(1),
          nvim__get_runtime = function()
            return {}
          end,
          nvim_buf_set_keymap = stub.new(),
          nvim_win_close = stub.new(),
        })
        local bo = {}
        setmetatable(bo, {
          __index = function()
            return {}
          end,
          __newindex = function() end,
        })
        rawset(vim, "bo", bo)
        rawset(vim, "keymap", {
          set = stub.new(),
        })

        spark.select_options()

        assert.stub(vim.fn.inputlist).was_called()
      end)
    end)
  end)
end)
