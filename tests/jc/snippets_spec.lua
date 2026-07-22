describe("bundled snippets", function()
  local function load(path)
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end

  it("java.json is valid and every entry has a prefix + body", function()
    local snips = load("snippets/java.json")
    local count = 0
    for name, entry in pairs(snips) do
      count = count + 1
      assert.is_string(entry.prefix, name .. " missing prefix")
      assert.is_truthy(entry.prefix ~= "", name .. " empty prefix")
      assert.is_truthy(type(entry.body) == "string" or type(entry.body) == "table", name .. " missing body")
    end
    assert.is_truthy(count > 0)
  end)

  it("prefixes are unique (no shadowing)", function()
    local snips = load("snippets/java.json")
    local seen = {}
    for name, entry in pairs(snips) do
      assert.is_nil(seen[entry.prefix], "duplicate prefix " .. entry.prefix .. " (" .. name .. ")")
      seen[entry.prefix] = name
    end
  end)

  it("package.json points at java.json for the java language", function()
    local pkg = load("snippets/package.json")
    local contribs = pkg.contributes.snippets
    assert.are.equal("java", contribs[1].language)
    assert.are.equal("./java.json", contribs[1].path)
  end)
end)
