describe("path cache invalidation", function()
  local path, settings

  -- create a temp dir with a pom.xml so project_root#find resolves it
  local function make_project()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "<project/>" }, dir .. "/pom.xml")
    vim.fn.writefile({ "class A {}" }, dir .. "/A.java")
    return dir
  end

  local root = vim.fn.getcwd()

  before_each(function()
    -- editing a project file triggers an lcd into it; restore cwd so the
    -- relative runtimepath ('.') keeps resolving jc.* modules
    vim.cmd("cd " .. root)
    vim.g.jc_basedir = vim.fn.tempname()
    package.loaded["jc.path"] = nil
    package.loaded["jc.settings"] = nil
    path = require("jc.path")
    settings = require("jc.settings")
  end)

  it("returns different workspace dirs for different projects", function()
    local p1 = make_project()
    vim.cmd("edit " .. p1 .. "/A.java")
    local ws1 = path.get_workspace_dir()

    local p2 = make_project()
    vim.cmd("edit " .. p2 .. "/A.java")
    local ws2 = path.get_workspace_dir()

    assert.are_not.equal(ws1, ws2)
  end)

  it("settings follow the active project", function()
    local p1 = make_project()
    vim.cmd("edit " .. p1 .. "/A.java")
    settings.write_project("debug-port", "5005")

    local p2 = make_project()
    vim.cmd("edit " .. p2 .. "/A.java")
    -- the second project hasn't stored anything yet
    assert.are.equal("9000", settings.read_project("debug-port", "9000"))

    vim.cmd("edit " .. p1 .. "/A.java")
    assert.are.equal("5005", settings.read_project("debug-port", "9000"))
  end)
end)
