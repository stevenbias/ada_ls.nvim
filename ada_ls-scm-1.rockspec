-- ada_ls-scm-1.rockspec
rockspec_format = "3.0"
package = "ada_ls"
version = "scm-1"
source = {
  url = "git@github.com:stevenbias/ada_ls.nvim.git",
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
    "plugin",
    "after",
  },
}
