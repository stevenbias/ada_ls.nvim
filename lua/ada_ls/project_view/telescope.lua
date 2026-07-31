-- Telescope integration for Project View
local M = {}

--- Get path relative to a base directory
--- Returns the relative path if inside base, or basename as fallback
---@param path string The full path
---@param base_dir string The base directory
---@return string The relative path or basename
local function get_relative_path(path, base_dir)
  if not path or path == "" then
    return ""
  end
  if not base_dir or base_dir == "" then
    return vim.fs.basename((path:gsub("/+$", ""))) or ""
  end

  -- Normalize paths (strip trailing slashes)
  local norm_path = path:gsub("/+$", "")
  local norm_base = base_dir:gsub("/+$", "")

  -- Check if path starts with base_dir
  if norm_path:sub(1, #norm_base) == norm_base then
    local relative = norm_path:sub(#norm_base + 1):gsub("^/", "")
    if relative == "" then
      return "."
    end
    return relative
  end

  -- Path is outside base directory - show basename as fallback
  return vim.fs.basename(norm_path) or ""
end

--- Pick a source file from the project using Telescope
---@param opts? { include_runtime: boolean }
function M.pick_file(opts)
  opts = opts or {}
  local data_mod = require("ada_ls.project_view.data")
  local utils = require("ada_ls.utils")

  -- Check if Telescope is available
  local ok, _ = pcall(require, "telescope")
  if not ok then
    utils.notify(
      "Telescope is required for project file picker",
      vim.log.levels.WARN
    )
    return
  end

  -- Fetch project data
  local data, err = data_mod.fetch()
  if not data then
    utils.notify(err or "Failed to fetch project data", vim.log.levels.ERROR)
    return
  end

  -- Debug: show project count
  local project_count = vim.tbl_count(data.projects or {})
  if project_count == 0 then
    utils.notify(
      "Project View: No projects found in data. Check ALS response.",
      vim.log.levels.WARN
    )
    return
  end

  -- Get all source files
  local sources = data_mod.get_all_sources(data, {
    include_runtime = opts.include_runtime or false,
  })

  if #sources == 0 then
    utils.notify("No source files found in project", vim.log.levels.INFO)
    return
  end

  -- Build entries for Telescope
  local entries = {}
  for _, item in ipairs(sources) do
    table.insert(entries, {
      display = item.source.simple_name,
      ordinal = item.source.simple_name
        .. " "
        .. item.project.name
        .. " "
        .. item.source.directory,
      path = item.source.file_name,
      project_name = item.project.name,
      project_directory = item.project.directory,
      directory = item.source.directory,
      is_root = item.is_root,
    })
  end

  -- Sort: root project files first, then alphabetically
  table.sort(entries, function(a, b)
    if a.is_root ~= b.is_root then
      return a.is_root
    end
    if a.project_name ~= b.project_name then
      return a.project_name < b.project_name
    end
    return a.display < b.display
  end)

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  -- Calculate max widths for alignment
  local max_name_width = 0
  local max_project_width = 0
  for _, entry in ipairs(entries) do
    max_name_width = math.max(max_name_width, #entry.display)
    max_project_width = math.max(max_project_width, #entry.project_name)
  end
  max_name_width = math.min(max_name_width, 40)
  max_project_width = math.min(max_project_width, 20)

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = max_name_width },
      { width = max_project_width + 2 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local item = entry.value
    local dir = get_relative_path(item.directory, item.project_directory)
    return displayer({
      item.display,
      { "[" .. item.project_name .. "]", "TelescopeResultsComment" },
      { dir, "TelescopeResultsComment" },
    })
  end

  pickers
    .new({}, {
      prompt_title = "Project Files",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = make_display,
            ordinal = entry.ordinal,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd.edit(selection.path)
          end
        end)

        -- Open in split
        map("i", "<C-x>", function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd.split(selection.path)
          end
        end)

        -- Open in vsplit
        map("i", "<C-v>", function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd.vsplit(selection.path)
          end
        end)

        -- Open in new tab
        map("i", "<C-t>", function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd.tabedit(selection.path)
          end
        end)

        return true
      end,
    })
    :find()
end

--- Pick a project from the project view
---@param opts? { on_select: fun(project: ProjectInfo) }
function M.pick_project(opts)
  opts = opts or {}
  local data_mod = require("ada_ls.project_view.data")
  local utils = require("ada_ls.utils")

  local ok, _ = pcall(require, "telescope")
  if not ok then
    utils.notify(
      "Telescope is required for project picker",
      vim.log.levels.WARN
    )
    return
  end

  local data, err = data_mod.fetch()
  if not data then
    utils.notify(err or "Failed to fetch project data", vim.log.levels.ERROR)
    return
  end

  -- Build list of projects
  local projects = {}
  for _, entry in pairs(data.projects) do
    local is_root = entry.project.id == data.root_project_id
    table.insert(projects, {
      project = entry.project,
      is_root = is_root,
      display = entry.project.name .. (is_root and " (Root)" or ""),
    })
  end

  -- Sort: root first, then alphabetically
  table.sort(projects, function(a, b)
    if a.is_root ~= b.is_root then
      return a.is_root
    end
    return a.project.name < b.project.name
  end)

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Select Project",
      finder = finders.new_table({
        results = projects,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.project.name,
            path = entry.project.file_name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and opts.on_select then
            opts.on_select(selection.value.project)
          elseif selection then
            -- Default: open project file
            vim.cmd.edit(selection.value.project.file_name)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
