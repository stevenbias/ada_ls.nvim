# AGENTS.md - ada_ls.nvim

## Project Overview

Neovim plugin (Lua) providing Ada Language Server (ALS) integration. Manages
`.gpr` project files, configures `gprbuild` as `:make`, offers a Telescope
picker for GPR files, exposes LSP commands, and integrates GNATprove (SPARK).

Requires Neovim >= 0.11. Optional deps: `nvim-notify`, `telescope.nvim`.

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
  spark/               -- GNATprove (SPARK) integration
    init.lua            -- prove project/file, state persistence
    config.lua          -- proof levels, option definitions, validation
    ui.lua              -- floating window option picker
  project_view/        -- Project View (ALS 2026.3+) integration
    init.lua            -- public API, view options state
    data.lua            -- fetch/parse/cache ALS project view response
    telescope.lua       -- Telescope pickers for files/projects
    tree.lua            -- tree buffer rendering, keymaps, expand/collapse
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

### Testing (Busted + nlua)

```bash
busted                                # run all tests with coverage
busted spec/some_spec.lua             # run a single test file
busted --filter "pattern"             # run tests matching a description
```

Uses `nlua` as interpreter so `vim.*` APIs are available. Coverage via LuaCov.
Test files live in `spec/` and end with `_spec.lua`. CI enforces **85% coverage**.

**Coverage workflow**: Coverage data accumulates across runs. Always clean before
measuring to get accurate results:

```bash
rm -f luacov.stats.out luacov.report.out   # clean previous data
ADA_LS_TEST_MODE=1 busted                   # run all tests
luacov                                       # generate report
cat luacov.report.out | grep "^Total"        # check total coverage
```

**ADA_LS_TEST_MODE**: Set `ADA_LS_TEST_MODE=1` when running tests. Source
modules conditionally expose private functions (prefixed `_`) for testing:

```lua
-- In source: exposes locals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._private_fn = private_fn
end

-- In spec: guards tests that depend on exposed internals
if os.getenv("ADA_LS_TEST_MODE") then
  describe("_private_fn", function() ... end)
end
```

**Test helpers** (`spec/helpers/common.lua`):
- `common.cleanup_packages()` -- clears `package.loaded`/`preload` for all
  ada_ls modules; call in `before_each`/`after_each`
- `common.setup_vim_globals(api, fn, other)` -- mocks all `vim.*` APIs via
  `rawset` to avoid triggering Neovim's lazy-load metamethods
- `common.setup_vim_health()` -- mocks `vim.health.*` functions for health check tests
- `common.create_lsp_client(overrides)` -- mock LSP client with stubs
- `common.setup_lsp_client(client)` -- wires mock into `vim.lsp.get_clients`
- `common.fixture_path(name)` -- returns `"spec/fixtures/" .. name`
- `common.symbol(name, start_line, end_line, start_char)` -- creates mock LSP symbol
- `common.mock_symbols(children)` -- wraps symbols in expected response format
- `common.setup_utils_mock(opts)` -- mock `ada_ls.utils` with `conf_file`/`server_project`
- `common.find_stub_call(stub, pattern)` -- search stub calls for Lua pattern match
- `common.create_temp_file(content, ext)` -- create temp file, returns path + cleanup fn
- `common.setup_spark_ui_mocks()` -- all vim mocks for spark/ui tests, returns captured keymaps
- `common.setup_spark_mock(opts)` -- mock `ada_ls.spark` with `proof_level`/`options`
- `common.create_project_view_response(opts)` -- creates mock ALS project view response
- `common.setup_lsp_cmd_project_view_mock(response, err)` -- mock lsp_cmd with project view

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

## CI / Branching

- **CI**: format check (StyLua) -> lint (Luacheck) -> test matrix (Neovim
  stable + nightly) -> coverage report (85% minimum)
- **Branches**: `main` (releases), `dev` (development)
- **Releases**: automated via `release.yml` and `pre-release.yml` workflows
- **Package**: `ada_ls.nvim-scm-1.rockspec` (LuaRocks)
