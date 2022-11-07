local M = {}
local paths = nil

local function locate_buffer(project_root_file)
  if vim.fn.filereadable(project_root_file) == 1 then
    vim.cmd("lcd " .. vim.fn.fnamemodify(project_root_file, ":h"))
  end
end

local function find_project_path()
  local result = {
    data_dir = vim.fn["project_root#get_basedir"]("data"),
    vendor_dir = vim.fn["project_root#get_basedir"]("vendor"),
    project_root_file = vim.fn["project_root#find"]()
  }

  local project_name = vim.fn.substitute(result.project_root_file, "[\\/:;.]", "_", "g")
  result.workspace_dir = vim.fn["project_root#get_basedir"]("workspaces") .. project_name .. "/"
  return result
end

function M.get_project_dirs()
  if not paths then
    paths = find_project_path()
  end
  locate_buffer(paths.project_root_file)
  return paths
end

function M.get_data_dir()
  return M.get_project_dirs().data_dir
end

function M.get_workspace_dir()
  return M.get_project_dirs().workspace_dir
end

function M.get_vendor_dir()
  return M.get_project_dirs().vendor_dir
end

return M
