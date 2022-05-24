local M = {}

local function choose_imports(params, _)
    local prompt = "Choose candidate:\n"
    for i, candidate in ipairs(params.arguments[2][1].candidates) do
        prompt = prompt .. i .. '. '.. candidate.fullyQualifiedName .. '\n'
    end
    local choice = tonumber(vim.fn.input(prompt.. "Your choice: "))

    return {params.arguments[2][1].candidates[choice]}
end

local function set_configuration(settings)
    vim.lsp.buf_request(0, 'workspace/didChangeConfiguration', {
        settings = settings}, function () end)
end

local client_commands = {
    ['java.action.organizeImports.chooseImports'] = choose_imports
}

vim.lsp.handlers['workspace/executeClientCommand'] = function(_, params, ctx)
    if client_commands[params.command] ~= nil then
        return client_commands[params.command](params, ctx)
    end

    return ''
end

local function document_symbols(callback)
    vim.lsp.buf_request(0, 'textDocument/documentSymbol', {textDocument = vim.lsp.util.make_text_document_params()}, function (e, r)
        if r then
            callback(r)
        elseif e then
            vim.notify(vim.inspect(e), vim.log.levels.ERROR)
        end
    end)
end

local function filter_fields(symbols)
    local fields = {}
    for _, node in ipairs(symbols[2].children) do
        if node.kind == 8 then
            table.insert(fields, node)
        end
    end

    return fields
end

function M.generate_accessor(accessor)
    document_symbols(function (symbols)
        vim.fn['generators#GenerateAccessor'](filter_fields(symbols), accessor)
    end)
end

function M.generate_accessors(fields)
    if not fields then
        vim.lsp.buf_request(0, 'java/resolveUnimplementedAccessors', vim.lsp.util.make_range_params(), function (e, r)
            if r then
                vim.fn['generators#GenerateAccessors'](r)
            else
                vim.notify(vim.inspect(e), vim.log.levels.ERROR)
            end
        end)
    else
        set_configuration({
            ['java.codeGeneration.insertionLocation'] = 'lastMember' })

        vim.lsp.buf_request(0, 'java/generateAccessors', {
            context = vim.lsp.util.make_range_params(), accessors = fields},
            function (e, r)
                if r then
                    vim.lsp.util.apply_workspace_edit(r, 'utf-16')
                elseif e then
                    vim.notify(vim.inspect(e), vim.log.levels.ERROR)
                end
            end)
    end
end

function M.generate_hashCodeAndEquals(fields)
    if not fields then
        vim.lsp.buf_request(0, 'java/checkHashCodeEqualsStatus', vim.lsp.util.make_range_params(), function (e, r)
            if r then
                vim.fn['generators#GenerateHashCodeAndEquals'](r.fields)
            else
                vim.notify(vim.inspect(e), vim.log.levels.ERROR)
            end
        end)
    else
        set_configuration({
            ['java.codeGeneration.insertionLocation'] = 'lastMember' })

        vim.lsp.buf_request(0, 'java/generateHashCodeEquals', {
            context = vim.lsp.util.make_range_params(),
            fields = fields,
            regenerate = true},
            function (e, r)
                if r then
                    vim.lsp.util.apply_workspace_edit(r, 'utf-16')
                elseif e then
                    vim.notify(vim.inspect(e), vim.log.levels.ERROR)
                end
            end)
    end
end

function M.generate_toString(fields, params)
    if not fields then
        vim.lsp.buf_request(0, 'java/checkToStringStatus', vim.lsp.util.make_range_params(), function (e, r)
            if r then
                vim.fn['generators#GenerateToString'](r.fields)
            else
                vim.notify(vim.inspect(e), vim.log.levels.ERROR)
            end
        end)
    else
        set_configuration({
            ['java.codeGeneration.toString.codeStyle'] = params.code_style,
            ['java.codeGeneration.insertionLocation'] = 'lastMember' })

        vim.lsp.buf_request(0, 'java/generateToString', {
            context = vim.lsp.util.make_range_params(),
            fields = fields},
            function (e, r)
                if r then
                    vim.lsp.util.apply_workspace_edit(r, 'utf-16')
                elseif e then
                    vim.notify(vim.inspect(e), vim.log.levels.ERROR)
                end
            end)
    end
end

function M.organize_imports()
    vim.lsp.buf_request(0, 'java/organizeImports', vim.lsp.util.make_range_params(), function (e, r)
        if r then
            vim.lsp.util.apply_workspace_edit(r, 'utf-16')
        elseif e then
            vim.notify(vim.inspect(e), vim.log.levels.ERROR)
        end
    end)
end

return M
