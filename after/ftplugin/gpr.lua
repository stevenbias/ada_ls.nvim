vim.treesitter.language.register("ada", "gpr")
vim.treesitter.start()

vim.lsp.start({
  name = "gpr_ls",
  cmd = { "ada_language_server", "--language-gpr" },
  filetypes = { "gpr" },
  on_attach = function()
    require("ada_ls.project").setup()
  end,
  root_dir = vim.fs.dirname(vim.fs.abspath(vim.fn.expand("%"))),
})
