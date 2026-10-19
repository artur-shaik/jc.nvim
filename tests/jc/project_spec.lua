describe("test file names", function()
  local project = require("jc.project")

  it("takes the junit naming conventions and src/test", function()
    assert.is_true(project.is_test_file("/p/src/test/java/a/FooTest.java"))
    assert.is_true(project.is_test_file("/p/src/main/java/a/FooTests.java"))
    assert.is_true(project.is_test_file("/p/src/main/java/a/TestFoo.java"))
    assert.is_true(project.is_test_file("/p/src/main/java/a/FooIT.java"))
    assert.is_true(project.is_test_file("/p/src/test/java/a/Fixtures.java"))
  end)

  it("leaves a production class out", function()
    assert.is_false(project.is_test_file("/p/src/main/java/a/FallbackController.java"))
    assert.is_false(project.is_test_file("/p/src/main/java/a/Contest.java"))
    assert.is_false(project.is_test_file("/p/src/main/resources/a.yml"))
    assert.is_false(project.is_test_file(nil))
  end)

  it("judges a test class by its name alone", function()
    -- src/test holds helpers and fixtures too, which hold no tests
    assert.is_true(project.is_test_class("/p/src/test/java/a/FooTest.java"))
    assert.is_false(project.is_test_class("/p/src/test/java/a/Fixtures.java"))
  end)
end)

describe("gradle build root", function()
  local project = require("jc.project")

  local function write(path, text)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "w"))
    fd:write(text)
    fd:close()
  end

  it("reads include paths off a settings file", function()
    local inc = project._parse_includes([[
rootProject.name = 'refunds'
include 'refunds-model'
include ':refunds-app'
include 'tools:codegen'
]])
    assert.is_true(inc[":refunds-model"])
    assert.is_true(inc[":refunds-app"])
    assert.is_true(inc[":tools:codegen"])
    assert.is_nil(inc[":missing"])
  end)

  it("matches a nested module against its include path", function()
    local text = "include 'tools:codegen'\n"
    assert.is_true(project._includes_project(text, "tools/codegen"))
    assert.is_false(project._includes_project(text, "tools"))
    assert.is_false(project._includes_project(text, ".claude/worktrees/wt"))
  end)

  it("climbs to the reactor root of a multi-module build", function()
    local root = vim.fn.tempname()
    write(root .. "/settings.gradle", "include 'mod'\n")
    write(root .. "/mod/settings.gradle", "")
    write(root .. "/mod/src/test/java/Keep.java", "")
    assert.are.equal(root, project.gradle_root(root .. "/mod/src/test/java"))
  end)

  it("stops at a nested checkout the outer build never included", function()
    local root = vim.fn.tempname()
    write(root .. "/settings.gradle", "include 'mod'\n")
    local wt = root .. "/.claude/worktrees/wt"
    write(wt .. "/settings.gradle", "include 'mod'\n")
    write(wt .. "/mod/src/test/java/Keep.java", "")
    assert.are.equal(wt, project.gradle_root(wt .. "/mod/src/test/java"))
  end)

  it("returns nil with no settings file above", function()
    local root = vim.fn.tempname()
    write(root .. "/mod/src/test/java/Keep.java", "")
    assert.is_nil(project.gradle_root(root .. "/mod/src/test/java"))
  end)
end)
