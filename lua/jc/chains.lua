local Chains = {}

function Chains:new()
  return setmetatable({ queue = {} }, { __index = Chains })
end

function Chains:add(command)
  assert(type(command) == "function", "jc.chains: command must be a function")
  table.insert(self.queue, command)
end

function Chains:execute_next_if_exists()
  if #self.queue > 0 then
    local command = table.remove(self.queue, 1)
    self:execute(command)
  end
end

function Chains:execute(command)
  local ok, err = pcall(command)
  if not ok then
    vim.notify("jc.chains: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local chains
return function()
  if chains then
    return chains
  end
  chains = Chains:new()
  return chains
end
