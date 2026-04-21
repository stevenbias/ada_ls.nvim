# ada_ls.nvim

[![CI](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-green.svg)](https://neovim.io)

Neovim plugin providing out-of-the-box Ada Language Server integration: GPR
project management, build commands, GPR file support, VS Code-compatible
snippets and SPARK formal verification.

## Features

- Out-of-the-box ALS configuration (no nvim-lspconfig needed)
- Automatic GPR project file management
- Telescope picker for GPR file selection
- gprbuild integration via `:make`
- SPARK formal verification with gnatprove
- Jump between `.ads` and `.adb` files
- GPR file support with treesitter highlighting and dedicated LSP
- VS Code-compatible snippets for Ada and GPR (via LuaSnip)
- Package body generation and update via LSP code actions
- VS Code-equivalent LSP capabilities

## Requirements

- **Neovim** >= 0.11 (developed and tested on 0.12)
- **[Ada Language Server](https://github.com/AdaCore/ada_language_server)** - Must be available in `$PATH`
- **GNAT** - Must be available in `$PATH`
- **[SPARK](https://github.com/AdaCore/spark2014)** - Formal verification tool for Ada (optional)

## Installation

### lazy.nvim

```lua
{
  "stevenbias/ada_ls.nvim",
  ft = { "ada", "gpr" },
  dependencies = {
    "nvim-telescope/telescope.nvim",  -- optional, for GPR file picker
    "rcarriga/nvim-notify",           -- optional, for notifications
    "L3MON4D3/LuaSnip",               -- optional, for snippets
  },
  opts = {},
}
```

### vim-plug

```vim
Plug 'nvim-telescope/telescope.nvim'  " optional
Plug 'rcarriga/nvim-notify'           " optional
Plug 'L3MON4D3/LuaSnip'               " optional
Plug 'stevenbias/ada_ls.nvim'

lua << EOF
require("ada_ls").setup()
EOF
```

## Usage

### Quick Start

1. Open an Ada file in your project
2. The plugin auto-detects your project and starts ALS
3. Select a GPR file if not auto-detected: `:Als pick_gpr`
4. Build your project: `:Als build`

### Commands

#### Ada commands
| Command | Description |
|---------|-------------|
| `:Als build` | Build project with gprbuild |
| `:Als clean` | Clean build artifacts with gprclean |
| `:Als config` | Edit project configuration (.als.json) |
| `:Als edit_gpr` | Open project file |
| `:Als other` | Go to corresponding .ads/.adb file |
| `:Als pick_gpr` | Select GPR file via Telescope picker |

#### Spark commands
| Command | Description |
|---------|-------------|
| `:Spark options` | Set proof level and options |
| `:Spark prove` | Run gnatprove on project |
| `:Spark prove_file` | Run gnatprove on current file |
| `:Spark clean` | Clean proof results |

### Suggested Keymaps

#### Ada keymaps
```lua
vim.keymap.set("n", "<leader>ab", "<cmd>Als build<cr>", { desc = "Als build" })
vim.keymap.set("n", "<leader>ac", "<cmd>Als clean<cr>", { desc = "Als clean" })
vim.keymap.set("n", "<leader>aj", "<cmd>Als config<cr>", { desc = "Als JSON config" })
vim.keymap.set("n", "<leader>ap", "<cmd>Als edit_gpr<cr>", { desc = "Als edit project file" })
vim.keymap.set("n", "<leader>ag", "<cmd>Als pick_gpr<cr>", { desc = "Als pick gpr" })
vim.keymap.set("n", "<leader>ao", "<cmd>Als other<cr>", { desc = "Als other file" })
```
#### Spark keymaps
```lua
vim.keymap.set("n", "<leader>sp", "<cmd>Spark prove<cr>", { desc = "Spark prove" })
vim.keymap.set("n", "<leader>sf", "<cmd>Spark prove_file<cr>", { desc = "Spark prove file" })
vim.keymap.set("n", "<leader>sc", "<cmd>Spark clean<cr>", { desc = "Spark clean" })
vim.keymap.set("n", "<leader>so", "<cmd>Spark options<cr>", { desc = "Spark options" })
```

### Removed Default Keymaps

This plugin removes the following useless default Ada keymaps:

| Keymap | Mode | Description |
|--------|------|-------------|
| `<leader>aj` | insert, normal | Removed |
| `<leader>al` | insert | Removed |

## GPR File Support

The plugin provides support for GPR project files (`.gpr`):

- `.gpr` files are registered as the `gpr` filetype automatically
- Treesitter highlighting using the Ada parser
- A dedicated LSP instance is started with `ada_language_server --language-gpr`

No additional configuration is required.

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

## Configuration

### Default Configuration

```lua
require("ada_ls").setup({
  spark = {
    proof_level = 0,              -- Proof level (0-4)
    options = { "multiprocessing" }, -- Enabled by default
  }
})
```

### Root Directory Detection

The plugin determines the project root by searching upward for the following
markers:

`.als.json`, `Makefile`, `.git`, `alire.toml`, `*.gpr`, `*.adc`

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

## License

MIT License - see [LICENSE](LICENSE) for details.
