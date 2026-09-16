describe("flip_call_args", function()
  local refactor = require("jc.refactor")

  -- Put `lines` in a java buffer, move the cursor to (row 1-based, col 0-based),
  -- run flip_call_args, return the resulting lines. Returns nil when the java
  -- treesitter grammar isn't installed (neovim bundles c/lua/vim/markdown but
  -- not java, so a bare CI runner has no parser) — callers then skip.
  local function flip(lines, row, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "java"
    vim.api.nvim_set_current_buf(buf)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
    if not ok or not parser then
      return nil
    end
    parser:parse()
    vim.api.nvim_win_set_cursor(0, { row, col })
    refactor.flip_call_args()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  it("swaps receiver and argument of equals", function()
    local out = flip({ "class C { boolean m() { return a.equals(b); } } " }, 1, 35)
    if not out then
      return
    end
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
    if not out then
      return
    end
    assert.are.equal("    return !Type.A.equals(x.getType());", out[3])
  end)

  it("works for any one-argument call, e.g. compareTo", function()
    local out = flip({ "class C { int m() { return a.compareTo(b); } }" }, 1, 30)
    if not out then
      return
    end
    assert.are.equal("class C { int m() { return b.compareTo(a); } }", out[1])
  end)

  it("flips a literal argument", function()
    local out = flip({ 'class C { boolean m() { return s.equals("x"); } }' }, 1, 34)
    if not out then
      return
    end
    assert.are.equal('class C { boolean m() { return "x".equals(s); } }', out[1])
  end)

  it("leaves a zero-argument call untouched", function()
    local out = flip({ "class C { String m() { return a.trim(); } }" }, 1, 30)
    if not out then
      return
    end
    assert.are.equal("class C { String m() { return a.trim(); } }", out[1])
  end)

  it("leaves a two-argument call untouched", function()
    local out = flip({ "class C { int m() { return Math.max(a, b); } }" }, 1, 33)
    if not out then
      return
    end
    assert.are.equal("class C { int m() { return Math.max(a, b); } }", out[1])
  end)
end)

describe("move destination derivation", function()
  local refactor = require("jc.refactor")

  it("_strip_package strips segments off a workspace path", function()
    assert.are.equal(
      "/proj/src/main/java",
      refactor._strip_package("/proj/src/main/java/com/app/model", "com.app.model")
    )
  end)

  it("_strip_package strips segments off an absolute uri", function()
    assert.are.equal(
      "file:///home/u/proj/src/main/java",
      refactor._strip_package("file:///home/u/proj/src/main/java/com/app/model", "com.app.model")
    )
  end)

  it("_strip_package returns the location itself for the default package", function()
    assert.are.equal("/proj/src/main/java", refactor._strip_package("/proj/src/main/java", ""))
  end)

  local base = {
    project = "app",
    displayName = "com.app.model",
    path = "/app/src/main/java/com/app/model",
    uri = "file:///home/u/app/src/main/java/com/app/model",
  }

  it("_derive_destination builds path and uri for a new sub-package", function()
    local d = refactor._derive_destination("com.app.model.dto", base)
    assert.are.equal("/app/src/main/java/com/app/model/dto", d.path)
    assert.are.equal("file:///home/u/app/src/main/java/com/app/model/dto", d.uri)
    assert.are.equal("com.app.model.dto", d.displayName)
    assert.are.equal("app", d.project)
    assert.is_false(d.isDefaultPackage)
  end)

  it("_derive_destination builds a sibling package under the same root", function()
    local d = refactor._derive_destination("com.app.other", base)
    assert.are.equal("/app/src/main/java/com/app/other", d.path)
    assert.are.equal("file:///home/u/app/src/main/java/com/app/other", d.uri)
  end)
end)

describe("move destinations", function()
  local refactor = require("jc.refactor")

  local MAIN = {
    project = "app",
    displayName = "com.example",
    path = "/app/src/main/java/com/example",
    uri = "file:///w/app/src/main/java/com/example",
  }
  local TEST = {
    project = "app",
    displayName = "com.example",
    path = "/app/src/test/java/com/example",
    uri = "file:///w/app/src/test/java/com/example",
  }
  local TEST_DTO = {
    project = "app",
    displayName = "com.example.dto",
    path = "/app/src/test/java/com/example/dto",
    uri = "file:///w/app/src/test/java/com/example/dto",
  }
  local ALL = { MAIN, TEST, TEST_DTO }

  it("names the source root a destination lives in", function()
    assert.are.equal("src/main/java", refactor._source_root_label("/app/src/main/java"))
    assert.are.equal("src/test/java", refactor._source_root_label("/w/mod/src/test/java"))
  end)

  it("keeps the picked entry when the package name is confirmed unchanged", function()
    -- the same name exists in both roots: the pick must win, not the last match
    assert.are.same(MAIN, refactor._resolve_destination(ALL, MAIN, "com.example"))
    assert.are.same(TEST, refactor._resolve_destination(ALL, TEST, "com.example"))
  end)

  it("resolves an edited name within the source root that was picked", function()
    assert.are.same(TEST_DTO, refactor._resolve_destination(ALL, TEST, "com.example.dto"))
    -- no com.example.dto under src/main: nil, so the caller creates it there
    assert.is_nil(refactor._resolve_destination(ALL, MAIN, "com.example.dto"))
  end)

  it("reports nothing for a package that exists nowhere", function()
    assert.is_nil(refactor._resolve_destination(ALL, MAIN, "com.example.brand.new"))
  end)
end)
