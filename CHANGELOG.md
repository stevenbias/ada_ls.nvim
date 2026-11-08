## v0.3.0-rc.0 (2026-11-08)

### BREAKING CHANGE

- Remove select_options() and :Als project_view_options
command. Configure options via setup() instead.

### Feat

- **scenario_variables**: Add a command to support scenario variables
- **project**: Get scenario variables from json file and keep their values after new gpr file picked
- Add the bare Als command to show a summary on how to use the plugin
- **ada_ls**: Add a subcommand to format current buffer
- **project-view**: Include collapsed obj dir files in filter results
- Improve neo-tree project view rendering
- add neo-tree backend for project view
- **project_view**: add Project View feature for ALS 2026.3+
- **lsp**: add get_project_view_info command
- Add new support for refactor code actions
- Improve support for gpr files
- Remove <leader>aj mapping in normal and insert mode
- Add a timeout parameter to lsp command and requests

### Fix

- pass scenario variables to gnatprove invocation
- gate release merges on publish completion
- set tag ref overrides for luarocks publish
- Use correct path for proof result in context of project change
- Remove recompute of the .als.json file after selection of the gpr file
- **project**: Fix regression on adding scenario variables when a gpr file is picked
- **gprtools**: Correct errorformat
- **project_view**: Prevent Neo-tree duplicate node IDs
- **utils**: restart gpr_ls correctly from .als.json write flow
- Correct the way to check if ada_ls is registered as sources for neo-tree
- Check ada_project has been registered as a neo-tree source before using neo-tree
- Expand object directories in project view
- invalidate project view cache when GPR file changes
- On setup, do not overwrite als.json file if it exists
- save_new_configuration
- get_prj_dependencies
- set makeprg for ada project

### Refactor

- Modif code review
- Improve performance
- Improve scenario variables support
- Improve performance to edit scenario variables
- Add treesitter as dependency and install ada parser at setup
- Remove summary after checkhealth in health command
- Improve checkhealth for this plugin
- **project_view**: Share node builders
- **utils**: Language server detection
- **project**: Improve the management of gpr file after selection
- Harden SPARK execution, project parsing, and root detection
- Improve ada/gpr ls refresh
- Improve filtering with builtin backend
- Add a nodes module for project tree
- Modif before PR
- Remove useless :Als reveal command
- simplify project_view with graceful fallback
- streamline project_view code and fix icon spacing
- extract get_relative_path to utils
- Do not move to the body file after a body generation
- Code review
- Fix typo
- Reset als command
- Use returned err in notif
- update als project file
- Always search gpr files upward and downward
- Always search gpr files upward and downward
- Rename "gpr" module to "gprtools" module
- Refactor and remove the absolute path to the GPR file in .als.json file
- Modif get_subprogram_name_from_line signature

## v0.2.0 (2026-05-16)

## v0.2.0-rc.3 (2026-05-17)

## v0.2.0-rc.2 (2026-05-16)

## v0.2.0-rc.1 (2026-05-16)

### Refactor

- Fix small issues after review

## v0.2.0-rc.0 (2026-05-16)

### Feat

- Fix default ada keymap deletion
- Add utils function to get project config sent to ALS
- Add a Spark cmd to prove subprogram from cursor position
- Add utils function to get subpr info from a line
- Filter lsp handler to ada_ls
- Fix some lsp req/cmd
- Set send_request and send_command public in order to be usable by other modules
- Add check for SPARK options index range
- on_detach is not part of vim.lsp.config parameter
- Remove empty last line created after package body generation
- Handle generation and update package body from code action
- Fix bug to update package body in nvim version 0.12
- ALS support out of the box
- Add ALS config for gpr file
- Distinguish gpr filetype to ada filetype
- Add VSCode snippets support
- Add vscode snippets from "version": "2026.1.202601121"
- Add same lsp capabilities as in vscode
- Add handler to have package generation suggestion in code action

### Refactor

- send_request and send_command are now async
- Avoid redundant reading to als config file
- Modif after review
- Split lsp config in two files
- Cleanup
- Fix als reload after opening the generated package body
- Fix warning after reloading plugin
- WIP update make cmd after writing the json config file
- als config

## v0.1.0 (2026-03-20)

## v0.1.0-rc.4 (2026-03-20)

## v0.1.0-rc.3 (2026-03-20)

## v0.1.0-rc.2 (2026-03-20)

## v0.1.0-rc.1 (2026-03-20)

## v0.1.0-rc.0 (2026-03-20)

### Feat

- Handle SPARK options from plugin's config
- Support for SPARK ok
- WIP Add support for SPARK
- Reload module after lsprestart and new project selection
- Add clean and build subcommand
- Delete <leader>aj keymap in normal mode
- Add a file to handle gpr tools
- Update the make cmd after new config
- Add function to get path to .als.json file
- Avoid error with delete mapping if it does not exist
- Delete weird and useless keybinding for ada
- Rewrite json file on pick project if it exists and add scenario variables from dependencies
- Use utils function to notify als
- Add utils function to notify als
- Add lsp command to get gpr dependencies
- Rename set_project command to pick_project and do not pick project by default
- Add print msg if ada_ls is not found
- Load ada_ls.project module at ada file type detection
- Add command to go to als config file
- Add command to edit gpr file
- Add a command to go to other file
- Add a file for LSP commands and requests to ALS
- Clean utils module
- WIP Create command to create ALS config from gpr file
- Initial commit

### Fix

- return nil if no project is found in get_prj_depedencies function

### Refactor

- Cleanup
- Cleanup
- Move function to open qflist from make message in init module
- Modif after code review
- Refactor makeprg_setup function and add gprbuild_cmd function
- Modif decode_json_config function
- Fix save_new_configuration function
- Move setup plugin from ftplugin to init.lua
- Stabilize Ada_ls setup and cache lsp client

### Perf

- Load Telescope only when it is needed
