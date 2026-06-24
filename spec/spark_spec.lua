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

        it("returns defaults when proof_level is string", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write('{ "/my/project": { "proof_level": "2", "options": [1] } }')
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return {
                ["/my/project"] = { proof_level = "2", options = { 1 } },
              }
            end,
          })

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when options is not a list", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write(
            '{ "/my/project": { "proof_level": 2, "options": { "foo": "bar" } } }'
          )
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return {
                ["/my/project"] = {
                  proof_level = 2,
                  options = { foo = "bar" },
                },
              }
            end,
          })
          rawset(vim, "islist", function(t)
            return type(t) == "table" and t[1] ~= nil
          end)

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when proof_level is nil", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write('{ "/my_project": { "options": [1, 2] } }')
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return { ["/my_project"] = { options = { 1, 2 } } }
            end,
          })

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when options is nil", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write('{ "/my_project": { "proof_level": 2 } }')
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return { ["/my_project"] = { proof_level = 2 } }
            end,
          })

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        it("returns defaults when decoded value is not a table", function()
          local mock_client =
            common.create_lsp_client({ root_dir = "/my/project" })
          common.setup_lsp_client(mock_client)
          package.loaded["ada_ls.utils"] = nil

          os.execute("mkdir -p /tmp/nvim-test-data")
          local f = io.open(test_state_file, "w")
          f:write('"just a string"')
          f:close()

          rawset(vim, "json", {
            encode = vim.json.encode,
            decode = function()
              return "just a string"
            end,
          })

          local state = spark._load_state()
          assert.same(spark.opts, state)
        end)

        after_each(function()
          vim.json = nil
          vim.islist = nil
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

        it("ignores out-of-range option index", function()
          local args = spark._state_to_args({
            proof_level = 0,
            options = { 1, 99 },
          })
          assert.equals(2, #args)
          assert.equals("--level=0", args[1])
          assert.equals("-j0", args[2])
        end)

        it("handles nil options in state", function()
          local args = spark._state_to_args({ proof_level = 2, options = nil })
          assert.same({ "--level=2" }, args)
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
        config.setup({})
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

        it("returns true with valid string option id", function()
          assert.is_true(config._is_valid({ options = { "multiprocessing" } }))
        end)

        it("returns true with valid numeric index", function()
          assert.is_true(config._is_valid({ options = { 1 } }))
        end)

        it("returns false for invalid option index", function()
          assert.is_false(config._is_valid({ options = { 99 } }))
        end)

        it("returns false for invalid string option", function()
          assert.is_false(config._is_valid({ options = { "bad_option" } }))
        end)
      end)

      describe("_opts_to_ids", function()
        it("returns id for valid index", function()
          assert.equals("multiprocessing", config._opts_to_ids(1))
        end)

        it("returns nil for out of range index", function()
          assert.is_nil(config._opts_to_ids(99))
        end)
      end)
    end)

    describe("ada_ls.spark.ui", function()
      local ui

      before_each(function()
        common.cleanup_packages()
        package.loaded["ada_ls.spark.ui"] = nil
      end)

      describe("_pick_proof_level", function()
        before_each(function()
          ui = require("ada_ls.spark.ui")
          rawset(vim, "fn", {
            inputlist = stub.new().returns(0),
            len = function(t)
              return #t
            end,
          })
        end)

        after_each(function()
          vim.fn = nil
        end)

        it("calls callback with selected index", function()
          local result = nil
          ui._pick_proof_level(0, function(r)
            result = r
          end)
          assert.equals(0, result)
        end)

        it("uses current_level when inputlist returns negative", function()
          vim.fn.inputlist = stub.new().returns(-1)
          local result = nil
          ui._pick_proof_level(2, function(r)
            result = r
          end)
          assert.equals(2, result)
        end)

        it("uses current_level when inputlist returns out of range", function()
          vim.fn.inputlist = stub.new().returns(99)
          local result = nil
          ui._pick_proof_level(1, function(r)
            result = r
          end)
          assert.equals(1, result)
        end)

        it("builds items with correct prefix for current level", function()
          vim.fn.inputlist = stub.new().returns(2)
          ui._pick_proof_level(2, function() end)
          assert.stub(vim.fn.inputlist).was_called()
          local call_args = vim.fn.inputlist.calls[1].vals
          assert.is_table(call_args[1])
          assert.equals("Select proof level:", call_args[1][1])
          local items = call_args[1][2]
          assert.matches("%● 2 ", items)
        end)
      end)

      describe("_pick_additional_options", function()
        local captured_keymaps

        before_each(function()
          captured_keymaps = {}
          rawset(vim, "o", { lines = 100, columns = 200 })
          rawset(vim, "api", {
            nvim_create_buf = stub.new().returns(1),
            nvim_buf_set_lines = stub.new(),
            nvim_open_win = stub.new().returns(2),
            nvim_win_set_cursor = stub.new(),
            nvim_win_get_cursor = stub.new().returns({ 3, 0 }),
            nvim_win_close = stub.new(),
            nvim_create_autocmd = stub.new(),
            nvim__get_runtime = function()
              return {}
            end,
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
            set = function(_, key, fn, _)
              captured_keymaps[key] = fn
            end,
          })
          ui = require("ada_ls.spark.ui")
        end)

        it("creates floating buffer with correct content", function()
          ui._pick_additional_options({ 1 }, function() end)

          assert.stub(vim.api.nvim_create_buf).was_called()
          assert.stub(vim.api.nvim_buf_set_lines).was_called()
          assert.stub(vim.api.nvim_open_win).was_called()
        end)

        it("sets up keymaps for Tab, CR, q, Esc", function()
          ui._pick_additional_options({ 1 }, function() end)

          assert.is_function(captured_keymaps["<Tab>"])
          assert.is_function(captured_keymaps["<CR>"])
          assert.is_function(captured_keymaps["q"])
          assert.is_function(captured_keymaps["<Esc>"])
        end)

        it("calls callback with selected indices on confirm", function()
          local result = nil
          ui._pick_additional_options({ 1, 3 }, function(r)
            result = r
          end)

          -- Toggle option 2 (row 4 = header + option 2)
          vim.api.nvim_win_get_cursor = stub.new().returns({ 4, 0 })
          captured_keymaps["<Tab>"]()

          -- Confirm
          captured_keymaps["<CR>"]()

          assert.same({ 1, 2, 3 }, result)
        end)

        it("calls callback with nil on cancel via q", function()
          local result = "not_called"
          ui._pick_additional_options({ 1 }, function(r)
            result = r
          end)

          captured_keymaps["q"]()

          assert.is_nil(result)
        end)

        it("calls callback with nil on cancel via Esc", function()
          local result = "not_called"
          ui._pick_additional_options({ 1 }, function(r)
            result = r
          end)

          captured_keymaps["<Esc>"]()

          assert.is_nil(result)
        end)

        it("tracks current_options in selected state", function()
          local result = nil
          ui._pick_additional_options({ 2, 4 }, function(r)
            result = r
          end)

          captured_keymaps["<CR>"]()

          assert.same({ 2, 4 }, result)
        end)

        it("returns empty when no options selected", function()
          local result = nil
          ui._pick_additional_options({}, function(r)
            result = r
          end)

          captured_keymaps["<CR>"]()

          assert.same({}, result)
        end)
      end)

      describe("ask_spark_options", function()
        local spark_ui
        local spark_mock
        local captured

        before_each(function()
          captured = common.setup_spark_ui_mocks()
          spark_mock = common.setup_spark_mock()
          package.loaded["ada_ls.spark.ui"] = nil
          spark_ui = require("ada_ls.spark.ui")
        end)

        it("returns nil when level selection cancelled", function()
          rawset(vim.fn, "inputlist", function()
            return -1
          end)
          spark_mock.load_state = function()
            return { proof_level = nil, options = {} }
          end

          local result = "not_called"
          spark_ui.ask_spark_options(function(r)
            result = r
          end)

          assert.is_nil(result)
        end)

        it("returns nil when options selection cancelled", function()
          local result = "not_called"
          spark_ui.ask_spark_options(function(r)
            result = r
          end)

          rawset(vim, "keymap", {
            set = function(_, key, fn, _)
              if key == "q" then
                fn()
              end
            end,
          })
          package.loaded["ada_ls.spark.ui"] = nil
          spark_ui = require("ada_ls.spark.ui")

          spark_ui.ask_spark_options(function(r)
            result = r
          end)

          assert.is_nil(result)
        end)

        it("saves state and calls callback on successful selection", function()
          local result = nil

          spark_ui.ask_spark_options(function(r)
            result = r
          end)

          if captured.cr_callback then
            captured.cr_callback()
          end

          assert.stub(spark_mock.save_state).was_called()
          assert.is_table(result)
          assert.is_number(result.proof_level)
        end)
      end)
    end)
  end

  describe("public API", function()
    describe("prove", function()
      it("notifies error when no project file", function()
        vim.lsp.get_clients = stub.new().returns({})

        spark.prove()

        assert.is_true(common.find_stub_call(vim.notify, "No project file"))
      end)

      it("calls vim.system with gnatprove when project exists", function()
        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
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
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
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
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
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

    describe("prove_subp", function()
      it("includes --limit-subp flag in args", function()
        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        -- Must set up FULL utils mock BEFORE spark module loads
        -- Should return mock_client when get_ada_ls is called
        rawset(package.loaded, "ada_ls.utils", {
          notify = function() end,
          get_ada_ls = function()
            return mock_client
          end,
          get_subprogram_name_from_line = function()
            return "My_Procedure",
              {
                start = { line = 10, character = 1 },
                end_ = { line = 25, character = 1 },
              }
          end,
        })

        spark.prove_subp()

        assert.stub(vim.system).was_called()
        local call_args = vim.system.calls[1].vals
        local cmd = call_args[1]

        local found_limit = false
        for _, arg in ipairs(cmd) do
          if arg:match("^--limit%-subp=") then
            found_limit = true
          end
        end
        assert.is_true(found_limit)
      end)
    end)

    describe("gnatprove async callbacks", function()
      it("notifies success when gnatprove returns code 0", function()
        local captured_callback
        rawset(vim, "system", function(_cmd, _opts, callback)
          captured_callback = callback
        end)

        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.is_function(captured_callback)
        captured_callback({ code = 0, stdout = "", stderr = "" })

        local found = false
        for _, call in ipairs(vim.notify.calls) do
          if call.vals[1] and call.vals[1]:match("completed successfully") then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)

      it("notifies warning when gnatprove returns non-zero", function()
        local captured_callback
        rawset(vim, "system", function(_cmd, _opts, callback)
          captured_callback = callback
        end)

        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.is_function(captured_callback)
        captured_callback({ code = 1, stdout = "", stderr = "error" })

        local found = false
        for _, call in ipairs(vim.notify.calls) do
          if call.vals[1] and call.vals[1]:match("completed with errors") then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)

      it("populates quickfix from gnatprove output on callback", function()
        local captured_callback
        rawset(vim, "system", function(_cmd, _opts, callback)
          captured_callback = callback
        end)

        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.is_function(captured_callback)
        captured_callback({
          code = 1,
          stdout = "main.adb:10:5: medium: overflow check\n",
          stderr = "",
        })

        assert.stub(vim.fn.setqflist).was_called()
      end)

      it("closes quickfix when no gnatprove output", function()
        local captured_callback
        rawset(vim, "system", function(_cmd, _opts, callback)
          captured_callback = callback
        end)

        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.is_function(captured_callback)
        captured_callback({ code = 0, stdout = "", stderr = "" })

        assert.stub(vim.cmd).was_called_with("cclose")
      end)

      it("calls vim.notify via stdout callback", function()
        local captured_opts
        rawset(vim, "system", function(_cmd, opts, _callback)
          captured_opts = opts
        end)

        local mock_client = common.create_lsp_client({
          root_dir = "/project/root",
          request = function(_self, _method, _params, callback)
            callback(nil, "file:///project/root/test.gpr")
          end,
        })
        common.setup_lsp_client(mock_client)
        package.loaded["ada_ls.utils"] = nil
        package.loaded["ada_ls.lsp_cmd"] = nil

        spark.prove()

        assert.is_table(captured_opts)
        assert.is_function(captured_opts.stdout)

        captured_opts.stdout()

        assert.stub(vim.notify).was_called()
        local found = false
        for _, call in ipairs(vim.notify.calls) do
          if call.vals[1] and call.vals[1]:match("running") then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)
    end)

    describe("setup", function()
      it("calls spark.config.setup when spark key present in opts", function()
        package.loaded["ada_ls.spark"] = nil
        package.loaded["ada_ls.spark.config"] = nil

        local fresh_spark = require("ada_ls.spark")
        fresh_spark.setup({ spark = { proof_level = 3 } })

        assert.equals(3, fresh_spark.opts.proof_level)
      end)

      it("uses defaults when spark key is nil", function()
        package.loaded["ada_ls.spark"] = nil
        package.loaded["ada_ls.spark.config"] = nil

        local fresh_spark = require("ada_ls.spark")
        fresh_spark.setup({})

        assert.equals(0, fresh_spark.opts.proof_level)
      end)

      it("uses defaults when opts is nil", function()
        package.loaded["ada_ls.spark"] = nil
        package.loaded["ada_ls.spark.config"] = nil

        local fresh_spark = require("ada_ls.spark")
        fresh_spark.setup(nil)

        assert.equals(0, fresh_spark.opts.proof_level)
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

      it("notifies proof level when state is returned", function()
        rawset(package.loaded, "ada_ls.spark.ui", {
          ask_spark_options = function(callback)
            callback({ proof_level = 2, options = {} })
          end,
        })
        rawset(package.loaded, "ada_ls.spark.config", {
          SPARK_OPTIONS = {},
        })
        local notify_stub = stub.new()
        rawset(package.loaded, "ada_ls.utils", {
          notify = notify_stub,
        })

        package.loaded["ada_ls.spark"] = nil
        local fresh_spark = require("ada_ls.spark")
        fresh_spark.select_options()

        assert.is_true(
          common.find_stub_call(notify_stub, "SPARK Level saved: 2")
        )
      end)

      it("notifies options when state includes options", function()
        rawset(package.loaded, "ada_ls.spark.ui", {
          ask_spark_options = function(callback)
            callback({ proof_level = 1, options = { 1, 2 } })
          end,
        })
        rawset(package.loaded, "ada_ls.spark.config", {
          SPARK_OPTIONS = {
            { id = "multiprocessing" },
            { id = "no_warnings" },
          },
        })
        local notify_stub = stub.new()
        rawset(package.loaded, "ada_ls.utils", {
          notify = notify_stub,
        })

        package.loaded["ada_ls.spark"] = nil
        local fresh_spark = require("ada_ls.spark")
        fresh_spark.select_options()

        assert.is_true(
          common.find_stub_call(notify_stub, "SPARK options saved:")
        )
      end)

      it("does nothing when callback returns nil", function()
        rawset(package.loaded, "ada_ls.spark.ui", {
          ask_spark_options = function(callback)
            callback(nil)
          end,
        })
        local notify_stub = stub.new()
        rawset(package.loaded, "ada_ls.utils", {
          notify = notify_stub,
        })

        package.loaded["ada_ls.spark"] = nil
        local fresh_spark = require("ada_ls.spark")
        fresh_spark.select_options()

        assert.stub(notify_stub).was_not_called()
      end)
    end)
  end)
end)
