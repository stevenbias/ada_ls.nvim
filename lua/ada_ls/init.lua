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

local function als_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  -- From: https://github.com/romgrk/fzy-lua-native/blob/master/lua/init.lua
  local dirname =
    string.sub(debug.getinfo(1).source, 2, string.len("/init.lua") * -1)

  local file = io.open(dirname .. "vscode_capabilities.json", "r")
  if not file then
    return capabilities
  end
  local raw = file:read("*a")
  file:close()

  local ok, json_capabilities = pcall(vim.json.decode, raw)
  if not ok then
    return capabilities
  end

  capabilities = vim.tbl_deep_extend("force", json_capabilities, capabilities)
  return capabilities
end

local function on_als_attach()
  require("ada_ls.project").setup()
  open_qf_on_make()
  vim.g.loaded_ada_ls = true
end

local function on_als_detach()
  clear()
end

local function als_handlers()
  local original_apply_edit = vim.lsp.handlers["workspace/applyEdit"]

  vim.lsp.handlers["workspace/applyEdit"] = function(err, result, ctx, config)
    -- ALS sends AnnotatedTextEdit without the required changeAnnotations
    -- map, causing Neovim >= 0.12 to fail. Remove the capability so ALS
    -- sends plain TextEdit instead.
    if result and result.edit and not result.edit.changeAnnotations then
      if result.edit.documentChanges then
        for _, change in ipairs(result.edit.documentChanges) do
          if change.edits then
            for _, text_edits in ipairs(change.edits) do
              text_edits.annotationId = nil
            end
          end
        end
      end
    end

    if result and result.edit and result.edit.documentChanges then
      local filename = ""
      for _, change in ipairs(result.edit.documentChanges) do
        if change.kind == "create" then
          require("ada_ls.utils").reset_als_client()
          filename = vim.uri_to_fname(change.uri)
          vim.schedule(function()
            vim.cmd.edit(filename)
            -- Fix last empty line that provokes bug on updating package body
            if vim.fn.getline("$") == "" then
              vim.cmd.normal("G")
              vim.cmd.normal("dd")
              vim.cmd.normal("gg")
            end
          end)
        elseif change.textDocument and filename == "" then
          vim.schedule(function()
            vim.cmd.edit(vim.uri_to_fname(change.textDocument.uri))
          end)
        end
      end
    end

    local response = original_apply_edit(err, result, ctx, config)
    return response
  end
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

  vim.lsp.config("ada_ls", {
    cmd = { "ada_language_server" },
    filetypes = { "ada" },
    capabilities = als_capabilities(),
    on_attach = on_als_attach,
    on_detach = on_als_detach,
    handlers = als_handlers(),
    root_dir = function(bufnr, on_dir)
      on_dir(
        vim.fs.root(
          bufnr,
          { ".als.json", "alire.toml", "Makefile", ".git", "*.gpr", "*.adc" }
        )
      )
    end,
  })
  vim.lsp.enable("ada_ls")
end

-- Test-specific exports - only exposed in test mode
if os.getenv("ADA_LS_TEST_MODE") then
  M._open_qf_on_make = open_qf_on_make
  M._clear = clear
  M._on_als_attach = on_als_attach
  M._on_als_detach = on_als_detach
  M._als_handlers = als_handlers
  M._als_capabilities = als_capabilities
  M._als_snippets = als_snippets
end

return M
