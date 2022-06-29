local mappings = require("jc.config.mappings")

local M = {}

function M.initialize_configuration(bufnr)
  if vim.g.jc_default_mappings then
    mappings.install_mappings(bufnr)
  end
end

return M
