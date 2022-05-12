local M = {}
local project_name = vim.fn.substitute(
                        vim.fn['project_root#find'](), '[\\/:;.]', '_', 'g')

local function download_jdtls()
    local servers = require("nvim-lsp-installer.servers")
    local installer = require("nvim-lsp-installer")

    vim.notify("Installing JDTLS language server...", vim.log.levels.INFO)
    installer.install('jdtls')

    local timer = vim.loop.new_timer()
    timer:start(2000, 750, function()
        if servers.is_server_installed('jdtls') then
            timer:close()
            installer.info_window.close()
            vim.defer_fn(function()
                M.jdtls_setup(M.config)
                vim.notify("JDTLS language server installed, completion should work now", vim.log.levels.INFO)
            end, 100)
        end
    end)
end

local function resolve_jdtls()
    local ok, servers = pcall(require, "nvim-lsp-installer.servers")
    assert(ok, 'nvim-lsp-installer is not installed')

    if servers.is_server_installed('jdtls') then
        local jdtls_path = servers.get_server_install_path('jdtls')
        return {
            jar = vim.fn.expand(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar'),
            config = vim.fn.expand(jdtls_path .. '/config_linux'),
        }
    else
        vim.loop.new_timer():start(1000, 0, vim.schedule_wrap(function()
            download_jdtls()
        end))
        return false
    end
end

local function resolve_path()
    local jdtls_path = resolve_jdtls()
    if not jdtls_path then
        return false
    end
    return {
        workspace_dir = vim.fn['project_root#get_basedir']('workspaces') .. project_name,
        jdtls = jdtls_path,
        java_debug = vim.fn.expand("~/.m2/repository/com/microsoft/java/com.microsoft.java.debug.plugin/*/com.microsoft.java.debug.plugin-*.jar"),
    }
end

local function lspconfig_setup(paths)
    if not paths then
        return
    end

    local cmd = {
        M.config.java_exec,
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
    }
    vim.notify("jdtls execution command: " .. vim.inspect(cmd), vim.log.levels.DEBUG)

    require('lspconfig').jdtls.setup{
        on_attach = M.config.on_attach,
        cmd = cmd,
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

function M.jdtls_setup(config)
    M.config = config
    lspconfig_setup(resolve_path())
end

return M
