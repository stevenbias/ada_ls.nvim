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

local function clear()
  require("ada_ls.project").clear()
  require("ada_ls.utils").clear()

  vim.g.loaded_ada_ls = nil
  for name, _ in pairs(package.loaded) do
    if name:match("^ada_ls") then
      package.loaded[name] = nil
    end
  end
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
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    pattern = {
      "*.ad[bs]",
    },
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "ada" then
        clear()
      end
    end,
  })
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._open_qf_on_make = open_qf_on_make
  M._clear = clear
end

return M
