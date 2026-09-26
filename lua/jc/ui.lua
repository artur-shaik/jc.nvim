local settings = require("jc.settings")

local M = {}

-- ask for a value, remembering the answer per project
-- (shared by the dap and vimspector debug backends); async via vim.ui.input
function M.ask_for(name, default, callback)
  local remembered = settings.read_project("debug-" .. name, default)
  vim.ui.input({ prompt = "Debug " .. name .. " (" .. remembered .. "): " }, function(result)
    if result == nil then
      return -- cancelled
    end
    if #result == 0 then
      result = remembered
    elseif result ~= remembered then
      settings.write_project("debug-" .. name, result)
    end
    callback(result)
  end)
end

-- Echo the latest line of a long-running command in the cmdline, refreshed in
-- place, so a silent wait (a gradle build, a maven download) shows it is alive.
-- Returns { note = fn(chunk), stop = fn() }: feed it the process output, stop it
-- when the process ends.
function M.progress(label)
  local latest = "starting..."
  local timer = vim.uv.new_timer()
  if timer then
    timer:start(
      400,
      400,
      vim.schedule_wrap(function()
        -- keep it on one line: a wrapped echo triggers the hit-enter prompt
        local room = math.max(20, (vim.o.columns or 80) - #label - 4)
        local text = #latest > room and ("..." .. latest:sub(-room + 3)) or latest
        vim.api.nvim_echo({ { label .. ": " .. text, "Comment" } }, false, {})
      end)
    )
  end
  return {
    note = function(chunk)
      for line in tostring(chunk or ""):gmatch("[^\r\n]+") do
        line = vim.trim(line)
        if line ~= "" then
          latest = line
        end
      end
    end,
    stop = function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      vim.schedule(function()
        vim.api.nvim_echo({ { "", "" } }, false, {})
      end)
    end,
  }
end

return M
