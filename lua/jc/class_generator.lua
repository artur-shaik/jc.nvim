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

-- parse "(mods type name, ...)" -> array of { mod, type, name }
function M.parse_fields(fieldstr)
  local inner = trim(fieldstr:sub(2, -2)) -- drop surrounding ()
  if inner == "" then
    return {}
  end
  local fields = {}
  for part in vim.gsplit(inner, ",", { plain = true }) do
    local tokens = {}
    for tok in part:gmatch("%S+") do
      tokens[#tokens + 1] = tok
    end
    -- leading modifier words, then type, then name
    local mods = {}
    local i = 1
    while tokens[i] and MODS[tokens[i]] do
      mods[#mods + 1] = tokens[i]
      i = i + 1
    end
    local typ = tokens[i]
    local name = tokens[i + 1]
    if typ and name then
      fields[#fields + 1] = {
        mod = #mods > 0 and table.concat(mods, " ") or "private",
        type = typ,
        name = name,
      }
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

-- full DSL -> resolved class data (or nil)
function M.parse(userinput, currentPath, currentPackage)
  local parsed = M.parse_input(userinput)
  if not parsed then
    return nil
  end
  local path = vim.split(parsed.path_str, ".", { plain = true })
  local data = M.build_path_data(path, parsed.subdir, currentPath, currentPackage)
  data.template = parsed.template
  data.extends = parsed.extends
  data.implements = parsed.implements
  if parsed.fields_str then
    local fields = M.parse_fields(parsed.fields_str)
    if #fields > 0 then
      data.fields = fields
    end
  end
  if parsed.flags then
    data.methods = M.parse_methods(parsed.flags)
  end
  return data
end

-- ---- materialization ----

local function template_options(data)
  return {
    name = data.class,
    package = data.package,
    fields = data.fields,
    extends = data.extends,
    implements = data.implements,
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
  chains:add(function()
    require("jc.jdtls").generate_abstractMethods()
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
  chains:execute_next_if_exists()
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

-- LSP SymbolKind: Class=5, Interface=11
local TYPE_KINDS = { extends = { [5] = true, [11] = true }, implements = { [11] = true } }

-- class/interface names from jdtls matching `query`, as "<prefix> <Name>"
local function type_completions(query, prefix, kinds)
  local client = require("jc.lsp").get_jdtls_client()
  if not client then
    return {}
  end
  -- synchronous: completion must return inline; jdtls answers quickly
  local response = client:request_sync("workspace/symbol", { query = query }, 1000)
  if not response or response.err or type(response.result) ~= "table" then
    return {}
  end
  local seen, result = {}, {}
  for _, sym in ipairs(response.result) do
    if kinds[sym.kind] and not seen[sym.name] then
      seen[sym.name] = true
      result[#result + 1] = prefix .. " " .. sym.name
    end
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

-- glob package candidates. Absolute (/) lists packages across all project
-- source roots; relative lists subpackages of the current package (and only
-- when the current file actually sits in one).
local function package_completions(command, completed, is_relative)
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
  local parts = vim.split(vim.fn.expand("%:p:h"), SEP, { plain = true })
  local src = index0(parts, "src")
  if src >= 0 then
    parts = slice(parts, 0, src)
  end
  local pre = SEP .. table.concat(parts, SEP) .. SEP
  local result = {}
  for _, path in ipairs(vim.fn.glob(pre .. command .. "*" .. SEP, false, true)) do
    result[#result + 1] = completed .. "[" .. path:sub(#pre + 1, -2) .. "]"
  end
  return result
end

local function method_completions(command, completed)
  local result = {}
  for _, kw in ipairs(METHOD_FLAGS) do
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

-- customlist completion entry point (exposed via v:lua for vim.fn.input)
-- follows the DSL shape: template:[subdir]:/package.Class extends/implements
-- (fields):flag:flag
function M.complete(_arglead, line)
  local tokens = vim.split(line, ":", { plain = true })
  local command = tokens[#tokens]
  local completed = completed_prefix(tokens)
  local result = {}
  local first = command:sub(1, 1)
  local path_given, subdir_given = prior_state(tokens)

  if first == "/" then
    -- absolute class path
    vim.list_extend(result, package_completions(command:sub(2), completed, false))
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
    vim.list_extend(result, package_completions(command, completed, true))
  end
  return result
end

function M.generate_class()
  -- use vim.fn.input directly (not vim.ui.input): the prompt needs cmdline
  -- completion, and custom-replacing vim.ui.input implementations (dressing,
  -- snacks, ...) don't reliably honour the `completion` option
  local ok, userinput = pcall(vim.fn.input, {
    prompt = "enter new class name: ",
    completion = "customlist,v:lua.require'jc.class_generator'.complete",
  })
  if not ok or userinput == "" then
    return
  end
  local current_package = vim.split(require("jc.treesitter").get_package() or "", ".", { plain = true })
  local current_path = vim.tbl_filter(function(v)
    return v ~= ""
  end, vim.split(vim.fn.expand("%:p:h"), SEP, { plain = true }))
  if vim.fn.has("win32") == 1 and current_path[1] and current_path[1]:sub(-1) == ":" then
    table.remove(current_path, 1)
  end

  local data = M.parse(userinput, reversed(current_path), current_package)
  if not data then
    vim.notify("jc: could not parse input line", vim.log.levels.ERROR)
    return
  end
  if not M.is_class_name(data.class) then
    vim.notify("jc: no class name given (looks like a package) — request ignored", vim.log.levels.WARN)
    return
  end
  data.current_path = SEP .. table.concat(current_path, SEP) .. SEP
  create_class(data)
end

return M
