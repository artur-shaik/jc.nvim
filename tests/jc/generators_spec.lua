describe("generators selection", function()
  local gen = require("jc.generators")

  local fields = {
    { type = "String", name = "a" },
    { type = "int", name = "b" },
    { type = "long", name = "c" },
  }

  it("keeps only fields whose f-line survived", function()
    -- user deleted the f1 line
    local lines = { '"-- header', "f0 --> String a", "f2 --> long c" }
    local selected = gen._select_fields(lines, fields)
    assert.are.same({ fields[1], fields[3] }, selected)
  end)

  it("ignores header and non-f lines", function()
    local lines = { '" q - close', "", "garbage", "f1 --> int b" }
    local selected = gen._select_fields(lines, fields)
    assert.are.same({ fields[2] }, selected)
  end)

  local acc_fields = {
    { fieldName = "name", generateSetter = true },
    { fieldName = "id", generateSetter = false },
  }

  it("sets getter/setter flags from surviving g/s lines", function()
    local lines = { "g0 -->  getName()", "s0 --> setName(name)", "g1 -->  getId()" }
    local selected = gen._select_accessors(lines, acc_fields)
    assert.are.equal(2, #selected)
    assert.are.same({ fieldName = "name", generateGetter = true, generateSetter = true }, selected[1])
    assert.are.same({ fieldName = "id", generateGetter = true, generateSetter = false }, selected[2])
  end)

  it("drops accessors whose lines were removed", function()
    -- only the setter line for name survives
    local lines = { "s0 --> setName(name)" }
    local selected = gen._select_accessors(lines, acc_fields)
    assert.are.same({ { fieldName = "name", generateGetter = false, generateSetter = true } }, selected)
  end)

  it("inline accessor: fields under the cursor line, flags from accessor string", function()
    local symbols = {
      { kind = 8, name = "x", range = { start = { line = 2 }, ["end"] = { line = 2 } } },
      { kind = 8, name = "y", range = { start = { line = 5 }, ["end"] = { line = 5 } } },
    }
    local got = gen._accessor_fields(symbols, "sg", { 2 })
    assert.are.equal(1, #got)
    assert.are.equal("x", got[1].fieldName)
    assert.is_true(got[1].generateSetter)
    assert.is_true(got[1].generateGetter)
  end)

  it("inline accessor: getter only", function()
    local symbols = { { kind = 8, name = "x", range = { start = { line = 0 }, ["end"] = { line = 0 } } } }
    local got = gen._accessor_fields(symbols, "g", { 0 })
    assert.is_true(got[1].generateGetter)
    assert.is_nil(got[1].generateSetter)
  end)
end)
