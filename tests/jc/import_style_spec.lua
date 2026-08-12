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
end)
