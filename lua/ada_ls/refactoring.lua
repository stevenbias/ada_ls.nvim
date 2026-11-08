-- Refactoring command handlers for Ada Language Server
-- These handlers intercept ALS refactoring commands that require user input,
-- prompt for the required value, then forward the command to the server.
local M = {}

--- Factory to create a handler for refactoring commands requiring user input
---@param field_name string The field in command.arguments[1] to populate
---@param prompt_msg string The prompt message shown to the user
---@return function handler The command handler function
local function make_handler(field_name, prompt_msg)
  return function(command, ctx)
    local als = vim.lsp.get_client_by_id(ctx.client_id)
    if not als or als.name ~= "ada_ls" then
      require("ada_ls.utils").notify(
        "Als client not found",
        vim.log.levels.ERROR
      )
      return
    end

    local args = command.arguments and command.arguments[1]
    if not args then
      vim.notify("Refactoring: missing command arguments", vim.log.levels.ERROR)
      return
    end

    vim.ui.input({ prompt = prompt_msg }, function(input)
      if not input or input == "" then
        vim.notify(
          "Refactoring cancelled: no input provided",
          vim.log.levels.WARN
        )
        return
      end

      args[field_name] = input
      als:request("workspace/executeCommand", command, function(err, _)
        if err then
          vim.notify(
            "Refactoring failed: " .. (err.message or "unknown error"),
            vim.log.levels.ERROR
          )
        end
      end)
    end)
  end
end

-- Command handlers for ALS refactoring operations
M.add_parameter = make_handler("newParameter", "New parameter: ")
M.change_parameter_type = make_handler("newParametersType", "New type: ")
M.change_parameter_default =
  make_handler("newParametersDefaultValue", "New default value: ")
M.replace_type = make_handler("newType", "New type: ")

-- Export internals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._make_handler = make_handler
end

return M
