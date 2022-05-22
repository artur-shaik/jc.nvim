local M = {}

local function choose_imports(params, ctx)
    local prompt = "Choose candidate:\n"
    for i, candidate in ipairs(params.arguments[2][1].candidates) do
        print(vim.inspect(candidate))
        prompt = prompt .. i .. '. '.. candidate.fullyQualifiedName .. '\n'
    end
    local choice = tonumber(vim.fn.input(prompt.. "Your choice: "))

    return {params.arguments[2][1].candidates[choice]}
end

local client_commands = {
    ['java.action.organize_imports.chooseImports'] = choose_imports
}

vim.lsp.handlers['workspace/executeClientCommand'] = function(_, params, ctx)
    if client_commands[params.command] ~= nil then
        return client_commands[params.command](params, ctx)
    end

    return ''
end

function M.generate_toString(fields, code_style)
    if not fields then
        vim.lsp.buf_request(0, 'java/checkToStringStatus', vim.lsp.util.make_range_params(), function (e, r)
            if r then
                vim.fn['generators#GenerateToString'](r.fields)
            else
                vim.log(vim.inspect(e), vim.log.levels.ERROR)
            end
        end)
    else
        vim.lsp.buf_request(0, 'workspace/didChangeConfiguration', {
            settings = {['java.codeGeneration.toString.codeStyle'] = code_style }},
            function () end)

        local params = vim.lsp.util.make_range_params()
        vim.lsp.buf_request(0, 'java/generateToString', {context = params, fields = fields}, function (e, r)
            if not e then
                vim.lsp.util.apply_workspace_edit(r, 'utf-16')
            else
                vim.log(vim.inspect(e), vim.log.levels.ERROR)
            end
        end)
    end
end

function M.organize_imports()
    vim.lsp.buf_request(0, 'java/organizeImports', vim.lsp.util.make_range_params(), function (e, r)
        if not e then
            vim.lsp.util.apply_workspace_edit(r, 'utf-16')
        else
            vim.log(vim.inspect(e), vim.log.levels.ERROR)
        end
    end)
end

return M
