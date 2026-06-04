local M = {}

local health = vim.health

local function jdtls_clients()
  return vim.lsp.get_clients({ name = "jdtls" })
end

local function client_has_command(client, command)
  local provider = client.server_capabilities.executeCommandProvider
  for _, server_command in ipairs(provider and provider.commands or {}) do
    if server_command == command then
      return true
    end
  end
  return false
end

function M.check()
  health.start("jc.nvim")

  -- neovim version
  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim >= 0.11")
  elseif vim.fn.has("nvim-0.10") == 1 then
    health.warn("Neovim 0.10 — works, but 0.11+ is recommended")
  else
    health.error("Neovim >= 0.10 required")
  end

  -- external jdtls client (jc.nvim is a layer, it never starts the server)
  local clients = jdtls_clients()
  if #clients == 0 then
    health.warn(
      "no jdtls client running",
      "start jdtls via nvim-java, nvim-jdtls or lspconfig and open a java buffer, then re-run :checkhealth jc"
    )
  else
    health.ok("jdtls client attached (id " .. clients[1].id .. ")")
    local client = clients[1]
    if client_has_command(client, "java.edit.organizeImports") then
      health.ok("organize imports command available")
    else
      health.warn(
        "java.edit.organizeImports not advertised by jdtls",
        "check that jdtls was started with extendedClientCapabilities"
      )
    end
    if client_has_command(client, "vscode.java.startDebugSession") then
      health.ok("java-debug bundle loaded (debug attach/launch available)")
    else
      health.warn(
        "vscode.java.startDebugSession not available — debug attach won't work",
        "load the java-debug bundle into jdtls (nvim-java bundles it; with nvim-jdtls add it to init_options.bundles)"
      )
    end
  end

  -- optional integrations
  local backend = require("jc.debug").backend()
  local has_dap = pcall(require, "dap")
  local has_vimspector = vim.fn.exists(":VimspectorReset") == 1
  if has_dap or has_vimspector then
    health.ok(
      "debug backend: "
        .. backend
        .. " (nvim-dap: "
        .. tostring(has_dap)
        .. ", vimspector: "
        .. tostring(has_vimspector)
        .. ")"
    )
  else
    health.warn("neither nvim-dap nor vimspector installed — JCdebug* commands won't work")
  end

  if require("jc.tools").resolve_jol() then
    health.ok("jol jar: " .. require("jc.tools").jol_path)
  else
    health.info("jol jar not found in ~/.m2 — :JCutilJol will offer to download it via maven")
  end

  -- java treesitter parser (class generator uses it to resolve packages)
  if pcall(vim.treesitter.language.add, "java") then
    health.ok("treesitter java parser available")
  else
    health.warn("treesitter java parser missing — class generation package detection degraded")
  end

  -- data dir
  local ok, basedir = pcall(vim.fn["project_root#get_basedir"], "workspaces")
  if ok and vim.fn.filewritable(basedir) == 2 then
    health.ok("data dir writable: " .. basedir)
  else
    health.error("data dir not writable: " .. tostring(basedir))
  end
end

return M
