-- Project View tree buffer rendering
local M = {}

-- Tree buffer state
local tree_state = {
  buf = nil,
  win = nil,
  expanded = {}, -- Set of expanded node IDs
  nodes = {}, -- Flat list of rendered nodes
  filter = "", -- Current filter string
  first_open = true, -- Track first open to auto-expand root
}

-- Tree connector characters
local tree_chars = {
  branch = "├── ",
  last = "└── ",
  vertical = "│   ",
  space = "    ",
}

-- Icons (clearer visual distinction)
local icons = {
  project_root = "◆ ",
  project = "◇ ",
  directory = "▸ ",
  directory_open = "▾ ",
  file = "  ",
  object_dir = "● ",
  runtime = "○ ",
}

-- Try to load devicons for file icons
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

---@class TreeNode
---@field id string Unique node ID
---@field type "project"|"directory"|"file"|"object_dir"|"runtime"
---@field name string Display name
---@field path? string File path (for files and directories)
---@field depth number Indentation depth
---@field expandable boolean Whether node can be expanded
---@field project_id? string Associated project ID
---@field children? TreeNode[] Child nodes (when expanded)

--- Generate a unique node ID
---@param type string
---@param path string
---@param project_id? string
---@return string
local function make_node_id(type, path, project_id)
  return string.format("%s:%s:%s", type, project_id or "", path)
end

--- Check if a node is expanded
---@param id string
---@return boolean
local function is_expanded(id)
  return tree_state.expanded[id] == true
end

--- Toggle node expansion
---@param id string
local function toggle_expanded(id)
  tree_state.expanded[id] = not tree_state.expanded[id]
end

--- Get icon for a file based on extension
---@param filename string
---@return string icon
---@return string? highlight
local function get_file_icon(filename)
  if has_devicons then
    local icon, hl = devicons.get_icon(filename, nil, { default = true })
    if icon then
      return icon .. " ", hl -- Add trailing space after devicon
    end
  end
  return icons.file, nil
end

--- Get icon for a node
---@param node TreeNode
---@return string icon
---@return string? highlight
local function get_node_icon(node)
  if node.type == "file" then
    return get_file_icon(node.name)
  elseif node.type == "directory" then
    return is_expanded(node.id) and icons.directory_open or icons.directory,
      "Directory"
  elseif node.type == "project" then
    if node.is_root then
      return is_expanded(node.id) and icons.directory_open or icons.project_root,
        "Title"
    end
    return is_expanded(node.id) and icons.directory_open or icons.project,
      "Type"
  elseif node.type == "object_dir" then
    return icons.object_dir, "Special"
  elseif node.type == "runtime" then
    return is_expanded(node.id) and icons.directory_open or icons.runtime,
      "Comment"
  end
  return " ", nil
end

--- Group sources by directory
---@param sources table[] List of source objects with 'directory' field
---@return table<string, table[]> dirs Map of directory to sources
---@return string[] sorted_dirs Sorted list of directories
local function group_sources_by_dir(sources)
  local dirs = {}
  for _, source in ipairs(sources) do
    local dir = source.directory
    if not dirs[dir] then
      dirs[dir] = {}
    end
    table.insert(dirs[dir], source)
  end
  local sorted_dirs = vim.tbl_keys(dirs)
  table.sort(sorted_dirs)
  return dirs, sorted_dirs
end

