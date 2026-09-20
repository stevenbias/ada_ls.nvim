# AGENTS.md - ada_ls.nvim

## Entry Points

- Pure Lua Neovim plugin; no build step.
- `plugin/ada_ls.lua` defines `:Als` and `:Spark` and must keep the standard load guard:
  `if vim.g.loaded_ada_ls then return end`
  `vim.g.loaded_ada_ls = true`
- `lua/ada_ls/init.lua` is the real setup entrypoint: it loads snippets, sets up SPARK and project view, registers LSP config with `vim.lsp.config("ada_ls", ...)`, then enables it with `vim.lsp.enable("ada_ls")`.

## Verification Order

- After Lua edits, run:
  `stylua lua/ plugin/ after/ spec/`
  `luacheck lua/ plugin/ after/ spec/`
- For changes that can affect behavior, tests, helpers, or optional dependency handling, run all three test commands:
  `busted -c`
  `ADA_LS_TEST_MODE=1 busted -c`
  `bash scripts/run-tests.sh`
- For focused iteration on one spec, use `ADA_LS_TEST_MODE=1 busted spec/project_view_spec.lua` or the relevant spec file.

## Test Environment Quirks

- `.busted` uses `nlua` and adds `.busted-test-env/share/lua/5.1` to module lookup paths.
- If `.busted-test-env/` exists, plain `busted` can see optional deps like `neo-tree` and `telescope`. Ungated tests must not assume those plugins are absent.
- `scripts/run-tests.sh` creates `.busted-test-env/`, installs optional deps there, writes coverage files, and removes the test env on exit. Never edit or commit `.busted-test-env/`.
- Coverage accumulates across runs. For manual coverage checks, delete `luacov.stats.out` and `luacov.report.out` first.

## Gated Tests

- Some production modules export test-only helpers only when `ADA_LS_TEST_MODE=1` is set.
- Any spec that calls a gated helper such as `project_view.set_neo_tree_available_fn()` must itself be wrapped in `if os.getenv("ADA_LS_TEST_MODE") then`.
- Ungated tests must not call gated helpers. If they need to control optional dependency behavior, mock the module directly before `require(...)`.

## Project View / Neo-tree

- `lua/ada_ls/project_view/init.lua` decides Neo-tree registration from `require("neo-tree").ensure_config().sources`.
- Tests must mock `ensure_config()`; do not mock `neo-tree.config.sources` anymore.
- Minimal compatible mock shape:
  `package.loaded["neo-tree"] = { ensure_config = function() return { sources = { "filesystem", "ada_project" } } end }`
- For ungated tests that should stay on builtin behavior even when Neo-tree is installed, pre-mock `package.loaded["neo-tree"]` with a non-matching `sources` list before requiring `ada_ls.project_view`.

## Test Helpers

- `spec/helpers/common.lua` is the main test reset/mocking utility.
- Use `common.cleanup_packages()` in `before_each` or `after_each`; it clears `ada_ls.*` modules and `neo-tree`.
- `common.setup_vim_globals()` uses `rawset` to avoid Neovim lazy-load traps and makes `vim.schedule()` run immediately, so async code often behaves synchronously in tests.

## Optional Dependencies

- Optional runtime deps are `telescope.nvim`, `neo-tree.nvim`, `nvim-notify`, and `LuaSnip`.
- Keep optional plugin requires guarded with `pcall(require, ...)` or lazy inline `require(...)`; do not add unconditional file-scope requires for optional plugins.

## CI And Commits

- CI order is format check -> luacheck -> test matrix -> coverage threshold.
- Pre-commit runs `commitizen`, `stylua`, and `luacheck`.
- Commit messages use conventional commits via Commitizen.
