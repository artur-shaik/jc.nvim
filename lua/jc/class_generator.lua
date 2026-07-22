-- New class generator, ported from autoload/class_generator.vim.
-- Parses the one-line DSL
--   [template:][[subdir]:][/|/.]package.Class [extends X] [implements Y](fields):flags
-- resolves the target file path/package, renders a template and queues the
-- follow-up code generation (constructor/accessors/toString/...).
local templates = require("jc.templates")

local M = {}

local SEP = package.config:sub(1, 1)

-- ---- small vimscript-list helpers (0-based, inclusive, negatives from end) ----

-- mimic vim's list[i:j] slice (0-based, both ends inclusive, neg from end)
local function slice(list, i, j)
  local n = #list
  if i == nil then
    i = 0
  end
  if j == nil then
    j = -1
  end
  if i < 0 then
    i = n + i
  end
  if j < 0 then
    j = n + j
  end
  local out = {}
  for k = i, j do
    out[#out + 1] = list[k + 1] -- 0-based -> 1-based
  end
  return out
end

-- 0-based index of value in list, or -1
local function index0(list, value)
  for k, v in ipairs(list) do
    if v == value then
      return k - 1
    end
  end
  return -1
end

local function reversed(list)
  local out = {}
  for k = #list, 1, -1 do
    out[#out + 1] = list[k]
  end
  return out
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---- parsing ----

local MODS = {
  public = true,
  protected = true,
  private = true,
  abstract = true,
  static = true,
  final = true,
  strictfp = true,
}

-- turn a bare "<>" into the wildcard "<?>" (valid Java), e.g.
-- "Comparable<>" -> "Comparable<?>"
local function normalize_generics(s)
  return s and (s:gsub("<%s*>", "<?>"))
end
M.normalize_generics = normalize_generics

-- number of type parameters for common generic JDK types, so a bare
-- collection field type gets wildcards (HashMap -> HashMap<?, ?>)
local GENERIC_ARITY = {
  Iterable = 1,
  Collection = 1,
  List = 1,
  ArrayList = 1,
  LinkedList = 1,
  Set = 1,
  HashSet = 1,
  TreeSet = 1,
  LinkedHashSet = 1,
  Queue = 1,
  Deque = 1,
  Stack = 1,
  Iterator = 1,
  Optional = 1,
  Stream = 1,
  Comparable = 1,
  Comparator = 1,
  Class = 1,
  Supplier = 1,
  Consumer = 1,
  Callable = 1,
  Map = 2,
  HashMap = 2,
  TreeMap = 2,
  LinkedHashMap = 2,
  ConcurrentHashMap = 2,
  Hashtable = 2,
  Function = 2,
  BiConsumer = 2,
  BiFunction = 3,
}

-- fill in wildcards for a known generic type given without parameters, and
-- complete an empty "<>" with the right number of "?": HashMap -> HashMap<?, ?>
local function infer_generics(typ)
  if not typ then
    return typ
  end
  local base, inside = typ:match("^(.-)<(.*)>%s*$")
  local simple = (base or typ):match("[%w_%$]+$")
  local arity = simple and GENERIC_ARITY[simple]
  -- already has non-empty parameters -> keep as is
  if base and vim.trim(inside) ~= "" then
    return typ
  end
  if not arity then
    return base and normalize_generics(typ) or typ -- e.g. unknown "<>" -> "<?>"
  end
  local wild = {}
  for _ = 1, arity do
    wild[#wild + 1] = "?"
  end
  return (base or typ) .. "<" .. table.concat(wild, ", ") .. ">"
end

-- split `s` on `sep` only at bracket depth 0, so a comma inside generics
-- ("HashMap<Long, String>") doesn't split the field
local function split_top_level(s, sep)
  local parts, depth, buf = {}, 0, {}
  for ch in s:gmatch(".") do
    if ch == "<" or ch == "(" or ch == "[" then
      depth = depth + 1
      buf[#buf + 1] = ch
    elseif ch == ">" or ch == ")" or ch == "]" then
      depth = depth - 1
      buf[#buf + 1] = ch
    elseif ch == sep and depth == 0 then
      parts[#parts + 1] = table.concat(buf)
      buf = {}
    else
      buf[#buf + 1] = ch
    end
  end
  parts[#parts + 1] = table.concat(buf)
  return parts
end

-- parse the "(...)" slot of an enum as a list of constant names ("MON, TUE")
function M.parse_enum_values(fieldstr)
  local inner = trim(fieldstr:sub(2, -2))
  if inner == "" then
    return {}
  end
  local values = {}
  for _, part in ipairs(split_top_level(inner, ",")) do
    part = trim(part)
    if part ~= "" then
      values[#values + 1] = part
    end
  end
  return values
end

-- parse "(mods type name, ...)" -> array of { mod, type, name }; the type may
-- contain generics with their own commas/spaces ("Map<String, Long>")
function M.parse_fields(fieldstr)
  local inner = trim(fieldstr:sub(2, -2)) -- drop surrounding ()
  if inner == "" then
    return {}
  end
  local fields = {}
  for _, part in ipairs(split_top_level(inner, ",")) do
    part = trim(part)
    local name = part:match("[%w_%$]+$") -- the field name = trailing identifier
    if name and name ~= part then
      local rest = trim(part:sub(1, #part - #name))
      -- peel leading modifier words; whatever remains is the type
      local mods = {}
      while true do
        local w, after = rest:match("^([%a]+)%s+(.*)$")
        if w and MODS[w] then
          mods[#mods + 1] = w
          rest = after
        else
          break
        end
      end
      if rest ~= "" then
        fields[#fields + 1] = {
          mod = #mods > 0 and table.concat(mods, " ") or "private",
          type = infer_generics(rest),
          name = name,
        }
      end
    end
  end
  return fields
end

-- parse ":flag(args):flag2" -> map flag -> args array
function M.parse_methods(flagstr)
  local methods = {}
  for method in vim.gsplit(flagstr:sub(2), ":", { plain = true }) do
    if method ~= "" then
      local paren = method:find("(", 1, true)
      if paren and paren > 1 then
        local name = method:sub(1, paren - 1)
        local args = {}
        for arg in vim.gsplit(method:sub(paren + 1, -2), ",", { plain = true }) do
          args[#args + 1] = arg == "*" and arg or tonumber(arg) or arg
        end
        methods[name] = args
      else
        methods[method] = {}
      end
    end
  end
  return methods
end

-- lombok flags -> a class annotation + its import (added to the class instead
-- of running a jdtls code generator). `lombok` is the common @Data default.
local LOMBOK = {
  lombok = { "@Data", "lombok.Data" },
  lombokData = { "@Data", "lombok.Data" },
  lombokValue = { "@Value", "lombok.Value" },
  lombokBuilder = { "@Builder", "lombok.Builder" },
  lombokGetter = { "@Getter", "lombok.Getter" },
  lombokSetter = { "@Setter", "lombok.Setter" },
  lombokToString = { "@ToString", "lombok.ToString" },
  lombokEqualsHashCode = { "@EqualsAndHashCode", "lombok.EqualsAndHashCode" },
  lombokNoArgs = { "@NoArgsConstructor", "lombok.NoArgsConstructor" },
  lombokAllArgs = { "@AllArgsConstructor", "lombok.AllArgsConstructor" },
  lombokRequiredArgs = { "@RequiredArgsConstructor", "lombok.RequiredArgsConstructor" },
  lombokSlf4j = { "@Slf4j", "lombok.extern.slf4j.Slf4j" },
}
M.LOMBOK = LOMBOK

-- split a parsed flags map into jdtls code-gen flags (kept in `methods`) and
-- lombok annotations/imports contributed to the class
local function split_lombok(methods)
  local codegen, annotations, imports = {}, {}, {}
  for name in pairs(methods or {}) do
    local lb = LOMBOK[name]
    if lb then
      annotations[#annotations + 1] = lb[1]
      imports[#imports + 1] = lb[2]
    else
      codegen[name] = methods[name]
    end
  end
  return codegen, annotations, imports
end

-- split the DSL string into its structural pieces (no path resolution yet)
function M.parse_input(userinput)
  local rest = userinput
  local result = {}

  -- template: leading "word:"
  local template, after = rest:match("^([%w_]+):(.*)$")
  if template then
    result.template = template
    rest = after
  end

  -- subdir: "[...]:"
  local subdir, after2 = rest:match("^%[(.-)%]:(.*)$")
  if subdir then
    result.subdir = subdir
    rest = after2
  end

  -- trailing flags ":..." (first colon at structural level)
  local colon = rest:find(":", 1, true)
  if colon then
    result.flags = rest:sub(colon)
    rest = rest:sub(1, colon - 1)
  end

  -- fields "(...)" at the end
  local fields = rest:match("(%b())%s*$")
  if fields then
    result.fields_str = fields
    rest = rest:sub(1, rest:find("%b()%s*$") - 1)
  end

  -- implements / extends
  local impl_at = rest:find("%s+implements%s+")
  if impl_at then
    result.implements = trim(rest:sub(impl_at):gsub("%s+implements%s+", "", 1))
    rest = rest:sub(1, impl_at - 1)
  end
  local ext_at = rest:find("%s+extends%s+")
  if ext_at then
    result.extends = trim(rest:sub(ext_at):gsub("%s+extends%s+", "", 1))
    rest = rest:sub(1, ext_at - 1)
  end

  result.path_str = trim(rest)
  if result.path_str == "" then
    return nil
  end
  return result
end

-- relative path: append parsed path to the current package
local function relative_path(path, new_path, currentPackage)
  local pkg_parts = {}
  vim.list_extend(pkg_parts, currentPackage)
  vim.list_extend(pkg_parts, slice(path, 0, -2))
  return {
    path = new_path .. table.concat(slice(path, 0, -2), SEP),
    class = path[#path],
    package = table.concat(pkg_parts, "."),
  }
end

-- resolve filesystem path + package from the parsed class path; ported 1:1
-- from s:BuildPathData (currentPath is the REVERSED dir list)
function M.build_path_data(path, subdir, currentPath, currentPackage)
  local new_path = ""
  if subdir and subdir ~= "" then
    local idx = index0(currentPath, "src")
    new_path = string.rep(".." .. SEP, idx >= 0 and idx or 0)
    new_path = new_path .. subdir .. SEP .. "java" .. SEP
    new_path = new_path .. table.concat(currentPackage, SEP) .. SEP
  end

  local is_absolute = path[1] == "/" or path[1]:sub(1, 1) == "/"
  if is_absolute then
    if path[1] == "/" then
      path = slice(path, 1, -1)
    else
      path[1] = path[1]:sub(2)
    end
    local sameSubpackageIdx = index0(currentPath, currentPackage[1])
    if sameSubpackageIdx < 0 then
      return relative_path(path, new_path, currentPackage)
    end
    local cur = slice(currentPath, 0, sameSubpackageIdx)
    local idx = index0(cur, path[1])
    local newPackage
    if idx < 0 then
      new_path = new_path .. string.rep(".." .. SEP, #cur)
      new_path = new_path .. table.concat(slice(path, 0, -2), SEP)
      newPackage = slice(path, 0, -2)
    else
      new_path = new_path .. (idx > 0 and string.rep(".." .. SEP, #slice(cur, 0, idx - 1)) or "")
      new_path = new_path .. table.concat(slice(path, 1, -2), SEP)
      newPackage = slice(path, 1, -2)
      -- prepend the shared parent packages (reversed tail of cur)
      local prefix = slice(reversed(cur), 0, -idx - 1)
      local merged = {}
      vim.list_extend(merged, prefix)
      vim.list_extend(merged, newPackage)
      newPackage = merged
    end
    return {
      path = new_path,
      class = path[#path],
      package = table.concat(newPackage, "."),
    }
  end
  return relative_path(path, new_path, currentPackage)
end

-- a class name must be present and follow Java convention (uppercase first);
-- a trailing dot or a lowercase segment means the user typed only a package
function M.is_class_name(name)
  return type(name) == "string" and name:match("^%u[%w_$]*$") ~= nil
end

-- copy the template/extends/implements/fields/flags from a parsed DSL onto
-- resolved path data
local function decorate(data, parsed)
  data.template = parsed.template
  -- supertypes can't carry a wildcard, so they are kept verbatim (a bare
  -- "<>" there is a user error caught by the wizard validator)
  data.extends = parsed.extends
  data.implements = parsed.implements
  if parsed.fields_str then
    if parsed.template == "enum" then
      -- for an enum the "(...)" slot lists the constants, not fields
      data.values = M.parse_enum_values(parsed.fields_str)
    else
      local fields = M.parse_fields(parsed.fields_str)
      if #fields > 0 then
        data.fields = fields
      end
    end
  end
  if parsed.flags then
    local codegen, annotations, imports = split_lombok(M.parse_methods(parsed.flags))
    data.methods = codegen
    if #annotations > 0 then
      data.annotations = annotations
      data.imports = imports
    end
  end
  return data
end

-- reassemble a parsed DSL back into its one-line form (used by the wizard to
-- show an editable command before generating)
function M.build_dsl(p)
  local s = ""
  if p.template then
    s = s .. p.template .. ":"
  end
  if p.subdir then
    s = s .. "[" .. p.subdir .. "]:"
  end
  s = s .. p.path_str
  if p.extends then
    s = s .. " extends " .. p.extends
  end
  if p.implements then
    s = s .. " implements " .. p.implements
  end
  if p.fields_str then
    s = s .. p.fields_str
  end
  if p.flags then
    s = s .. p.flags
  end
  return s
end

-- full DSL -> resolved class data (or nil)
function M.parse(userinput, currentPath, currentPackage)
  local parsed = M.parse_input(userinput)
  if not parsed then
    return nil
  end
  local path = vim.split(parsed.path_str, ".", { plain = true })
  return decorate(M.build_path_data(path, parsed.subdir, currentPath, currentPackage), parsed)
end

-- ---- materialization ----

local function template_options(data)
  return {
    name = data.class,
    package = data.package,
    fields = data.fields,
    extends = data.extends,
    implements = data.implements,
    annotations = data.annotations, -- lombok @-annotations, if any
    imports = data.imports,
    values = data.values, -- enum constants, if any
  }
end

-- queue the follow-up code generation in the same order as the vimscript
local function queue_generation(data)
  local chains = require("jc.chains")()
  local methods = data.methods or {}
  local is_interface = data.template == "interface"

  chains:add(function()
    require("jc.jdtls").organize_imports(0, false)
  end)
  if methods.constructor then
    chains:add(function()
      require("jc.jdtls").generate_constructor(nil, nil, { default = false })
    end)
  end
  -- wait for jdtls diagnostics on a freshly-created class that has a supertype
  local has_supertype = (data.extends and data.extends ~= "") or (data.implements and data.implements ~= "")
  chains:add(function()
    require("jc.jdtls").generate_abstractMethods(has_supertype)
  end)
  if not is_interface and data.fields then
    chains:add(function()
      require("jc.jdtls").generate_accessors()
    end)
  end
  if methods.equals or methods.hashCode then
    chains:add(function()
      require("jc.jdtls").generate_hashCodeAndEquals()
    end)
  end
  if methods.toString then
    chains:add(function()
      require("jc.jdtls").generate_toString()
    end)
  end
  -- give jdtls time to index the just-written class (and its fields) before
  -- the first code-gen step, so e.g. toString sees the fields
  vim.defer_fn(function()
    chains:execute_next_if_exists()
  end, 800)
end

local function create_class(data)
  local path = data.current_path .. SEP .. data.path
  -- collapse the duplicate separators an empty data.path introduces
  local file_name = (vim.fn.fnamemodify(path .. SEP .. data.class, ":p") .. ".java"):gsub(SEP .. SEP .. "+", SEP)

  -- don't clobber an existing class — open it and bail
  if vim.fn.filereadable(file_name) == 1 then
    vim.notify("jc: class already exists: " .. file_name, vim.log.levels.WARN)
    vim.cmd("edit " .. vim.fn.fnameescape(file_name))
    return
  end

  if vim.fn.filewritable(path) ~= 2 then
    vim.fn.mkdir(path, "p")
  end
  -- split if the current buffer has unsaved changes and isn't hidden
  if vim.bo.modified and not vim.o.hidden then
    vim.cmd("vs")
  end
  vim.cmd("edit " .. vim.fn.fnameescape(file_name))

  local size = vim.fn.getfsize(file_name)
  local empty = (size <= 0 and size > -2) or (vim.fn.line("$") == 1 and vim.fn.getline(1) == "")
  if not empty then
    return
  end

  local rendered = templates.render(data.template, template_options(data))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(rendered, "\n"))
  vim.cmd("silent! normal! gg=G")
  vim.fn.search(data.class)
  vim.cmd("silent! normal! j")
  vim.cmd("silent! write")
  vim.cmd("silent! edit")
  -- mark as a brand-new file so jc.lua's BufWritePost hook refreshes the
  -- jdtls build path (gd/codegen need the class registered)
  vim.b.jc_new_java_file = true
  queue_generation(data)
end

-- ---- prompt completion (ported from class_generator#Completion) ----

local KEYWORDS = { "extends", "implements" }
local METHOD_FLAGS = { "constructor", "toString", "hashCode", "equals" }

-- all flag names for completion: jdtls code-gen flags first, then lombok
local ALL_FLAGS
local function all_flags()
  if not ALL_FLAGS then
    ALL_FLAGS = vim.deepcopy(METHOD_FLAGS)
    local lombok = vim.tbl_keys(LOMBOK)
    table.sort(lombok)
    vim.list_extend(ALL_FLAGS, lombok)
  end
  return ALL_FLAGS
end

-- "a:b:c" -> "a:b:" (everything already typed before the current segment)
local function completed_prefix(tokens)
  local done = table.concat(slice(tokens, 0, -2), ":")
  if done ~= "" then
    done = done .. ":"
  end
  return done
end

local function template_completions(command, add_sep)
  local result = {}
  for _, name in ipairs(require("jc.templates").names()) do
    if name:sub(1, #command) == command then
      result[#result + 1] = name .. (add_sep and ":" or "")
    end
  end
  return result
end

-- project source roots (.../src/main/java, .../src/test/java) are discovered
-- once per project so package completion is scoped to real java sources and
-- never globs bin/build/module dirs. Cached by project root.
local source_root_cache = {}

local function project_root_dir()
  local root =
    vim.fs.root(0, { ".git", "settings.gradle", "settings.gradle.kts", "pom.xml", "build.gradle", "mvnw", "gradlew" })
  return root or vim.fn.getcwd()
end

local function source_roots()
  local root = project_root_dir()
  if source_root_cache[root] then
    return source_root_cache[root]
  end
  local roots = {}
  for _, kind in ipairs({ "main", "test" }) do
    -- multi-module (**) and single-module (direct) layouts
    for _, p in ipairs(vim.fn.glob(root .. "/**/src/" .. kind .. "/java", true, true)) do
      roots[#roots + 1] = p
    end
    local direct = root .. "/src/" .. kind .. "/java"
    if vim.fn.isdirectory(direct) == 1 then
      roots[#roots + 1] = direct
    end
  end
  source_root_cache[root] = roots
  return roots
end

-- exposed for goto_fqn's filesystem fallback
M.source_roots = source_roots

-- subprojects keyed by name: { <name> = { dir, sets = { main=path, test=path } } }
-- derived from the discovered source roots (.../<module>/src/<set>/java)
local module_cache = {}

function M.modules()
  local root = project_root_dir()
  if module_cache[root] then
    return module_cache[root]
  end
  local mods = {}
  local tail = SEP .. "src" .. SEP .. "([^" .. SEP .. "]+)" .. SEP .. "java$"
  for _, sr in ipairs(source_roots()) do
    local set = sr:match(tail)
    if set then
      local dir = sr:gsub(tail, "")
      local name = vim.fn.fnamemodify(dir, ":t")
      if name ~= "" then
        mods[name] = mods[name] or { dir = dir, sets = {} }
        mods[name].sets[set] = sr
      end
    end
  end
  module_cache[root] = mods
  return mods
end

-- LSP SymbolKind: Class=5, Enum=10, Interface=11
local TYPE_KINDS = { extends = { [5] = true, [11] = true }, implements = { [11] = true } }
local FIELD_TYPE_KINDS = { [5] = true, [10] = true, [11] = true }

-- package segments that mark non-API / internal types you can't import
local BLOCKED_SEGMENTS = { internal = true, impl = true, shaded = true, bundled = true, relocated = true }
-- group-id roots that, appearing AFTER the first segment, signal a shaded /
-- relocated jar (e.g. wiremock.com.fasterxml...). Kept to com/org only —
-- net/io/etc. are legitimate JDK package segments (java.io, java.net)
local SHADE_ROOT = { com = true, org = true }
-- standard top packages whose own subpackages are never relocations
local STD_ROOT = {
  java = true,
  javax = true,
  jakarta = true,
  jdk = true,
  sun = true,
  kotlin = true,
  scala = true,
  groovy = true,
  android = true,
}

-- default prefixes of known non-API packages (JDK internals + internal
-- packages of common libraries) that workspace/symbol surfaces but you can't
-- import. Not exhaustive — extend per setup with `class_type_exclude`.
local DEFAULT_EXCLUDES = {
  "sun",
  "com.sun",
  "jdk.internal",
  "java.lang.invoke",
  "com.fasterxml.jackson.databind.introspect",
  "com.fasterxml.jackson.databind.cfg",
  "com.fasterxml.jackson.databind.deser",
  "com.fasterxml.jackson.databind.ser",
  "org.springframework.aop.framework.autoproxy",
  "org.hibernate.internal",
}

-- user-supplied package prefixes added on top of DEFAULT_EXCLUDES via the
-- setup option `class_type_exclude`
local excludes = vim.deepcopy(DEFAULT_EXCLUDES)
function M.set_type_excludes(prefixes)
  excludes = vim.deepcopy(DEFAULT_EXCLUDES)
  vim.list_extend(excludes, prefixes or {})
end

-- heuristically reject types not meant to be imported: internal/impl/shaded
-- packages, shaded relocations (a TLD segment appearing after the first,
-- e.g. wiremock.com.fasterxml...), and excluded prefixes (defaults + user).
-- Can't catch every package-private type in ordinary packages — the protocol
-- gives no visibility; those need a `class_type_exclude` entry.
local function blocked_package(container)
  if not container or container == "" then
    return false
  end
  for _, prefix in ipairs(excludes) do
    if container == prefix or container:sub(1, #prefix + 1) == prefix .. "." then
      return true
    end
  end
  local segs = vim.split(container, ".", { plain = true })
  for _, seg in ipairs(segs) do
    if BLOCKED_SEGMENTS[seg] then
      return true
    end
  end
  -- shaded relocation: a com/org root reappears past the first segment, and
  -- the package doesn't start at a standard root (java.io stays allowed)
  if not STD_ROOT[segs[1]] then
    for i = 2, #segs do
      if SHADE_ROOT[segs[i]] then
        return true
      end
    end
  end
  return false
end

-- type names from jdtls matching `query`, as "<prefix><sep><Name>"
local function type_completions(query, prefix, kinds, sep)
  local client = require("jc.lsp").get_jdtls_client()
  if not client then
    return {}
  end
  -- synchronous: completion must return inline; jdtls answers quickly
  local response = client:request_sync("workspace/symbol", { query = query }, 1000)
  if not response or response.err or type(response.result) ~= "table" then
    return {}
  end
  -- workspace/symbol indexes every project jdtls has opened, not just this
  -- one; keep only types that are actually importable here — library types
  -- on the classpath (jdt://) and sources under the current project root
  local root = project_root_dir()
  local seen, matches = {}, {}
  for _, sym in ipairs(response.result) do
    local uri = sym.location and sym.location.uri or ""
    local from_project = uri:match("^file:") ~= nil and vim.uri_to_fname(uri):sub(1, #root + 1) == root .. SEP
    local importable = uri:match("^jdt:") ~= nil or from_project
    -- skip nested types (containerName ends in a class name, or the uri
    -- carries a "$"): they can't be imported by their simple name, so
    -- organize_imports would leave them unresolved (e.g. ImmutableTable$X)
    local enclosing = sym.containerName and sym.containerName:match("[^.]+$")
    local nested = uri:find("%$") ~= nil or (enclosing ~= nil and enclosing:match("^%u") ~= nil)
    local junk = nested or blocked_package(sym.containerName)
    if importable and not junk and kinds[sym.kind] and not seen[sym.name] then
      seen[sym.name] = true
      -- rank: common JDK (java.lang/util) < project < other JDK < libraries
      local c = sym.containerName or ""
      local rank = 3
      if c == "java.lang" or c == "java.util" then
        rank = 0
      elseif from_project then
        rank = 1
      elseif c:match("^javax?%.") or c:match("^jakarta%.") then
        rank = 2
      end
      matches[#matches + 1] = { name = sym.name, rank = rank }
    end
  end
  table.sort(matches, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.name < b.name
  end)
  local result = {}
  for _, m in ipairs(matches) do
    result[#result + 1] = prefix .. (sep or " ") .. m.name
  end
  return result
end

-- the trailing type identifier of `s` and the text before it; the boundary is
-- any non-identifier char (space, "<", ",", "(", "[") so completion works
-- inside generics: "List<Strin" -> ("Strin", "List<")
local function trailing_type_query(s)
  local q = s:match("[%w_%$%.]*$")
  return q, s:sub(1, #s - #q)
end

-- for the current field text `frag` (after the last comma), return the jdtls
-- type names for its type token + the token, or ({}, "") when typing the field
-- name or a modifier
local function field_type_completions(frag)
  local trailing = frag:match("%s$") ~= nil
  local words = {}
  for w in frag:gmatch("%S+") do
    words[#words + 1] = w
  end
  -- the word under the cursor (empty right after "(", "," or a space)
  local word = (not trailing) and (words[#words] or "") or ""
  local preceding = #words - ((not trailing) and 1 or 0)
  -- a non-modifier word before the cursor means the type is already given
  for k = 1, preceding do
    if not MODS[words[k]] then
      return {}, "" -- typing the field name, not the type
    end
  end
  if word ~= "" and MODS[word] then
    return {}, "" -- still finishing a modifier
  end
  -- complete the trailing identifier so generics ("List<Strin") work
  local query = trailing_type_query(word)
  return type_completions(query, "", FIELD_TYPE_KINDS, ""), query
end

-- inside the field list "(...)", complete the type token of the current field
local function field_completions(command, completed)
  local paren = command:find("%([^)]*$") -- last unclosed "("
  if not paren then
    return nil
  end
  local frag = command:sub(paren + 1):match("[^,]*$"):gsub("^%s+", "") -- current field
  local names, current = field_type_completions(frag)
  local prefix = completed .. command:sub(1, #command - #current)
  local result = {}
  for _, name in ipairs(names) do
    result[#result + 1] = prefix .. name
  end
  return result
end

local function keyword_completions(command, completed, is_relative)
  local tokens = vim.split(command, " ", { plain = true })
  local prev = tokens[#tokens - 1]
  local prefix = completed .. (is_relative and "" or "/") .. table.concat(slice(tokens, 0, -2), " ")
  -- right after "extends "/"implements " -> complete class/interface names
  if #tokens > 1 and TYPE_KINDS[prev] then
    return type_completions(tokens[#tokens], prefix, TYPE_KINDS[prev])
  end
  -- otherwise offer the keywords themselves
  local result = {}
  for _, kw in ipairs(KEYWORDS) do
    if not command:find("%f[%w]" .. kw .. "%f[%W]") and kw:sub(1, #tokens[#tokens]) == tokens[#tokens] then
      result[#result + 1] = prefix .. " " .. kw
    end
  end
  return result
end

-- glob package candidates. With `roots` (a chosen [module]) packages come
-- from those source roots; otherwise absolute (/) lists packages across all
-- project source roots and relative lists subpackages of the current package.
local function package_completions(command, completed, is_relative, roots)
  if command:find(" ") then -- past the class name -> suggest keywords
    return keyword_completions(command, completed, is_relative)
  end

  local pattern = command:gsub("%.", SEP)
  local seen, result = {}, {}
  local function add(prefix, rel)
    rel = rel:gsub(SEP, "."):gsub("%.$", "")
    if rel ~= "" and not seen[rel] then
      seen[rel] = true
      result[#result + 1] = completed .. prefix .. rel
    end
  end

  -- "**" before the typed segment so it matches a package at any depth
  -- (e.g. /model finds com.foo.model), mirroring the original glob; collapse
  -- duplicate separators so a bare/leading dot ("." -> "/") doesn't break it
  local matcher = (SEP .. "**" .. SEP .. pattern .. "*" .. SEP):gsub(SEP .. SEP .. "+", SEP)

  -- scoped to a chosen [module]: packages from its source roots, bare names
  if roots then
    for _, sr in ipairs(roots) do
      for _, path in ipairs(vim.fn.glob(sr .. matcher, true, true)) do
        add("", path:sub(#sr + 2))
      end
    end
    return result
  end

  if is_relative then
    -- only meaningful inside a package; otherwise stay quiet (no project noise)
    local ok, pkg = pcall(function()
      return require("jc.treesitter").get_package()
    end)
    if not ok or not pkg or pkg == "" then
      return result
    end
    local dir = vim.fn.expand("%:p:h")
    for _, path in ipairs(vim.fn.glob(dir .. matcher, true, true)) do
      add("", path:sub(#dir + 2))
    end
    return result
  end

  for _, sr in ipairs(source_roots()) do
    for _, path in ipairs(vim.fn.glob(sr .. matcher, true, true)) do
      add("/", path:sub(#sr + 2))
    end
  end
  return result
end

local function subdir_completions(command, completed)
  -- tolerate an autopairs-inserted closing bracket: "[module]" -> "module"
  command = command:gsub("%]$", "")
  local parts = vim.split(vim.fn.expand("%:p:h"), SEP, { plain = true })
  local src = index0(parts, "src")
  if src >= 0 then
    parts = slice(parts, 0, src)
  end
  local pre = SEP .. table.concat(parts, SEP) .. SEP
  local result, seen = {}, {}
  local function add(name)
    if name:sub(1, #command) == command and not seen[name] then
      seen[name] = true
      result[#result + 1] = completed .. "[" .. name .. "]"
    end
  end
  -- source-set dirs at the current src level (test, main, androidTest, ...)
  for _, path in ipairs(vim.fn.glob(pre .. command .. "*" .. SEP, false, true)) do
    add(path:sub(#pre + 1, -2))
  end
  -- subprojects (and module/<set> to target a specific source set)
  for name, mod in pairs(M.modules()) do
    add(name)
    for set in pairs(mod.sets) do
      add(name .. "/" .. set)
    end
  end
  return result
end

local function method_completions(command, completed)
  local result = {}
  for _, kw in ipairs(all_flags()) do
    if kw:sub(1, #command) == command then
      result[#result + 1] = completed .. kw
    end
  end
  return result
end

local function is_template_name(name)
  return vim.tbl_contains(require("jc.templates").names(), name)
end

-- a colon segment is "the class path" once it carries a class/package marker
-- (slash, dot or uppercase first letter), distinguishing it from a template
-- name or a [subdir]
local function is_path_token(t)
  return t ~= "" and (t:find("/", 1, true) ~= nil or t:find(".", 1, true) ~= nil or t:match("^%u") ~= nil)
end

-- classify the already-typed segments to know which structural slot the
-- current (last) segment is in
local function prior_state(tokens)
  local path_given, subdir_given = false, false
  for i = 1, #tokens - 1 do
    local t = tokens[i]
    local is_template = i == 1 and is_template_name(t)
    if t:match("^%[.*%]$") then
      subdir_given = true
    elseif not is_template and is_path_token(t) then
      path_given = true
    end
  end
  return path_given, subdir_given
end

-- source roots of the subproject containing the current file (so its source
-- sets see each other)
local function current_module_roots()
  local file = vim.fn.expand("%:p")
  for _, m in pairs(M.modules()) do
    if file:sub(1, #m.dir + 1) == m.dir .. SEP then
      return vim.tbl_values(m.sets)
    end
  end
  return nil
end

-- the source roots to scope package completion to once a [..] slot is set:
-- a subproject name -> that module (a specific set if given, else all); a
-- plain source-set ([test]/[main]) -> the current module's sets (test and
-- main see each other)
local function module_scope(tokens)
  for i = 1, #tokens - 1 do
    local content = tokens[i]:match("^%[(.-)%]$")
    if content then
      local mod, set = content:match("^([^/]+)/?(.*)$")
      local m = M.modules()[mod]
      if m then
        if set ~= "" and m.sets[set] then
          return { m.sets[set] }
        end
        return vim.tbl_values(m.sets)
      end
      return current_module_roots()
    end
  end
  return nil
end

-- customlist completion entry point (exposed via v:lua for vim.fn.input)
-- follows the DSL shape: template:[subdir]:/package.Class extends/implements
-- (fields):flag:flag
function M.complete(_arglead, line, cursorpos)
  -- complete what's left of the cursor, not the whole line, so editing mid
  -- string (e.g. right after "[") offers the right candidates
  if cursorpos then
    line = line:sub(1, cursorpos)
  end
  local tokens = vim.split(line, ":", { plain = true })
  local command = tokens[#tokens]
  local completed = completed_prefix(tokens)
  local result = {}
  local first = command:sub(1, 1)
  local path_given, subdir_given = prior_state(tokens)
  -- once a [module] is chosen, packages come from that module
  local scope = module_scope(tokens)

  -- inside the field list of the class path: complete the field type
  if not path_given then
    local fields = field_completions(command, completed)
    if fields then
      return fields
    end
  end

  if first == "/" then
    -- absolute class path
    vim.list_extend(result, package_completions(command:sub(2), completed, false, scope))
  elseif first == "[" then
    -- subdirectory
    vim.list_extend(result, subdir_completions(command:sub(2), completed))
  elseif path_given then
    -- the class path is in; remaining colon segments are method flags
    vim.list_extend(result, method_completions(command, completed))
  elseif #tokens == 1 then
    -- first slot: a template or the (relative) class path
    vim.list_extend(result, template_completions(command, true))
    vim.list_extend(result, package_completions(command, completed, true))
  else
    -- after template:/subdir:, before the class path -> offer the remaining
    -- prefix options (subdir if not given) and the class path
    if not subdir_given then
      vim.list_extend(result, subdir_completions(command, completed))
    end
    vim.list_extend(result, package_completions(command, completed, true, scope))
  end
  return result
end

-- resolve a class directly into `base` (a source root): the package is taken
-- from the typed path literally, no backtracking
local function direct_data(parsed, base)
  local pkg_path = vim.split((parsed.path_str:gsub("^/", "")), ".", { plain = true })
  local pkg = table.concat(slice(pkg_path, 0, -2), ".")
  return decorate({
    class = pkg_path[#pkg_path],
    package = pkg,
    current_path = base .. SEP,
    path = (pkg:gsub("%.", SEP)),
  }, parsed)
end

-- the source root (.../src/<set>/java) the current file sits in
local function current_source_root()
  local file = vim.fn.expand("%:p")
  for _, sr in ipairs(source_roots()) do
    if file:sub(1, #sr + 1) == sr .. SEP then
      return sr
    end
  end
  return nil
end

-- source roots whose directory already contains `pkg` (completion offers
-- packages from every module, so a picked one may live in another subproject)
function M.roots_with_package(pkg)
  local rel = (pkg or ""):gsub("%.", SEP)
  local out = {}
  if rel == "" then
    return out
  end
  for _, sr in ipairs(source_roots()) do
    if vim.fn.isdirectory(sr .. SEP .. rel) == 1 then
      out[#out + 1] = sr
    end
  end
  return out
end

-- short module label for a source root: <module>[/<set>] (set omitted for main)
local function module_label(sr)
  local moddir = sr:gsub("[/\\]src[/\\][^/\\]+[/\\]java$", "")
  local set = sr:match("[/\\]src[/\\]([^/\\]+)[/\\]java$")
  local name = vim.fn.fnamemodify(moddir, ":t")
  return (set and set ~= "main") and (name .. "/" .. set) or name
end

-- when the [..] slot names a subproject, resolve straight into its source
-- root (no backtracking). returns data, nil (not a module) or false (module
-- named but the requested source set is missing -> abort)
function M.module_data(parsed)
  if not parsed.subdir then
    return nil
  end
  local mod, set = parsed.subdir:match("^([^/]+)/?(.*)$")
  local m = M.modules()[mod]
  if not m then
    return nil -- a plain source-set like [test], handled by build_path_data
  end
  if set == "" then
    set = "main"
  end
  local base = m.sets[set]
  if not base then
    vim.notify("jc: module '" .. mod .. "' has no '" .. set .. "' source set", vim.log.levels.ERROR)
    return false
  end
  return direct_data(parsed, base)
end

-- keys an autopairs plugin would auto-close inside the DSL prompt
local PAIR_KEYS = { "[", "(", "{", "<", '"', "'", "`" }

-- remove and return any cmdline-mode mappings on the pairing keys
local function suppress_cmdline_pairs()
  local saved = {}
  for _, key in ipairs(PAIR_KEYS) do
    local map = vim.fn.maparg(key, "c", false, true)
    if type(map) == "table" and not vim.tbl_isempty(map) then
      saved[#saved + 1] = map
      pcall(vim.keymap.del, "c", key)
    end
  end
  return saved
end

local function restore_cmdline_pairs(saved)
  for _, map in ipairs(saved) do
    pcall(vim.fn.mapset, "c", false, map)
  end
end

-- validate the class name and materialize the file
local function finalize(data)
  if not M.is_class_name(data.class) then
    vim.notify("jc: no class name given (looks like a package) — request ignored", vim.log.levels.WARN)
    return
  end
  create_class(data)
end

-- resolve a parsed DSL to class data and create the file (shared by the
-- one-line prompt and the wizard)
local function resolve_and_create(parsed)
  local data = M.module_data(parsed)
  if data == false then
    return -- module named but its source set is missing
  end

  -- absolute path "/pkg.Class" -> the package literally, no backtracking. The
  -- package may exist in another subproject (completion spans all modules); if
  -- so, ask which module to create it in. Otherwise the current source root.
  local src_root = current_source_root()
  if data == nil and parsed.path_str:sub(1, 1) == "/" and not parsed.subdir and src_root then
    local parts = vim.split(parsed.path_str:gsub("^/", ""), ".", { plain = true })
    local pkg = table.concat(slice(parts, 0, -2), ".")
    local others = vim.tbl_filter(function(sr)
      return sr ~= src_root
    end, M.roots_with_package(pkg))
    if #others == 0 then
      return finalize(direct_data(parsed, src_root))
    end
    -- prompt: current first, then each module that has the package
    local choices = { { label = module_label(src_root) .. " (current)", root = src_root } }
    for _, sr in ipairs(others) do
      choices[#choices + 1] = { label = module_label(sr), root = sr }
    end
    vim.ui.select(choices, {
      prompt = "Package exists elsewhere — create in:",
      format_item = function(c)
        return c.label
      end,
    }, function(choice)
      if choice then
        finalize(direct_data(parsed, choice.root))
      end
    end)
    return
  end

  if data == nil then
    -- relative path: resolve against the current file's package
    local current_package = vim.split(require("jc.treesitter").get_package() or "", ".", { plain = true })
    local current_path = vim.tbl_filter(function(v)
      return v ~= ""
    end, vim.split(vim.fn.expand("%:p:h"), SEP, { plain = true }))
    if vim.fn.has("win32") == 1 and current_path[1] and current_path[1]:sub(-1) == ":" then
      table.remove(current_path, 1)
    end
    local path = vim.split(parsed.path_str, ".", { plain = true })
    data = decorate(M.build_path_data(path, parsed.subdir, reversed(current_path), current_package), parsed)
    data.current_path = SEP .. table.concat(current_path, SEP) .. SEP
  end

  finalize(data)
end

-- the one-line DSL prompt with cmdline completion
function M.generate_class_oneline()
  -- any autopairs plugin that maps in the cmdline would auto-insert a closing
  -- "]"/")" when typing "["/"(", breaking the DSL. Plugin-agnostically strip
  -- the cmdline mappings on the pairing keys for the prompt, then restore.
  local saved_pairs = suppress_cmdline_pairs()

  -- use vim.fn.input directly (not vim.ui.input): the prompt needs cmdline
  -- completion, and custom-replacing vim.ui.input implementations (dressing,
  -- snacks, ...) don't reliably honour the `completion` option
  local ok, userinput = pcall(vim.fn.input, {
    prompt = "enter new class name: ",
    completion = "customlist,v:lua.require'jc.class_generator'.complete",
  })

  restore_cmdline_pairs(saved_pairs)
  if not ok or userinput == "" then
    return
  end
  local parsed = M.parse_input(userinput)
  if not parsed then
    vim.notify("jc: could not parse input line", vim.log.levels.ERROR)
    return
  end
  resolve_and_create(parsed)
end

-- ---- wizard prompt: step-by-step vim.ui, each step a short clean list ----

-- subpackages of `roots` as dotted names (for the package picker)
local function packages_in(roots)
  local seen, names = {}, {}
  for _, sr in ipairs(roots or {}) do
    for _, path in ipairs(vim.fn.glob(sr .. SEP .. "**", true, true)) do
      if vim.fn.isdirectory(path) == 1 then
        local rel = path:sub(#sr + 2):gsub(SEP, ".")
        if rel ~= "" and not seen[rel] then
          seen[rel] = true
          names[#names + 1] = rel
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- are <> () [] balanced (catches half-typed generics like "HashMap<String")
local function brackets_balanced(s)
  local close = { ["<"] = ">", ["("] = ")", ["["] = "]" }
  local stack = {}
  for ch in s:gmatch(".") do
    if close[ch] then
      stack[#stack + 1] = close[ch]
    elseif ch == ">" or ch == ")" or ch == "]" then
      if stack[#stack] ~= ch then
        return false
      end
      stack[#stack] = nil
    end
  end
  return #stack == 0
end

-- validators return an error string (re-prompt) or nil (accept). They run
-- only on a non-empty value; an empty value means the step was skipped.
local VALIDATE = {
  class = function(v)
    return not M.is_class_name(v) and "invalid class name: " .. v or nil
  end,
  type = function(v)
    if not brackets_balanced(v) then
      return "unbalanced <>/()/[] in: " .. v
    end
    -- a supertype may not be a wildcard, and a bare "<>" can't be a raw type
    if v:find("<%s*>") then
      return "supertype can't have an empty/wildcard generic: " .. v
    end
    return nil
  end,
  fields = function(v)
    if not brackets_balanced(v) then
      return "unbalanced <>/()/[] in fields: " .. v
    end
    if #M.parse_fields("(" .. v .. ")") == 0 then
      return "couldn't parse fields (expected: type name, ...): " .. v
    end
    return nil
  end,
  flags = function(v)
    for w in v:gmatch("%w+") do
      if not vim.tbl_contains(METHOD_FLAGS, w) and not LOMBOK[w] then
        return "unknown flag '" .. w .. "' (codegen: " .. table.concat(METHOD_FLAGS, " ") .. "; or lombok*)"
      end
    end
    return nil
  end,
}

-- run validate on a value; on error notify and return true (re-prompt)
local function rejected(value, validate)
  if value and validate then
    local err = validate(value)
    if err then
      vim.notify("jc: " .. err, vim.log.levels.WARN)
      return true
    end
  end
  return false
end

-- prompt for a value, "" -> nil (skipped); re-prompts with the entered text
-- when `validate` rejects it
local function ui_input(prompt, default, cb, validate)
  vim.ui.input({ prompt = prompt, default = default or "" }, function(value)
    value = value and value ~= "" and value or nil
    if rejected(value, validate) then
      return ui_input(prompt, value, cb, validate)
    end
    cb(value)
  end)
end

-- complete the trailing type identifier of the line: works for the 2nd+
-- interface of an implements list (boundary ",") and inside generics ("<")
local function complete_type_segment(line, pos, kinds)
  line = pos and line:sub(1, pos) or line
  local query, prefix = trailing_type_query(line)
  local result = {}
  for _, name in ipairs(type_completions(query, "", kinds, "")) do
    result[#result + 1] = prefix .. name
  end
  return result
end

-- cmdline completion functions for the wizard's extends/implements steps:
-- class+interface for extends, interface only for implements
function M.complete_extends(_arglead, line, pos)
  return complete_type_segment(line, pos, { [5] = true, [11] = true })
end
function M.complete_implements(_arglead, line, pos)
  return complete_type_segment(line, pos, { [11] = true })
end

-- method-flag completion for the wizard (space-separated): the current word
-- against the known flags, minus the ones already typed
-- jdtls code-gen flags first, then the lombok flags (sorted)
function M.complete_flags(_arglead, line, pos)
  line = pos and line:sub(1, pos) or line
  -- the current word (after the last space or comma) and the chosen ones
  local current = line:match("[%w]*$")
  local chosen = {}
  for w in line:sub(1, #line - #current):gmatch("[%w]+") do
    chosen[w] = true
  end
  local prefix = line:sub(1, #line - #current)
  local result = {}
  for _, flag in ipairs(all_flags()) do
    if not chosen[flag] and flag:sub(1, #current) == current then
      result[#result + 1] = prefix .. flag
    end
  end
  return result
end

-- field-list completion for the wizard (bare "type a, type b", no parens):
-- complete the type token of the current field
function M.complete_fields(_arglead, line, pos)
  line = pos and line:sub(1, pos) or line
  local frag = line:match("[^,]*$"):gsub("^%s+", "")
  local names, current = field_type_completions(frag)
  local prefix = line:sub(1, #line - #current)
  local result = {}
  for _, name in ipairs(names) do
    result[#result + 1] = prefix .. name
  end
  return result
end

-- blocking prompt with jdtls type completion (vim.fn.input honours the
-- completion option, unlike custom vim.ui.input replacements); "" -> nil;
-- re-prompts with the entered text when `validate` rejects it
local function type_input(prompt, complete_fn, cb, validate, default)
  local saved = suppress_cmdline_pairs()
  local ok, value = pcall(vim.fn.input, {
    prompt = prompt,
    default = default or "",
    completion = "customlist,v:lua.require'jc.class_generator'." .. complete_fn,
  })
  restore_cmdline_pairs(saved)
  value = ok and value ~= "" and value or nil
  if rejected(value, validate) then
    return type_input(prompt, complete_fn, cb, validate, value)
  end
  cb(value)
end

function M.generate_class_wizard()
  local modules = M.modules()
  local module_names = vim.tbl_keys(modules)
  table.sort(module_names)

  -- 1. template
  vim.ui.select(require("jc.templates").names(), { prompt = "Template:" }, function(template)
    if not template then
      return
    end
    -- 2. target module (only meaningful in multi-module projects)
    local module_choices = { "(current module)" }
    vim.list_extend(module_choices, module_names)
    vim.ui.select(module_choices, { prompt = "Module:" }, function(module_choice)
      if not module_choice then
        return
      end
      local module = module_choice ~= "(current module)" and module_choice or nil
      local roots = module and vim.tbl_values(modules[module].sets) or current_module_roots()
      -- 3. package (existing ones, or a fresh one typed in)
      local pkg_choices = { "(new package…)" }
      vim.list_extend(pkg_choices, packages_in(roots))
      vim.ui.select(pkg_choices, { prompt = "Package:" }, function(pkg_choice)
        if not pkg_choice then
          return
        end
        local function with_package(package)
          -- 4. class name (must be a valid Java class name)
          ui_input("Class name: ", nil, function(name)
            if not name then
              return
            end
            -- 5/6. extends / implements (jdtls type completion), 7/8 fields/flags;
            -- each step validates and re-prompts the same value on error
            type_input("extends (optional): ", "complete_extends", function(extends)
              type_input("implements (optional): ", "complete_implements", function(implements)
                type_input("fields, e.g. String a, int b (optional): ", "complete_fields", function(fields)
                  type_input("flags, e.g. constructor toString equals (optional): ", "complete_flags", function(flags)
                    local parsed = {
                      template = template ~= "class" and template or nil,
                      subdir = module,
                      path_str = "/" .. (package and (package .. ".") or "") .. name,
                      extends = extends,
                      implements = implements,
                      fields_str = fields and ("(" .. fields .. ")") or nil,
                      -- flags entered space- or comma-separated -> ":a:b:c"
                      flags = flags and (":" .. vim.trim(flags):gsub("[%s,]+", ":")) or nil,
                    }
                    -- show the assembled DSL for a final edit (with completion)
                    -- before generating; empty/cancel aborts
                    local saved = suppress_cmdline_pairs()
                    local ok, edited = pcall(vim.fn.input, {
                      prompt = "confirm: ",
                      default = M.build_dsl(parsed),
                      completion = "customlist,v:lua.require'jc.class_generator'.complete",
                    })
                    restore_cmdline_pairs(saved)
                    if not ok or edited == "" then
                      return
                    end
                    local final = M.parse_input(edited)
                    if not final then
                      vim.notify("jc: could not parse input line", vim.log.levels.ERROR)
                      return
                    end
                    resolve_and_create(final)
                  end, VALIDATE.flags)
                end, VALIDATE.fields)
              end, VALIDATE.type)
            end, VALIDATE.type)
          end, VALIDATE.class)
        end
        if pkg_choice == "(new package…)" then
          ui_input("Package: ", nil, with_package)
        else
          with_package(pkg_choice)
        end
      end)
    end)
  end)
end

function M.generate_class()
  local ok, jc = pcall(require, "jc")
  local mode = (ok and jc.config and jc.config.class_prompt) or vim.g.jc_class_prompt or "oneline"
  if mode == "wizard" then
    M.generate_class_wizard()
  else
    M.generate_class_oneline()
  end
end

-- Package picker entries built from every source root: each existing package,
-- labelled with its module/source-set when the layout is multi-module or the
-- set isn't main. Returns a list of { display, pkg, subdir }.
local function package_choices()
  local multi = vim.tbl_count(M.modules()) > 1
  local out, seen = {}, {}
  for _, sr in ipairs(source_roots()) do
    local label = module_label(sr) -- "core" | "core/test" | <root-name>
    local set = label:match("/(.+)$")
    local subdir
    if multi then
      subdir = label
    elseif set then
      subdir = set
    end
    for _, pkg in ipairs(packages_in({ sr })) do
      local key = (subdir or "") .. "\0" .. pkg
      if not seen[key] then
        seen[key] = true
        local prefix = (multi and (label .. ": ")) or (set and (set .. ": ")) or ""
        out[#out + 1] = { display = prefix .. pkg, pkg = pkg, subdir = subdir }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.display < b.display
  end)
  return out
end

-- Create a class referenced by the code but missing from the project: with the
-- cursor on the type name, pick a package (and module, multi-module), then land
-- in the DSL prompt pre-filled with `[module]:/pkg.Name` for any final edits.
function M.generate_class_from_cursor()
  local name = require("jc.treesitter").type_at_cursor()
  if not name then
    vim.notify("jc: put the cursor on a class name (a capitalized identifier)", vim.log.levels.WARN)
    return
  end

  local function open_dsl(subdir, pkg)
    local path = "/" .. (pkg ~= "" and (pkg .. ".") or "") .. name
    local saved = suppress_cmdline_pairs()
    local ok, edited = pcall(vim.fn.input, {
      prompt = "create class: ",
      default = M.build_dsl({ subdir = subdir, path_str = path }),
      completion = "customlist,v:lua.require'jc.class_generator'.complete",
    })
    restore_cmdline_pairs(saved)
    if not ok or edited == "" then
      return
    end
    local final = M.parse_input(edited)
    if not final then
      vim.notify("jc: could not parse input line", vim.log.levels.ERROR)
      return
    end
    resolve_and_create(final)
  end

  local function pick_new_package()
    local current = require("jc.treesitter").get_package()
    vim.ui.input({ prompt = "Package: ", default = current or "" }, function(pkg)
      if not pkg then
        return
      end
      pkg = vim.trim(pkg)
      local names = vim.tbl_keys(M.modules())
      if #names > 1 then
        table.sort(names)
        vim.ui.select(names, { prompt = "Module:" }, function(mod)
          if mod then
            open_dsl(mod, pkg)
          end
        end)
      else
        open_dsl(nil, pkg)
      end
    end)
  end

  local choices, meta = {}, {}
  local current = require("jc.treesitter").get_package()
  if current and current ~= "" then
    local display = "(current) " .. current
    choices[#choices + 1] = display
    meta[display] = { subdir = nil, pkg = current }
  end
  for _, c in ipairs(package_choices()) do
    choices[#choices + 1] = c.display
    meta[c.display] = c
  end
  local NEW = "(new package…)"
  choices[#choices + 1] = NEW

  vim.ui.select(choices, { prompt = "Package for " .. name .. ":" }, function(choice)
    if not choice then
      return
    end
    if choice == NEW then
      pick_new_package()
    else
      open_dsl(meta[choice].subdir, meta[choice].pkg)
    end
  end)
end

-- the test/source counterpart of a java file: toggles the "Test" suffix and
-- the src/main<->src/test source set, keeping the package. Pure (no fs).
function M.test_counterpart(file)
  local dir = vim.fn.fnamemodify(file, ":h")
  local class = vim.fn.fnamemodify(file, ":t:r")
  local target_class, from_set, to_set
  if class:match("Test$") then
    target_class, from_set, to_set = (class:gsub("Test$", "")), "test", "main"
  else
    target_class, from_set, to_set = class .. "Test", "main", "test"
  end
  local from = SEP .. "src" .. SEP .. from_set .. SEP .. "java"
  local to = SEP .. "src" .. SEP .. to_set .. SEP .. "java"
  local target_dir = dir:gsub(vim.pesc(from), to)
  return target_dir .. SEP .. target_class .. ".java", target_class
end

-- the java package a source file sits in, derived from its path
-- (.../src/<set>/java/<pkg>/Foo.java -> <pkg>), or "" for the default package
function M.package_of(file)
  local dir = vim.fn.fnamemodify(file, ":h")
  local pkg = dir:match("[/\\]src[/\\][^/\\]+[/\\]java[/\\](.+)$")
  return pkg and (pkg:gsub("[/\\]", ".")) or ""
end

-- jump to the test class of the current production class (or back); creates
-- the file (and dirs) when it doesn't exist, filling it from a template
-- (junit5 for a new test, class for a new source)
function M.goto_test()
  if vim.bo.filetype ~= "java" then
    vim.notify("jc: not a java buffer", vim.log.levels.WARN)
    return
  end
  local target, target_class = M.test_counterpart(vim.fn.expand("%:p"))
  if vim.fn.filereadable(target) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(target))
    return
  end
  local dir = vim.fn.fnamemodify(target, ":h")
  if vim.fn.isdirectory(dir) ~= 1 then
    pcall(vim.fn.mkdir, dir, "p")
  end
  vim.cmd("edit " .. vim.fn.fnameescape(target))
  -- fill the fresh file from a template
  local is_test = target_class:match("Test$") ~= nil
  local rendered = templates.render(is_test and "junit5" or "class", {
    name = target_class,
    package = M.package_of(target),
    fields = {},
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(rendered, "\n"))
  vim.cmd("silent! normal! gg=G")
  vim.cmd("silent! write")
  vim.b.jc_new_java_file = true -- register with jdtls on first write
end

return M
