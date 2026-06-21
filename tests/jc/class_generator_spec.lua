describe("class_generator parsing", function()
  local cg = require("jc.class_generator")

  describe("parse_input", function()
    it("plain class name", function()
      local p = cg.parse_input("Foo")
      assert.are.equal("Foo", p.path_str)
      assert.is_nil(p.template)
      assert.is_nil(p.flags)
    end)

    it("template prefix", function()
      local p = cg.parse_input("enum:Color")
      assert.are.equal("enum", p.template)
      assert.are.equal("Color", p.path_str)
    end)

    it("subdir in brackets", function()
      local p = cg.parse_input("[test]:Foo")
      assert.are.equal("test", p.subdir)
      assert.are.equal("Foo", p.path_str)
    end)

    it("absolute path with package", function()
      local p = cg.parse_input("/com.example.Foo")
      assert.are.equal("/com.example.Foo", p.path_str)
    end)

    it("extends and implements", function()
      local p = cg.parse_input("Foo extends Base implements Runnable")
      assert.are.equal("Foo", p.path_str)
      assert.are.equal("Base", p.extends)
      assert.are.equal("Runnable", p.implements)
    end)

    it("fields", function()
      local p = cg.parse_input("Foo(String a, int b)")
      assert.are.equal("Foo", p.path_str)
      assert.are.equal("(String a, int b)", p.fields_str)
    end)

    it("trailing flags (after fields, since a bare word: is read as template)", function()
      local p = cg.parse_input("Foo(int x):constructor:toString")
      assert.are.equal("Foo", p.path_str)
      assert.are.equal("(int x)", p.fields_str)
      assert.are.equal(":constructor:toString", p.flags)
    end)

    it("bare word + colon is greedily a template (vimscript parity)", function()
      local p = cg.parse_input("Foo:constructor")
      assert.are.equal("Foo", p.template)
      assert.are.equal("constructor", p.path_str)
    end)

    it("everything together", function()
      local p = cg.parse_input("singleton:[main]:/com.foo.Bar extends B implements I(String s):constructor:equals")
      assert.are.equal("singleton", p.template)
      assert.are.equal("main", p.subdir)
      assert.are.equal("/com.foo.Bar", p.path_str)
      assert.are.equal("B", p.extends)
      assert.are.equal("I", p.implements)
      assert.are.equal("(String s)", p.fields_str)
      assert.are.equal(":constructor:equals", p.flags)
    end)

    it("returns nil on empty path", function()
      assert.is_nil(cg.parse_input(""))
    end)
  end)

  describe("parse_fields", function()
    it("defaults modifier to private", function()
      local f = cg.parse_fields("(String name, int count)")
      assert.are.same({
        { mod = "private", type = "String", name = "name" },
        { mod = "private", type = "int", name = "count" },
      }, f)
    end)

    it("keeps explicit modifiers", function()
      local f = cg.parse_fields("(public static final String NAME)")
      assert.are.same({ { mod = "public static final", type = "String", name = "NAME" } }, f)
    end)

    it("empty field list", function()
      assert.are.same({}, cg.parse_fields("()"))
    end)
  end)

  describe("parse_methods", function()
    it("flags without args", function()
      local m = cg.parse_methods(":constructor:toString:equals")
      assert.is_not_nil(m.constructor)
      assert.is_not_nil(m.toString)
      assert.is_not_nil(m.equals)
      assert.is_nil(m.hashCode)
    end)

    it("flag with numeric args", function()
      local m = cg.parse_methods(":constructor(1,2)")
      assert.are.same({ 1, 2 }, m.constructor)
    end)
  end)

  describe("build_path_data", function()
    -- file at .../src/main/java/com/example/Cur.java
    local current_path = { "example", "com", "java", "main", "src", "proj" } -- reversed dir list
    local current_package = { "com", "example" }

    it("relative class -> same package, empty path", function()
      local d = cg.build_path_data({ "Bar" }, nil, current_path, current_package)
      assert.are.equal("Bar", d.class)
      assert.are.equal("com.example", d.package)
      assert.are.equal("", d.path)
    end)

    it("relative subpackage", function()
      local d = cg.build_path_data({ "sub", "Bar" }, nil, current_path, current_package)
      assert.are.equal("Bar", d.class)
      assert.are.equal("com.example.sub", d.package)
      assert.are.equal("sub", d.path)
    end)

    it("absolute path resolves package from class name", function()
      local d = cg.build_path_data({ "/com", "other", "Baz" }, nil, current_path, current_package)
      assert.are.equal("Baz", d.class)
      assert.are.equal("com.other", d.package)
    end)

    -- build a temp multi-module project and open a file inside it so the
    -- project root resolves there
    local function make_multimodule()
      local root = vim.fn.tempname()
      for _, m in ipairs({ "app", "model" }) do
        vim.fn.mkdir(root .. "/" .. m .. "/src/main/java", "p")
        vim.fn.mkdir(root .. "/" .. m .. "/src/test/java", "p")
      end
      vim.fn.writefile({ "" }, root .. "/settings.gradle")
      vim.fn.writefile({ "package p;" }, root .. "/app/src/main/java/Cur.java")
      vim.cmd("edit " .. root .. "/app/src/main/java/Cur.java")
      return root
    end

    it("modules() discovers subprojects and their source sets", function()
      make_multimodule()
      local mods = cg.modules()
      assert.is_not_nil(mods.app)
      assert.is_not_nil(mods.model)
      assert.is_truthy(mods.app.sets.main)
      assert.is_truthy(mods.model.sets.test)
    end)

    it("module_data routes [module]:/pkg.Class into that module's source root", function()
      make_multimodule()
      local d = cg.module_data(cg.parse_input("[model]:/p.q.Foo"))
      assert.are.equal("Foo", d.class)
      assert.are.equal("p.q", d.package)
      assert.is_truthy(d.current_path:find("model" .. "/src/main/java", 1, true))

      local d2 = cg.module_data(cg.parse_input("[model/test]:Bar"))
      assert.is_truthy(d2.current_path:find("model" .. "/src/test/java", 1, true))

      -- a plain source-set is not a module -> nil (falls back to build_path_data)
      assert.is_nil(cg.module_data(cg.parse_input("[test]:Bar")))
    end)

    it("package completion after [module] is scoped to that module", function()
      local root = make_multimodule()
      vim.fn.mkdir(root .. "/model/src/main/java/m/dto", "p")
      vim.fn.mkdir(root .. "/app/src/main/java/apponly", "p")
      local r = cg.complete("", "[model]:") -- empty path slot -> all model packages
      assert.is_true(vim.tbl_contains(r, "[model]:m"))
      assert.is_true(vim.tbl_contains(r, "[model]:m.dto"))
      -- app-only package must not leak into the model-scoped completion
      assert.is_false(vim.tbl_contains(r, "[model]:apponly"))
    end)

    it("absolute path resolves into the current source root, no backtracking", function()
      local root = make_multimodule() -- current file: app/src/main/java/Cur.java
      local saved_input = vim.fn.input
      vim.fn.input = function()
        return "/com.foo.Bar"
      end
      local ok = pcall(cg.generate_class)
      vim.fn.input = saved_input
      assert.is_true(ok)
      assert.are.equal(1, vim.fn.filereadable(root .. "/app/src/main/java/com/foo/Bar.java"))
    end)

    it("[test]/[main] source-sets see both sets of the current module", function()
      local root = make_multimodule() -- current file is app/src/main/java/Cur.java
      vim.fn.mkdir(root .. "/app/src/main/java/inmain", "p")
      vim.fn.mkdir(root .. "/app/src/test/java/intest", "p")
      local r = cg.complete("", "[test]:")
      assert.is_true(vim.tbl_contains(r, "[test]:inmain")) -- from src/main
      assert.is_true(vim.tbl_contains(r, "[test]:intest")) -- from src/test
    end)

    it("[test] subdir targets the test source root (src/test/java)", function()
      -- file under src/main/java/com/example -> [test] mirrors into src/test/java
      local d = cg.build_path_data({ "Bar" }, "test", current_path, current_package)
      assert.are.equal("Bar", d.class)
      assert.are.equal("com.example", d.package)
      -- climbs to src then descends test/java/<package>
      assert.is_truthy(d.path:find("test/java/com/example", 1, true))
    end)
  end)

  describe("complete", function()
    it("first token suggests template names with a separator", function()
      local r = cg.complete("", "enu")
      assert.is_true(vim.tbl_contains(r, "enum:"))
    end)

    it("method flags after the class segment", function()
      local r = cg.complete("", "enum:Foo:to")
      assert.are.same({ "enum:Foo:toString" }, r)
    end)

    it("extends/implements keywords after the class name", function()
      local r = cg.complete("", "Foo ext")
      assert.is_true(vim.tbl_contains(r, "Foo extends"))
    end)

    it("does not re-offer a keyword already present", function()
      local r = cg.complete("", "Foo extends Base imp")
      assert.is_true(vim.tbl_contains(r, "Foo extends Base implements"))
      assert.is_false(vim.tbl_contains(r, "Foo extends Base extends"))
    end)

    it("completes at the cursor, not the whole line (mid-string editing)", function()
      -- cursor sits right after "[", with text still trailing after it
      local line = "service:[:/kz.foo.Bar"
      local pos = #"service:[" -- byte offset of the cursor
      local r = cg.complete("", line, pos)
      -- routed to the subdir slot (offers source-sets/modules), not the path
      assert.is_false(vim.tbl_contains(r, "service:[:/kz.foo.Bar"))
      -- and the trailing path text after the cursor is not treated as command
      for _, item in ipairs(r) do
        assert.is_truthy(item:find("%[", 1))
      end
    end)

    it("after a template, offers no method flags (the subdir/path slot)", function()
      local r = cg.complete("", "enum:")
      assert.is_false(vim.tbl_contains(r, "enum:constructor"))
      assert.is_false(vim.tbl_contains(r, "enum:toString"))
    end)

    it("offers method flags only once the class path is given", function()
      local r = cg.complete("", "/kz.foo.Bar:con")
      assert.are.same({ "/kz.foo.Bar:constructor" }, r)
    end)

    it("chained method flags keep completing", function()
      local r = cg.complete("", "/kz.foo.Bar:constructor:to")
      assert.are.same({ "/kz.foo.Bar:constructor:toString" }, r)
    end)

    it("inside the field list routes to type completion, not templates", function()
      -- no jdtls -> empty, but must route to field-type (not offer templates)
      assert.are.same({}, cg.complete("", "Test(Stri"))
      assert.are.same({}, cg.complete("", "Test(public "))
      assert.are.same({}, cg.complete("", "Test("))
    end)

    it("does not complete the field name as a type", function()
      assert.are.same({}, cg.complete("", "Test(String fo"))
    end)

    it("a closed field list is no longer a field context", function()
      -- after ")" the keyword completion takes over
      local r = cg.complete("", "Test(String s) ext")
      assert.is_true(vim.tbl_contains(r, "Test(String s) extends"))
    end)

    it("after 'extends ' routes to type completion (empty without jdtls)", function()
      -- no jdtls client in the test env -> empty, but must not error and must
      -- not fall back to offering keywords again
      assert.has_no.errors(function()
        local r = cg.complete("", "Foo extends Ru")
        assert.are.same({}, r)
      end)
    end)
  end)

  describe("is_class_name", function()
    it("accepts a conventional class name", function()
      assert.is_true(cg.is_class_name("AccountType"))
      assert.is_true(cg.is_class_name("Foo2"))
    end)

    it("rejects empty / package-only input", function()
      assert.is_false(cg.is_class_name(""))
      assert.is_false(cg.is_class_name("refund_service"))
      assert.is_false(cg.is_class_name(nil))
    end)
  end)

  describe("parse (full)", function()
    local current_path = { "example", "com", "java", "main", "src", "proj" }
    local current_package = { "com", "example" }

    it("builds full class data", function()
      local d = cg.parse("Bar extends Base(String s):toString", current_path, current_package)
      assert.are.equal("Bar", d.class)
      assert.are.equal("com.example", d.package)
      assert.are.equal("Base", d.extends)
      assert.are.equal(1, #d.fields)
      assert.are.equal("s", d.fields[1].name)
      assert.is_not_nil(d.methods.toString)
    end)
  end)
end)
