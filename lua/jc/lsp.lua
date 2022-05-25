local M = {}
local opts = { noremap=true, silent=true }

function M.on_attach(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-k>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>D', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>ca', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gr', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>F', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)

    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jI', '<cmd>lua require("jc.jdtls").organize_imports()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>I', '<cmd>lua require("jc.jdtls").organize_imports()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jts', '<cmd>lua require("jc.jdtls").generate_toString()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jeq', '<cmd>lua require("jc.jdtls").generate_hashCodeAndEquals()<CR>', opts)

    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jA', '<cmd>lua require("jc.jdtls").generate_accessors()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>js', '<cmd>lua require("jc.jdtls").generate_accessor("s")<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jg', '<cmd>lua require("jc.jdtls").generate_accessor("g")<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>ja', '<cmd>lua require("jc.jdtls").generate_accessor("gs")<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>s', '<cmd>lua require("jc.jdtls").generate_accessor("s")<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>g', '<cmd>lua require("jc.jdtls").generate_accessor("g")<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>a', '<cmd>lua require("jc.jdtls").generate_accessor("sg")<CR>', opts)

    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jc', '<cmd>lua require("jc.jdtls").generate_constructor(nil, nil, {default = false})<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>jcc', '<cmd>lua require("jc.jdtls").generate_constructor(nil, nil, {default = true})<CR>', opts)
end

function M.executeCommand(command, callback, on_failure)
    local clients = vim.lsp.buf_get_clients()
    local capableClient = nil

    for _, client in ipairs(clients) do
        for _, serverCommand in ipairs(client.server_capabilities.executeCommandProvider.commands) do
            if serverCommand == command.command then
                capableClient = client
                break
            end
        end
        if capableClient then
            break
        end
    end

    if not capableClient then
        callback({ error = "No capable client found for this command" }, nil)
    else
        capableClient.request("workspace/executeCommand", command, function (error, response)
            if error then
                if on_failure then
                    on_failure()
                else
                    vim.notify(vim.inspect(error), vim.log.levels.ERROR)
                end
            else
                callback(response)
            end
        end)
    end
end

return M
