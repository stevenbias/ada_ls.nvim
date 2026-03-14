-- Remove useless default keymaps
pcall(vim.keymap.del, { "i", "n" }, "<leader>aj", { buffer = true })
pcall(vim.keymap.del, "i", "<leader>al", { buffer = true })
