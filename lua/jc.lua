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
  end,
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

return M
