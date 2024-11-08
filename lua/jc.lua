local lsp = require("jc.lsp")
local server = require("jc.server")

M = {}
local user_on_attach = function(_, _) end

local config = {
  java_exec = "java",
  jc_on_attach = function(args)
    if args.data then
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      lsp.on_attach(M.config, client, args.buf)
      user_on_attach(client, args.buf)
    end
  end,
  keys_prefix = "<leader>j",
}

M.setup = function(args)
  if args.on_attach then
    user_on_attach = args.on_attach
  end
  M.config = vim.tbl_deep_extend("keep", args, config)
end

function M.run_setup()
  server.jdtls_setup(M.config)
end

return M
