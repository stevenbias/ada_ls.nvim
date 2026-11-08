-- Remove useless default keymaps
pcall(vim.keymap.del, "n", "<leader>al", { buffer = true })
pcall(vim.keymap.del, { "n", "i" }, "<leader>aj", { buffer = true })
pcall(vim.keymap.del, "i", "<leader>al", { buffer = true })
