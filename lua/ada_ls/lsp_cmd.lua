local M = {}

local utils = require("ada_ls.utils")

local function lsp_request(req)
  local client = utils.get_ada_ls()
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
  local client = utils.get_ada_ls()
  if not client then
    return nil, "Ada LSP client not found"
  end

  local params = {
    command = cmd,
    arguments = { args },
  }
  local result, err =
    client:request_sync("workspace/executeCommand", params, 1000)

  if err or not result or not result.result then
    return nil, err or ("Command '" .. cmd .. "' failed")
  end

  return vim.islist(result.result) and result.result or { result.result }
end

function M.get_root_dir()
  local client = utils.get_ada_ls()
  if not client then
    return nil
  end
  return utils.get_ada_ls().root_dir
end

function M.get_symbols()
  return lsp_request("textDocument/documentSymbol")
end

function M.get_declarations()
  return lsp_request("textDocument/declaration")
end

function M.get_prj_file()
  local prj_file = lsp_command("als-project-file")
  if not prj_file or #prj_file == 0 then
    return nil, "No project file found"
  end
  return prj_file[1]
end

function M.get_prj_dependencies()
  local prj_file = M.get_prj_file()
  if not prj_file then
    return nil, "No project file found"
  end
  local arg = {
    uri = prj_file,
    direction = 1,
  }
  return lsp_command("als-gpr-dependencies", arg)
end

function M.go_to_other()
  local arg = { uri = vim.uri_from_bufnr(0) }
  return lsp_command("als-other-file", arg)
end

function M.get_src_dirs()
  return lsp_command("als-source-dirs")
end

function M.get_obj_dir()
  return lsp_command("als-object-dir")
end

return M
