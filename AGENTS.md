# AGENTS.md - ada_ls.nvim

## Project Overview

Neovim plugin (Lua) providing Ada Language Server (ALS) integration. Manages
`.gpr` project files, configures `gprbuild` as `:make`, offers a Telescope
picker for GPR files, exposes LSP commands, and integrates GNATprove (SPARK).

Requires Neovim >= 0.11 (developed and tested on 0.12). Optional deps: `nvim-notify`, `telescope.nvim`.

## Directory Layout

```
lua/ada_ls/
  init.lua             -- entry point, setup() with LspAttach autocmd
  gprtools.lua         -- gprbuild/gprclean integration, makeprg/errorformat
  lsp_cmd.lua          -- LSP request/command wrappers for ALS
  lspconfig.lua        -- nvim-lspconfig integration helpers
  project.lua          -- project file management, Telescope picker, config I/O
  refactoring.lua      -- refactoring command handlers (parameter changes, etc.)
  utils.lua            -- notification helpers, LSP client caching, buffer utils
  health.lua           -- :checkhealth provider
  vscode_capabilities.json -- VS Code-compatible LSP client capabilities
  spark/               -- GNATprove (SPARK) integration
    init.lua            -- prove project/file, state persistence
    config.lua          -- proof levels, option definitions, validation
    ui.lua              -- floating window option picker
  project_view/        -- Project View (ALS 2026.3+) integration
    init.lua            -- public API, view options state, backend dispatch
    data.lua            -- fetch/parse/cache ALS project view response
    telescope.lua       -- Telescope pickers for files/projects
    tree.lua            -- builtin tree buffer rendering, keymaps
    neo_tree/           -- neo-tree integration (optional backend)
      init.lua          -- neo-tree source registration
      commands.lua      -- neo-tree commands (open, refresh, etc.)
      components.lua    -- neo-tree custom component renderers
      items.lua         -- transform ALS data to neo-tree nodes
  snippets/            -- VS Code-compatible Ada/GPR snippets (JSON)
plugin/ada_ls.lua      -- :Als user command with subcommands
ftdetect/gpr.lua       -- registers .gpr filetype
after/ftplugin/ada.lua -- removes default Ada keymaps
after/ftplugin/gpr.lua -- treesitter + LSP for .gpr files
spec/                  -- busted tests (*_spec.lua)
  helpers/common.lua   -- shared test utilities (vim mocks, cleanup)
  fixtures/            -- test fixture files (e.g. als_config.json)
doc/                   -- vimdoc
```

## Build / Lint / Test Commands

No build step required (pure Lua plugin).

### Formatting (StyLua)

```bash
stylua lua/ plugin/ after/ spec/      # format all Lua files
stylua --check lua/ plugin/ after/    # check without modifying
```

### Linting (Luacheck)

```bash
luacheck lua/ plugin/ after/ spec/    # lint all Lua files
luacheck lua/ada_ls/project.lua       # lint a single file
```

### Test Build Requirements

The test infrastructure requires:
- **Lua >= 5.1** - Language runtime
- **luarocks** - Package manager for test dependencies
- **lua-filesystem (lfs)** - Required prerequisite for telescope.nvim and neo-tree.nvim
- **busted** - Test framework
- **nlua** - Neovim Lua interpreter for vim.* API access in tests
- **LuaCov** - Coverage measurement

Install on Ubuntu:
```bash
sudo apt-get install lua-filesystem
sudo luarocks install busted nlua luacov
```

Or via package manager on other systems. The CI workflow (`.github/workflows/ci.yml`) installs these automatically.

**CI Pinned Versions**: For reproducibility, the CI workflow pins dependency versions:
- **LuaCov 0.16.0**
- **Busted 2.2.0**

These are the tested and stable versions used in the CI environment. Local development can use any compatible version.

**Important**: `nlua` requires Neovim to be installed in `$PATH`. If installation fails
or busted complains it can't find `nlua`, ensure Neovim is available: `nvim --version`

### Testing (Busted + nlua)

Tests use `nlua` (Neovim Lua interpreter) to access `vim.*` APIs in tests. Coverage
via LuaCov. Test files live in `spec/` and end with `_spec.lua`. CI enforces **85% coverage**.

**Quick Reference - Three test commands:**

