local lsp = require("jc.lsp")
local server = require("jc.server")
local jdtls = require("jc.jdtls")

M = {}

local config = {
  java_exec = "java",
  on_attach = lsp.on_attach,
}

M.setup = function(args)
  config = vim.tbl_deep_extend("keep", args, config)
  server.jdtls_setup(config)
end

local definitions_handler = vim.lsp.handlers["textDocument/definition"]
vim.lsp.handlers["textDocument/definition"] = function(_, result, ctx, config)
  if vim.startswith(result[1].uri, "jdt:/") then
    jdtls.read_class_content({ result = result, ctx = ctx, config = config }, definitions_handler)
  else
    definitions_handler(nil, result, ctx, config)
  end
end

return M
