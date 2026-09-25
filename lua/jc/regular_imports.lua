local paths = require("jc.path")

local RegularImports = {}

-- The workspace dir depends on the current project, so it can change within one
-- nvim session (open a file from another project) - create it right before a
-- write instead of once at construction.
local function ensure_dir()
  local dir = paths.get_workspace_dir()
  if vim.fn.isdirectory(dir) == 1 then
    return true
  end
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then
    vim.notify("jc: couldn't create workspace dir " .. dir .. ": " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

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

-- Never let a write throw: this runs inside the synchronous
-- workspace/executeClientCommand handler for choose_imports, where an error
-- turns into a -32603 back to jdtls instead of a chosen candidate.
function RegularImports:write(lines)
  if not ensure_dir() then
    return false
  end
  local file = self.filename()
  local ok, err = pcall(vim.fn.writefile, lines, file)
  if not ok then
    vim.notify("jc: couldn't save " .. file .. ": " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

function RegularImports:add(class_name)
  local loaded = self:load()
  table.insert(loaded, class_name)
  self:write(loaded)
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
    self:write(loaded)
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
