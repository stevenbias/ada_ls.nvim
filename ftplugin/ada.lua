vim.api.nvim_create_autocmd("LspAttach", {
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
