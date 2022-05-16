local M = {}
local settings = require('jc.settings')

local function ask_for(name, default)
    local default_result = settings.read_project('debug-' .. name, default)
    local result = vim.fn.input('Debug ' .. name .. ' (' .. default_result .. '): ')
    if #result == 0 then
        result = default_result
    elseif result ~= default_result then
        settings.write_project('debug-' .. name, result)
    end
    return result
end

function M.debug_attach()
    local lsp = require('jc.lsp')
    lsp.executeCommand({command = 'vscode.java.startDebugSession'}, function (error, response)
        if error then
            vim.notify(vim.inspect(error), vim.log.levels.ERROR)
            return
        end

        local host = ask_for('host', '127.0.0.1')
        local port = ask_for('port', '9000')
        vim.fn['vimspector#LaunchWithConfigurations']({
           attach = {
             adapter = {
                 name = 'vscode-java',
                 port = response
             },
             configuration = {
                request = 'attach',
                host = host,
                port = port
             },
             breakpoints = {
                 exception = {
                     caught = 'N',
                     uncaught = 'N'
                 }
             }
           }
        })
    end)
end

return M
