vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("AdaLsSetup", { clear = true }),
  pattern = {
    "*.ad[bs]",
  },
  callback = function()
    local client = require("ada_ls.utils").get_ada_ls()
    if client ~= nil then
      require("ada_ls.project").setup()
    end
  end,
})
