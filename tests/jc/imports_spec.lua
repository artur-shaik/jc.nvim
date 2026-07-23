describe("replace import (set_import)", function()
  local jdtls = require("jc.jdtls")

  local function run(lines, name, fqn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    jdtls._set_import(buf, name, fqn)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  it("replaces an existing import of the same simple name", function()
    local out = run({
      "package p;",
      "",
      "import lombok.Value;",
      "",
      "@Value class C {}",
    }, "Value", "org.springframework.beans.factory.annotation.Value")
    assert.are.equal("import org.springframework.beans.factory.annotation.Value;", out[3])
    assert.is_nil(vim.tbl_filter(function(l)
      return l == "import lombok.Value;"
    end, out)[1])
  end)

  it("adds after the last import when none matches", function()
    local out = run({
      "package p;",
      "",
      "import java.util.List;",
      "",
      "class C {}",
    }, "Value", "lombok.Value")
    assert.are.equal("import java.util.List;", out[3])
    assert.are.equal("import lombok.Value;", out[4])
  end)

  it("adds after the package line when there are no imports", function()
    local out = run({ "package p;", "", "class C {}" }, "Value", "lombok.Value")
    assert.are.equal("package p;", out[1])
    assert.are.equal("import lombok.Value;", out[3])
  end)
end)

describe("_filter_type_symbols", function()
  local jdtls = require("jc.jdtls")
  local function sym(name, kind, container, uri)
    return { name = name, kind = kind, containerName = container, location = { uri = uri } }
  end

  it("exact match keeps only the exact simple name", function()
    local r = {
      sym("Data", 11, "lombok", "file:///x"),
      sym("DataSource", 11, "javax.sql", "file:///y"),
    }
    assert.are.same({ "lombok.Data" }, jdtls._filter_type_symbols(r, "Data", true))
  end)

  it("prefix match finds longer names, not unrelated ones", function()
    local r = {
      sym("Getter", 11, "lombok", "jdt://x"),
      sym("GetMapping", 11, "org.springframework.web.bind.annotation", "jdt://y"),
      sym("Target", 11, "java.lang.annotation", "jdt://z"),
    }
    local out = jdtls._filter_type_symbols(r, "Get", false)
    assert.are.equal(2, #out)
    assert.is_truthy(vim.tbl_contains(out, "lombok.Getter"))
    assert.is_falsy(vim.tbl_contains(out, "java.lang.annotation.Target"))
  end)

  it("drops non-importable, non-type and nested symbols", function()
    local r = {
      sym("Foo", 11, "pkg", "untitled:x"), -- not importable
      sym("Bar", 6, "pkg", "file:///x"), -- method kind (not a type)
      sym("Baz", 11, "Outer", "file:///y"), -- nested (enclosing is a type)
      sym("Ok", 11, "com.app", "file:///z"), -- valid
    }
    -- empty prefix matches every name, isolating the other filters
    assert.are.same({ "com.app.Ok" }, jdtls._filter_type_symbols(r, "", false))
  end)

  it("dedupes identical FQNs", function()
    local r = {
      sym("Data", 11, "lombok", "file:///a"),
      sym("Data", 11, "lombok", "file:///b"),
    }
    assert.are.equal(1, #jdtls._filter_type_symbols(r, "Data", true))
  end)
end)

describe("_prioritize_types", function()
  local jdtls = require("jc.jdtls")

  local function with_buffer(lines, fqns)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return jdtls._prioritize_types(fqns, buf)
  end

  it("sorts a type already imported in the buffer to the top", function()
    local out = with_buffer({
      "package p;",
      "",
      "import org.other.Data;",
      "",
      "class C {}",
    }, { "lombok.Data", "org.other.Data", "com.acme.Data" })
    assert.are.equal("org.other.Data", out[1])
  end)

  it("keeps the rest alphabetical after the preferred ones", function()
    local out = with_buffer({ "class C {}" }, { "z.B", "a.A", "m.M" })
    -- nothing imported -> pure alphabetical
    assert.are.same({ "a.A", "m.M", "z.B" }, out)
  end)
end)
