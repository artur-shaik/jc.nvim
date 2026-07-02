-- Declarative class templates. A template is either:
--   * a function(opts) -> java source string (full control), or
--   * a spec table describing only the essence; the engine assembles the
--     surrounding class structure (package, declaration, extends/implements,
--     fields, braces).
--
-- opts passed to templates/specs:
--   name       class name
--   package    package name (may be empty -> default package)
--   fields     array of { mod, type, name } (mod defaults to "private")
--   extends    optional superclass (from user input, overrides spec default)
--   implements optional interface list (from user input)
--
-- Spec fields (all optional):
--   kind        "class" | "interface" | "enum" | "annotation" | "record"
--   modifiers   declaration modifiers (default "public")
--   extends     default superclass when the user gives none
--   implements  default interface list
--   imports     string | {string} | function(opts) -> string|{string}
--   annotations string | {string} | function(opts) -> string|{string}
--   body        string | function(opts) -> string ; members after the fields
--
-- The result is reindented by the caller (gg=G), so exact whitespace here
-- does not matter — only structure does.
local M = {}

-- which declaration parts each kind allows (Java rules)
local KINDS = {
  class = { keyword = "class", extends = true, implements = true },
  interface = { keyword = "interface", extends = true, implements = false },
  enum = { keyword = "enum", extends = false, implements = true },
  annotation = { keyword = "@interface", extends = false, implements = false },
  record = { keyword = "record", extends = false, implements = true, record = true },
}

-- package declaration, or "" for the default (empty) package — emitting
-- "package ;" produces invalid Java and pushes organize_imports above it
local function package_line(opts)
  if opts.package and opts.package ~= "" then
    return "package " .. opts.package .. ";\n\n"
  end
  return ""
end

-- field declarations; `suffix` is "" for "type name;" or "()" for interface
-- method-style "type name();". `annotate(field)` may return an annotation to
-- place above each field (e.g. @Column for an entity).
local function fields_block(opts, suffix, annotate)
  local fields = opts.fields or {}
  local result = ""
  for i, field in ipairs(fields) do
    if annotate then
      local a = annotate(field)
      if a and a ~= "" then
        result = result .. a .. "\n"
      end
    end
    result = result .. field.mod .. " " .. field.type .. " " .. field.name .. (suffix or "") .. ";\n"
    -- blank line between annotated fields for readability
    if annotate and i < #fields then
      result = result .. "\n"
    end
  end
  return result
end