--- Build tree nodes from project data
---@param data table ProjectViewData
---@param opts { flat_mode: boolean, show_object_dirs: boolean, show_runtime: boolean }
---@return TreeNode[]
local function build_tree(data, opts)
  local nodes = {}

  --- Build nodes for a project entry
  ---@param entry table ProjectEntry
  ---@param depth number
  ---@param is_root boolean
  local function build_project_nodes(entry, depth, is_root)
    local project = entry.project
    local project_id = make_node_id("project", project.file_name, project.id)

    local project_node = {
      id = project_id,
      type = "project",
      name = project.name .. (is_root and " (Root)" or ""),
      path = project.file_name,
      depth = depth,
      expandable = true,
      project_id = project.id,
      is_root = is_root,
    }
    table.insert(nodes, project_node)

    if is_expanded(project_id) then
      -- Group sources by directory
      local dirs, dir_list = group_sources_by_dir(entry.sources)

      -- Add directory nodes
      for _, dir in ipairs(dir_list) do
        local dir_id = make_node_id("directory", dir, project.id)
        local dir_name =
          require("ada_ls.utils").get_relative_path(dir, project.directory)

        local dir_node = {
          id = dir_id,
          type = "directory",
          name = dir_name,
          path = dir,
          depth = depth + 1,
          expandable = true,
          project_id = project.id,
        }
        table.insert(nodes, dir_node)

        if is_expanded(dir_id) then
          -- Sort files
          local files = dirs[dir]
          table.sort(files, function(a, b)
            return a.simple_name < b.simple_name
          end)

          for _, source in ipairs(files) do
            local file_id = make_node_id("file", source.file_name, project.id)
            table.insert(nodes, {
              id = file_id,
              type = "file",
              name = source.simple_name,
              path = source.file_name,
              depth = depth + 2,
              expandable = false,
              project_id = project.id,
            })
          end
        end
      end

      -- Add object directory if enabled
      if opts.show_object_dirs and project.object_dir then
        local obj_id =
          make_node_id("object_dir", project.object_dir, project.id)
        table.insert(nodes, {
          id = obj_id,
          type = "object_dir",
          name = require("ada_ls.utils").safe_basename(project.object_dir)
            .. " (obj)",
          path = project.object_dir,
          depth = depth + 1,
          expandable = false,
          project_id = project.id,
        })
      end

      -- Add sub-projects if not in flat mode
      if not opts.flat_mode then
        local sub_ids = {}
        for _, id in ipairs(entry.imports or {}) do
          table.insert(sub_ids, id)
        end
        for _, id in ipairs(entry.aggregated or {}) do
          table.insert(sub_ids, id)
        end
        for _, id in ipairs(entry.extended or {}) do
          table.insert(sub_ids, id)
        end

        -- Sort and add sub-projects
        table.sort(sub_ids, function(a, b)
          local pa = data.projects[a]
          local pb = data.projects[b]
          if pa and pb then
            return pa.project.name < pb.project.name
          end
          return a < b
        end)

        for _, sub_id in ipairs(sub_ids) do
          local sub_entry = data.projects[sub_id]
          if sub_entry then
            build_project_nodes(sub_entry, depth + 1, false)
          end
        end
      end
    end
  end

  if opts.flat_mode then
    -- Flat mode: show all projects at root level
    local project_list = {}
    for _, entry in pairs(data.projects) do
      table.insert(project_list, entry)
    end
    -- Sort: root first, then alphabetically
    table.sort(project_list, function(a, b)
      local a_root = a.project.id == data.root_project_id
      local b_root = b.project.id == data.root_project_id
      if a_root ~= b_root then
        return a_root
      end
      return a.project.name < b.project.name
    end)

    for _, entry in ipairs(project_list) do
      local is_root = entry.project.id == data.root_project_id
      build_project_nodes(entry, 0, is_root)
    end
  else
    -- Hierarchical mode: start from root project
    local root_entry = data.projects[data.root_project_id]
    if root_entry then
      build_project_nodes(root_entry, 0, true)
    end
  end

  -- Add runtime project if enabled
  if opts.show_runtime and data.runtime_project then
    local runtime = data.runtime_project
    local runtime_id = make_node_id("runtime", "runtime", "runtime")

    table.insert(nodes, {
      id = runtime_id,
      type = "runtime",
      name = "Runtime",
      depth = 0,
      expandable = true,
      project_id = "runtime",
    })

    if is_expanded(runtime_id) then
      -- Group runtime sources by directory
      local dirs, dir_list = group_sources_by_dir(runtime.sources)

      for _, dir in ipairs(dir_list) do
        local dir_id = make_node_id("directory", dir, "runtime")
        local runtime_dir = runtime.project and runtime.project.directory or ""
        local dir_name =
          require("ada_ls.utils").get_relative_path(dir, runtime_dir)

        table.insert(nodes, {
          id = dir_id,
          type = "directory",
          name = dir_name,
          path = dir,
          depth = 1,
          expandable = true,
          project_id = "runtime",
        })

        if is_expanded(dir_id) then
          local files = dirs[dir]
          table.sort(files, function(a, b)
            return a.simple_name < b.simple_name
          end)

          for _, source in ipairs(files) do
            local file_id = make_node_id("file", source.file_name, "runtime")
            table.insert(nodes, {
              id = file_id,
              type = "file",
              name = source.simple_name,
              path = source.file_name,
              depth = 2,
              expandable = false,
              project_id = "runtime",
            })
          end
        end
      end
    end
  end

  return nodes
end

