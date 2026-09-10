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
    assert.is_truthy(out:find("public interface Foo extends X {", 1, true))
    -- interface members carry no modifier: a `private` one would need a body
    assert.is_truthy(out:find("String bar();", 1, true))
    assert.is_truthy(out:find("int n();", 1, true))
    assert.is_nil(out:find("private String bar();", 1, true))
    assert.is_nil(out:find("implements", 1, true))
  end)

  it("enum: renders constants from values", function()
    local out = templates.render("enum", { name = "Day", package = "p", values = { "MON", "TUE", "WED" } })
    assert.is_truthy(out:find("public enum Day {", 1, true))
    assert.is_truthy(out:find("MON, TUE, WED;", 1, true))
  end)

  it("enum: no extends, but implements is honoured", function()
    local out = templates.render("enum", { name = "E", package = "p", fields = { opts.fields[1] }, extends = "X" })
    assert.is_truthy(out:find("public enum E {", 1, true))
    assert.is_nil(out:find("extends", 1, true)) -- enum cannot extend
    local out2 = templates.render("enum", { name = "E", package = "p", fields = {}, implements = "Serializable" })
    assert.is_truthy(out2:find("public enum E implements Serializable {", 1, true))
  end)

  it("exception: default extends Exception and the four constructors", function()
    local out = templates.render("exception", { name = "MyErr", package = "p", fields = {} })
    assert.is_truthy(out:find("public class MyErr extends Exception {", 1, true))
    assert.is_truthy(out:find("public MyErr() {", 1, true))
    assert.is_truthy(out:find("public MyErr(String message) {\nsuper(message);", 1, true))
    assert.is_truthy(out:find("public MyErr(String message, Throwable cause) {\nsuper(message, cause);", 1, true))
    assert.is_truthy(out:find("public MyErr(Throwable cause) {\nsuper(cause);", 1, true))
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
    assert.is_truthy(out:find('urlPatterns = {"/my"}', 1, true)) -- name minus the Servlet suffix
    -- the 2008 HTML boilerplate is gone
    assert.is_nil(out:find("out.println", 1, true))
    assert.is_truthy(out:find("extends HttpServlet", 1, true))
    assert.is_truthy(out:find("protected void doGet(", 1, true))
  end)

  it("android templates carry their default superclass and override", function()
    local act = templates.render("android_activity", { name = "A", package = "p", fields = {} })
    assert.is_truthy(act:find("extends Activity", 1, true))
    assert.is_truthy(act:find("protected void onCreate(Bundle savedInstanceState) {", 1, true))
    assert.is_truthy(act:find("super.onCreate(savedInstanceState);", 1, true))

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

  it("names() lists class first (the default), then the rest sorted", function()
    local names = templates.names()
    assert.are.equal("class", names[1])
    assert.is_true(names[2] < names[3]) -- remainder alphabetical
  end)

  it("register adds a custom template", function()
    templates.register("rec", function(o)
      return "record " .. o.name
    end)
    assert.are.equal("record Foo", templates.render("rec", { name = "Foo" }))
    assert.is_truthy(vim.tbl_contains(templates.names(), "rec"))
  end)

  it("record: components from fields, no field declarations", function()
    local out = templates.render("record", {
      name = "Point",
      package = "p",
      fields = { { type = "int", name = "x" }, { type = "int", name = "y" } },
    })
    assert.is_truthy(out:find("public record Point(int x, int y) {", 1, true))
  end)

  it("spring stereotypes carry their annotation", function()
    assert.is_truthy(templates.render("service", { name = "S", package = "p", fields = {} }):find("@Service", 1, true))
    assert.is_truthy(
      templates.render("controller", { name = "C", package = "p", fields = {} }):find("@RestController", 1, true)
    )
  end)

  it("junit5: jupiter imports, BeforeEach and Test", function()
    local out = templates.render("junit5", { name = "FooTest", package = "p", fields = {} })
    assert.is_truthy(out:find("org.junit.jupiter.api.Test", 1, true))
    assert.is_truthy(out:find("@BeforeEach", 1, true))
    assert.is_truthy(out:find("@Test", 1, true))
  end)

  it("entity: @Entity, @Id id, @Column on prompt fields, no imports", function()
    local out = templates.render("entity", {
      name = "User",
      package = "p",
      fields = {
        { mod = "private", type = "String", name = "firstName" },
        { mod = "private", type = "Long", name = "taxOrgId" },
      },
    })
    assert.is_truthy(out:find("@Entity", 1, true))
    -- @Id id comes before the prompt fields
    assert.is_truthy(out:find('private Long id;.-@Column%(name = "first_name"'))
    -- a blank line separates the annotated fields
    assert.is_truthy(out:find('@Column%(name = "first_name"%)\nprivate String firstName;\n\n@Column'))
    assert.is_truthy(out:find('@Column(name = "tax_org_id")\nprivate Long taxOrgId;', 1, true))
    assert.is_nil(out:find("import ", 1, true)) -- imports come from the LSP, not the template
  end)

  it("load_dir registers *.lua templates returning a function", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "return function(o) return 'custom ' .. o.name end" }, dir .. "/mytpl.lua")
    templates.load_dir(dir)
    assert.are.equal("custom Foo", templates.render("mytpl", { name = "Foo" }))
  end)

  describe("declarative spec", function()
    it("user input overrides the spec default extends", function()
      templates.register("exc", { extends = "Exception" })
      local out = templates.render("exc", { name = "E", package = "p", fields = {}, extends = "RuntimeException" })
      assert.is_truthy(out:find("extends RuntimeException", 1, true))
      assert.is_nil(out:find("extends Exception", 1, true))
    end)

    it("imports and annotations resolve from string, list and function", function()
      templates.register("ann", {
        imports = function(o)
          return { "java.util.List", "a." .. o.name }
        end,
        annotations = "@Generated",
      })
      local out = templates.render("ann", { name = "Foo", package = "p", fields = {} })
      assert.is_truthy(out:find("import java.util.List;", 1, true))
      assert.is_truthy(out:find("import a.Foo;", 1, true))
      assert.is_truthy(out:find("@Generated", 1, true))
    end)

    it("a spec carries no boilerplate — only the essence", function()
      -- declarative DTO: just imports + annotation, no class skeleton
      templates.register("dto", { imports = { "lombok.Data" }, annotations = { "@Data" } })
      local out = templates.render("dto", {
        name = "User",
        package = "com.app",
        fields = { { mod = "private", type = "String", name = "name" } },
      })
      assert.is_truthy(out:find("package com.app;", 1, true))
      assert.is_truthy(out:find("import lombok.Data;", 1, true))
      assert.is_truthy(out:find("@Data\npublic class User {", 1, true))
      assert.is_truthy(out:find("private String name;", 1, true))
    end)

    it("load_dir accepts a spec table too", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ 'return { annotations = "@Entity" }' }, dir .. "/entity.lua")
      templates.load_dir(dir)
      local out = templates.render("entity", { name = "User", package = "p", fields = {} })
      assert.is_truthy(out:find("@Entity\npublic class User {", 1, true))
    end)
  end)
