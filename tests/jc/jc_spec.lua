local plugin = require("jc")

describe("setup", function()
    it("works with default", function()
        assert("init default", plugin.setup({}))
    end)

    it("works with custom var", function()
        assert("init with param", plugin.setup({ java_exec = "/usr/local/bin/java" }))
    end)
end)
