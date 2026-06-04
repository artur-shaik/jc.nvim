describe("chains", function()
  local chains = require("jc.chains")()

  it("is a singleton", function()
    assert.are.equal(chains, require("jc.chains")())
  end)

  it("executes queued functions in order", function()
    local order = {}
    chains:add(function()
      table.insert(order, "first")
    end)
    chains:add(function()
      table.insert(order, "second")
    end)
    chains:execute_next_if_exists()
    chains:execute_next_if_exists()
    chains:execute_next_if_exists() -- empty queue is a no-op
    assert.are.same({ "first", "second" }, order)
  end)

  it("rejects non-function commands", function()
    assert.has_error(function()
      chains:add("require('jc.jdtls').organize_imports()")
    end)
  end)

  it("survives an erroring command", function()
    local executed = false
    chains:add(function()
      error("boom")
    end)
    chains:add(function()
      executed = true
    end)
    assert.has_no.errors(function()
      chains:execute_next_if_exists()
    end)
    chains:execute_next_if_exists()
    assert.is_true(executed)
  end)
end)