```bash
# 1. Single file (fast iteration, ~1-2 sec)
ADA_LS_TEST_MODE=1 busted spec/utils_spec.lua

# 2. All Tier 1 tests (pre-commit, ~10 sec)
ADA_LS_TEST_MODE=1 busted -c

# 3. Full suite with Tier 2 (pre-push, ~11 sec, simulates CI)
bash scripts/run-tests.sh
```

**Coverage workflow**: Coverage data accumulates across runs. Always clean before
measuring to get accurate results:

```bash
rm -f luacov.stats.out luacov.report.out   # clean previous data
ADA_LS_TEST_MODE=1 busted                   # run all tests
luacov                                       # generate report
cat luacov.report.out | grep "^Total"        # check total coverage
```

## Test Environment Setup

The test infrastructure uses several sophisticated techniques to ensure test
isolation and handle optional dependencies cleanly:

### `.busted` Configuration

- **Lua interpreter**: `nlua` (embedded Neovim) to access `vim.*` APIs in tests
- **Module paths**: `.busted` config adds `lua/?.lua` and `spec/?.lua` to LUA_PATH
- **Optional test deps**: `nlua`-compiled modules available at `.busted-test-env/` if present
- **Coverage**: LuaCov enabled by default in `.busted` (see `.luacov` for config)

### Optional Dependencies & Tier Testing

The test suite runs in two tiers based on available dependencies:

- **Tier 1 (always runs)**: Mock-based tests for core functionality
  - Tests are gated with `if os.getenv("ADA_LS_TEST_MODE") then` blocks in specs
  - Plain `busted` (no env var) runs only ungated tests (~247)
  - `ADA_LS_TEST_MODE=1 busted` runs all tests including gated ones (~509 total)
  - Achieves ~85% coverage (acceptable for CI)
  - **vim.schedule mock** (lines 253-258 in common.lua) enables neo-tree backend tests to run synchronously
  
- **Tier 2 (when deps available)**: Integration tests with real libraries
  - `scripts/run-tests.sh` attempts to install `telescope.nvim` and `neo-tree.nvim` into `.busted-test-env/`
  - If installation succeeds (30 sec timeout per package), Tier 2 tests run
  - **Full test count: 518 tests** (509 Tier 1 gated + ~9 Tier 2)
  - `.busted-test-env/` is **auto-cleaned on exit** (success or failure)
  - **vim.schedule mock enables neo-tree tests**: The mock in `setup_vim_globals` executes
    async callbacks immediately, allowing neo-tree backend tests to pass in the synchronous
    nlua/busted environment instead of hanging.

### Running Tests Locally

**Three commands for different purposes:**

```bash
# 1. Development iteration (fastest, single file)
ADA_LS_TEST_MODE=1 busted spec/utils_spec.lua       # single file
ADA_LS_TEST_MODE=1 busted --filter "notify"         # matching pattern

# 2. Pre-commit check (fast, catches errors before commit)
ADA_LS_TEST_MODE=1 busted -c                         # all 509 tests (Tier 1 + gated)

# 3. Pre-push verification (slow, simulates full CI)
bash scripts/run-tests.sh                            # all 518 tests (Tier 1 + Tier 2, like CI)
```

**Which to use:**
- **Single file** (`ADA_LS_TEST_MODE=1 busted spec/file.lua`): Fast feedback during development
- **Pre-commit** (`ADA_LS_TEST_MODE=1 busted -c`): Catch errors before committing; runs 509 tests in ~10 sec
- **Pre-push** (`bash scripts/run-tests.sh`): Full suite before pushing to main; runs 518 tests in ~11 sec (same as CI)

**Important**: Always set `ADA_LS_TEST_MODE=1` when running busted directly.
Without it, tests that conditionally expose private functions will fail (error: "attempt to call field (a nil value)").

### Test Coverage Workflow

Coverage data accumulates across runs. Always clean before measuring:

```bash
rm -f luacov.stats.out luacov.report.out   # clear previous data
ADA_LS_TEST_MODE=1 busted                   # run tests
luacov                                       # generate report
cat luacov.report.out | grep "^Total"        # inspect total coverage
```

Or use `bash scripts/run-tests.sh` which does this automatically.

**Test helpers** (`spec/helpers/common.lua`):

