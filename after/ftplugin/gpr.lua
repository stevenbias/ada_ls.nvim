vim.treesitter.language.register("ada", "gpr")
vim.treesitter.start()

vim.lsp.start({
  cmd = { "ada_language_server", "--language-gpr" },
  filetypes = { "gpr" },
})
