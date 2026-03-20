-- ada_ls-scm-1.rockspec
rockspec_format = "3.0"
package = "ada_ls"
version = "scm-1"
source = {
  url = "https://github.com/stevenbias/ada_ls.nvim.git",
}
description = {
  summary = "Neovim plugin for Ada Language Server integration",
  detailed = "Manages .gpr project files, configures gprbuild as :make, "
    .. "offers a Telescope picker for GPR files, and exposes LSP commands.",
  homepage = "https://github.com/stevenbias/ada_ls.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
test_dependencies = {
  "busted",
  "nlua",
}
build = {
  type = "builtin",
  copy_directories = {
    "doc",
    "plugin",
    "after",
  },
}
