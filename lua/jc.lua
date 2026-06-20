local lsp = require("jc.lsp")

local M = {}
local user_on_attach = function(_, _) end

local default_config = {
  keys_prefix = "<leader>j",
  -- refresh the jdtls build path when a java file is created in-editor, so
  -- go-to-definition resolves on it without a manual :JCutilUpdateConfig
  update_config_on_new_file = true,
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

  if M.config.templates_dir then
    require("jc.templates").load_dir(M.config.templates_dir)
  end

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

  -- Newly created java files aren't on jdtls' build path until the project
  -- configuration is refreshed, so go-to-definition returns nothing on them
  -- (find-references still works off the search index). Mark files created
  -- in-editor (BufNewFile = path absent on disk) and fire a
  -- projectConfigurationUpdate on their first write so gd resolves.
  if M.config.update_config_on_new_file ~= false then
    vim.api.nvim_create_autocmd("BufNewFile", {
      group = group,
      pattern = "*.java",
      callback = function(a)
        vim.b[a.buf].jc_new_java_file = true
      end,
    })
    -- setup may run lazily on FileType, after BufNewFile already fired for the
    -- buffer that triggered loading; mark it now if it's an unsaved new file
    local cur = vim.api.nvim_get_current_buf()
    if vim.bo[cur].filetype == "java" then
      local name = vim.api.nvim_buf_get_name(cur)
      if name ~= "" and vim.fn.filereadable(name) == 0 then
        vim.b[cur].jc_new_java_file = true
      end
    end
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = "*.java",
      callback = function(a)
        if not vim.b[a.buf].jc_new_java_file then
          return
        end
        vim.b[a.buf].jc_new_java_file = nil
        -- defer so jdtls processes didSave before we refresh the build path
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(a.buf) then
            require("jc.jdtls").update_project_config(a.buf, { silent = true })
          end
        end, 200)
      end,
    })
  end

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
