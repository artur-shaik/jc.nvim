describe("flip_call_args", function()
  local refactor = require("jc.refactor")

  -- put `code` in a java buffer, move the cursor onto (row,col) — 1-based row,
  -- 0-based col — run flip_call_args, return the resulting lines
  local function flip(lines, row, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "java"
    vim.api.nvim_set_current_buf(buf)
    -- make sure a java parser is attached before we query nodes
    vim.treesitter.get_parser(buf, "java"):parse()
    vim.api.nvim_win_set_cursor(0, { row, col })
    refactor.flip_call_args()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  it("swaps receiver and argument of equals", function()
    -- cursor on `.equals`
    local out = flip({ "class C { boolean m() { return a.equals(b); } } " }, 1, 27)
    assert.are.equal("class C { boolean m() { return b.equals(a); } } ", out[1])
  end)

  it("keeps a surrounding ! negation and the method name", function()
    local out = flip({
      "class C {",
      "  boolean m() {",
      "    return !x.getType().equals(Type.A);",
      "  }",
      "}",
    }, 3, 25)
    assert.are.equal("    return !Type.A.equals(x.getType());", out[3])
  end)

  it("works for any one-argument call, e.g. compareTo", function()
    local out = flip({ "class C { int m() { return a.compareTo(b); } }" }, 1, 30)
    assert.are.equal("class C { int m() { return b.compareTo(a); } }", out[1])
  end)

  it("flips a literal argument", function()
    local out = flip({ 'class C { boolean m() { return s.equals("x"); } }' }, 1, 34)
    assert.are.equal('class C { boolean m() { return "x".equals(s); } }', out[1])
  end)

  it("leaves a zero-argument call untouched", function()
    local out = flip({ "class C { String m() { return a.trim(); } }" }, 1, 30)
    assert.are.equal("class C { String m() { return a.trim(); } }", out[1])
  end)

  it("leaves a two-argument call untouched", function()
    local out = flip({ "class C { int m() { return Math.max(a, b); } }" }, 1, 33)
    assert.are.equal("class C { int m() { return Math.max(a, b); } }", out[1])
  end)
end)