--- Filter nodes based on filter string
---@param nodes TreeNode[]
---@param filter string
---@return TreeNode[]
local function filter_nodes(nodes, filter)
  if filter == "" then
    return nodes
  end

  local lower_filter = filter:lower()
  local matching_ids = {}

  -- First pass: find all matching nodes
  for _, node in ipairs(nodes) do
    if node.name:lower():find(lower_filter, 1, true) then
      matching_ids[node.id] = true
    end
  end

  -- Second pass: include parents of matching nodes
  local function include_parents(node_id)
    for _, node in ipairs(nodes) do
      if node.id == node_id then
        -- Find parent by checking if this node's path starts with another's
        for _, potential_parent in ipairs(nodes) do
          if
            potential_parent.expandable
            and potential_parent.depth < node.depth
            and node.project_id == potential_parent.project_id
          then
            matching_ids[potential_parent.id] = true
          end
        end
        break
      end
    end
  end

  for id, _ in pairs(matching_ids) do
    include_parents(id)
  end

  -- Third pass: filter
  local filtered = {}
  for _, node in ipairs(nodes) do
    if matching_ids[node.id] then
      table.insert(filtered, node)
    end
  end

  return filtered
end

--- Build tree prefix with connector lines
---@param node_idx number Current node index
---@param nodes TreeNode[] All nodes
---@return string prefix
local function build_tree_prefix(node_idx, nodes)
  local node = nodes[node_idx]
  if node.depth == 0 then
    return ""
  end

  -- Find if this node is the last at its depth under its parent
  local is_last = true
  for j = node_idx + 1, #nodes do
    local next_node = nodes[j]
    if next_node.depth < node.depth then
      break -- Parent ended
    elseif next_node.depth == node.depth then
      is_last = false -- There's a sibling after us
      break
    end
  end

  -- Build prefix for parent depths
  local prefix_parts = {}
  -- Track which depth levels have more siblings
  local has_more_at_depth = {}

  -- Look backwards to find parent structure
  for d = 1, node.depth - 1 do
    -- Check if there are more nodes at this depth after current node
    local found_sibling = false
    for j = node_idx + 1, #nodes do
      local check = nodes[j]
      if check.depth < d then
        break
      elseif check.depth == d then
        found_sibling = true
        break
      end
    end
    has_more_at_depth[d] = found_sibling
  end

  -- Build the prefix
  for d = 1, node.depth - 1 do
    if has_more_at_depth[d] then
      table.insert(prefix_parts, tree_chars.vertical)
    else
      table.insert(prefix_parts, tree_chars.space)
    end
  end

  -- Add the connector for this node
  if is_last then
    table.insert(prefix_parts, tree_chars.last)
  else
    table.insert(prefix_parts, tree_chars.branch)
  end

  return table.concat(prefix_parts)
end

--- Render tree to buffer
---@param buf number
---@param nodes TreeNode[]
local function render_tree(buf, nodes)
  local lines = {}
  local highlights = {}

  for i, node in ipairs(nodes) do
    local prefix = build_tree_prefix(i, nodes)
    local icon, icon_hl = get_node_icon(node)
    local line = string.format("%s%s%s", prefix, icon, node.name)
    table.insert(lines, line)

    -- Store highlight info for icon
    if icon_hl then
      local col_start = #prefix
      local col_end = col_start + #icon - 1 -- -1 to exclude trailing space
      table.insert(highlights, {
        line = i - 1,
        col_start = col_start,
        col_end = col_end,
        hl_group = icon_hl,
      })
    end

    -- Highlight folder names differently
    if node.type == "directory" or node.type == "project" then
      local name_start = #prefix + #icon
      table.insert(highlights, {
        line = i - 1,
        col_start = name_start,
        col_end = name_start + #node.name,
        hl_group = node.type == "project" and "Title" or "Directory",
      })
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("ada_project_view")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      buf,
      ns,
      hl.hl_group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end

  tree_state.nodes = nodes
end

--- Get node at cursor position
---@return TreeNode?
local function get_node_at_cursor()
  local line = vim.fn.line(".") - 1
  return tree_state.nodes[line + 1]
end

--- Open a file
---@param path string
---@param cmd? string
local function open_file(path, cmd)
  cmd = cmd or "edit"
  -- Switch to previous window before opening
  vim.cmd.wincmd("p")
  vim.cmd[cmd](path)
end

-- Keymap handler: Open file or toggle expand
local function handle_enter()
  local node = get_node_at_cursor()
  if not node then
    return
  end
  if node.expandable then
    toggle_expanded(node.id)
    M.refresh()
  elseif node.path then
    open_file(node.path)
  end
end

-- Keymap handler: Open in split
local function handle_open_split()
  local node = get_node_at_cursor()
  if node and node.type == "file" and node.path then
    open_file(node.path, "split")
  end
end

