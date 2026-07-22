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