**Core utilities:**
- `common.cleanup_packages()` -- clears `package.loaded`/`preload` for all
  ada_ls modules; call in `before_each`/`after_each`
- `common.setup_vim_globals(api, fn, other)` -- mocks all `vim.*` APIs via
  `rawset` to avoid triggering Neovim's lazy-load metamethods
- `vim.schedule` mock in `setup_vim_globals` -- executes fn() immediately, enabling async tests
  to run synchronously
- `vim.fn.stdpath` mock -- returns test paths for config/data/cache/state queries
- `vim.hl.highlight` mock -- required for telescope integration tests
- `common.create_lsp_client(overrides)` -- mock LSP client with stubs
- `common.setup_lsp_client(client)` -- wires mock into `vim.lsp.get_clients`

**LSP & Symbol utilities:**
- `common.symbol(name, start_line, end_line, start_char)` -- creates mock LSP symbol
- `common.mock_symbols(children)` -- wraps symbols in expected response format
- `common.setup_lsp_cmd_project_view_mock(response, err)` -- mock lsp_cmd with project view

**File & Project utilities:**
- `common.fixture_path(name)` -- returns `"spec/fixtures/" .. name`
- `common.create_temp_file(content, ext)` -- create temp file, returns path + cleanup fn
- `common.setup_utils_mock(opts)` -- mock `ada_ls.utils` with `conf_file`/`server_project`

**SPARK-specific utilities:**
- `common.setup_spark_ui_mocks()` -- all vim mocks for spark/ui tests, returns captured keymaps
- `common.setup_spark_mock(opts)` -- mock `ada_ls.spark` with `proof_level`/`options`

**Project View utilities:**
- `common.create_project_view_response(opts)` -- creates mock ALS project view response
- `common.find_stub_call(stub, pattern)` -- search stub calls for Lua pattern match

**Tier 2 integration test helpers** (for tests using real Telescope/Neo-tree):
- `common.has_telescope()` -- returns boolean, checks if telescope.nvim is available
- `common.has_neo_tree()` -- returns boolean, checks if neo-tree.nvim is available
- `common.has_telescope_full_environment()` -- checks if telescope.previewers and pickers available
- `common.has_neo_tree_full_environment()` -- checks if neo-tree full environment available
- `common.require_optional(module_name)` -- safely require a module, returns (ok, result) tuple

### Test Mocking Pattern - Stubs vs. Manual Mocks

The test suite uses two mocking patterns depending on test requirements:

**Older pattern (stub-based)**:
```lua
local tree = require("ada_ls.project_view.tree")
stub(tree, "is_open").returns(false)
stub(tree, "refresh")
```

**Newer pattern (pre-mocked `package.loaded`)**:
```lua
rawset(package.loaded, "ada_ls.project_view.tree", {
  is_open = function() return false end,
  refresh = function() end,
})
local tree = require("ada_ls.project_view.tree")
```

**When to use which:**
- **Stubs**: For testing behavior of functions that are already loaded (composition/interaction tests)
- **Pre-mocked modules**: For testing initialization logic or backend detection (modules that make decisions based on what they can load)

**Example**: In `project_view_spec.lua`, tests that verify backend detection (builtin vs. neo-tree)
pre-mock the module before requiring it. This ensures the module initialization sees the mocked
state. Post-requiring stubs don't affect initialization decisions already made.

**Preference in new tests**: Pre-mocked `package.loaded` is more robust for this codebase's
architecture because it tests the full initialization path, not just post-load behavior.

### Test Gating Coherence Pattern

**Core principle: Test availability must match function availability.**

The project gates test-only functions in production code with `if os.getenv("ADA_LS_TEST_MODE")`:

```lua
-- lua/ada_ls/project_view/init.lua
if os.getenv("ADA_LS_TEST_MODE") then
  function M.set_neo_tree_available_fn(fn)
    neo_tree_available_fn = fn
  end
end
```

**Any test calling a gated function must also be gated:**

```lua
-- spec/project_view_spec.lua - CORRECT
if os.getenv("ADA_LS_TEST_MODE") then
  it("uses builtin backend when neo-tree not available", function()
    project_view.set_neo_tree_available_fn(function() return false end)
    -- ...
  end)
end

-- spec/project_view_spec.lua - WRONG (will error without ADA_LS_TEST_MODE)
it("uses builtin backend when neo-tree not available", function()
  project_view.set_neo_tree_available_fn(function() return false end)  -- nil function!
  -- ...
end)
```

