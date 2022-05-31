local M = {}

local function get_text(node)
  local line, row, line_end, row_end = node:range()
  local lines = vim.api.nvim_buf_get_lines(0, line, line_end + 1, false)
  local result = nil
  if #lines > 0 then
    if line == line_end then
      result = string.sub(lines[1], row, row_end)
    else
      for i, _ in ipairs(lines) do
        if i == 1 then
          lines[i] = vim.fn.trim(string.sub(lines[i], row + 1, #lines[i]))
        elseif i == #lines then
          lines[i] = vim.trim(string.sub(lines[i], 1, row_end))
        else
          lines[i] = vim.trim(lines[i])
        end
      end
      result = vim.fn.join(lines, "")
    end
  end
  return result
end

function M.get_package()
  local tree = vim.treesitter.get_parser():trees()[1]
  for node in tree:root():iter_children() do
    if node:type() == "package_declaration" then
      for child in node:iter_children() do
        if child:type() == "scoped_identifier" then
          return get_text(child)
        end
      end
      break
    end
  end
  return nil
end

return M
