std = "luajit"
cache = true
codes = true

read_globals = {
  "vim",
}

files["tests/**/*_spec.lua"] = {
  read_globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
  },
}

-- long lines are stylua's business
max_line_length = false
