local M = {}

function M.generate_class()
  vim.fn["class_generator#CreateClass"]()
end

return M
