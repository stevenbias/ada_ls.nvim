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

local function on_als_attach()
  print("Attach")
  require("ada_ls.project").setup()
  open_qf_on_make()
  vim.g.loaded_ada_ls = true
end

local function on_als_detach()
  clear()
end

function M.setup(opts)
  require("ada_ls.spark").setup(opts)

  vim.lsp.config("ada", {
    cmd = { "ada_language_server" },
    filetypes = { "ada" },
    on_attach = on_als_attach,
    on_detach = on_als_detach,
    root_dir = function(bufnr, on_dir)
      on_dir(
        vim.fs.root(
          bufnr,
          { ".als.json", "Makefile", ".git", "alire.toml", "*.gpr", "*.adc" }
        )
      )
    end,
  })
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._open_qf_on_make = open_qf_on_make
  M._clear = clear
end

return M
