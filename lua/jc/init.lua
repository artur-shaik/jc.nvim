local M = {}

function M.jdtls(config)
    local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
    local workspace_dir = '/tmp/workspace-root/' .. project_name
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
            '-jar', '/home/ash/.local/share/nvim/lsp_servers/jdtls/plugins/org.eclipse.equinox.launcher_1.6.400.v20210924-0641.jar',
            '-configuration', '/home/ash/.local/share/nvim/lsp_servers/jdtls/config_linux/',
            '-data', workspace_dir
        },
        -- root_dir = require('jdtls.setup').find_root({'.git', 'mvnw', 'gradlew', 'pom.xml'}),
        settings = {
            java = {
            }
        },
        init_options = {
            bundles = {
                "/home/ash/.m2/repository/com/microsoft/java/com.microsoft.java.debug.plugin/0.36.0/com.microsoft.java.debug.plugin-0.36.0.jar"
            }
        },
    }
end

return M
