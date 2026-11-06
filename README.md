# ada_ls.nvim

[![CI](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-green.svg)](https://neovim.io)


**Ada development in Neovim: LSP, build integration, project management, and formal verification—out of the box.**\
[![Watch a one-minute video tour of ada_ls.nvim](https://gitdiagram.com/video-badge.svg)](https://gitdiagram.com/stevenbias/ada_ls.nvim/video)

## What is ada_ls.nvim?

Neovim plugin providing out-of-the-box Ada Language Server integration: GPR
project management, project view, build commands, GPR file support, VS Code-compatible
snippets and SPARK formal verification.

### Demo
[ada_ls.nvim in action](media/ada_ls_als_demo.mp4)

## Quick Start (30 seconds)

1. Install this plugin (see [Installation](#installation) below)
2. Open an Ada file in your project
3. Run `:Als pick_gpr` to select your project's `.gpr` file
4. Run `:Als build` to build
5. Use LSP features normally (hover, goto definition, completions, etc.)

> If you have any issues, you can check if your environment is ready for the plugin with `:Als health` or `:checkhealth ada_ls`

## Features

This plugin goes beyond standard LSP by providing:

- Out-of-the-box ALS configuration (no nvim-lspconfig needed)
- GPR project file support
- Scenario variable management for GPR projects
- gprbuild integration via `:make`
- Project view with optional [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) integration
- Research on project source files via Telescope picker
- SPARK formal verification with gnatprove
- Jump between `.ads` and `.adb` files
- VS Code-equivalent LSP capabilities
    - snippets for Ada and GPR (via LuaSnip)
    - Package body generation and update via LSP code actions

## Requirements

- **Neovim** >= 0.11 (developed and tested on 0.12)
- **[Ada Language Server](https://github.com/AdaCore/ada_language_server)** >= 2027.0 - Must be available in `$PATH`
- **GNAT** (`gprbuild`, `gprclean`) - Must be available in `$PATH`
- **[SPARK](https://github.com/AdaCore/spark2014)** / `gnatprove` - Optional, required only for `:Spark` commands

## Installation

### lazy.nvim

```lua
{
  "stevenbias/ada_ls.nvim",
  ft = { "ada", "gpr" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim",  -- optional, for GPR file picker
    "nvim-neo-tree/neo-tree.nvim",    -- optional, for project view integration with neo-tree
    "rcarriga/nvim-notify",           -- optional, for notifications
    "L3MON4D3/LuaSnip",               -- optional, for snippets
  },
  opts = {},
}
```

With `lazy.nvim`, `opts = {}` automatically calls `require("ada_ls").setup({})`.

### vim-plug

```vim
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-telescope/telescope.nvim'  " optional
Plug 'nvim-neo-tree/neo-tree.nvim'    " optional
Plug 'rcarriga/nvim-notify'           " optional
Plug 'L3MON4D3/LuaSnip'               " optional
Plug 'stevenbias/ada_ls.nvim'

lua << EOF
require("ada_ls").setup()
EOF
```

For plugin managers without automatic `opts` handling, call `require("ada_ls").setup()` manually.

During `setup()`, `ada_ls.nvim` checks whether the Ada Tree-sitter parser is
available. If it is missing and `nvim-treesitter` is installed, the plugin
automatically runs `require("nvim-treesitter").install("ada")`.

## Usage

1. Open an Ada file in your project
2. The plugin configures ALS automatically for Ada buffers
3. Select a GPR project file if the current project is not active yet: `:Als pick_gpr`
4. Build your project: `:Als build`

> If Telescope is installed, `:Als pick_gpr` uses a Telescope picker. Otherwise it falls back to `vim.ui.select()`.

### Commands

#### Ada commands
| Command | Description |
|---------|-------------|
| `:Als build` | Build project with gprbuild |
| `:Als clean` | Clean build artifacts with gprclean |
| `:Als config` | Edit project configuration (.als.json) |
| `:Als edit_gpr` | Open the active GPR project file |
| `:Als format` | Format the current buffer via Neovim LSP formatting |
| `:Als health` | Open `:checkhealth ada_ls` |
| `:Als other` | Go to corresponding .ads/.adb file |
| `:Als pick_gpr` | Select GPR file via Telescope picker or `vim.ui.select()` fallback |

#### Project View and Scenario Variables commands
> requires Ada Language Server 2027.0+

| Command | Description |
|---------|-------------|
| `:Als project_view` | Toggle project tree buffer and reveal current file when opening |
| `:Als project_files` | Select source file via Telescope picker |
| `:Als scenario_variables` | Select and update scenario variables |

##### neo-tree setup
Project View uses the builtin tree by default. To use the neo-tree backend, register the custom source in your neo-tree setup:

```lua
require("neo-tree").setup({
  sources = {
    "filesystem",
    "buffers",
    "git_status",
    "ada_ls.project_view.neo_tree", -- Add this line
  },
})
```

#### Spark commands
| Command | Description |
|---------|-------------|
| `:Spark options` | Set proof level and options |
| `:Spark prove` | Run gnatprove on project |
| `:Spark prove_file` | Run gnatprove on current file |
| `:Spark prove_subprogram` | Run gnatprove on current subprogram |
| `:Spark clean` | Clean proof results |

### Suggested Keymaps

These keymaps are suggested for convenience, but you can configure your own.

#### Ada keymaps
```lua
vim.keymap.set("n", "<leader>ab", "<cmd>Als build<cr>", { desc = "Als Build" })
vim.keymap.set("n", "<leader>ac", "<cmd>Als clean<cr>", { desc = "Als Clean" })
vim.keymap.set("n", "<leader>aj", "<cmd>Als config<cr>", { desc = "Als JSON config" })
vim.keymap.set("n", "<leader>ap", "<cmd>Als edit_gpr<cr>", { desc = "Als edit Project file" })
vim.keymap.set("n", "<leader>ag", "<cmd>Als pick_gpr<cr>", { desc = "Als pick Gpr" })
vim.keymap.set("n", "<leader>ao", "<cmd>Als other<cr>", { desc = "Als Other file" })
vim.keymap.set("n", "<leader>af", "<cmd>Als format<cr>", { desc = "Als Format" })
vim.keymap.set("n", "<leader>as", "<cmd>Als scenario_variables<cr>", { desc = "Als Scenario variables" })
vim.keymap.set("n", "<leader>av", "<cmd>Als project_view<cr>", { desc = "Als project View" })
vim.keymap.set("n", "<leader>al", "<cmd>Als project_files<cr>", { desc = "Als List project files" })
```
#### Spark keymaps
```lua
vim.keymap.set("n", "<leader>sp", "<cmd>Spark prove<cr>", { desc = "Spark prove Project" })
vim.keymap.set("n", "<leader>sf", "<cmd>Spark prove_file<cr>", { desc = "Spark prove File" })
vim.keymap.set("n", "<leader>sc", "<cmd>Spark clean<cr>", { desc = "Spark Clean" })
vim.keymap.set("n", "<leader>so", "<cmd>Spark options<cr>", { desc = "Spark Options" })
vim.keymap.set("n", "<leader>ss", "<cmd>Spark prove_subprogram<cr>", { desc = "Spark prove Subprogram" })
```

### Removed Default Keymaps

This plugin removes the following useless default Ada keymaps:

| Keymap | Mode | Description |
|--------|------|-------------|
| `<leader>aj` | normal, insert | Removed |
| `<leader>al` | normal, insert | Removed |

## GPR File Support

The plugin provides support for GPR project files (`.gpr`):

- `.gpr` files are registered as the `gpr` filetype automatically
- Treesitter highlighting using the Ada parser
- Missing Ada parser is installed automatically through `nvim-treesitter`
  during `setup()`
- A dedicated LSP instance is started with `ada_language_server --language-gpr`

No additional configuration is required beyond having `nvim-treesitter`
installed.

## Project Configuration File

The plugin stores the selected project in `.als.json`, created alongside the
selected GPR file when you use `:Als pick_gpr`.

```json
{
  "projectFile": "my_project.gpr",
  "scenarioVariables": {
    "MODE": "debug"
  }
}
```

When the plugin writes a new `.als.json`, it stores the project filename rather
than an absolute path so the file is easier to share across environments.
Existing configs that already use absolute paths are still supported.

## Snippets

The plugin ships VS Code-compatible snippets for Ada and GPR files, loaded
automatically via LuaSnip's `lazy_load`. If LuaSnip is not installed,
snippets are silently skipped.

## Code Actions

The plugin integrates with ALS code actions to provide:

- **Package body generation**: When editing an Ada specification (`.ads`), ALS
  can generate the corresponding package body (`.adb`) via
  `vim.lsp.buf.code_action()`.
- **Package body update**: When the specification changes, ALS can update the
  existing body to match through the same mechanism.

## Statusline Integration

The plugin exposes a function to get the current GPR project name for Ada
statusline integration:

```lua
-- lualine example
require("lualine").setup({
  sections = {
    lualine_c = {
      {
        function()
          local name = require("ada_ls.utils").get_server_project_name()
          return name and ("GPR: " .. name) or ""
        end,
        cond = function()
          return vim.bo.filetype == "ada" or vim.bo.filetype == "gpr"
        end,
      },
    },
  },
})
```

## Configuration

### Default Configuration

```lua
require("ada_ls").setup({
  project_view = {
    backend = "auto",         -- "auto" | "neo-tree" | "builtin"
    flat_mode = false,        -- Show all projects at root level
    show_object_dirs = false, -- Show object directory nodes
    show_runtime = false,     -- Show runtime project sources
  },
  spark = {
    proof_level = 0,              -- Proof level (0-4)
    options = { "multiprocessing" }, -- Enabled by default
  },
})
```

### Project View Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `backend` | string | `"auto"` | Tree backend: `"auto"`, `"neo-tree"`, or `"builtin"` |
| `flat_mode` | boolean | `false` | Show all projects at root level |
| `show_object_dirs` | boolean | `false` | Show object directory nodes |
| `show_runtime` | boolean | `false` | Show runtime project sources |

When `backend = "auto"`, neo-tree is used only if `ada_ls.project_view.neo_tree`
is registered in neo-tree's `sources` list (check the [neo-tree setup](#neo-tree-setup) section above). Otherwise the builtin project tree
is used.

### SPARK Proof Levels

| Level | Description |
|-------|-------------|
| 0 | Fast, one prover (default) |
| 1 | Fast, most provers |
| 2 | Most provers |
| 3 | Slower, most provers |
| 4 | Slowest, most provers |

### SPARK Options

| Option | Description |
|--------|-------------|
| `multiprocessing` | Enable multiprocessing (-j0) |
| `no_warnings` | Disable warnings (--warnings=off) |
| `report_all` | Report all checks (--report=all) |
| `info` | Output info messages (--info) |
| `proof_warnings` | Enable proof warnings (--proof-warnings=on) |


## Compatibility & Limitations

### Supported Versions

| Component | Versions | Notes |
|-----------|----------|-------|
| Neovim | 0.11, 0.12, nightly | Tested regularly on 0.12 |
| Ada Language Server | 2027.0+ |
| GNAT | 12.0+ | Any recent GNAT version with gprbuild |
| Treesitter Ada parser | Any | Auto-installed if nvim-treesitter is available |

## Related Projects

The Ada community has created several excellent tools for Neovim development. Here's how ada_ls.nvim fits into the ecosystem:

- **[Ada Language Server (ALS)](https://github.com/AdaCore/ada_language_server)** — The core server that ada_ls.nvim wraps
- **[gnattest.nvim](https://github.com/AdaCore/gnattest.nvim)** — Neovim plugin to support [GNATtest](https://github.com/AdaCore/gnattest) for test-driven development
- **[Neovim Best Practices](https://github.com/lumen-oss/nvim-best-practices)** — Plugin development guidelines

### Neovim Ecosystem Integration

These plugins work great alongside ada_ls.nvim:

- **[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)** — File and project picker (optional but recommended)
- **[neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)** — Project view backend (optional, uses builtin tree by default)
- **[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)** — Nvim Treesitter configurations and abstraction layer
- **[LuaSnip](https://github.com/L3MON4D3/LuaSnip)** — Snippet engine (optional, ada_ls.nvim provides VS Code-compatible snippets)
- **[nvim-notify](https://github.com/rcarriga/nvim-notify)** — Enhanced notifications (optional, ada_ls.nvim gracefully degrades to echo)

## License

MIT License - see [LICENSE](LICENSE) for details.
