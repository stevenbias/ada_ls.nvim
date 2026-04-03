vim.treesitter.language.register("ada", "gpr")
vim.treesitter.start()

vim.lsp.start({
  name = "ada_ls",
  cmd = { "ada_language_server", "--language-gpr" },
  filetypes = { "gpr" },
})
