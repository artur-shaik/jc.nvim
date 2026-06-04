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

return M
