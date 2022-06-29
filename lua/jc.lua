local lsp = require("jc.lsp")
local server = require("jc.server")
local jdtls = require("jc.jdtls")

M = {}
local user_on_attach = function(_, _) end

local config = {
  java_exec = "java",
  jc_on_attach = function(client, bufnr)
    lsp.on_attach(client, bufnr)
    user_on_attach(client, bufnr)
  end
}

M.setup = function(args)
  if args.on_attach then
    user_on_attach = args.on_attach
  end
  M.config = vim.tbl_deep_extend("keep", args, config)
  -- server.jdtls_setup(config)
end

function M.run_setup()
  server.jdtls_setup(M.config)
end

local definitions_handler = vim.lsp.handlers["textDocument/definition"]

local function custom_def_handler(_, result, ctx, conf)
  if vim.startswith(result[1].uri, "jdt:/") then
    jdtls.read_class_content({ result = result, ctx = ctx, config = conf }, definitions_handler)
  else
    definitions_handler(nil, result, ctx, conf)
  end
end
vim.lsp.handlers["textDocument/definition"] = custom_def_handler
vim.lsp.handlers["textDocument/declaration"] = custom_def_handler
vim.lsp.handlers["textDocument/implementation"] = custom_def_handler

return M
