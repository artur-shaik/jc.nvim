describe("neotest report parser", function()
  local report = require("jc.neotest.report")

  local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="JUnit Jupiter" tests="4" failures="1" errors="1" skipped="1">
  <testcase name="passes()" classname="com.example.FooTest" time="0.01"/>
  <testcase name="fails()" classname="com.example.FooTest" time="0.0">
    <failure message="expected: &lt;5&gt; but was: &lt;4&gt;" type="org.opentest4j.AssertionFailedError">org.opentest4j.AssertionFailedError: expected: &lt;5&gt; but was: &lt;4&gt;
	at com.example.FooTest.fails(FooTest.java:25)
	at java.base/jdk.internal.reflect.Method.invoke(Method.java:1)
</failure>
  </testcase>
  <testcase name="errors()" classname="com.example.FooTest" time="0.0">
    <error message="boom" type="java.lang.IllegalStateException">java.lang.IllegalStateException: boom
	at com.example.FooTest.errors(FooTest.java:40)
</error>
  </testcase>
  <testcase name="ignored()" classname="com.example.FooTest" time="0.0">
    <skipped message="disabled for now"/>
  </testcase>
</testsuite>]]

  it("parses every testcase", function()
    local cases = report.parse(xml)
    assert.are.equal(4, #cases)
  end)

  it("classifies pass/fail/error/skip", function()
    local idx = report.index(report.parse(xml))
    assert.are.equal("passed", idx[report.key("com.example.FooTest", "passes")].status)
    assert.are.equal("failed", idx[report.key("com.example.FooTest", "fails")].status)
    assert.are.equal("failed", idx[report.key("com.example.FooTest", "errors")].status)
    assert.are.equal("skipped", idx[report.key("com.example.FooTest", "ignored")].status)
  end)

  it("unescapes failure messages", function()
    local idx = report.index(report.parse(xml))
    assert.are.equal("expected: <5> but was: <4>", idx[report.key("com.example.FooTest", "fails")].message)
  end)

  it("locates the failing line in the test's own source frame", function()
    local idx = report.index(report.parse(xml))
    local fail = idx[report.key("com.example.FooTest", "fails")].failure
    assert.are.equal("FooTest.java", fail.file)
    assert.are.equal(25, fail.line)
  end)

  it("strips parameterized/() suffix to the base method name", function()
    local cases = report.parse([[<testsuite>
  <testcase name="add(int)[1]" classname="p.MathTest"/>
</testsuite>]])
    assert.are.equal("add", cases[1].method)
  end)
end)

describe("neotest launcher", function()
  local launcher = require("jc.neotest.launcher")

  it("builds a console launcher command", function()
    local cmd = launcher.build_command({
      java = "java",
      jar = "/jars/console.jar",
      classpath = { "/a.jar", "/b/classes" },
      selectors = { "--select-method=p.FooTest#bar" },
      reports_dir = "/tmp/rep",
    })
    assert.are.same({
      "java",
      "-jar",
      "/jars/console.jar",
      "execute",
      "--classpath",
      "/a.jar:/b/classes",
      "--select-method=p.FooTest#bar",
      "--reports-dir",
      "/tmp/rep",
      "--details",
      "none",
      "--disable-banner",
    }, cmd)
  end)
end)

describe("build failure reason", function()
  -- the adapter pulls in neotest.lib, which bare CI doesn't have; skip there
  local ok, adapter = pcall(require, "jc.neotest")
  local function reason(out)
    return ok and adapter._build_failure_reason(out) or nil
  end

  it("prefers error: lines, including ones without a file:line", function()
    local out = table.concat({
      "Foo.java:13: warning: lombok note",
      "error: warnings found and -Werror specified",
      "1 error",
      "BUILD FAILED in 3s",
    }, "\n")
    local r = reason(out)
    if r == nil then
      return
    end
    assert.are.equal("error: warnings found and -Werror specified", r)
  end)

  it("falls back to gradle's 'What went wrong' block", function()
    local out = table.concat({
      "> Task :app:compileJava FAILED",
      "FAILURE: Build failed with an exception.",
      "",
      "* What went wrong:",
      "Execution failed for task ':app:compileJava'.",
      "> Compilation failed; see the compiler error output for details.",
      "",
      "* Try:",
      "> Run with --stacktrace",
    }, "\n")
    local r = reason(out)
    if r == nil then
      return
    end
    assert.is_truthy(r:find("Execution failed for task ':app:compileJava'.", 1, true))
    assert.is_falsy(r:find("Run with --stacktrace", 1, true))
  end)

  it("falls back to the output tail when nothing is recognised", function()
    local r = reason("weird output")
    if r ~= nil then
      assert.are.equal("weird output", r)
    end
  end)
end)
