local mappings = require("jc.config.mappings")

local M = {}

function M.initialize_configuration(conf, bufnr)
  if vim.g.jc_default_mappings then
    mappings.install_mappings(conf, bufnr)
  end
end

return M
