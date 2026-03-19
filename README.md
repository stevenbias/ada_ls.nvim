# ada_ls.nvim

[![CI](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/stevenbias/ada_ls.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.10+-green.svg)](https://neovim.io)

Neovim plugin providing Ada Language Server integration: GPR project management, build commands, and SPARK formal verification.

## Requirements

- **Neovim** >= 0.10
- **[Ada Language Server](https://github.com/AdaCore/ada_language_server)** - Must be configured and running
- **GNAT** - Must be available in `$PATH`
- **[SPARK](https://github.com/AdaCore/spark2014)** - Formal verification tool for Ada (optional)

## Installation

### lazy.nvim

```lua
{
  "stevenbias/ada_ls.nvim",
  ft = { "ada" },
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "rcarriga/nvim-notify",  -- optional, for notifications
  },
  opts = {},
}
```

### vim-plug

```vim
Plug 'nvim-telescope/telescope.nvim'
Plug 'rcarriga/nvim-notify'  " optional
Plug 'stevenbias/ada_ls.nvim'

lua << EOF
require("ada_ls").setup()
EOF
```

## Usage

### Quick Start

1. Open an Ada file in a project
2. Configure Ada Language Server with the correct GPR file
3. Use `:Als build` to compile

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
