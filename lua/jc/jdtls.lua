local M = {}

vim.lsp.handlers['workspace/executeClientCommand'] = function(_, params, ctx)
    local prompt = "Choose candidate:\n"
    for i, candidate in ipairs(params.arguments[2][1].candidates) do
        print(vim.inspect(candidate))
        prompt = prompt .. i .. '. '.. candidate.fullyQualifiedName .. '\n'
    end
    local choice = tonumber(vim.fn.input(prompt.. "Your choice: "))

    return {params.arguments[2][1].candidates[choice]}
end

function M.organizeImports()
    vim.lsp.buf_request(0, 'java/organizeImports', vim.lsp.util.make_range_params(), function (e, r)
        if not e then
            vim.lsp.util.apply_workspace_edit(r, 'utf-16')
        else
            print(vim.inspect(e))
        end
    end)
end

return M
