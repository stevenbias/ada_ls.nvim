local M = {}

local group = vim.api.nvim_create_augroup("AdaLsSetup", { clear = true })

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

local function on_als_detach()
  clear()
end

local function als_snippets()
  if require("ada_ls.utils").try_require("luasnip") then
    local dirname =
      string.sub(debug.getinfo(1).source, 2, string.len("/init.lua") * -1)
    require("luasnip.loaders.from_vscode").lazy_load({
      paths = { dirname .. "snippets" },
    })
  end
end

function M.setup(opts)
  als_snippets()
  require("ada_ls.spark").setup(opts)

  local lspconfig = require("ada_ls.lspconfig").get()

  vim.lsp.config("ada_ls", lspconfig)

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    pattern = { "*.ad[bs]" },
    callback = on_als_detach,
  })

  vim.lsp.enable("ada_ls")
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._clear = clear
  M._on_als_detach = on_als_detach
  M._als_snippets = als_snippets
end

return M