-- Keymap handler: Open in vsplit
local function handle_open_vsplit()
  local node = get_node_at_cursor()
  if node and node.type == "file" and node.path then
    open_file(node.path, "vsplit")
  end
end

-- Keymap handler: Open in tab
local function handle_open_tab()
  local node = get_node_at_cursor()
  if node and node.type == "file" and node.path then
    open_file(node.path, "tabedit")
  end
end

-- Keymap handler: Preview file
local function handle_preview()
  local node = get_node_at_cursor()
  if node and node.type == "file" and node.path then
    vim.cmd.wincmd("p")
    vim.cmd.edit(node.path)
    vim.cmd.wincmd("p")
  end
end

-- Keymap handler: Refresh tree
local function handle_refresh()
  require("ada_ls.project_view.data").invalidate()
  M.refresh()
end

-- Keymap handler: Expand node
local function handle_expand()
  local node = get_node_at_cursor()
  if node and node.expandable and not is_expanded(node.id) then
    toggle_expanded(node.id)
    M.refresh()
  end
end

-- Keymap handler: Collapse node
local function handle_collapse()
  local node = get_node_at_cursor()
  if node and node.expandable and is_expanded(node.id) then
    toggle_expanded(node.id)
    M.refresh()
  end
end

-- Keymap handler: Collapse all
local function handle_collapse_all()
  tree_state.expanded = {}
  M.refresh()
end

-- Keymap handler: Expand all
local function handle_expand_all()
  for _, node in ipairs(tree_state.nodes) do
    if node.expandable then
      tree_state.expanded[node.id] = true
    end
  end
  M.refresh()
end

-- Keymap handler: Filter
local function handle_filter()
  vim.ui.input({ prompt = "Filter: " }, function(input)
    if input then
      tree_state.filter = input
      M.refresh()
    end
  end)
end

-- Keymap handler: Clear filter
local function handle_clear_filter()
  if tree_state.filter ~= "" then
    tree_state.filter = ""
    M.refresh()
  end
end

-- Keymap handler: Show help
local function handle_help()
  local help = {
    "Project View Keymaps:",
    "",
    "<CR>    Open file / toggle expand",
    "o       Open in horizontal split",
    "v       Open in vertical split",
    "t       Open in new tab",
    "p       Preview file",
    "r       Refresh tree",
    "R       Reveal current file",
    "zo      Expand node",
    "zc      Collapse node",
    "zM      Collapse all",
    "zR      Expand all",
    "/       Filter",
    "<Esc>   Clear filter",
    "q       Close tree",
    "g?      Show this help",
  }
  vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
end

--- Set up keymaps for tree buffer
---@param buf number
local function setup_keymaps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", "<CR>", handle_enter, opts)
  vim.keymap.set("n", "o", handle_open_split, opts)
  vim.keymap.set("n", "v", handle_open_vsplit, opts)
  vim.keymap.set("n", "t", handle_open_tab, opts)
  vim.keymap.set("n", "p", handle_preview, opts)
  vim.keymap.set("n", "r", handle_refresh, opts)
  vim.keymap.set("n", "R", M.reveal_current_file, opts)
  vim.keymap.set("n", "zo", handle_expand, opts)
  vim.keymap.set("n", "zc", handle_collapse, opts)
  vim.keymap.set("n", "zM", handle_collapse_all, opts)
  vim.keymap.set("n", "zR", handle_expand_all, opts)
  vim.keymap.set("n", "/", handle_filter, opts)
  vim.keymap.set("n", "<Esc>", handle_clear_filter, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "g?", handle_help, opts)
end

--- Check if tree is currently open
---@return boolean
function M.is_open()
  return tree_state.win ~= nil and vim.api.nvim_win_is_valid(tree_state.win)
end

