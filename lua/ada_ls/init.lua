local M = {}

local group = vim.api.nvim_create_augroup("AdaLsSetup", { clear = true })

local function open_qf_on_make()
  -- auto-open quickfix only when :make produced entries
  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = group,
    pattern = "make",
    callback = function()
      if #vim.fn.getqflist() > 0 then
        vim.cmd("copen")
      end
    end,
  })
end

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    pattern = {
      "*.ad[bs]",
    },
    callback = function()
      local client = require("ada_ls.utils").get_ada_ls()
      if client ~= nil then
        require("ada_ls.project").setup()
        require("ada_ls.gpr").makeprg_setup()
        open_qf_on_make()
      end
    end,
  })
end

return M