**Why this matters:**
- Plain `busted` (without ADA_LS_TEST_MODE) will error if tests call gated functions
- Gated tests disappear from `busted -c` output (expected behavior)
- `ADA_LS_TEST_MODE=1 busted` runs all tests including gated ones
- Coherence prevents "attempt to call nil function" errors

## Common Mistakes

Mistakes agents commonly make when working on this repo:

### Testing & Environment (most critical)

- **Forgot `ADA_LS_TEST_MODE=1`**: When running `busted` directly (not via
  `scripts/run-tests.sh`), **always set `ADA_LS_TEST_MODE=1`** or tests that
  depend on exposed private functions will fail with "attempt to call field (a nil value)".
  This is non-negotiable when using the quick commands like `ADA_LS_TEST_MODE=1 busted spec/file.lua`.

- **Test gating coherence required**: If a test calls a function that's only exported
  when `ADA_LS_TEST_MODE=1`, the test MUST also be gated:
  ```lua
  -- CORRECT: Test and function availability match
  if os.getenv("ADA_LS_TEST_MODE") then
    it("uses builtin backend", function()
      project_view.set_neo_tree_available_fn(function() return false end)
      -- ...
    end)
  end

  -- WRONG: Function is gated but test is not
  it("uses builtin backend", function()
    project_view.set_neo_tree_available_fn(function() return false end)  -- nil!
    -- ...
  end)
  ```
  Plain `busted` (without ADA_LS_TEST_MODE) will error on the gated function.
  Gated tests correctly disappear from `busted -c` output (expected behavior).

- **Coverage accumulates**: Coverage data from `luacov.stats.out` and
  `luacov.report.out` accumulates across runs. Before measuring, always clean:
  ```bash
  rm -f luacov.stats.out luacov.report.out
  ```
  Unlike `.busted-test-env/`, coverage data is **NOT auto-cleaned** — you must
  clean it manually. Coverage artifacts from prior runs will pollute your results.

- **Never modify `.busted-test-env/`**: This directory is created and destroyed
  by `scripts/run-tests.sh` on every run. It's in `.gitignore` for a reason.
  Never commit it or any files inside it. If you see it locally, it will be
  auto-cleaned on the next `run-tests.sh` execution.

### Test Runner Choice

Choose the right command for your task (don't skip steps):

| Task | Command | Time | When |
|------|---------|------|------|
| Single file dev iteration | `ADA_LS_TEST_MODE=1 busted spec/file.lua` | ~1-2 sec | Quick feedback during development |
| Pre-commit verification | `ADA_LS_TEST_MODE=1 busted -c` | ~10 sec | Before committing; runs all 509 Tier 1 + gated tests |
| Pre-push full suite | `bash scripts/run-tests.sh` | ~11 sec | Before pushing to main; runs all 518 tests (Tier 1 + Tier 2), same as CI |

### Configuration & Environment

- **LUA_PATH not set**: When tests run via `scripts/run-tests.sh`, the script
  sets `LUAROCKS_CONFIG`, `LUA_PATH`, and `LUA_CPATH` if optional dependencies
  are available. Running busted directly won't have these (which is fine for
  Tier 1 tests, but Tier 2 tests will fail).

### Code Quality & Linting

- **Luacheck warnings**: ALL code (production and test) must have zero Luacheck warnings.
  In tests with intentionally unused function parameters (mock definitions matching real
  signatures), use the underscore prefix convention: `function(_name, _opts)`. All declared
  variables must be used; remove unused ones or add assertions to verify they're set.

## Commit Convention

**IMPORTANT: Never commit, amend, push, or create PRs without explicit user
confirmation.** Always show the planned changes and wait for approval.

