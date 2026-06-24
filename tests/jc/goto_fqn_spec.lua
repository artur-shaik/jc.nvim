describe("goto_fqn parse", function()
  local goto_fqn = require("jc.goto_fqn")

  it("parses a stack-trace frame with line", function()
    local fqn, line = goto_fqn.parse("at com.foo.Bar.method(Bar.java:25)")
    assert.are.equal("com.foo.Bar", fqn)
    assert.are.equal(25, line)
  end)

  it("parses an underscored package frame", function()
    local fqn, line =
      goto_fqn.parse("\tat kz.grazhdanin.isna.refund_service.common.FooTest.t(FooTest.java:9)")
    assert.are.equal("kz.grazhdanin.isna.refund_service.common.FooTest", fqn)
    assert.are.equal(9, line)
  end)

  it("parses FQN:line", function()
    local fqn, line = goto_fqn.parse("com.foo.Bar:42")
    assert.are.equal("com.foo.Bar", fqn)
    assert.are.equal(42, line)
  end)

  it("parses a bare FQN, no line", function()
    local fqn, line = goto_fqn.parse("com.foo.Bar")
    assert.are.equal("com.foo.Bar", fqn)
    assert.is_nil(line)
  end)

  it("strips a trailing method to the class FQN", function()
    assert.are.equal("com.foo.Bar", (goto_fqn.parse("com.foo.Bar.doThing")))
  end)

  it("reduces a nested class to its top-level file", function()
    assert.are.equal("com.foo.Bar", (goto_fqn.parse("com.foo.Bar$Inner")))
  end)

  it("ignores filesystem paths (handled by builtin gf)", function()
    assert.is_nil(goto_fqn.parse("lua/jc/test.lua"))
    assert.is_nil(goto_fqn.parse("./src/main/java/Foo.java"))
  end)

  it("ignores a lowercase-only dotted word", function()
    assert.is_nil(goto_fqn.parse("foo.bar.baz"))
  end)

  it("returns nil for a plain word", function()
    assert.is_nil(goto_fqn.parse("hello"))
  end)
end)
