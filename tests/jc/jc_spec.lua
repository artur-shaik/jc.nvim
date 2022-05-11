local plugin = require("jc")

describe("setup", function()
    it("works with default", function()
        assert("my first function with param = Hello!", plugin.setup({}))
    end)

    it("works with custom var", function()
        assert("my first function with param = custom", plugin.setup({ opt = "custom" }))
    end)
end)
