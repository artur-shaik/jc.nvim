local lsp = require("jc.lsp")

local M = {}
local user_on_attach = function(_, _) end

local default_config = {
  keys_prefix = "<leader>j",
}

-- setup(opts) is the single configuration entry point; these opts are
-- bridged to the legacy g:jc_* variables that vimscript parts and older
-- configs still read
local g_bridge = {
  default_mappings = "jc_default_mappings",
  autoformat_on_save = "jc_autoformat_on_save",
  debug_backend = "jc_debug_backend",
  basedir = "jc_basedir",
}

M.config = vim.deepcopy(default_config)

local did_setup = false

local function on_jdtls_attach(client, bufnr)
  lsp.on_attach(M.config, client, bufnr)
  user_on_attach(client, bufnr)
end

-- jc.nvim is a layer over an externally managed jdtls (nvim-java,
-- nvim-jdtls, lspconfig, ...): it never starts the server itself, only
-- hooks into whatever jdtls client attaches.
function M.setup(args)
  args = args or {}
  did_setup = true

  if args.on_attach then
    user_on_attach = args.on_attach
    args.on_attach = nil
  end
  for opt, gvar in pairs(g_bridge) do
    if args[opt] ~= nil then
      vim.g[gvar] = args[opt]
      args[opt] = nil
    end
  end
  M.config = vim.tbl_deep_extend("keep", args, default_config)

  local group = vim.api.nvim_create_augroup("jc_nvim_attach", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(a)
      local client = vim.lsp.get_client_by_id(a.data.client_id)
      if client and client.name == "jdtls" then
        on_jdtls_attach(client, a.buf)
      end
    end,
  })

  -- jdtls may already be attached when setup runs (lazy-loaded plugin,
  -- session restore) — hook into the existing clients too
  for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
    for bufnr, _ in pairs(client.attached_buffers or {}) do
      on_jdtls_attach(client, bufnr)
    end
  end
end

-- idempotent entry point for the FileType autocmd (autoload/jc.vim):
-- doesn't clobber an explicit setup{} done by the user's plugin manager
function M.ensure_setup()
  if not did_setup then
    M.setup()
  end
end

return M
