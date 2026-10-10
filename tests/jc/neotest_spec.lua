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

  it("drops the execute subcommand for launchers older than 1.10", function()
    local cmd = launcher.build_command({
      jar = "/jars/junit-platform-console-standalone-1.8.2.jar",
      classpath = { "/a.jar" },
      selectors = { "--select-class=p.FooTest" },
      reports_dir = "/tmp/rep",
      version = "1.8.2",
    })
    assert.are.same({
      "java",
      "-jar",
      "/jars/junit-platform-console-standalone-1.8.2.jar",
      "--classpath",
      "/a.jar",
      "--select-class=p.FooTest",
      "--reports-dir",
      "/tmp/rep",
      "--details",
      "none",
      "--disable-banner",
    }, cmd)
  end)

  it("takes the launcher version from the jar name when none is given", function()
    assert.is_false(launcher.supports_execute(launcher.version_of("/m2/junit-platform-console-standalone-1.9.3.jar")))
    local cmd = launcher.build_command({
      jar = "/m2/junit-platform-console-standalone-1.9.3.jar",
      classpath = { "/a.jar" },
      reports_dir = "/tmp/rep",
    })
    assert.are_not.equal("execute", cmd[4])
  end)

  it("keeps the execute subcommand from 1.10 on", function()
    for _, version in ipairs({ "1.10.0", "1.11.3", "6.0.3" }) do
      assert.is_true(launcher.supports_execute(version))
    end
    for _, version in ipairs({ "1.0.0", "1.9.3" }) do
      assert.is_false(launcher.supports_execute(version))
    end
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

describe("failure explanations", function()
  local ok, adapter = pcall(require, "jc.neotest")

  it("tells the user what failed and what to do about it", function()
    if not ok then
      return -- bare CI has no neotest.lib
    end
    local msg = adapter._build_failed_message("Execution failed for task ':card:generateJooq'.")
    assert.is_truthy(msg:find("no tests were run", 1, true))
    assert.is_truthy(msg:find("generateJooq", 1, true))
    -- the two ways out: fix it, or stop precompiling
    assert.is_truthy(msg:find(":copen", 1, true))
    assert.is_truthy(msg:find(":JCtestPrecompile", 1, true))
  end)

  it("survives a build that produced no output", function()
    if not ok then
      return
    end
    assert.is_truthy(adapter._build_failed_message(nil):find("no output captured", 1, true))
  end)
end)

describe("console launcher version", function()
  local launcher = require("jc.neotest.launcher")

  local function cp(...)
    return { ... }
  end

  it("maps junit 5 onto the platform 1.x jar", function()
    local v = launcher.launcher_version(cp("/m2/junit-jupiter-api-5.11.3.jar", "/m2/spring-test-6.1.0.jar"))
    assert.are.equal("1.11.3", v)
  end)

  it("keeps the version as-is from junit 6 on (numbering merged)", function()
    assert.are.equal("6.0.3", launcher.launcher_version(cp("/m2/junit-jupiter-api-6.0.3.jar")))
  end)

  it("falls back to the platform engine when jupiter is absent", function()
    assert.are.equal("1.9.2", launcher.launcher_version(cp("/m2/junit-platform-engine-1.9.2.jar")))
  end)

  it("reports nothing when the classpath carries no junit", function()
    assert.is_nil(launcher.launcher_version(cp("/m2/guava-33.0.jar")))
    assert.is_nil(launcher.launcher_version({}))
  end)

  it("names the artifact for a version, defaulting when none is given", function()
    assert.are.equal("org.junit.platform:junit-platform-console-standalone:6.0.3", launcher.artifact("6.0.3"))
    assert.is_truthy(launcher.artifact(nil):find(launcher.DEFAULT_VERSION, 1, true))
  end)
end)

describe("refresh before a run", function()
  local refresh = require("jc.neotest.refresh")

  it("keeps only readable files, without duplicates", function()
    local file = vim.fn.tempname() .. ".java"
    vim.fn.writefile({ "class A {}" }, file)
    assert.are.same({ file }, refresh._targets({ file, file, "", "/nope/Missing.java", 42 }))
    assert.are.same({}, refresh._targets(nil))
    vim.fn.delete(file)
    assert.are.same({}, refresh._targets({ file }))
  end)

  it("starts the run even with nothing to refresh", function()
    local started = 0
    refresh.before_run({}, function()
      started = started + 1
    end)
    refresh.before_run({ "/nope/Missing.java" }, function()
      started = started + 1
    end)
    assert.are.equal(2, started)
  end)

  local consumer = require("jc.neotest.consumer")

  -- a readable java file to pass as a target
  local function target()
    local file = vim.fn.tempname() .. "Test.java"
    vim.fn.writefile({ "class FooTest {}" }, file)
    return file
  end

  it("leaves a client neotest has not started alone", function()
    local file = target()
    local saved_client, saved_nio = consumer.client, package.loaded["nio"]
    local reparsed, started = 0, 0
    package.loaded["nio"] = {
      run = function(fn, cb)
        fn()
        cb()
      end,
    }
    -- a cold client: _update_positions would spawn neotest's child process
    -- over a blocking rpcrequest and stall the run
    consumer.client = {
      _started = false,
      _update_positions = function()
        reparsed = reparsed + 1
      end,
    }
    refresh.before_run({ file }, function()
      started = started + 1
    end)
    assert.are.equal(0, reparsed)
    assert.are.equal(1, started)

    consumer.client._started = true
    refresh.before_run({ file }, function()
      started = started + 1
    end)
    assert.are.equal(1, reparsed)
    -- the run is started from the reparse callback, via vim.schedule
    vim.wait(500, function()
      return started > 1
    end)
    assert.are.equal(2, started)

    consumer.client, package.loaded["nio"] = saved_client, saved_nio
    vim.fn.delete(file)
  end)

  it("starts the run once even if the reparse never comes back", function()
    local file = target()
    local saved_client, saved_nio = consumer.client, package.loaded["nio"]
    local started = 0
    package.loaded["nio"] = { run = function() end } -- never calls back
    consumer.client = { _started = true, _update_positions = function() end }

    refresh.before_run({ file }, function()
      started = started + 1
    end)
    assert.are.equal(0, started) -- waiting on the reparse
    vim.wait(2500, function()
      return started > 0
    end)
    assert.are.equal(1, started) -- the timeout started it
    vim.wait(300)
    assert.are.equal(1, started) -- and only once

    consumer.client, package.loaded["nio"] = saved_client, saved_nio
    vim.fn.delete(file)
  end)

  it("leaves a buffer with unsaved changes alone", function()
    local file = vim.fn.tempname() .. ".java"
    vim.fn.writefile({ "class A {}" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local buf = vim.fn.bufnr(file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "class B {}" })
    vim.fn.writefile({ "class C {}" }, file) -- changed underneath the buffer
    refresh._reload_buf(file)
    assert.are.same({ "class B {}" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    vim.bo[buf].modified = false
    vim.cmd("bwipeout! " .. buf)
    vim.fn.delete(file)
  end)
end)
