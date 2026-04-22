local M = {}

function M.send_request(req)
  local utils = require("ada_ls.utils")
  local client = utils.get_ada_ls()
  if not client then
    return nil, "Ada LSP client not found"
  end

  local result, err = nil, nil
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request(req, params, function(e, r)
    err = e
    result = r
  end)
  vim.wait(2000, function()
    return result ~= nil or err ~= nil
  end)

  if err or not result then
    return nil, err or ("Request '" .. req .. "' failed")
  end

  return vim.islist(result) and result or { result }
end

function M.send_command(cmd, args)
  local utils = require("ada_ls.utils")
  local client = utils.get_ada_ls()
  if not client then
    return nil, "Ada LSP client not found"
  end

  local params = {
    command = cmd,
    arguments = { args },
  }
  local result, err
  client:request("workspace/executeCommand", params, function(e, r)
    err = e
    result = r
  end)
  vim.wait(2000, function()
    return result ~= nil or err ~= nil
  end)

  if err or not result then
    return nil, err or ("Command '" .. cmd .. "' failed")
  end

  return vim.islist(result) and result or { result }
end

function M.get_root_dir()
  local utils = require("ada_ls.utils")
  local client = utils.get_ada_ls()
  if not client then
    return nil
  end
  return client.root_dir
end

function M.get_symbols()
  return M.send_request("textDocument/documentSymbol")
end

function M.get_declarations()
  return M.send_request("textDocument/declaration")
end

function M.get_prj_file()
  local prj_file = M.send_command("als-project-file")
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
  return M.send_command("als-gpr-dependencies", arg)
end

function M.go_to_other()
  local arg = { uri = vim.uri_from_bufnr(0) }
  return M.send_command("als-other-file", arg)
end

function M.get_src_dirs()
  return M.send_command("als-source-dirs")
end

function M.get_obj_dir()
  return M.send_command("als-object-dir")
end

return M
