local output = require("jc.output")()

Job = {}

function Job:new(command, opts, on_success, on_failure)
    return setmetatable({
        command = command,
        opts = opts,
        on_success = on_success,
        on_failure = on_failure,
        output = output
    }, { __index = Job })
end

function Job:_on_stdout(data, event)
    if event == 'stdout' then
        vim.defer_fn(function ()
            self.output:append(data[1]:gsub("%c*", ""):gsub("\n*", ""):gsub("\r*", ""))
        end, 1)
    end
end

function Job:_on_exit(data, event)
    if event == 'exit' and data == 0 then
        self:on_success()
        self.output:close()
    else
        self:on_failure(data)
    end
end

function Job:execute()
    self.output:open()
    if self.command.title then
        self.output:new_line()
        self.output:append(self.command.title)
        self.output:new_line()
    end
    self.output:append("> " .. vim.fn.join(self.command.exec, " "))

    self.opts.on_stdout = function (_, data, event)
        self:_on_stdout(data, event)
    end
    self.opts.on_stderr = function (_, data, _)
        self:_on_stdout(data, 'stdout')
    end
    self.opts.on_exit = function (_, data, event)
        self:_on_exit(data, event)
    end

    self.job_id = vim.fn.jobstart(self.command.exec, self.opts)
    if self.job_id == 0 then
        self.output:append("JC ERROR: invalid arguments")
    elseif self.job_id < 0 then
        self.output:append("JC ERROR: " .. self.command.exec[1] .. " is not executable")
    end
end

return Job
