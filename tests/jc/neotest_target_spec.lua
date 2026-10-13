describe("run target", function()
  local target = require("jc.neotest.target")

  local function project()
    local root = vim.fn.tempname()
    local file = root .. "/mod/src/test/java/FooTest.java"
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
    local fd = assert(io.open(root .. "/settings.gradle", "w"))
    fd:write("include 'mod'\n")
    fd:close()
    fd = assert(io.open(file, "w"))
    fd:write("class FooTest {}\n")
    fd:close()
    return root, file
  end

  -- stands in for neotest's client: the adapters it knows and their trees
  local function client(adapters, position)
    return {
      _adapters = adapters or {},
      _state = {
        positions = function(_, _id, pos)
          return pos and position or nil
        end,
      },
    }
  end

  it("names the adapter by the root that owns the file", function()
    local root, file = project()
    assert.are.equal("jc:" .. root, target.adapter_id(file))
  end)

  it("pins a run to the adapter that holds the position", function()
    local root, file = project()
    local id = "jc:" .. root
    local args = target.run_args(file, file, client({ [id] = true }, { id = file }))
    assert.are.same({ file, adapter = id }, args)
  end)

  it("does not pin a position the adapter does not know, so the run still happens", function()
    local root, file = project()
    local args = target.run_args(file, file, client({ ["jc:" .. root] = true }, nil))
    assert.are.same({ file }, args)
  end)

  it("does not pin an adapter neotest has never registered", function()
    local _, file = project()
    local args = target.run_args(file, file, client({}, { id = file }))
    assert.are.same({ file }, args)
  end)

  it("pins a cursor run, which carries no position, by the file", function()
    local root, file = project()
    local id = "jc:" .. root
    assert.are.same({ adapter = id }, target.run_args(nil, file, client({ [id] = true })))
  end)
end)
