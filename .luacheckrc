max_comment_line_length = false
read_globals = {
  "vim",
}
globals = {
  "vim.o",
  "vim.g",
}

-- Spec files need to mock vim APIs
files["spec/**/*.lua"] = {
  globals = {
    "vim",
    "describe",
    "it",
    "before_each",
    "after_each",
    "setup",
    "teardown",
    "pending",
    "spy",
    "stub",
    "mock",
    "assert",
  },
}
