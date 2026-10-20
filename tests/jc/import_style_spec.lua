describe("import_style", function()
  local style = require("jc.import_style")

  it("lists presets in a stable order, all defined", function()
    assert.are.equal(4, #style.order)
    for _, name in ipairs(style.order) do
      assert.is_not_nil(style.presets[name], name .. " missing from presets")
    end
  end)

  it("maps a preset onto the jdtls import settings", function()
    local s = style.settings_for("IntelliJ IDEA")
    assert.are.same({ "", "javax", "java", "#" }, s["java.completion.importOrder"])
    assert.are.equal(5, s["java.sources.organizeImports.starThreshold"])
    assert.are.equal(3, s["java.sources.organizeImports.staticStarThreshold"])
  end)

  it("puts static imports on top for Eclipse (# first) and never wildcards", function()
    local s = style.settings_for("Eclipse")
    assert.are.equal("#", s["java.completion.importOrder"][1])
    assert.are.same({ "#", "java", "javax", "org", "com" }, s["java.completion.importOrder"])
    assert.are.equal(99, s["java.sources.organizeImports.starThreshold"])
  end)

  it("returns nil for an unknown style", function()
    assert.is_nil(style.settings_for("Emacs"))
    assert.is_nil(style.settings_for(""))
  end)

  it("raises both thresholds when the project asked for no wildcards", function()
    local s = style.settings_for("IntelliJ IDEA", true)
    -- the group order stays the preset's, only the wildcards go
    assert.are.same({ "", "javax", "java", "#" }, s["java.completion.importOrder"])
    assert.are.equal(style.NO_WILDCARDS, s["java.sources.organizeImports.starThreshold"])
    assert.are.equal(style.NO_WILDCARDS, s["java.sources.organizeImports.staticStarThreshold"])
  end)
end)

describe("import_style per project", function()
  local style

  before_each(function()
    vim.g.jc_basedir = vim.fn.tempname()
    package.loaded["jc.import_style"] = nil
    package.loaded["jc.path"] = nil
    style = require("jc.import_style")
  end)

  it("remembers nothing until something is saved", function()
    assert.is_nil(style.load())
    assert.is_false(style.no_wildcards())
  end)

  it("remembers the preset and the wildcard toggle together", function()
    style.save("IntelliJ IDEA", true)
    assert.are.equal("IntelliJ IDEA", style.load())
    assert.is_true(style.no_wildcards())
    style.save("IntelliJ IDEA", false)
    assert.are.equal("IntelliJ IDEA", style.load())
    assert.is_false(style.no_wildcards())
  end)

  it("reads a file written before the toggle existed", function()
    local dir = require("jc.path").get_workspace_dir()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "Eclipse" }, dir .. ".import_style")
    assert.are.equal("Eclipse", style.load())
    assert.is_false(style.no_wildcards())
  end)

  it("ignores an unknown preset name on disk", function()
    local dir = require("jc.path").get_workspace_dir()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "Emacs", "no-wildcards" }, dir .. ".import_style")
    assert.is_nil(style.load())
    -- the toggle is still readable: it is not tied to a known preset
    assert.is_true(style.no_wildcards())
  end)

  it("saves nothing for an unknown preset", function()
    style.save("Emacs", true)
    assert.is_nil(style.load())
    assert.is_false(style.no_wildcards())
  end)
end)
