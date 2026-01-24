local M = {}

function M.get_ada_ls()
  local clients = vim.lsp.get_clients({ name = "ada" })
  if not clients or #clients == 0 then
    require("gnattest.utils").notify(
      "Ada LSP client not found",
      vim.log.levels.WARN
    )
    return nil
  else
    return clients[1]
  end
end

function M.get_root_dir()
  if M.root_dir ~= nil then
    return M.root_dir
  end

  if M.get_ada_ls() ~= nil then
    M.root_dir = M.get_ada_ls().root_dir
  end
  return M.root_dir
end

local function lsp_request(req)
  local client = M.get_ada_ls()
  if not client then
    return nil, "Ada LSP client not found"
  end

  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local result, err = client:request_sync(req, params, 1000)

  if err or not result or not result.result then
    return nil, err or ("Request '" .. req .. "' failed")
  end

  return vim.islist(result.result) and result.result or { result.result }
end

local function lsp_command(cmd, args)
  local client = M.get_ada_ls()
  if not client then
    return nil, "Ada LSP client not found"
  end

  local params = {
    command = cmd,
    arguments = args,
  }
  local result, err =
    client:request_sync("workspace/executeCommand", params, 1000)

  if err or not result or not result.result then
    return nil, err or ("Command '" .. cmd .. "' failed")
  end

  return vim.islist(result.result) and result.result or { result.result }
end

function M.get_symbols()
  return lsp_request("textDocument/documentSymbol")
end

function M.get_declarations()
  return lsp_request("textDocument/declaration")
end

function M.get_prj_file()
  if utils.is_gnattest_file() or M.prj_file ~= "" then
    return M.prj_file
  end

  local cmd = lsp_command("als-project-file")
  if cmd ~= nil and next(cmd) ~= nil then
    M.prj_file = vim.uri_to_fname(cmd[1])
  end
  return M.prj_file
end

function M.get_prj_file()
  if utils.is_gnattest_file() or M.prj_file ~= "" then
    return M.prj_file
  end

  local cmd = lsp_command("als-project-file")
  if cmd ~= nil and next(cmd) ~= nil then
    M.prj_file = vim.uri_to_fname(cmd[1])
  end
  return M.prj_file
end

return M
