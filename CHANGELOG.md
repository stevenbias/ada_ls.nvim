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
