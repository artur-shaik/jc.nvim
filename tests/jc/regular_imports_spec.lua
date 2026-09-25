describe("regular_imports", function()
  local imports

  before_each(function()
    -- fresh basedir and module state per test
    vim.g.jc_basedir = vim.fn.tempname()
    package.loaded["jc.regular_imports"] = nil
    package.loaded["jc.path"] = nil
    imports = require("jc.regular_imports")()
  end)

  it("creates the workspace dir when something is written", function()
    -- constructing alone must not need the dir: the project (and so the dir)
    -- can still change within the session
    imports:add("java.util.List")
    assert.are.equal(1, vim.fn.isdirectory(require("jc.path").get_workspace_dir()))
  end)

  it("writes into the current project's dir, not the one seen at construction", function()
    -- the module is a singleton, so a second project in the same session used to
    -- write into a directory nobody had created: E482 out of choose_imports
    vim.g.jc_basedir = vim.fn.tempname()
    package.loaded["jc.path"] = nil
    local moved = require("jc.path").get_workspace_dir()
    imports:add("java.util.Map")
    assert.are.equal(1, vim.fn.isdirectory(moved))
    assert.are.same({ "java.util.Map" }, imports:load())
  end)

  it("loads empty list when nothing was saved", function()
    assert.are.same({}, imports:load())
  end)

  it("remembers added classes", function()
    imports:add("java.util.List")
    imports:add("java.util.Map")
    assert.are.same({ "java.util.List", "java.util.Map" }, imports:load())
  end)

  it("removes a class", function()
    imports:add("java.util.List")
    imports:add("java.awt.List")
    imports:remove("java.awt.List")
    assert.are.same({ "java.util.List" }, imports:load())
  end)

  it("persists across instances", function()
    imports:add("java.util.List")
    package.loaded["jc.regular_imports"] = nil
    local reloaded = require("jc.regular_imports")()
    assert.are.same({ "java.util.List" }, reloaded:load())
  end)
end)
