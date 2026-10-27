local M = {}

function M.get_info()
  local lsp_cmd = require("ada_ls.lsp_cmd")
  local result, err = lsp_cmd.get_scenario_variables_info()
  if err then
    return nil, err
  end
  return result
end

function M.get_variables()
  local result, err = M.get_info()

  if err or result == nil then
    return nil, err
  end

  local scenario_variables = {}
  for _, var in ipairs(result.variables) do
    scenario_variables[var.name] = { value = var.value, possible_values = {} }
    for _, val in ipairs(var["possible-values"]) do
      table.insert(scenario_variables[var.name].possible_values, val)
    end
  end

  return scenario_variables
end

function M.set_variable()
  local scenario_variables, err = M.get_variables()

  if not scenario_variables then
    return nil, err or "Failed to retrieve scenario variables"
  end

  local names = {}
  local items_name = {}
  local name_idx = 1
  for name, var in pairs(scenario_variables) do
    table.insert(names, name)
    if var.value == nil then
      var.value = "nil"
    end
    table.insert(items_name, name_idx .. " - " .. name .. ": " .. var.value)
    name_idx = name_idx + 1
  end

  local project_name = nil or require("ada_ls.utils").get_server_project_name()
  if not project_name then
    return nil, "Please pick a project first using the 'pick_gpr' command"
  end

  local idx = vim.fn.inputlist({
    "Select scenario variable to edit for " .. project_name,
    table.concat(items_name, "\n"),
  })

  if idx < 1 or idx > #items_name then
    return nil, "Invalid selection"
  end

  vim.cmd.redraw() -- Redraw the screen to clear the inputlist prompt

  local possible_values = scenario_variables[names[idx]].possible_values
  local idx_val = vim.fn.inputlist({
    "Select value for " .. names[idx] .. ":",
    table.concat(possible_values, "\n"),
  })

  if idx_val < 1 or idx_val > #possible_values then
    return nil, "Invalid selection"
  end

  require("ada_ls.project").update_scenario_variable(
    names[idx],
    possible_values[idx_val]
  )
end

return M
