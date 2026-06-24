-- neotest adapter for jc.nvim. Optional: this module is only loaded when the
-- user wires it into their neotest setup via require("jc").neotest_adapter().
-- It resolves the test classpath from jdtls (no gradle/maven daemon) and runs
-- the JUnit Platform Console Standalone launcher, then maps the XML report
-- back onto neotest positions.
local lib = require("neotest.lib")

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
  local cp
  require("jc.tools").classpaths_for(uri, function(c)
    cp = c
  end, scope)
  if not vim.wait(20000, function()
    return cp ~= nil
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
local function resolve_classpath(file)
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
      local set = entry:match("[/\\]bin[/\\]([^/\\]+)$")
      if set == "test" then
        -- edited test classes must win, so jdtls' fresh bin/test goes first
        -- and the CLI build is only a fallback
        add(entry)
        add_build_outputs(entry)
      elseif set == "main" or set == "default" then
        -- jdtls' bin/main can be a stale/incomplete compile; the CLI build is
        -- a complete, internally consistent set of production classes, so it
        -- wins (mid-session production edits need a CLI rebuild — rare; tests
        -- are what people iterate on)
        add_build_outputs(entry)
        add(entry)
      else
        add(entry)
      end
    end
  end
  return out
end

-- the project's configured JDK (matching its Java compliance) rather than
-- whatever `java` sits on PATH: running 11-target tests on a newer JVM can
-- break old byte-buddy/Mockito (mock-creation failures the gradle toolchain
-- run doesn't hit). Falls back to "java".
local function resolve_java()
  local java
  require("jc.lsp").executeCommand({
    command = "vscode.java.resolveJavaExecutable",
    arguments = { "", "" },
  }, function(j)
    java = (type(j) == "string" and j ~= "") and j or "java"
  end, function()
    java = "java"
  end)
  if not vim.wait(10000, function()
    return java ~= nil
  end, 50) then
    return "java"
  end
  return java
end

-- exposed for :JCtestDebugClasspath so the dump reflects the augmented
-- classpath the runner actually launches with
adapter.resolve_classpath = resolve_classpath

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

  -- let any in-flight jdtls indexing/compile (e.g. the recompile triggered by
  -- saving the edited test) settle so we launch against fresh bin output
  if require("jc.lsp").jdtls_busy() then
    vim.schedule(function()
      vim.notify("jc: waiting for jdtls to finish indexing...", vim.log.levels.INFO)
    end)
    require("jc.lsp").wait_until_idle(60000)
  end

  local java = resolve_java()

  -- one spec per file, each with that file's module classpath
  local specs = {}
  for file, selectors in pairs(by_file) do
    local classpath = resolve_classpath(file)
    if classpath then
      local reports_dir = vim.fn.tempname()
      vim.fn.mkdir(reports_dir, "p")
      specs[#specs + 1] = {
        command = launcher.build_command({
          java = java,
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
      vim.notify("jc: timed out resolving test classpath from jdtls", vim.log.levels.ERROR)
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
          short = "test runner produced no report — see :JCtestOutput",
          output = result.output,
        }
      end
    end
  end

  if runner_failed then
    if notify_enabled() then
      running = false
      vim.schedule(function()
        vim.notify(
          "jc tests: runner produced no report (exit " .. tostring(result.code) .. ") — :JCtestOutput for details",
          vim.log.levels.ERROR
        )
      end)
    end
  else
    schedule_notify(tally)
  end

  -- nothing in the tree was a test (e.g. a bare file/dir node): surface output
  if not next(results) then
    results[tree:data().id] = { status = "failed", output = result.output }
  end
  return results
end

return adapter
