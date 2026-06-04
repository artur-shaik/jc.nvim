std = "luajit"
cache = true
codes = true
self = false

-- vim is writable: the plugin sets vim.g.*, vim.bo.* and lsp handlers
globals = {
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
