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

adapter.root = lib.files.match_root_pattern(
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "settings.gradle.kts",
  ".git"
)

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
local function resolve_classpath(file)
  local classpath
  require("jc.tools").classpaths_for(vim.uri_from_fname(file), function(cp)
    classpath = cp
  end, "test")
  if not vim.wait(20000, function()
    return classpath ~= nil
  end, 50) then
    return nil
  end
  return classpath
end

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

  -- one spec per file, each with that file's module classpath
  local specs = {}
  for file, selectors in pairs(by_file) do
    local classpath = resolve_classpath(file)
    if classpath then
      local reports_dir = vim.fn.tempname()
      vim.fn.mkdir(reports_dir, "p")
      specs[#specs + 1] = {
        command = launcher.build_command({
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
