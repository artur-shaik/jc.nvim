local M = {}

-- derived dirs are memoized per project root, so switching between
-- projects in one session yields the right paths (the old code cached
-- the first project forever)
local cache = {}

local function locate_buffer(project_root_file)
  if vim.fn.filereadable(project_root_file) == 1 then
    vim.cmd("lcd " .. vim.fn.fnamemodify(project_root_file, ":h"))
  end
end

local function find_project_path(project_root_file)
  local project_name = vim.fn.substitute(project_root_file, "[\\/:;.]", "_", "g")
  return {
    data_dir = vim.fn["project_root#get_basedir"]("data"),
    project_root_file = project_root_file,
    workspace_dir = vim.fn["project_root#get_basedir"]("workspaces") .. project_name .. "/",
  }
end

function M.get_project_dirs()
  local project_root_file = vim.fn["project_root#find"]()
  local paths = cache[project_root_file]
  if not paths then
    paths = find_project_path(project_root_file)
    cache[project_root_file] = paths
  end
  locate_buffer(project_root_file)
  return paths
end

function M.get_data_dir()
  return M.get_project_dirs().data_dir
end

function M.get_workspace_dir()
  return M.get_project_dirs().workspace_dir
end

return M
