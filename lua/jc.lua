local init = require("jc.init")

M = {}

local config = {
    java_exec = 'java'
}

M.setup = function(args)
    config = vim.tbl_deep_extend("keep", args, config)
    init.jdtls_setup(config)
end

return M
