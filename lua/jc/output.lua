Output = {}

function Output:new()
    local output_buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[output_buffer].buftype='nofile'
    vim.bo[output_buffer].bufhidden='hide'
    vim.bo[output_buffer].swapfile=false

    return setmetatable({ output_buffer = output_buffer }, { __index = Output })
end

function Output:_window_config()
    local border = vim.g.workbench_border or "double"

    local ui = vim.api.nvim_list_uis()[1]

    local width = math.floor(ui.width * 0.8)
    local height = math.floor(ui.height * 0.6)
    return {
        relative = "editor",
        width = width,
        height = height,
        col = (ui.width - width) / 2,
        row = (ui.height - height) / 2,
        style = 'minimal',
        focusable = false,
        border = border
    }
end

function Output:open()
    if not self.output_window then
        self.output_window = vim.api.nvim_open_win(self.output_buffer, true, self:_window_config())
    end
end

function Output:append(data)
    if data and self.output_window then
        vim.api.nvim_set_current_win(self.output_window)
        vim.fn.appendbufline(self.output_buffer, vim.fn.line('$'), data)
        vim.fn.cursor(vim.fn.line('$'), vim.fn.col("$"))
    end
end

function Output:new_line()
    vim.api.nvim_set_current_win(self.output_window)
    vim.fn.appendbufline(self.output_buffer, vim.fn.line('$'), "")
    vim.fn.cursor(vim.fn.line('$'), vim.fn.col("$"))
end

function Output:close()
    vim.api.nvim_win_close(self.output_window, true)
    self.output_window = nil
end

local output
return function ()
    if output then
        return output
    end
    output = Output:new()
    return output
end
