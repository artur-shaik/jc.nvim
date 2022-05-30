local M = {}

local project_name = vim.fn["project_root#get_name"]()
local workspace_dir = vim.fn["project_root#get_basedir"]("workspaces") .. project_name

function M.read_project(name, default)
  local result = default
  local file_name = workspace_dir .. "." .. name
  if vim.fn.filereadable(file_name) == 1 then
    local file = io.open(file_name)
    if file then
      result = file:read()
      file:close()
    end
  end
  return result
end

function M.write_project(name, value)
  local file_name = workspace_dir .. "." .. name
  local file = io.open(file_name, "w+")
  if file then
    file:write(value)
    file:close()
  end
end

return M