Conventional commits enforced by commitizen. Format: `type: short description`

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`, `style`, `perf`

Examples: `feat: Add clean subcommand`, `fix: return nil if no project found`

**AI-generated commits**: Append `Generated by AI (Claude)` as the last line of
the commit message body.

## Code Style Guidelines

### Formatting (StyLua - .stylua.toml)

- **Indent:** 2 spaces (no tabs)
- **Line width:** 80 columns
- **Quotes:** prefer double quotes
- **Line endings:** Unix (LF)

### Module Pattern

```lua
local M = {}
-- module contents
return M
```

Module-level state in `M` fields. Private state uses file-scope `local` vars.

### Naming Conventions

| Element             | Convention   | Example                                |
|---------------------|--------------|----------------------------------------|
| Functions/Variables | `snake_case` | `M.pick_gpr_file`, `prj_file`         |
| Module filenames    | `snake_case` | `lsp_cmd.lua`, `utils.lua`            |
| JSON config keys    | `camelCase`  | `"projectFile"`, `"scenarioVariables"` |
| Autocommand groups  | `PascalCase` | `"AdaLsSetup"`, `"AdaLsMakeprg"`      |
| User commands       | `PascalCase` | `"Als"`                                |

### Imports / Requires

- **Prefer lazy inline requires** for cross-module and optional dependencies:
  ```lua
  require("ada_ls.utils").get_conf_file()
  ```
- File-scope caching acceptable when a module is used heavily:
  ```lua
  local utils = require("ada_ls.utils")
  ```
- Never `require` optional dependencies (telescope, notify) at file scope;
  always require inline or guard with `pcall`.

### Type Annotations

Use LuaLS annotations for public APIs: `---@class`, `---@type`, `---@param`,
`---@return`. See `plugin/ada_ls.lua` for examples.

### Error Handling

- Use `vim.notify_once(msg, vim.log.levels.WARN/ERROR)` for user-facing errors
- Use `require("ada_ls.utils").notify()` for `nvim-notify` integration
- Return `nil, "error description"` tuples from fallible functions (see
  `lsp_cmd.lua`)
- Guard with nil checks and early returns: `if client == nil then return end`
- Use `pcall` only for truly optional operations
- Do NOT use `assert()` or `error()` -- fail gracefully with notifications

### Plugin Load Guard

The plugin entry point (`plugin/ada_ls.lua`) must use:

```lua
if vim.g.loaded_ada_ls then return end
vim.g.loaded_ada_ls = true
```

### Neovim API Preferences

- `vim.fs.find`, `vim.fs.dirname`, `vim.fs.basename` for filesystem
- `vim.lsp.get_clients()` (NOT deprecated `get_active_clients()`)
- `vim.json.encode` / `vim.json.decode` for JSON
- `vim.uri_from_bufnr` / `vim.uri_to_fname` for URI conversions
- `vim.iter()` for functional iteration
- `vim.islist()` to check if table is a list
- `vim.api.nvim_create_autocmd` / `nvim_create_augroup` for autocommands
- `vim.api.nvim_create_user_command` for user commands
- Standard Lua `io.open` / `io.lines` for file I/O

### Luacheck (.luacheckrc)

`vim` is a read-only global; `vim.g`, `vim.o`, `vim.bo`, `vim.lsp` are
writable. No other globals permitted. All variables must be `local`. Spec files
additionally allow busted globals (`describe`, `it`, `assert`, `stub`, etc.).

## CI / Branching / Releases

### Continuous Integration

**Job pipeline** (sequential, must all pass):
1. **Format check** (StyLua) - `stylua --check lua/ plugin/ after/ spec/`
2. **Code quality** (Luacheck) - `luacheck lua/ plugin/ after/ spec/`
3. **Test matrix** (parallel across Neovim versions):
   - Neovim stable
   - Neovim nightly
   - Each runs: `bash scripts/run-tests.sh` with `ADA_LS_TEST_MODE=1`
4. **Coverage report** - Verifies 85% threshold on stable coverage artifact

**Pre-commit hooks** (enforced locally via `.pre-commit-config.yaml`):
- **commitizen** - Validates commit messages (conventional commits)
- **StyLua** - Auto-formats Lua code before commit
- **Luacheck** - Lints Lua code (fails commit if issues found)

### Branches & Releases

- **Branches**: `main` (releases), `dev` (development)
- **Changelog**: Auto-updated via `.cz.yaml` config on version bumps
- **Package**: `ada_ls.nvim-scm-1.rockspec` (LuaRocks package definition)
- **Releases**: Automated via `release.yml` and `pre-release.yml` workflows
