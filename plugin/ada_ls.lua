-- Define commands with subcommands, from: https://github.com/lumen-oss/nvim-best-practices?tab=readme-ov-file#speaking_head-user-commands

if vim.g.loaded_ada_ls then
  return
end
vim.g.loaded_ada_ls = true

local cmd_name = "Als"

---@class MyCmdSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback, taking the lead of the subcommand's arguments

---@type table<string, MyCmdSubcommand>
local subcommand_tbl = {
  build = {
    impl = function()
      vim.cmd("cclose")
      vim.cmd("make")
    end,
  },
  clean = {
    impl = function()
      require("ada_ls.gpr").clean()
    end,
  },
  config = {
    impl = function()
      local config_path = require("ada_ls.utils").get_conf_file()
      if config_path then
        vim.cmd("edit " .. config_path)
      end
    end,
  },
  edit_gpr = {
    impl = function()
      local gpr_uri = require("ada_ls.lsp_cmd").get_prj_file()[1]
      if gpr_uri then
        vim.cmd("edit" .. vim.uri_to_fname(gpr_uri))
      end
    end,
  },
  other = {
    impl = function()
      require("ada_ls.lsp_cmd").go_to_other()
    end,
  },
  pick_gpr = {
    impl = function()
      require("ada_ls.project").pick_gpr_file()
    end,
  },
}

---@param opts table :h lua-guide-commands-create
local function subcmd(opts)
  local fargs = opts.fargs
  local subcommand_key = fargs[1]
  -- Get the subcommand's arguments, if any
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local subcommand = subcommand_tbl[subcommand_key]
  if not subcommand then
    vim.notify(
      cmd_name .. ": Unknown command: " .. subcommand_key,
      vim.log.levels.ERROR
    )
    return
  end
  -- Invoke the subcommand
  subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command(cmd_name, subcmd, {
  nargs = "+",
  desc = cmd_name .. " commands",
  complete = function(arg_lead, cmdline, _)
    -- Get the subcommand.
    local subcmd_key, subcmd_arg_lead =
      cmdline:match("^['<,'>]*" .. cmd_name .. "[!]*%s(%S+)%s(.*)$")
    if
      subcmd_key
      and subcmd_arg_lead
      and subcommand_tbl[subcmd_key]
      and subcommand_tbl[subcmd_key].complete
    then
      -- The subcommand has completions. Return them.
      return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
    end
    -- Check if cmdline is a subcommand
    if cmdline:match("^['<,'>]*" .. cmd_name .. "[!]*%s+%w*$") then
      -- Filter subcommands that match
      local subcommand_keys = vim.tbl_keys(subcommand_tbl)
      return vim
        .iter(subcommand_keys)
        :filter(function(key)
          return key:find(arg_lead) ~= nil
        end)
        :totable()
    end
  end,
  bang = true,
})
