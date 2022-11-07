local paths = require("jc.path")

RegularImports = {}

function RegularImports.new()
  return setmetatable({}, { __index = RegularImports })
end

function RegularImports.filename()
  return paths.get_workspace_dir() .. ".regular_imports"
end

function RegularImports:load()
  local filename = self.filename()
  if vim.fn.filereadable(filename) == 1 then
    return vim.fn.readfile(filename)
  end
  return {}
end

function RegularImports:add(class_name)
  local loaded = self:load()
  table.insert(loaded, class_name)
  vim.fn.writefile(loaded, self.filename())
end

function RegularImports:remove(class_name)
  local loaded = self:load()
  local removed = false
  for index, value in ipairs(loaded) do
    if value == class_name then
      table.remove(loaded, index)
      removed = true
    end
  end
  if removed then
    vim.fn.writefile(loaded, self.filename())
  end
end

local regular_imports
return function()
  if regular_imports then
    return regular_imports
  end
  regular_imports = RegularImports:new()
  return regular_imports
end
