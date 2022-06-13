local Chains = {}

function Chains:new()
  return setmetatable({ queue = {} }, { __index = Chains })
end

function Chains:add(command)
  table.insert(self.queue, command)
end

function Chains:execute_next_if_exists()
  if #self.queue > 0 then
    local command = table.remove(self.queue, 1)
    self:execute(command)
  end
end

function Chains:execute(command)
  print("executing command: " .. command)
  vim.fn.luaeval(command)
end

local chains
return function()
  if chains then
    return chains
  end
  chains = Chains:new()
  return chains
end
