-- Field-selection buffers for code generation, ported from generators.vim.
-- A scratch buffer lists the candidate fields; the user deletes lines to
-- deselect, then presses a key to confirm. The confirmation collects the
-- remaining lines and calls back into jc.jdtls with the chosen fields.
local M = {}

-- ---- pure selection helpers (exported for tests) ----

-- collect fields whose "f<idx> --> ..." line survived in `lines`
function M._select_fields(lines, fields)
  local selected = {}
  for _, line in ipairs(lines) do
    local idx = line:match("^f(%d+)")
    if idx then
      local field = fields[tonumber(idx) + 1] -- buffer is 0-indexed
      if field then
        table.insert(selected, field)
      end
    end
  end
  return selected
end

-- build accessor field list from surviving "g<idx>"/"s<idx>" lines; each
-- field carries generateGetter/generateSetter flags
function M._select_accessors(lines, fields)
  local by_idx = {}
  local order = {}
  for _, line in ipairs(lines) do
    local kind, idx = line:match("^([gs])(%d+)")
    if kind then
      local i = tonumber(idx) + 1
      local src = fields[i]
      if src then
        local field = by_idx[i]
        if not field then
          field = { fieldName = src.fieldName, generateGetter = false, generateSetter = false }
          by_idx[i] = field
          table.insert(order, field)
        end
        if kind == "g" then
          field.generateGetter = true
        else
          field.generateSetter = true
        end
      end
    end
  end
  return order
end

-- fields for the inline accessor (g/s/sg) from document symbols within the
-- given 0-based line range
function M._accessor_fields(symbols, accessor, line_range)
  local fields = {}
  for _, d in ipairs(symbols or {}) do
    if d.kind == 8 then
      for _, l in ipairs(line_range) do
        if l >= d.range.start.line and l <= d.range["end"].line then
          local field = { fieldName = d.name }
          if accessor:find("s") then
            field.generateSetter = true
          end
          if accessor:find("g") then
            field.generateGetter = true
          end
          table.insert(fields, field)
        end
      end
    end
  end
  return fields
end

-- ---- buffer UI ----

-- open a scratch selection buffer; `commands` is a list of
-- { key, desc, run = function() } and `body` the candidate lines
local function open_buffer(name, title, commands, body)
  if vim.fn.bufwinnr(name) ~= -1 then
    vim.cmd("bwipeout!")
  end
  vim.cmd("silent! split " .. name)
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.wo.wrap = false
  vim.bo[buf].buflisted = false

  local header = {
    '"-----------------------------------------------------',
    '" ' .. title,
    '"',
    '" q                      - close this window',
  }
  for _, command in ipairs(commands) do
    header[#header + 1] = '" ' .. command.key .. "                      - " .. command.desc
  end
  header[#header + 1] = '"-----------------------------------------------------'

  local lines = vim.list_extend(header, body)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd([[syn match Comment "^\".*"]])

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", "<cmd>bwipeout!<CR>", opts)
  for _, command in ipairs(commands) do
    vim.keymap.set("n", command.key, function()
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      vim.cmd("bwipeout!")
      command.run(buf_lines)
    end, opts)
  end

  -- first candidate line, clamped (the list may be empty for a fieldless class)
  local cursor = math.min(#header + 1, vim.api.nvim_buf_line_count(buf))
  vim.api.nvim_win_set_cursor(0, { cursor, 0 })
end

-- "f0 --> type name" candidate lines
local function field_body(fields)
  local body = {}
  for idx, field in ipairs(fields) do
    body[#body + 1] = "f" .. (idx - 1) .. " --> " .. field.type .. " " .. field.name
  end
  return body
end

local function jdtls()
  return require("jc.jdtls")
end

function M.toString(fields)
  local styles = {
    { key = "1", style = "STRING_CONCATENATION" },
    { key = "2", style = "STRING_BUILDER" },
    { key = "3", style = "STRING_BUILDER_CHAINED" },
    { key = "4", style = "STRING_FORMAT" },
  }
  local commands = {}
  for _, s in ipairs(styles) do
    commands[#commands + 1] = {
      key = s.key,
      desc = "generate `toString` " .. s.style,
      run = function(lines)
        jdtls().generate_toString(M._select_fields(lines, fields), { code_style = s.style })
      end,
    }
  end
  open_buffer("__FieldsListBuffer__", "remove unnecessary fields", commands, field_body(fields))
end

function M.hashCodeEquals(fields)
  local commands = {
    {
      key = "1",
      desc = "generate `hashCode and equals`",
      run = function(lines)
        jdtls().generate_hashCodeAndEquals(M._select_fields(lines, fields))
      end,
    },
  }
  open_buffer("__FieldsListBuffer__", "remove unnecessary fields", commands, field_body(fields))
end

function M.constructor(fields, constructors, opts)
  if opts and opts.default then
    jdtls().generate_constructor({}, { default_constructor = true, constructors = constructors })
    return
  end
  local commands = {
    {
      key = "1",
      desc = "generate default constructor",
      run = function()
        jdtls().generate_constructor({}, { default_constructor = true, constructors = constructors })
      end,
    },
    {
      key = "2",
      desc = "generate constructor",
      run = function(lines)
        jdtls().generate_constructor(
          M._select_fields(lines, fields),
          { default_constructor = false, constructors = constructors }
        )
      end,
    },
  }
  open_buffer("__FieldsListBuffer__", "remove unnecessary fields", commands, field_body(fields))
end

function M.accessors(fields)
  local body = {}
  for idx, var in ipairs(fields) do
    local i = idx - 1
    local cap = var.fieldName:sub(1, 1):upper() .. var.fieldName:sub(2)
    body[#body + 1] = "g" .. i .. " -->  get" .. cap .. "()"
    if var.generateSetter then
      body[#body + 1] = "s" .. i .. " --> set" .. cap .. "(" .. var.fieldName .. ")"
    end
    body[#body + 1] = ""
  end
  local commands = {
    {
      key = "s",
      desc = "generate accessors",
      run = function(lines)
        jdtls().generate_accessors(M._select_accessors(lines, fields))
      end,
    },
  }
  open_buffer("__AccessorsBuffer__", "remove unnecessary accessors", commands, body)
end

-- inline accessor for fields under the cursor / visual selection
function M.accessor(symbols, accessor)
  local mode = vim.fn.mode()
  local line_range
  if mode == "v" or mode == "V" or mode == "\22" then
    local l1 = vim.fn.getpos("'<")[2]
    local l2 = vim.fn.getpos("'>")[2]
    line_range = {}
    for l = l1 - 1, l2 - 1 do
      line_range[#line_range + 1] = l
    end
  else
    line_range = { vim.fn.line(".") - 1 }
  end
  jdtls().generate_accessors(M._accessor_fields(symbols, accessor, line_range))
end

return M
