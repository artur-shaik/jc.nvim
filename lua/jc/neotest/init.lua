-- neotest adapter for jc.nvim. Optional: this module is only loaded when the
-- user wires it into their neotest setup via require("jc").neotest_adapter().
-- It resolves the test classpath from jdtls (no gradle/maven daemon) and runs
-- the JUnit Platform Console Standalone launcher, then maps the XML report
-- back onto neotest positions.
local lib = require("neotest.lib")
local nio = require("nio")

local report = require("jc.neotest.report")
local launcher = require("jc.neotest.launcher")

local adapter = { name = "jc" }

local QUERY = [[
  ;; test classes (and nested classes) are namespaces
  (class_declaration
    name: (identifier) @namespace.name
  ) @namespace.definition

  ;; @Test / @ParameterizedTest / ... methods are tests
  (method_declaration
    (modifiers
      [
        (marker_annotation name: (identifier) @_annot)
        (annotation name: (identifier) @_annot)
      ]
      (#any-of? @_annot "Test" "ParameterizedTest" "RepeatedTest" "TestFactory" "TestTemplate"))
    name: (identifier) @test.name
  ) @test.definition
]]

-- package declared in a java source file ("" if none / default package)
local function read_package(path)
  local ok, fd = pcall(io.open, path)
  if not ok or not fd then
    return ""
  end
  local pkg = ""
  for line in fd:lines() do
    -- package segments may contain underscores; Lua's %w excludes "_"
    local p = line:match("^%s*package%s+([%w_%.]+)%s*;")
    if p then
      pkg = p
      break
    end
  end
  fd:close()
  return pkg
end

-- fully qualified binary name of the class enclosing a tree node: package +
-- the namespace chain joined with "$" (nested classes).
local function fqn_of(node, package)
  local names = {}
  local n = node
  while n do
    local d = n:data()
    if d.type == "namespace" then
      table.insert(names, 1, d.name)
    end
    n = n:parent()
  end
  local cls = table.concat(names, "$")
  if package ~= "" then
    return package .. "." .. cls
  end
  return cls
end

local function method_name(name)
  return (name:gsub("%(.*$", ""))
end

-- A run is broken into several build_spec/results calls (one per file/class).
-- Accumulate the leaf-test tallies and emit a single toast once the calls go
-- quiet, so the user gets one "done" notification per logical run. Opt out via
-- setup{ test = { notify = false } }.
local pending = { passed = 0, failed = 0, skipped = 0 }
local notify_gen = 0
local running = false

local function notify_enabled()
  local ok, jc = pcall(require, "jc")
  if not ok then
    return true
  end
  local t = jc.config and jc.config.test
  return not (t and t.notify == false)
end

-- one "running" toast per logical run: the first build_spec of a run sets the
-- flag, the completion toast clears it.
local function notify_start()
  if not notify_enabled() then
    return
  end
  vim.schedule(function()
    if running then
      return
    end
    running = true
    vim.notify("jc tests: running...", vim.log.levels.INFO)
  end)
end

local function schedule_notify(tally)
  if not notify_enabled() then
    return
  end
  vim.schedule(function()
    pending.passed = pending.passed + tally.passed
    pending.failed = pending.failed + tally.failed
    pending.skipped = pending.skipped + tally.skipped
    notify_gen = notify_gen + 1
    local mine = notify_gen
    vim.defer_fn(function()
      if mine ~= notify_gen then
        return -- a later results() batch superseded this one
      end
      local p = pending
      pending = { passed = 0, failed = 0, skipped = 0 }
      running = false
      if p.passed + p.failed + p.skipped == 0 then
        return
      end
      vim.notify(
        string.format("jc tests: %d passed, %d failed, %d skipped", p.passed, p.failed, p.skipped),
        p.failed > 0 and vim.log.levels.ERROR or vim.log.levels.INFO
      )
    end, 400)
  end)
end

-- Root at the OUTERMOST project marker so a multi-module build is one neotest
-- tree, not one per submodule (each submodule's own build.gradle would
-- otherwise split the same project into several roots in the summary).
function adapter.root(dir)
  local settings = vim.fs.find(
    { "settings.gradle", "settings.gradle.kts" },
    { path = dir, upward = true, type = "file", limit = math.huge }
  )
  if #settings > 0 then
    return vim.fs.dirname(settings[#settings])
  end
  return vim.fs.root(dir, { "build.gradle", "build.gradle.kts", "pom.xml", ".git" }) or dir
end

function adapter.filter_dir(name)
  return name ~= "build" and name ~= "target" and name ~= ".git" and name ~= "bin"
end

function adapter.is_test_file(file_path)
  if not vim.endswith(file_path, ".java") then
    return false
  end
  local base = file_path:match("([^/\\]+)%.java$") or ""
  if base:match("Test$") or base:match("Tests$") or base:match("^Test") or base:match("IT$") then
    return true
  end
  return file_path:find("[/\\]src[/\\]test[/\\]") ~= nil
end

function adapter.discover_positions(file_path)
  return lib.treesitter.parse_positions(file_path, QUERY, { nested_tests = true })
end

-- true when no enclosing namespace exists, i.e. a top-level test class; used
-- to skip @Nested classes (covered by selecting their outer class).
local function is_top_namespace(node)
  local p = node:parent()
  while p do
    if p:data().type == "namespace" then
      return false
    end
    p = p:parent()
  end
  return true
end

-- group console-launcher selectors by the source file they belong to. Each
-- file gets its own launch because the classpath is per-module: a single
-- launch with classes from several modules would miss the test output of all
-- but one module (cross-module ClassNotFoundException).
local function selectors_by_file(tree)
  local pos = tree:data()
  local by_file = {}
  if pos.type == "test" then
    by_file[pos.path] = { "--select-method=" .. fqn_of(tree, read_package(pos.path)) .. "#" .. method_name(pos.name) }
    return by_file
  end
  for _, node in tree:iter_nodes() do
    local d = node:data()
    if d.type == "namespace" and is_top_namespace(node) then
      by_file[d.path] = by_file[d.path] or {}
      table.insert(by_file[d.path], "--select-class=" .. fqn_of(node, read_package(d.path)))
    end
  end
  return by_file
end

-- jdtls classpath resolution is async; bridge to sync (neotest runs build_spec
-- off the main loop, so vim.wait pumps the event loop safely).
local function classpath_scope(uri, scope)
  local cp, failed
  require("jc.tools").classpaths_for(
    uri,
    function(c)
      cp = c
    end,
    scope,
    function()
      failed = true
    end
  )
  if not vim.wait(20000, function()
    return cp ~= nil or failed
  end, 50) then
    return nil
  end
  return cp
end

-- gradle/maven output dirs paralleling a jdtls eclipse output dir
-- (.../<module>/bin/<set>). They are added AFTER the jdtls "bin" dir so the
-- fresh in-editor compile wins (edits take effect on save) and the CLI build
-- only fills gaps: jdtls' incremental "bin" can be incomplete (missing classes
-- -> ByteBuddy/Mockito NoClassDefFoundError), a CLI build has the full set
-- under build/ or target/. The resource dirs also put application.yml etc. on
-- the classpath for Spring.
local function build_outputs(bin_dir)
  local module, set = bin_dir:match("^(.*)[/\\]bin[/\\]([^/\\]+)$")
  if not module then
    return {}
  end
  local gset = set == "default" and "main" or set
  local out = {
    module .. "/build/classes/java/" .. gset,
    module .. "/build/resources/" .. gset,
    module .. (gset == "test" and "/target/test-classes" or "/target/classes"),
  }
  return out
end

-- union the test and runtime classpaths and prepend CLI build outputs for each
-- project module. jdtls' "test" scope omits runtimeOnly deps (gradle's
-- testRuntimeClasspath has them) and its "bin" output can lag a CLI build, so
-- both gaps show up as "green from the CLI but ClassNotFound here". Order is
-- preserved (build outputs first), duplicates dropped.
-- drop_bin: when the CLI build tool compiled the project (precompile), the
-- gradle/maven build/-target/ output is the complete, correct-bytecode source,
-- so the project's jdtls bin dirs are dropped entirely (jdtls may fail to
-- compile some classes, and its bin is a newer bytecode level). Otherwise bin
-- goes first (fresh from java/buildWorkspace) with build/ as a fallback.
local function resolve_classpath(file, drop_bin)
  local uri = vim.uri_from_fname(file)
  local test = classpath_scope(uri, "test")
  if not test then
    return nil
  end
  local runtime = classpath_scope(uri, "runtime") or {}

  local seen, out = {}, {}
  local function add(entry)
    if entry ~= "" and not seen[entry] then
      seen[entry] = true
      out[#out + 1] = entry
    end
  end
  local function add_build_outputs(entry)
    for _, extra in ipairs(build_outputs(entry)) do
      if vim.fn.isdirectory(extra) == 1 then
        add(extra)
      end
    end
  end

  for _, list in ipairs({ test, runtime }) do
    for _, entry in ipairs(list) do
      if entry:match("[/\\]bin[/\\][^/\\]+$") then
        if drop_bin then
          add_build_outputs(entry)
        else
          -- bin first (fresh from java/buildWorkspace), build/ as a fallback
          add(entry)
          add_build_outputs(entry)
        end
      else
        add(entry)
      end
    end
  end
  return out
end

-- gradle/maven module dir for a file (.../<module>/src/<set>/java/...)
local function module_dir(file)
  return file:match("^(.*)[/\\]src[/\\][^/\\]+[/\\]java[/\\]")
end

local function class_major(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local head = fd:read(8)
  fd:close()
  if head and #head >= 8 then
    return head:byte(7) * 256 + head:byte(8) - 44 -- feature version: 52->8, 61->17
  end
  return nil
end

-- the HIGHEST java feature version among a module's compiled classes. The JVM
-- must be >= every bytecode version on the run classpath (Java is backward
-- compatible), and jdtls' bin output is often compiled to a newer level than
-- the gradle build/, so a single dir underestimates — take the max.
function adapter._module_java_version(module, build_only)
  if not module then
    return nil
  end
  -- build_only: after a CLI precompile, bin is dropped from the classpath, so
  -- only the build/ bytecode (the project's real target) matters
  local subs = build_only and { "/build/classes/java/main", "/build/classes/java/test" }
    or { "/build/classes/java/main", "/bin/main", "/build/classes/java/test", "/bin/test" }
  local max
  for _, sub in ipairs(subs) do
    local hits = vim.fs.find(function(n)
      return n:match("%.class$")
    end, { path = module .. sub, type = "file", limit = 1 })
    local v = hits[1] and class_major(hits[1])
    if v and (not max or v > max) then
      max = v
    end
  end
  return max
end

local function runtime_version(name)
  local v = name and name:match("^JavaSE%-(.+)$")
  if not v then
    return nil
  end
  return v == "1.8" and 8 or tonumber(v:match("^(%d+)"))
end

-- a configured jdtls runtime that can run feature version `ver`: the exact
-- match, else the smallest configured runtime >= ver (backward compatible).
function adapter._runtime_for_version(ver)
  local client = require("jc.lsp").get_jdtls_client()
  local runtimes = client and vim.tbl_get(client.config or {}, "settings", "java", "configuration", "runtimes")
  if type(runtimes) ~= "table" then
    return nil
  end
  local best, best_v
  for _, r in ipairs(runtimes) do
    local rv = runtime_version(r.name)
    if rv and type(r.path) == "string" and r.path ~= "" then
      if rv == ver then
        return r.path .. "/bin/java"
      end
      if rv > ver and (not best_v or rv < best_v) then
        best, best_v = r.path .. "/bin/java", rv
      end
    end
  end
  return best
end

-- the JDK to run a module's tests on. resolveJavaExecutable only ever returns
-- jdtls' DEFAULT runtime (not the project's compliance), so an 11-target
-- project would run on a newer default JVM — which breaks old byte-buddy/
-- Mockito. Instead detect the module's bytecode target and pick the matching
-- configured runtime; fall back to resolveJavaExecutable, then "java".
local java_cache = {}
local function resolve_java(file, build_only)
  local module = module_dir(file)
  local key = (build_only and "b:" or "") .. (module or file)
  if java_cache[key] then
    return java_cache[key]
  end

  local ver = adapter._module_java_version(module, build_only)
  local java = ver and adapter._runtime_for_version(ver) or nil

  if not java then
    local project = module and vim.fn.fnamemodify(module, ":t") or ""
    local resolved
    require("jc.lsp").executeCommand({
      command = "vscode.java.resolveJavaExecutable",
      arguments = { "", project },
    }, function(j)
      resolved = (type(j) == "string" and j ~= "") and j or false
    end, function()
      resolved = false
    end)
    vim.wait(10000, function()
      return resolved ~= nil
    end, 50)
    java = resolved or "java"
  end

  java_cache[key] = java
  return java
end

-- force jdtls to compile the whole workspace (incremental) and wait for it, so
-- its bin output is fresh and complete before we read the classpath from it.
-- Both jdtls' bin and the CLI build/ dirs can otherwise be partially compiled.
local function build_workspace()
  local client = require("jc.lsp").get_jdtls_client()
  if not client then
    return
  end
  local done
  local ok = client:request("java/buildWorkspace", false, function()
    done = true
  end)
  if not ok then
    return
  end
  vim.wait(120000, function()
    return done
  end, 100)
end

-- gradle subproject path for a module dir under the build root (":a:b"), or
-- nil for a single-module / root project
local function gradle_path(root, module)
  if not module or module == root then
    return nil
  end
  local rel = module:sub(#root + 2)
  return ":" .. rel:gsub("[/\\]", ":")
end

-- compile the project with its build tool before launching, so the run uses a
-- complete, correct-bytecode build/ output. jdtls can leave classes out of its
-- bin (e.g. spring-data repositories), and a CLI build is the source of truth.
-- Returns ok, output. Enabled via setup{ test = { precompile = true } }.
local function precompile_enabled()
  local ok, jc = pcall(require, "jc")
  local t = ok and jc.config and jc.config.test
  return t and t.precompile == true
end

local function precompile(file)
  local root = adapter.root(file)
  local module = module_dir(file)
  local label = module and vim.fn.fnamemodify(module, ":t") or "project"
  local tool, cmd
  if
    vim.fn.filereadable(root .. "/settings.gradle") == 1
    or vim.fn.filereadable(root .. "/settings.gradle.kts") == 1
    or vim.fn.filereadable(root .. "/build.gradle") == 1
    or vim.fn.filereadable(root .. "/build.gradle.kts") == 1
  then
    tool = "gradle"
    local gw = root .. "/gradlew"
    cmd = vim.fn.executable(gw) == 1 and { gw } or { "gradle" }
    local gp = gradle_path(root, module)
    table.insert(cmd, gp and (gp .. ":testClasses") or "testClasses")
    vim.list_extend(cmd, { "--console=plain" })
  elseif vim.fn.filereadable(root .. "/pom.xml") == 1 then
    tool = "maven"
    local mw = root .. "/mvnw"
    cmd = { vim.fn.executable(mw) == 1 and mw or "mvn", "-B", "test-compile" }
    if module and module ~= root then
      vim.list_extend(cmd, { "-pl", module:sub(#root + 2), "-am" })
    end
  else
    return true, "" -- unknown build system: don't block the run
  end

  -- progress feedback: a start toast, then the latest build line echoed in the
  -- cmdline (updated in place — no notification spam) while it compiles
  vim.schedule(function()
    vim.notify("jc: precompiling " .. label .. " (" .. tool .. ")...", vim.log.levels.INFO)
  end)
  -- handlers receive the output, so vim.system no longer fills res.stdout —
  -- accumulate it ourselves for the failure message
  local latest, chunks = "starting...", {}
  local function on_data(_, data)
    if not data then
      return
    end
    chunks[#chunks + 1] = data
    for line in data:gmatch("[^\r\n]+") do
      line = vim.trim(line)
      if line ~= "" then
        latest = line
      end
    end
  end
  local timer = vim.uv.new_timer()
  if timer then
    timer:start(
      400,
      400,
      vim.schedule_wrap(function()
        vim.api.nvim_echo({ { "jc " .. tool .. " " .. label .. ": " .. latest, "Comment" } }, false, {})
      end)
    )
  end

  -- run async: a future yields the neotest nio task instead of blocking the UI
  -- (vim.system():wait() would freeze the editor for the whole compile)
  local future = nio.control.future()
  vim.system(cmd, { cwd = root, text = true, stdout = on_data, stderr = on_data }, function(r)
    future.set(r)
  end)
  local res = future.wait()

  if timer then
    timer:stop()
    timer:close()
  end
  vim.schedule(function()
    vim.api.nvim_echo({ { "", "" } }, false, {})
  end)
  return res.code == 0, table.concat(chunks)
end

-- precompile result per module, persisted across the (broken-down) build_spec
-- calls of one run so a module is built once and a failure reported once.
-- Cleared at the start of each user-initiated run (jc.test).
local precompile_cache = {}
function adapter.clear_precompile_cache()
  precompile_cache = {}
end

-- exposed for :JCtestDebugClasspath / :JCtestDebugJava so the dumps reflect
-- what the runner actually launches with
adapter.resolve_classpath = resolve_classpath
adapter.resolve_java = resolve_java

function adapter.build_spec(args)
  local by_file = selectors_by_file(args.tree)
  if not next(by_file) then
    return nil
  end

  local jar = launcher.resolve_jar()
  if not jar then
    vim.schedule(function()
      vim.notify(
        "jc: junit-platform-console-standalone jar not found — run :JCtestInstall or set "
          .. "require('jc.neotest.launcher').console_launcher_path",
        vim.log.levels.ERROR
      )
    end)
    return nil
  end

  local pre = precompile_enabled()
  if not pre then
    -- force jdtls to (incrementally) compile the workspace so its bin output is
    -- fresh and complete before we read the classpath from it
    build_workspace()
  end

  -- one spec per file, each with that file's module classpath and project JDK
  local specs = {}
  for file, selectors in pairs(by_file) do
    -- precompile the module with its build tool once per run (cached across the
    -- run's build_spec calls); a failed module isn't retried and reports once
    local ok_compile = true
    if pre then
      local module = module_dir(file) or file
      if precompile_cache[module] == nil then
        local ok, out = precompile(file)
        precompile_cache[module] = { ok = ok }
        if not ok then
          -- build errors are at the tail of the output; show the last lines
          local tail = vim.trim(out or "")
          if #tail > 1500 then
            tail = "..." .. tail:sub(-1500)
          end
          vim.schedule(function()
            vim.notify(
              "jc: build failed for " .. (vim.fn.fnamemodify(module, ":t")) .. ":\n" .. tail,
              vim.log.levels.ERROR
            )
          end)
        end
      end
      ok_compile = precompile_cache[module].ok
    end

    local classpath = ok_compile and resolve_classpath(file, pre)
    if classpath then
      local reports_dir = vim.fn.tempname()
      vim.fn.mkdir(reports_dir, "p")
      specs[#specs + 1] = {
        command = launcher.build_command({
          java = resolve_java(file, pre),
          jar = jar,
          classpath = classpath,
          selectors = selectors,
          reports_dir = reports_dir,
        }),
        cwd = adapter.root(file) or vim.fn.getcwd(),
        context = { reports_dir = reports_dir },
      }
    end
  end

  if #specs == 0 then
    vim.schedule(function()
      vim.notify(
        "jc: jdtls couldn't resolve the test classpath — the project may still be "
          .. "importing (e.g. just after :JCutilWipeWorkspace). Wait for jdtls to "
          .. "finish, then re-run.",
        vim.log.levels.WARN
      )
    end)
    return nil
  end

  notify_start()
  -- a single spec is returned directly; neotest also accepts a list
  return #specs == 1 and specs[1] or specs
end

function adapter.results(spec, result, tree)
  local reports_dir = spec.context and spec.context.reports_dir
  local xml_files = reports_dir and vim.fn.glob(reports_dir .. "/*.xml", false, true) or {}
  local cases = {}
  for _, f in ipairs(xml_files) do
    local fd = io.open(f)
    if fd then
      vim.list_extend(cases, report.parse(fd:read("*a")))
      fd:close()
    end
  end
  local idx = report.index(cases)

  -- No report at all means the launcher never got to running tests (bad
  -- classpath, class not compiled, jvm/launcher error) — that is a runner
  -- failure, not a set of failing tests. Mark every requested test failed
  -- and point at the raw output so the cause is one keystroke away.
  local runner_failed = #cases == 0

  local results = {}
  local tally = { passed = 0, failed = 0, skipped = 0 }
  for _, node in tree:iter_nodes() do
    local d = node:data()
    if d.type == "test" then
      local fqn = fqn_of(node, read_package(d.path))
      local case = idx[report.key(fqn, method_name(d.name))]
      if case then
        local res = { status = case.status, output = result.output }
        if case.status == "failed" then
          res.short = case.message
          local err = { message = case.message or case.trace or "test failed" }
          if case.failure and case.failure.line then
            err.line = case.failure.line - 1
          end
          res.errors = { err }
        end
        results[d.id] = res
        if tally[case.status] ~= nil then
          tally[case.status] = tally[case.status] + 1
        end
      elseif runner_failed then
        results[d.id] = {
          status = "failed",
          short = "test runner produced no report (exit " .. tostring(result.code) .. ") — see :JCtestOutput",
          output = result.output,
        }
        -- count these so the run isn't treated as all-green (no auto-close)
        tally.failed = tally.failed + 1
      end
    end
  end

  -- every spec's tally feeds the single debounced toast; failures here keep the
  -- auto-close from firing on a run that actually had red
  schedule_notify(tally)

  -- nothing in the tree was a test (e.g. a bare file/dir node): surface output
  if not next(results) then
    results[tree:data().id] = { status = "failed", output = result.output }
  end
  return results
end

return adapter
