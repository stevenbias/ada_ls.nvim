local M = {}

local function check_executable(cmd, opts)
  opts = opts or {}
  local found = vim.fn.executable(cmd) == 1

  if found then
    local version_cmd = opts.version_arg or "--version"
    local version_result = vim.fn.system(cmd .. " " .. version_cmd .. " 2>&1")
    local version_line = vim.split(version_result, "\n")[1] or ""
    local version = vim.trim(version_line)
    vim.health.ok(string.format("`%s` found (%s)", cmd, version))
    return true
  else
    if opts.optional then
      vim.health.warn(string.format("`%s` not found", cmd), opts.advice or {})
    else
      vim.health.error(
        string.format("`%s` not found", cmd),
        opts.advice or { "Install it with your package manager" }
      )
    end
    return false
  end
end

local function check_lsp_client()
  local clients = vim.lsp.get_clients({ name = "ada" })

  if #clients > 0 then
    local client = clients[1]
    local root_dir = client.config.root_dir or "unknown"
    vim.health.ok(
      string.format("Ada Language Server running (root: %s)", root_dir)
    )
    return true, client
  else
    vim.health.error("Ada Language Server not running", {
      "Configure Ada Language Server first",
      "See: https://github.com/AdaCore/ada_language_server",
    })
    return false, nil
  end
end

local function check_project_file()
  local bufname = vim.api.nvim_buf_get_name(0)

  if not bufname or bufname == "" then
    vim.health.info("No file loaded - skipping project checks")
    return
  end

  local lsp_ok, client = check_lsp_client()

  if not lsp_ok or client == nil then
    return
  end

  local project_file = nil
  if client and client.config.root_dir then
    local json_file = client.config.root_dir .. "/.als.json"
    local ok, content = pcall(vim.fn.readfile, json_file)
    if ok then
      local json = vim.fn.json_decode(content)
      if json and json.projectFile then
        project_file = json.projectFile
        vim.health.ok(string.format("Project file found (%s)", project_file))
      end
    end
  end

  if not project_file then
    vim.health.warn("Project file (.als.json) not configured", {
      "Run :Als pick_gpr to select a GPR file",
      "Or manually create .als.json with projectFile field",
    })
  end
end

local function check_config()
  local ok, config = pcall(require, "ada_ls.spark.config")
  if not ok then
    vim.health.info("Using default configuration")
    return
  end

  local cfg = config.get()
  vim.health.info(string.format("proof_level = %s", tostring(cfg.proof_level)))
  vim.health.info(
    string.format("options = { %s }", table.concat(cfg.options or {}, ", "))
  )

  if
    type(cfg.proof_level) == "number"
    and cfg.proof_level >= 0
    and cfg.proof_level <= 4
  then
    vim.health.ok("Configuration is valid")
  else
    vim.health.error("Configuration has invalid proof_level (must be 0-4)")
  end
end

function M.check()
  vim.health.start("ada_ls.nvim: Neovim version")
  if vim.fn.has("nvim-0.10") == 1 then
    local version = vim.version()
    vim.health.ok(
      string.format(
        "Neovim %d.%d.%d",
        version.major,
        version.minor,
        version.patch
      )
    )
  else
    vim.health.error(
      "Neovim >= 0.10 required",
      { "Upgrade Neovim to version 0.10 or newer" }
    )
  end

  vim.health.start("ada_ls.nvim: External dependencies")
  check_executable("gprbuild", {
    advice = {
      "Install gprbuild (part of GNAT toolchain)",
      "Required for :Als build",
    },
  })
  check_executable("gprclean", {
    advice = {
      "Install gprclean (part of GNAT toolchain)",
      "Required for :Als clean",
    },
  })
  check_executable("gnatprove", {
    advice = {
      "Install gnatprove (part of GNAT toolchain)",
      "Required for :Spark prove commands",
    },
  })

  vim.health.start("ada_ls.nvim: Ada Language Server")
  check_lsp_client()

  vim.health.start("ada_ls.nvim: Configuration")
  check_config()

  vim.health.start("ada_ls.nvim: Project detection")
  check_project_file()

  vim.health.start("ada_ls.nvim: Plugin status")
  if vim.g.loaded_ada_ls then
    vim.health.ok("Plugin loaded")
  else
    vim.health.warn("Plugin not loaded", {
      "Ensure plugin is properly installed",
      "Check that plugin/ada_ls.lua can be found",
    })
  end
end

return M
