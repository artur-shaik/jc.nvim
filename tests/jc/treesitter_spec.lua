describe("type_at_cursor", function()
  local ts = require("jc.treesitter")

  -- returns the type name for the cursor at (row 1-based, col 0-based), or nil.
  -- Returns false when the java grammar isn't installed (bare CI) so callers skip.
  local function at(lines, row, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "java"
    vim.api.nvim_set_current_buf(buf)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
    if not ok or not parser then
      return false
    end
    parser:parse()
    vim.api.nvim_win_set_cursor(0, { row, col })
    return ts.type_at_cursor()
  end

  it("returns the capitalized type under the cursor", function()
    -- cursor on `Foo`
    local out = at({ "class C { void m() { Foo x; } }" }, 1, 21)
    if out == false then
      return
    end
    assert.are.equal("Foo", out)
  end)

  it("returns nil on a lowercase identifier (variable, not a type)", function()
    -- cursor on `x`
    local out = at({ "class C { void m() { Foo x; } }" }, 1, 25)
    if out == false then
      return
    end
    assert.is_nil(out)
  end)

  it("finds the type in a `new` expression", function()
    -- cursor on `Bar`
    local out = at({ "class C { Object m() { return new Bar(); } }" }, 1, 35)
    if out == false then
      return
    end
    assert.are.equal("Bar", out)
  end)
end)

describe("enclosing_declaration", function()
  local ts = require("jc.treesitter")

  -- node type of the enclosing `kind` for the cursor at (row 1-based, col
  -- 0-based), or the string "skip" when the java grammar isn't installed.
  local function enclosing(lines, row, col, kind)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "java"
    vim.api.nvim_set_current_buf(buf)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
    if not ok or not parser then
      return "skip"
    end
    parser:parse()
    vim.api.nvim_win_set_cursor(0, { row, col })
    local node = ts.enclosing_declaration(kind)
    return node and node:type() or nil
  end

  local SRC = { "class C {", "  void m() {", "    int x = 1;", "  }", "}" }

  it("finds the enclosing method from inside its body", function()
    local out = enclosing(SRC, 3, 8, "method_declaration")
    if out == "skip" then
      return
    end
    assert.are.equal("method_declaration", out)
  end)

  it("finds the enclosing class from inside a method", function()
    local out = enclosing(SRC, 3, 8, "class_declaration")
    if out == "skip" then
      return
    end
    assert.are.equal("class_declaration", out)
  end)

  it("returns nil for a method when the cursor is at class level", function()
    -- cursor on the class name, not inside any method
    local out = enclosing(SRC, 1, 6, "method_declaration")
    if out == "skip" then
      return
    end
    assert.is_nil(out)
  end)
end)