end)

describe("repository template", function()
  local templates = require("jc.templates")

  it("is an interface extending JpaRepository over the implied entity", function()
    local out = templates.render("repository", { name = "UserRepository", package = "p", fields = {} })
    assert.is_truthy(out:find("public interface UserRepository extends JpaRepository<User, Long>", 1, true))
    -- spring-data builds the bean from the interface; no stereotype annotation
    assert.is_falsy(out:find("@Repository", 1, true))
    assert.is_falsy(out:find("public class", 1, true))
  end)

  it("also strips a Repo suffix, and falls back to Entity", function()
    local repo = templates.render("repository", { name = "OrderRepo", package = "p", fields = {} })
    assert.is_truthy(repo:find("OrderRepo extends JpaRepository<Order, Long>", 1, true))
    local bare = templates.render("repository", { name = "Repository", package = "p", fields = {} })
    assert.is_truthy(bare:find("JpaRepository<Entity, Long>", 1, true))
  end)

  it("lets the DSL override the supertype", function()
    local out = templates.render("repository", {
      name = "UserRepository",
      package = "p",
      fields = {},
      extends = "CrudRepository<User, UUID>",
    })
    assert.is_truthy(out:find("extends CrudRepository<User, UUID>", 1, true))
    assert.is_falsy(out:find("JpaRepository", 1, true))
  end)
end)