--- Open the project view tree
---@param opts { flat_mode: boolean, show_object_dirs: boolean, show_runtime: boolean }
function M.open(opts)
  local data_mod = require("ada_ls.project_view.data")
  local utils = require("ada_ls.utils")

  -- Check ALS support
  local supported, err = data_mod.is_supported()
  if not supported then
    utils.notify(err or "Project View not supported", vim.log.levels.WARN)
    return
  end

  -- Fetch data
  local data, fetch_err = data_mod.fetch()
  if not data then
    utils.notify(
      fetch_err or "Failed to fetch project data",
      vim.log.levels.ERROR
    )
    return
  end

  -- Auto-expand root project on first open
  if tree_state.first_open and data.root_project_id then
    local root_entry = data.projects[data.root_project_id]
    if root_entry then
      local root_id = make_node_id(
        "project",
        root_entry.project.file_name,
        root_entry.project.id
      )
      tree_state.expanded[root_id] = true
    end
    tree_state.first_open = false
  end

  -- Create or reuse buffer
  if not tree_state.buf or not vim.api.nvim_buf_is_valid(tree_state.buf) then
    tree_state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[tree_state.buf].buftype = "nofile"
    vim.bo[tree_state.buf].bufhidden = "hide"
    vim.bo[tree_state.buf].swapfile = false
    vim.bo[tree_state.buf].filetype = "ada_project_view"
    vim.api.nvim_buf_set_name(tree_state.buf, "Project View")
    setup_keymaps(tree_state.buf)
  end

  -- Create window if needed
  if not M.is_open() then
    -- Open in left split
    vim.cmd("topleft 35vsplit")
    tree_state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(tree_state.win, tree_state.buf)

    -- Window options
    vim.wo[tree_state.win].number = false
    vim.wo[tree_state.win].relativenumber = false
    vim.wo[tree_state.win].signcolumn = "no"
    vim.wo[tree_state.win].foldcolumn = "0"
    vim.wo[tree_state.win].wrap = false
    vim.wo[tree_state.win].cursorline = true
  end

  -- Build and render tree
  local nodes = build_tree(data, opts)
  if tree_state.filter ~= "" then
    nodes = filter_nodes(nodes, tree_state.filter)
  end
  render_tree(tree_state.buf, nodes)

  -- Store current opts for refresh
  tree_state.opts = opts
end

--- Close the project view tree
function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(tree_state.win, true)
    tree_state.win = nil
  end
end

--- Toggle the project view tree
---@param opts { flat_mode: boolean, show_object_dirs: boolean, show_runtime: boolean }
function M.toggle(opts)
  if M.is_open() then
    M.close()
  else
    M.open(opts)
  end
end

--- Refresh the tree with current data
function M.refresh()
  if not M.is_open() then
    return
  end

  local data_mod = require("ada_ls.project_view.data")
  local data = data_mod.fetch()
  if not data then
    return
  end

  local nodes = build_tree(data, tree_state.opts or {})
  if tree_state.filter ~= "" then
    nodes = filter_nodes(nodes, tree_state.filter)
  end
  render_tree(tree_state.buf, nodes)
end

--- Reveal the current file in the tree
function M.reveal_current_file()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    return
  end

  local data_mod = require("ada_ls.project_view.data")
  local data = data_mod.fetch()
  if not data then
    return
  end

  -- Find the source in project data
  local found = data_mod.find_source(data, current_file)
  if not found then
    require("ada_ls.utils").notify(
      "File not found in project",
      vim.log.levels.INFO
    )
    return
  end

  -- Expand necessary nodes
  local project_id =
    make_node_id("project", found.project.file_name, found.project.id)
  tree_state.expanded[project_id] = true

  local dir_id =
    make_node_id("directory", found.source.directory, found.project.id)
  tree_state.expanded[dir_id] = true

  -- Refresh to show expanded nodes
  M.refresh()

  -- Find and move cursor to the file
  local file_id = make_node_id("file", found.source.file_name, found.project.id)
  for i, node in ipairs(tree_state.nodes) do
    if node.id == file_id then
      if M.is_open() then
        vim.api.nvim_win_set_cursor(tree_state.win, { i, 0 })
      end
      break
    end
  end
end

-- Export internals for testing
if os.getenv("ADA_LS_TEST_MODE") then
  M._tree_state = tree_state
  M._build_tree = build_tree
  M._filter_nodes = filter_nodes
  M._make_node_id = make_node_id
  M._group_sources_by_dir = group_sources_by_dir
  M._build_tree_prefix = build_tree_prefix
  M._tree_chars = tree_chars
  M._toggle_expanded = toggle_expanded
  M._is_expanded = is_expanded
  M._get_node_icon = get_node_icon
  M._icons = icons
  -- Internal functions
  M._render_tree = render_tree
  M._get_node_at_cursor = get_node_at_cursor
  M._open_file = open_file
  -- Handler functions
  M._handle_enter = handle_enter
  M._handle_open_split = handle_open_split
  M._handle_open_vsplit = handle_open_vsplit
  M._handle_open_tab = handle_open_tab
  M._handle_preview = handle_preview
  M._handle_refresh = handle_refresh
  M._handle_expand = handle_expand
  M._handle_collapse = handle_collapse
  M._handle_collapse_all = handle_collapse_all
  M._handle_expand_all = handle_expand_all
  M._handle_filter = handle_filter
  M._handle_clear_filter = handle_clear_filter
  M._handle_help = handle_help
end

return M
