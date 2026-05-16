-- Remove useless default keymaps
pcall(vim.keymap.del, "n", "<leader>aj", { buffer = true })
pcall(vim.keymap.del, "i", "<leader>al", { buffer = true })
