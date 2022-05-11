local servers = require "nvim-lsp-installer.servers"

local M = {}

local function resolve_jdtls()
    local jdtls_path = servers.get_server_install_path('jdtls')
    return {
        jar = vim.fn.expand(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar'),
        config = vim.fn.expand(jdtls_path .. '/config_linux'),
    }
end

local function resolve_path()
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
    local jdtls_path = resolve_jdtls()
    return {
        workspace_dir = '/tmp/workspace-root/' .. project_name,
        jdtls = jdtls_path,
        java_debug = vim.fn.expand("~/.m2/repository/com/microsoft/java/com.microsoft.java.debug.plugin/*/com.microsoft.java.debug.plugin-*.jar"),
    }
end

function M.jdtls_setup(config)
    local paths = resolve_path()
    require('lspconfig').jdtls.setup{
        on_attach = M.on_attach,
        cmd = {
            config.java_exec,
            '-Declipse.application=org.eclipse.jdt.ls.core.id1',
            '-Dosgi.bundles.defaultStartLevel=4',
            '-Declipse.product=org.eclipse.jdt.ls.core.product',
            '-Dlog.protocol=true',
            '-Dlog.level=ALL',
            '-Xms1g',
            '--add-modules=ALL-SYSTEM',
            '--add-opens', 'java.base/java.util=ALL-UNNAMED',
            '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
            '-jar', paths.jdtls.jar,
            '-configuration', paths.jdtls.config,
            '-data', paths.workspace_dir
        },
        settings = {
            java = {
            }
        },
        init_options = {
            bundles = {
                paths.java_debug
            }
        },
    }
end

return M
