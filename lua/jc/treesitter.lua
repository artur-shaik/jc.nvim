local M = {}

local function get_text(node)
  local line, row, line_end, row_end = node:range()
  local lines = vim.api.nvim_buf_get_lines(0, line, line_end + 1, false)
  local result = nil
  if #lines > 0 then
    if line == line_end then
      result = vim.trim(string.sub(lines[1], row, row_end))
    else
      for i, _ in ipairs(lines) do
        if i == 1 then
          lines[i] = vim.trim(string.sub(lines[i], row + 1, #lines[i]))
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

-- name of the first class declared in the current buffer (used for
-- decompiled jdt:// buffers where the filename isn't meaningful)
function M.get_class_name()
  local tree = vim.treesitter.get_parser():trees()[1]
  for node in tree:root():iter_children() do
    if node:type() == "class_declaration" then
      for child in node:iter_children() do
        if child:type() == "identifier" then
          return get_text(child)
        end
      end
    end
  end
  return nil
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

-- the qualifier of the "Qualifier.member" access under the cursor (e.g. cursor
-- on MyEnum.A or A returns "MyEnum"), or nil
function M.qualifier_at_cursor()
  local node = vim.treesitter.get_node()
  while node do
    if node:type() == "field_access" then
      local object = node:field("object")[1]
      if object and object:type() == "identifier" then
        return vim.treesitter.get_node_text(object, 0)
      end
    end
    node = node:parent()
  end
  return nil
end

-- unique member names of every "qualifier.member" access in the buffer (e.g.
-- the enum constants used: { "MON", "TUE" }). Collected in one parse so it is
-- stable while the caller edits the buffer.
function M.qualified_member_names(qualifier)
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then
    return {}
  end
  local root = parser:parse()[1]:root()
  local query =
    vim.treesitter.query.parse("java", "(field_access object: (identifier) @obj field: (identifier) @field) @fa")
  local seen, names = {}, {}
  for id, node in query:iter_captures(root, 0) do
    if query.captures[id] == "fa" then
      local object = node:field("object")[1]
      local field = node:field("field")[1]
      if object and field and vim.treesitter.get_node_text(object, 0) == qualifier then
        local name = vim.treesitter.get_node_text(field, 0)
        if not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
  end
  return names
end

return M
