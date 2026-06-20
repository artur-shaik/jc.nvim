-- Class boilerplate templates, ported 1:1 from plugin/res/gen__class_*.tpl.
-- Each template is function(opts) -> java source string. opts:
--   name       class name
--   package    package name
--   fields     array of { mod, type, name } (mod defaults to "private")
--   extends    optional superclass
--   implements optional interface list
-- The result is reindented by the caller (gg=G), so exact whitespace here
-- does not matter — only structure does.
local M = {}

-- package declaration, or "" for the default (empty) package — emitting
-- "package ;" produces invalid Java and pushes organize_imports above it
local function package_line(opts)
  if opts.package and opts.package ~= "" then
    return "package " .. opts.package .. ";\n\n"
  end
  return ""
end

local function header(opts, keyword, default_extends)
  local result = package_line(opts)
  result = result .. "public " .. keyword .. " " .. opts.name
  if opts.extends then
    result = result .. " extends " .. opts.extends
  elseif default_extends then
    result = result .. " extends " .. default_extends
  end
  if opts.implements then
    result = result .. " implements " .. opts.implements
  end
  return result
end

-- field declarations; `suffix` is "" for "type name;" or "()" for interface
-- method-style "type name();"
local function fields_block(opts, suffix)
  local result = ""
  for _, field in ipairs(opts.fields or {}) do
    result = result .. field.mod .. " " .. field.type .. " " .. field.name .. (suffix or "") .. ";\n"
  end
  return result
end

local templates = {}

templates["class"] = function(opts)
  return header(opts, "class") .. " {\n\n" .. fields_block(opts) .. "\n}"
end

templates["interface"] = function(opts)
  -- interface fields render as method signatures (type name();)
  local result = package_line(opts)
  result = result .. "public interface " .. opts.name
  if opts.extends then
    result = result .. " extends " .. opts.extends
  end
  return result .. " {\n" .. fields_block(opts, "()") .. "\n}"
end

templates["enum"] = function(opts)
  local result = package_line(opts)
  result = result .. "public enum " .. opts.name
  return result .. " {\n" .. fields_block(opts) .. "\n}"
end

templates["annotation"] = function(opts)
  return header(opts, "@interface") .. " {\n" .. fields_block(opts) .. "\n}"
end

templates["exception"] = function(opts)
  local result = header(opts, "class", "Exception") .. " {\n" .. fields_block(opts)
  result = result .. "\npublic " .. opts.name .. "() {\n\n}\n"
  result = result .. "\npublic " .. opts.name .. "(String msg) {\nsuper(msg);\n}\n"
  return result .. "\n}"
end

templates["main"] = function(opts)
  local result = header(opts, "class") .. " {\n" .. fields_block(opts)
  result = result .. "\npublic static void main(String[] args) {\n\n}\n"
  return result .. "\n}"
end

templates["junit"] = function(opts)
  local result = package_line(opts)
  result = result .. "import static org.junit.Assert.*;\n\n"
  result = result .. "public class " .. opts.name
  if opts.extends then
    result = result .. " extends " .. opts.extends
  end
  if opts.implements then
    result = result .. " implements " .. opts.implements
  end
  result = result .. " {\n" .. fields_block(opts)
  result = result .. "\n@Before\npublic void setUp() {\n\n}\n"
  return result .. "\n}"
end

templates["singleton"] = function(opts)
  local name = opts.name
  local result = header(opts, "class") .. " {\n" .. fields_block(opts)
  result = result .. "\nprivate " .. name .. "() {\n\n}\n"
  result = result .. "\npublic static " .. name .. " getInstance() {\n"
  result = result .. "return " .. name .. "Holder.INSTANCE;\n"
  result = result .. "}\n"
  result = result .. "\nprivate static class " .. name .. "Holder {\n"
  result = result .. "private static final " .. name .. " INSTANCE = new " .. name .. "();\n"
  result = result .. "}\n"
  return result .. "\n}"
end

templates["servlet"] = function(opts)
  local name = opts.name
  local url = vim.fn.tolower(vim.fn.substitute(name, "\\C\\([A-Z]\\)", "/\\1", "g"))
  local result = package_line(opts)
  result = result .. '@WebServlet(name = "' .. name .. '", urlPatterns = {"' .. url .. '"})\n'
  result = result .. "public class " .. name
  if opts.extends then
    result = result .. " extends " .. opts.extends
  else
    result = result .. " extends HttpServlet"
  end
  if opts.implements then
    result = result .. " implements " .. opts.implements
  end
  result = result .. " {\n" .. fields_block(opts)
  result = result
    .. "\nprotected void processRequest(HttpServletRequest request, HttpServletResponse response)"
    .. " throws ServletException, IOException {\n"
  result = result .. 'response.setContentType("text/html;charset=UTF-8");\n'
  result = result .. "try (PrintWriter out = response.getWriter()) {\n"
  result = result .. 'out.println("<!DOCTYPE HTML");\n'
  result = result .. 'out.println("<html>");\n'
  result = result .. 'out.println("<head>");\n'
  result = result .. 'out.println("<title>Servlet ' .. name .. '</title>");\n'
  result = result .. 'out.println("</head>");\n'
  result = result .. 'out.println("<body>");\n'
  result = result .. 'out.println("<h1>Servlet ' .. name .. " at " .. url .. '</h1>");\n'
  result = result .. 'out.println("</body>");\n'
  result = result .. 'out.println("</html>");\n'
  result = result .. "}\n"
  result = result .. "}\n"
  result = result
    .. "\nprotected void doGet(HttpServletRequest request, HttpServletResponse response)"
    .. " throws ServletException, IOException {\n"
  result = result .. "processRequest(request, response);\n"
  result = result .. "}\n"
  result = result
    .. "\nprotected void doPost(HttpServletRequest request, HttpServletResponse response)"
    .. " throws ServletException, IOException {\n"
  result = result .. "processRequest(request, response);\n"
  result = result .. "}\n"
  return result .. "\n}"
end

local function android(default_extends, override)
  return function(opts)
    local result = header(opts, "class", default_extends) .. " {\n" .. fields_block(opts)
    result = result .. "\n@Override\n" .. override
    return result .. "\n}"
  end
end

templates["android_activity"] =
  android("Activity", "public void onCreate(Bundle savedInstanceState) {\nsuper.onCreate(savedInstanceBundle);\n}\n")
templates["android_fragment"] = android(
  "Fragment",
  "public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {\nreturn null;\n}\n"
)
templates["android_service"] = android("Service", "public IBinder onBind(Intent intent) {\nreturn null;\n}\n")
templates["android_broadcast_receiver"] =
  android("BroadcastReceiver", "public void onReceive(Context context, Intent intent) {\nreturn null;\n}\n")

-- user templates registered via setup{ templates_dir } land here
local custom = {}

function M.register(name, fn)
  custom[name] = fn
end

function M.get(name)
  return custom[name] or templates[name or "class"]
end

function M.names()
  local names = {}
  for name in pairs(templates) do
    names[#names + 1] = name
  end
  for name in pairs(custom) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

-- render template `name` (defaults to "class") with opts
function M.render(name, opts)
  return M.get(name)(opts)
end

return M