-- camelCase -> snake_case (for @Column names)
local function snake_case(s)
  return (s:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2")):lower()
end

-- spec values may be a string, a list of strings or a function returning
-- either; normalize to a list / single string
local function resolve_list(value, opts)
  if value == nil then
    return {}
  end
  if type(value) == "function" then
    return resolve_list(value(opts), opts)
  end
  if type(value) == "string" then
    return { value }
  end
  return value
end

local function resolve_str(value, opts)
  if type(value) == "function" then
    return value(opts)
  end
  return value
end

-- assemble a full class source from a declarative spec
local function assemble(spec, opts)
  local kind = KINDS[spec.kind or "class"] or KINDS.class
  local out = package_line(opts)

  -- spec imports/annotations plus any contributed at runtime (e.g. lombok
  -- flags add @Data and its import on top of the chosen template)
  local imports = resolve_list(spec.imports, opts)
  vim.list_extend(imports, opts.imports or {})
  if #imports > 0 then
    for _, imp in ipairs(imports) do
      out = out .. "import " .. imp .. ";\n"
    end
    out = out .. "\n"
  end

  local annotations = resolve_list(spec.annotations, opts)
  vim.list_extend(annotations, opts.annotations or {})
  for _, annotation in ipairs(annotations) do
    out = out .. annotation .. "\n"
  end

  out = out .. (spec.modifiers or "public") .. " " .. kind.keyword .. " " .. opts.name

  if kind.record then
    local comp = {}
    for _, field in ipairs(opts.fields or {}) do
      comp[#comp + 1] = field.type .. " " .. field.name
    end
    out = out .. "(" .. table.concat(comp, ", ") .. ")"
  end
  if kind.extends then
    local ext = opts.extends or resolve_str(spec.extends, opts)
    if ext then
      out = out .. " extends " .. ext
    end
  end
  if kind.implements then
    local impl = opts.implements or resolve_str(spec.implements, opts)
    if impl then
      out = out .. " implements " .. impl
    end
  end

  out = out .. " {\n\n"
  -- enum constants come first as "A, B, C;"
  if kind.keyword == "enum" and opts.values and #opts.values > 0 then
    out = out .. table.concat(opts.values, ", ") .. ";\n"
  end
  -- members that must precede the prompt fields (e.g. an entity's @Id id)
  local pre = resolve_str(spec.pre_fields, opts)
  if pre then
    out = out .. pre .. "\n\n"
  end
  if not kind.record then
    out = out .. fields_block(opts, spec.kind == "interface" and "()" or "", spec.field_annotation)
  end
  local body = resolve_str(spec.body, opts)
  if body then
    out = out .. body .. "\n"
  end
  return out .. "\n}"
end

-- ---- built-in templates as declarative specs ----

local templates = {
  class = {},
  interface = { kind = "interface" },
  enum = { kind = "enum" },
  annotation = { kind = "annotation" },
  record = { kind = "record" },

  exception = {
    extends = "Exception",
    body = function(opts)
      return "public " .. opts.name .. "() {\n\n}\n\npublic " .. opts.name .. "(String msg) {\nsuper(msg);\n}"
    end,
  },

  main = { body = "public static void main(String[] args) {\n\n}" },

  singleton = {
    body = function(opts)
      local n = opts.name
      return "private "
        .. n
        .. "() {\n\n}\n\npublic static "
        .. n
        .. " getInstance() {\nreturn "
        .. n
        .. "Holder.INSTANCE;\n}\n\nprivate static class "
        .. n
        .. "Holder {\nprivate static final "
        .. n
        .. " INSTANCE = new "
        .. n
        .. "();\n}"
    end,
  },

  servlet = {
    extends = "HttpServlet",
    annotations = function(opts)
      local url = vim.fn.tolower(vim.fn.substitute(opts.name, "\\C\\([A-Z]\\)", "/\\1", "g"))
      return '@WebServlet(name = "' .. opts.name .. '", urlPatterns = {"' .. url .. '"})'
    end,
    body = function(opts)
      local url = vim.fn.tolower(vim.fn.substitute(opts.name, "\\C\\([A-Z]\\)", "/\\1", "g"))
      return "protected void processRequest(HttpServletRequest request, HttpServletResponse response)"
        .. " throws ServletException, IOException {\n"
        .. 'response.setContentType("text/html;charset=UTF-8");\n'
        .. "try (PrintWriter out = response.getWriter()) {\n"
        .. 'out.println("<!DOCTYPE HTML");\n'
        .. 'out.println("<html>");\n'
        .. 'out.println("<head>");\n'
        .. 'out.println("<title>Servlet '
        .. opts.name
        .. '</title>");\n'
        .. 'out.println("</head>");\n'
        .. 'out.println("<body>");\n'
        .. 'out.println("<h1>Servlet '
        .. opts.name
        .. " at "
        .. url
        .. '</h1>");\n'
        .. 'out.println("</body>");\n'
        .. 'out.println("</html>");\n'
        .. "}\n}\n\nprotected void doGet(HttpServletRequest request, HttpServletResponse response)"
        .. " throws ServletException, IOException {\nprocessRequest(request, response);\n}\n"
        .. "\nprotected void doPost(HttpServletRequest request, HttpServletResponse response)"
        .. " throws ServletException, IOException {\nprocessRequest(request, response);\n}"
    end,
  },

  junit = {
    imports = "static org.junit.Assert.*",
    body = "@Before\npublic void setUp() {\n\n}",
  },

  junit5 = {
    imports = {
      "org.junit.jupiter.api.Test",
      "org.junit.jupiter.api.BeforeEach",
      "static org.junit.jupiter.api.Assertions.*",
    },
    body = "@BeforeEach\nvoid setUp() {\n\n}\n\n@Test\nvoid test() {\n\n}",
  },

  -- JPA entity: @Entity with an @Id. Imports are intentionally omitted — the
  -- creation chain runs organize-imports, which pulls the project's own
  -- persistence package (jakarta.* or javax.*), so the template stays portable.
  entity = {
    annotations = "@Entity",
    -- @Id id comes before the prompt fields
    pre_fields = "@Id\n@GeneratedValue(strategy = GenerationType.IDENTITY)\nprivate Long id;",
    -- annotate each prompt field with @Column(name = "<snake_case>")
    field_annotation = function(field)
      return '@Column(name = "' .. snake_case(field.name) .. '")'
    end,
  },
}

-- spring stereotypes: a class carrying the matching @ annotation
for name, annotation in pairs({
  service = "Service",
  component = "Component",
  repository = "Repository",
  controller = "RestController",
}) do
  templates[name] = { annotations = "@" .. annotation }
end

-- android components: a class with a default superclass and one override
for name, def in pairs({
  android_activity = {
    "Activity",
    "@Override\npublic void onCreate(Bundle savedInstanceState) {\nsuper.onCreate(savedInstanceBundle);\n}",
  },
  android_fragment = {
    "Fragment",
    "@Override\npublic View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {\nreturn null;\n}",
  },
  android_service = { "Service", "@Override\npublic IBinder onBind(Intent intent) {\nreturn null;\n}" },
  android_broadcast_receiver = {
    "BroadcastReceiver",
    "@Override\npublic void onReceive(Context context, Intent intent) {\nreturn null;\n}",
  },
}) do
  templates[name] = { extends = def[1], body = def[2] }
end

-- user templates registered via setup{ templates_dir } land here
local custom = {}

function M.register(name, template)
  custom[name] = template
end

-- load user templates from a directory: each `<name>.lua` returns a
-- function(opts) -> string OR a declarative spec table
function M.load_dir(dir)
  dir = vim.fn.expand(dir)
  if vim.fn.isdirectory(dir) ~= 1 then
    return
  end
  for _, file in ipairs(vim.fn.glob(dir .. "/*.lua", true, true)) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    local ok, template = pcall(dofile, file)
    if ok and (type(template) == "function" or type(template) == "table") then
      custom[name] = template
    else
      vim.notify("jc: invalid template " .. file, vim.log.levels.WARN)
    end
  end
end

function M.get(name)
  return custom[name] or templates[name or "class"]
end

function M.names()
  local names = {}
  for name in pairs(templates) do
    if name ~= "class" then
      names[#names + 1] = name
    end
  end
  for name in pairs(custom) do
    names[#names + 1] = name
  end
  table.sort(names)
  -- "class" is the default, so it leads the list (e.g. the wizard picker)
  table.insert(names, 1, "class")
  return names
end

-- render template `name` (defaults to "class") with opts
function M.render(name, opts)
  local template = M.get(name)
  if type(template) == "function" then
    return template(opts)
  end
  return assemble(template, opts)
end

return M
