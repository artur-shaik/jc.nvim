describe("templates", function()
  local templates = require("jc.templates")

  local opts = {
    name = "Foo",
    package = "com.example",
    fields = {
      { mod = "private", type = "String", name = "bar" },
      { mod = "public", type = "int", name = "n" },
    },
    extends = "Base",
    implements = "Runnable",
  }

  it("class: package, modifiers, extends, implements, fields", function()
    local out = templates.render("class", opts)
    assert.are.equal(
      "package com.example;\n\n"
        .. "public class Foo extends Base implements Runnable {\n\n"
        .. "private String bar;\npublic int n;\n"
        .. "\n}",
      out
    )
  end)

  it("interface: fields become method signatures, no implements", function()
    local out = templates.render("interface", { name = "Foo", package = "p", fields = opts.fields, extends = "X" })
    assert.are.equal("package p;\n\npublic interface Foo extends X {\nprivate String bar();\npublic int n();\n\n}", out)
  end)

  it("enum: no extends/implements", function()
    local out = templates.render("enum", { name = "E", package = "p", fields = { opts.fields[1] } })
    assert.are.equal("package p;\n\npublic enum E {\nprivate String bar;\n\n}", out)
  end)

  it("exception: default extends Exception and two constructors", function()
    local out = templates.render("exception", { name = "MyErr", package = "p", fields = {} })
    assert.is_truthy(out:find("public class MyErr extends Exception {", 1, true))
    assert.is_truthy(out:find("public MyErr() {", 1, true))
    assert.is_truthy(out:find("public MyErr(String msg) {\nsuper(msg);", 1, true))
  end)

  it("exception: explicit extends overrides default", function()
    local out =
      templates.render("exception", { name = "MyErr", package = "p", fields = {}, extends = "RuntimeException" })
    assert.is_truthy(out:find("extends RuntimeException", 1, true))
    assert.is_nil(out:find("extends Exception", 1, true))
  end)

  it("main: has main method", function()
    local out = templates.render("main", { name = "App", package = "p", fields = {} })
    assert.is_truthy(out:find("public static void main(String[] args) {", 1, true))
  end)

  it("junit: junit import and setUp", function()
    local out = templates.render("junit", { name = "FooTest", package = "p", fields = {} })
    assert.is_truthy(out:find("import static org.junit.Assert.*;", 1, true))
    assert.is_truthy(out:find("@Before\npublic void setUp() {", 1, true))
  end)

  it("singleton: holder idiom", function()
    local out = templates.render("singleton", { name = "S", package = "p", fields = {} })
    assert.is_truthy(out:find("public static S getInstance() {", 1, true))
    assert.is_truthy(out:find("private static final S INSTANCE = new S();", 1, true))
  end)

  it("annotation: @interface", function()
    local out = templates.render("annotation", { name = "Ann", package = "p", fields = {} })
    assert.is_truthy(out:find("public @interface Ann {", 1, true))
  end)

  it("servlet: WebServlet annotation with derived url and HttpServlet default", function()
    local out = templates.render("servlet", { name = "MyServlet", package = "p", fields = {} })
    assert.is_truthy(out:find('@WebServlet(name = "MyServlet"', 1, true))
    assert.is_truthy(out:find("/my/servlet", 1, true)) -- camelCase -> /my/servlet lowercased
    assert.is_truthy(out:find("extends HttpServlet", 1, true))
    assert.is_truthy(out:find("protected void doGet(", 1, true))
  end)

  it("android templates carry their default superclass and override", function()
    local act = templates.render("android_activity", { name = "A", package = "p", fields = {} })
    assert.is_truthy(act:find("extends Activity", 1, true))
    assert.is_truthy(act:find("public void onCreate(Bundle savedInstanceState) {", 1, true))

    local frag = templates.render("android_fragment", { name = "F", package = "p", fields = {} })
    assert.is_truthy(frag:find("extends Fragment", 1, true))
    assert.is_truthy(frag:find("public View onCreateView(", 1, true))
  end)

  it("omits the package line for the default (empty) package", function()
    local out = templates.render("class", { name = "Foo", package = "", fields = {} })
    assert.is_nil(out:find("package", 1, true))
    assert.is_truthy(out:find("^public class Foo"))

    local iface = templates.render("interface", { name = "I", package = "", fields = {} })
    assert.is_nil(iface:find("package", 1, true))
  end)

  it("default template is class when name omitted", function()
    assert.are.equal(templates.get(), templates.get("class"))
  end)

  it("register adds a custom template", function()
    templates.register("rec", function(o)
      return "record " .. o.name
    end)
    assert.are.equal("record Foo", templates.render("rec", { name = "Foo" }))
    assert.is_truthy(vim.tbl_contains(templates.names(), "rec"))
  end)
end)
