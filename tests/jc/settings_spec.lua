describe("settings", function()
  local settings

  before_each(function()
    vim.g.jc_basedir = vim.fn.tempname()
    package.loaded["jc.settings"] = nil
    settings = require("jc.settings")
  end)

  it("returns default when nothing was saved", function()
    assert.are.equal("127.0.0.1", settings.read_project("debug-host", "127.0.0.1"))
  end)

  it("roundtrips a written value", function()
    settings.write_project("debug-port", "5005")
    assert.are.equal("5005", settings.read_project("debug-port", "9000"))
  end)

  it("keys are independent", function()
    settings.write_project("debug-host", "10.0.0.1")
    settings.write_project("debug-port", "8000")
    assert.are.equal("10.0.0.1", settings.read_project("debug-host", "x"))
    assert.are.equal("8000", settings.read_project("debug-port", "x"))
  end)
end)
