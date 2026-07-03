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
