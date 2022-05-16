local M = {}
local settings = require('jc.settings')
local lsp = require('jc.lsp')

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

local function resolve_main_class(callback)
    lsp.executeCommand({command = 'vscode.java.resolveMainClass'}, function (response)
        if #response > 0 then
            callback(response[1].mainClass)
        else
            callback()
        end
    end)
end

local function resolve_classpaths(main_class, callback)
    lsp.executeCommand({
        command = 'vscode.java.resolveClasspath',
        arguments = {
            main_class,
            vim.fn['project_root#get_project_name']()
            }
        },
        callback,
        callback)
end

function M.debug_launch()
    resolve_main_class(function (main_class)
        resolve_classpaths(main_class, function (classpaths)
            if not classpaths then
                classpaths = { "${workspaceRoot}/" }
            else
                classpaths = classpaths[2]
            end
            lsp.executeCommand({command = 'vscode.java.startDebugSession'}, function (response)
                vim.fn['vimspector#LaunchWithConfigurations']({
                   attach = {
                     adapter = {
                         name = 'vscode-java',
                         port = response
                     },
                     configuration = {
                        request = 'launch',
                        mainClass = main_class,
                        args = ask_for('arguments', ''),
                        classPaths = classpaths,
                        console = "integratedTerminal",
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
        end)
    end)
end

function M.debug_attach()
    lsp.executeCommand({command = 'vscode.java.startDebugSession'}, function (response)
        vim.fn['vimspector#LaunchWithConfigurations']({
           attach = {
             adapter = {
                 name = 'vscode-java',
                 port = response
             },
             configuration = {
                request = 'attach',
                host = ask_for('host', '127.0.0.1'),
                port = ask_for('port', '9000')
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
