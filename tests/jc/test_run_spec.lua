describe("tests in the same package", function()
  local test = require("jc.test")

  -- a module with a class and a few files next to its tests
  local function module_with(files)
    local root = vim.fn.tempname()
    for _, rel in ipairs(files) do
      local path = root .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      vim.fn.writefile({ "// " .. rel }, path)
    end
    return root
  end

  it("offers the test classes of the class's own package", function()
    local root = module_with({
      "src/main/java/a/b/Fallback.java",
      "src/test/java/a/b/RoutingTest.java",
      "src/test/java/a/b/LimitsTest.java",
      "src/test/java/a/b/Fixtures.java",
      "src/test/java/a/b/c/DeeperTest.java",
      "src/test/java/a/OuterTest.java",
    })
    assert.are.same({
      root .. "/src/test/java/a/b/LimitsTest.java",
      root .. "/src/test/java/a/b/RoutingTest.java",
    }, test._package_tests(root .. "/src/main/java/a/b/Fallback.java"))
    vim.fn.delete(root, "rf")
  end)

  it("offers nothing when the package has no tests", function()
    local root = module_with({ "src/main/java/a/b/Fallback.java", "src/test/java/a/b/Fixtures.java" })
    assert.are.same({}, test._package_tests(root .. "/src/main/java/a/b/Fallback.java"))
    assert.are.same({}, test._package_tests(root .. "/src/main/java/a/Missing.java"))
    vim.fn.delete(root, "rf")
  end)

  it("offers nothing for a file outside src/main/java", function()
    assert.are.same({}, test._package_tests("/tmp/loose/Thing.java"))
  end)
end)
