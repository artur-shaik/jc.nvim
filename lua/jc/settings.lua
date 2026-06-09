local M = {}

-- resolved per call: the project (and thus the workspace dir) can change
-- within one session, so this must not be cached at module load
local function project_file(name)
  local project_name = vim.fn["project_root#get_name"]()
  return vim.fn["project_root#get_basedir"]("workspaces") .. project_name .. "." .. name
end

function M.read_project(name, default)
  local result = default
  local file_name = project_file(name)
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
  local file = io.open(project_file(name), "w+")
  if file then
    file:write(value)
    file:close()
  end
end

return M
