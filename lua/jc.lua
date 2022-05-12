local lsp = require("jc.lsp")
local server = require("jc.server")

M = {}

local config = {
    java_exec = 'java',
    on_attach = lsp.on_attach
}

M.setup = function(args)
    print(vim.inspect())
    config = vim.tbl_deep_extend("keep", args, config)
    server.jdtls_setup(config)
end

return M
