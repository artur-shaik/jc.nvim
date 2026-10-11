-- Does the editor see this project at the same java level the build produces?
--
-- jdtls imports a gradle project through the Tooling API and writes its own
-- eclipse state (compliance level, `bin` output, a buildship JDK pinned per
-- project). None of that has to agree with the build, and when it does not:
--
--   * the LSP checks the code at the wrong language level, so it accepts API
--     the build will reject (or vice versa);
--   * gradle keeps one daemon per JDK, so the editor's sync and jc's
--     precompile each hold their own ~1GB daemon;
--   * `bin` and `build/classes` end up at different levels, and the test
--     runner has to pick a JVM that copes with the higher one.
--
-- The usual root cause is a build that declares its level somewhere the
-- Tooling API does not look - `compileJava { sourceCompatibility = 11 }`
-- instead of `java { sourceCompatibility = 11 }` - so eclipse falls back to
-- whatever JDK ran the import.
local M = {}

-- ---- parsing (pure) ----

-- an eclipse .prefs file as a key -> value table
function M._parse_prefs(text)
  local out = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([^#=][^=]*)=(.*)$")
    if k then
      out[vim.trim(k)] = vim.trim(v)
    end
  end
  return out
end

-- the java level a gradle build declares, and where it says it. `where`
-- matters: only the java extension and a toolchain reach the Tooling API, so a
-- level set on the compile task alone is invisible to jdtls.
function M._parse_gradle_level(text)
  text = text or ""
  local function level_in(block)
    local v = block and block:match("sourceCompatibility%s*=%s*['\"]?([%d.]+)")
    return v and tonumber(v:match("^1%.(%d+)$") or v:match("^(%d+)")) or nil
  end
  local toolchain = text:match("languageVersion%s*=%s*JavaLanguageVersion%.of%(%s*(%d+)%s*%)")
  if toolchain then
    return { level = tonumber(toolchain), where = "toolchain" }
  end
  -- java { ... } and compileJava { ... }, matched non-greedily to the block's
  -- own closing brace at the same indentation
  local java_block = text:match("\n%s*java%s*{(.-)\n%s*}")
  local task_block = text:match("compileJava%s*{(.-)\n%s*}")
  local in_java = level_in(java_block)
  if in_java then
    return { level = in_java, where = "java extension" }
  end
  local in_task = level_in(task_block)
  if in_task then
    return { level = in_task, where = "compileJava task" }
  end
  local bare = text:match("\n%s*sourceCompatibility%s*=%s*['\"]?([%d.]+)")
  if bare then
    return { level = tonumber(bare:match("^(%d+)")), where = "project property" }
  end
  return nil
end

-- the java level a maven build declares
function M._parse_maven_level(text)
  text = text or ""
  for _, tag in ipairs({ "maven%.compiler%.release", "maven%.compiler%.source", "release", "source" }) do
    local v = text:match("<" .. tag .. ">%s*([%d.]+)%s*</")
    if v then
      local n = tonumber(v:match("^1%.(%d+)$") or v:match("^(%d+)"))
      if n then
        return { level = n, where = "pom property" }
      end
    end
  end
  return nil
end

-- ---- facts ----

local function read(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

-- everything the checks below need, read off disk. `root` is the project root.
function M.scan(root)
  local jdk = require("jc.jdk")
  local facts = { root = root }

  local gradle = read(root .. "/build.gradle") or read(root .. "/build.gradle.kts")
  local pom = not gradle and read(root .. "/pom.xml") or nil
  facts.tool = gradle and "gradle" or (pom and "maven") or nil
  facts.declared = gradle and M._parse_gradle_level(gradle) or (pom and M._parse_maven_level(pom)) or nil

  -- eclipse keeps its state per eclipse project, so on a multi-module build the
  -- levels live in the modules rather than at the root
  local core_files = { root .. "/.settings/org.eclipse.jdt.core.prefs" }
  vim.list_extend(core_files, vim.fn.glob(root .. "/*/.settings/org.eclipse.jdt.core.prefs", true, true))
  for _, file in ipairs(core_files) do
    local text = read(file)
    if text then
      local prefs = M._parse_prefs(text)
      local raw = prefs["org.eclipse.jdt.core.compiler.compliance"] or ""
      local level = tonumber(raw:match("^1%.(%d+)$") or raw:match("^(%d+)"))
      if level and (not facts.compliance or level > facts.compliance) then
        facts.compliance = level
      end
      facts.method_parameters = facts.method_parameters
        or prefs["org.eclipse.jdt.core.compiler.codegen.methodParameters"]
    end
  end
  -- unset per project: the global file java.settings.url names decides, and
  -- failing that the JDT default, which does not write parameter names
  if not facts.method_parameters then
    local client = require("jc.lsp").get_jdtls_client()
    local url = client and vim.tbl_get(client.config or {}, "settings", "java", "settings", "url")
    local global = type(url) == "string" and read((url:gsub("^file://", ""))) or nil
    facts.method_parameters = global
        and M._parse_prefs(global)["org.eclipse.jdt.core.compiler.codegen.methodParameters"]
      or "do not generate"
  end

  local buildship = read(root .. "/.settings/org.eclipse.buildship.core.prefs")
  if buildship then
    local prefs = M._parse_prefs(buildship)
    facts.buildship_home = prefs["java.home"] ~= "" and prefs["java.home"] or nil
    facts.buildship_overrides = prefs["override.workspace.settings"] == "true"
  end

  -- a multi-module build keeps its output per module, so probe both layouts
  local build_dirs, bin_dirs = {}, {}
  for _, dir in ipairs(vim.fn.glob(root .. "/*/build/classes/java/main", true, true)) do
    build_dirs[#build_dirs + 1] = dir
  end
  for _, dir in ipairs(vim.fn.glob(root .. "/*/bin/main", true, true)) do
    bin_dirs[#bin_dirs + 1] = dir
  end
  build_dirs[#build_dirs + 1] = root .. "/build/classes/java/main"
  build_dirs[#build_dirs + 1] = root .. "/target/classes"
  bin_dirs[#bin_dirs + 1] = root .. "/bin/main"
  facts.build_level = jdk.level_of(build_dirs)
  facts.bin_level = jdk.level_of(bin_dirs)

  return facts
end

-- ---- checks (pure over facts) ----

local function jdk_major(path)
  if not path then
    return nil
  end
  -- .../java/11.0.12-open, .../openjdk/17/jdk-17.0.12, .../java/21.0.7-tem
  local tail = path:match("([^/\\]+)$") or ""
  return tonumber(tail:match("^(%d+)") or tail:match("jdk%-(%d+)"))
end
M._jdk_major = jdk_major

-- the level the build really produces, else the one it declares
local function target_level(facts)
  return facts.build_level or (facts.declared and facts.declared.level)
end
M._target_level = target_level

-- findings, worst first. Each is { id, severity, message, hint, fix }; `fix`
-- names a repair M.apply can make, or is nil when only the user can.
function M._findings(facts)
  local out = {}
  local target = target_level(facts)

  local buildship = jdk_major(facts.buildship_home)
  if facts.tool == "gradle" and buildship and target and buildship ~= target then
    out[#out + 1] = {
      id = "buildship_jdk",
      severity = "warn",
      message = ("jdtls syncs gradle on JDK %d, the build targets java %d"):format(buildship, target),
      hint = "gradle keeps a daemon per JDK, so the editor and the test runner each hold their own",
      fix = "buildship_jdk",
    }
  end

  if facts.compliance and target and facts.compliance ~= target then
    local hint = "the LSP checks the code at java " .. facts.compliance .. ", the build at " .. target
    if facts.declared and facts.declared.where == "compileJava task" then
      hint = "the level is set on the compile task, which the gradle Tooling API does not report; "
        .. "move it to `java { sourceCompatibility = ... }` so eclipse sees it"
    end
    out[#out + 1] = {
      id = "compliance",
      severity = "warn",
      message = ("eclipse compliance is java %d, the build targets java %d"):format(facts.compliance, target),
      hint = hint,
    }
  end

  if facts.bin_level and facts.build_level and facts.bin_level ~= facts.build_level then
    out[#out + 1] = {
      id = "bytecode_split",
      severity = "info",
      message = ("jdtls writes java %d bytecode to bin, the build writes java %d"):format(
        facts.bin_level,
        facts.build_level
      ),
      hint = "the test runner has to launch on the higher of the two unless precompile is on",
    }
  end

  if facts.method_parameters and facts.method_parameters ~= "generate" then
    out[#out + 1] = {
      id = "method_parameters",
      severity = "warn",
      message = "jdtls compiles without method parameter names",
      hint = "spring-data repositories with named query parameters fail on jdtls' bin output; set "
        .. "org.eclipse.jdt.core.compiler.codegen.methodParameters=generate (or the file java.settings.url names)",
    }
  end

  return out
end

-- the current project root, or nil outside one
function M.root(path)
  path = path or vim.fn.expand("%:p")
  if path == "" then
    path = vim.fn.getcwd()
  end
  return vim.fs.root(path, { "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "pom.xml" })
end

function M.diagnose(root)
  root = root or M.root()
  if not root then
    return nil, nil
  end
  local facts = M.scan(root)
  return M._findings(facts), facts
end

-- ---- repair ----

-- rewrite one key in an eclipse .prefs file, keeping the rest as-is
function M._set_pref(path, key, value)
  local text = read(path)
  if not text then
    return false, path .. " not found"
  end
  local pattern = "\n" .. key:gsub("%p", "%%%0") .. "=[^\n]*"
  local replacement = "\n" .. key .. "=" .. value
  local new, n = ("\n" .. text):gsub(pattern, replacement, 1)
  if n == 0 then
    new = "\n" .. text .. key .. "=" .. value .. "\n"
  end
  local fd = io.open(path, "w")
  if not fd then
    return false, "cannot write " .. path
  end
  new = new:gsub("^\n", "")
  if not new:match("\n$") then
    new = new .. "\n"
  end
  fd:write(new)
  fd:close()
  return true
end

-- apply the repair a finding names. Only touches files eclipse generates;
-- build.gradle and pom.xml are never rewritten.
function M.apply(finding, facts)
  if finding.fix ~= "buildship_jdk" then
    return false, "nothing to apply"
  end
  local want = target_level(facts)
  local home = want and require("jc.jdk").home_for_version(want)
  if not home then
    return false, ("no configured runtime for java %s - add one to java.configuration.runtimes"):format(tostring(want))
  end
  local ok, err = M._set_pref(facts.root .. "/.settings/org.eclipse.buildship.core.prefs", "java.home", home)
  if not ok then
    return false, err
  end
  return true, home
end

-- :JCutilFixJdk - report the findings and offer to apply the ones jc can.
-- Only eclipse's own generated files are touched, and only after a yes.
function M.fix()
  local findings, facts = M.diagnose()
  if not facts then
    vim.notify("jc: not inside a gradle/maven project", vim.log.levels.WARN)
    return
  end
  if #findings == 0 then
    vim.notify("jc: project java levels agree, nothing to fix", vim.log.levels.INFO)
    return
  end
  local fixable = vim.tbl_filter(function(f)
    return f.fix ~= nil
  end, findings)
  for _, f in ipairs(findings) do
    if not f.fix then
      vim.notify("jc: " .. f.message .. "\n     " .. f.hint, vim.log.levels.WARN)
    end
  end
  if #fixable == 0 then
    vim.notify("jc: nothing jc can change by itself — see the hints above", vim.log.levels.INFO)
    return
  end
  local target = target_level(facts)
  local home = target and require("jc.jdk").home_for_version(target)
  vim.ui.select({ "yes", "no" }, {
    prompt = fixable[1].message .. " — point jdtls at java " .. tostring(target) .. "?",
    format_item = function(item)
      return item == "yes" and ("yes, use " .. tostring(home)) or "no, leave it"
    end,
  }, function(choice)
    if choice ~= "yes" then
      return
    end
    local ok, result = M.apply(fixable[1], facts)
    if not ok then
      vim.notify("jc: " .. tostring(result), vim.log.levels.ERROR)
      return
    end
    vim.notify(
      "jc: buildship java.home set to " .. result .. " — run :JCutilUpdateConfig to re-sync",
      vim.log.levels.INFO
    )
  end)
end

return M