describe("template regressions", function()
  local templates = require("jc.templates")
  local F = { { mod = "private", type = "String", name = "name" } }

  it("an @interface takes elements, not fields", function()
    local out = templates.render("annotation", { name = "Ann", package = "p", fields = F })
    assert.is_truthy(out:find("String name();", 1, true))
    assert.is_nil(out:find("private String name;", 1, true))
  end)

  it("android callbacks compile: right parameter, no return from void", function()
    local act = templates.render("android_activity", { name = "A", package = "p", fields = {} })
    assert.is_nil(act:find("savedInstanceBundle", 1, true))

    local rcv = templates.render("android_broadcast_receiver", { name = "R", package = "p", fields = {} })
    assert.is_truthy(rcv:find("public void onReceive(", 1, true))
    assert.is_nil(rcv:find("return null", 1, true))
  end)

  it("junit scaffolds a runnable test, not just setUp", function()
    local out = templates.render("junit", { name = "FooTest", package = "p", fields = {} })
    assert.is_truthy(out:find("@Test", 1, true))
    assert.is_truthy(out:find("import org.junit.Test;", 1, true))
  end)

  it("controller maps the path its name implies", function()
    local out = templates.render("controller", { name = "UserController", package = "p", fields = {} })
    assert.is_truthy(out:find("@RestController", 1, true))
    assert.is_truthy(out:find('@RequestMapping("/user")', 1, true))
  end)
end)

describe("serializable template", function()
  local templates = require("jc.templates")

  local function render(o)
    o = o or {}
    o.name, o.package, o.fields = o.name or "Foo", "p", o.fields or {}
    return templates.render("serializable", o)
  end

  it("implements Serializable and declares a generated UID", function()
    local out = render()
    assert.is_truthy(out:find("import java.io.Serializable;", 1, true))
    assert.is_truthy(out:find("public class Foo implements Serializable {", 1, true))
    local uid = out:match("private static final long serialVersionUID = (%-?%d+)L;")
    assert.is_not_nil(uid)
    -- 18 digits, so it always fits a java long
    assert.are.equal(18, #uid:gsub("^%-", ""))
  end)

  it("generates a different UID each time", function()
    local seen = {}
    for _ = 1, 5 do
      seen[render():match("serialVersionUID = (%-?%d+)L")] = true
    end
    assert.is_true(vim.tbl_count(seen) > 1)
  end)

  it("keeps Serializable when the DSL adds its own interface", function()
    local out = render({ implements = "Comparable<Foo>" })
    assert.is_truthy(out:find("implements Serializable, Comparable<Foo>", 1, true))
  end)

  it("does not repeat an interface the user already asked for", function()
    local out = render({ implements = "Serializable, Cloneable" })
    assert.is_truthy(out:find("implements Serializable, Cloneable {", 1, true))
  end)

  it("the UID precedes the prompt fields, right under the declaration", function()
    local out = render({ fields = { { mod = "private", type = "String", name = "name" } } })
    assert.is_true(out:find("serialVersionUID", 1, true) < out:find("private String name;", 1, true))
    -- no blank line between "class Foo ... {" and the UID
    assert.is_truthy(out:find("implements Serializable {\nprivate static final long serialVersionUID", 1, true))
  end)
end)
