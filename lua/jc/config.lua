local mappings = require("jc.config.mappings")

local M = {}

function M.initialize_configuration(conf, bufnr)
  -- mappings are on unless explicitly disabled
  if vim.g.jc_default_mappings == false or vim.g.jc_default_mappings == 0 then
    return
  end
  -- LspAttach can fire repeatedly for the same buffer (reattach, multiple
  -- workspace folders) — install only once
  if vim.b[bufnr].jc_mappings_installed then
    return
  end
  vim.b[bufnr].jc_mappings_installed = true
  mappings.install_mappings(conf, bufnr)
end

return M
