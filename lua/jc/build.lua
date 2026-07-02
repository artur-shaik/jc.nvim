-- run gradle/maven tasks from the editor: free-form args, a task picker, and
-- a repeat-last. Detects the build tool and the project root, prefers the
-- wrapper (gradlew/mvnw), runs in a terminal at the root.
local settings = require("jc.settings")

local M = {}

local MAVEN_LIFECYCLE =
  { "clean", "validate", "compile", "test-compile", "test", "package", "verify", "install", "clean install" }

local function is_file(path)
  return vim.fn.filereadable(path) == 1
end

-- climb from a dir while the parent still has `marker` (the topmost of a
-- contiguous chain) — the multi-module reactor root
local function climb_contiguous(dir, marker)
  while true do
    local parent = vim.fs.dirname(dir)
    if parent == dir or not is_file(parent .. "/" .. marker) then
      return dir
    end
    dir = parent
  end
end

-- project root to run from. Maven resolves ${maven.multiModuleProjectDirectory}
-- (and the reactor) from the launch dir, so a multi-module build must run from
-- the reactor root, not a submodule — otherwise paths like that variable point
-- at the wrong module. Gradle likewise wants the settings.gradle root.
local function find_root()
  local here = vim.fn.expand("%:p:h")
  if here == "" then
    here = vim.fn.getcwd()
  end
  local settings_files = vim.fs.find(
    { "settings.gradle", "settings.gradle.kts" },
    { upward = true, path = here, type = "file", limit = math.huge }
  )
  if #settings_files > 0 then
    return vim.fs.dirname(settings_files[#settings_files])
  end
  local pom = vim.fs.root(here, { "pom.xml" })
  if pom then
    return climb_contiguous(pom, "pom.xml")
  end
  return vim.fs.root(here, { "build.gradle", "build.gradle.kts", "mvnw", "gradlew" }) or vim.fn.getcwd()
end

-- { tool, runner } for the project root, or nil
local function detect(root)
  if
    is_file(root .. "/settings.gradle")
    or is_file(root .. "/settings.gradle.kts")
    or is_file(root .. "/build.gradle")
    or is_file(root .. "/build.gradle.kts")
  then
    local gw = root .. "/gradlew"
    return { tool = "gradle", runner = vim.fn.executable(gw) == 1 and gw or "gradle" }
  elseif is_file(root .. "/pom.xml") then
    local mw = root .. "/mvnw"
    return { tool = "maven", runner = vim.fn.executable(mw) == 1 and mw or "mvn" }
  end
  return nil
end

-- errorformat for javac (gradle) and maven compile errors
local BUILD_EFM = table.concat({
  "%E%f:%l: error: %m",
  "%W%f:%l: warning: %m",
  "%E[ERROR] %f:[%l\\,%c] %m",
  "%-G%.%#",
}, ",")

-- parse the finished build's terminal output into the quickfix list; only
-- touches the list (and opens it) when there are real file:line errors
local function collect_errors(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = vim.fn.getqflist({ lines = lines, efm = BUILD_EFM }).items
  local valid = vim.tbl_filter(function(item)
    return item.valid == 1
  end, parsed)
  if #valid == 0 then
    return
  end
  vim.fn.setqflist({}, " ", { title = "jc build", items = valid })
  vim.cmd("botright copen")
  vim.notify("jc: build has " .. #valid .. " error(s) — see quickfix", vim.log.levels.WARN)
end

local function term_run(cmd, cwd)
  -- open the build in a dedicated bottom split (not in the current window, so
  -- the code view is kept); `q` closes just this split
  local buf = vim.api.nvim_create_buf(false, true)
  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 15)
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, nowait = true, silent = true })
  local opts = {
    cwd = cwd,
    -- wide pty so long "file:line: error:" lines aren't hard-wrapped by the
    -- terminal (which would split them across buffer lines and break the efm
    -- parse); the buffer keeps the full lines, display scrolls horizontally
    width = math.max(vim.o.columns, 320),
    on_exit = function()
      vim.schedule(function()
        collect_errors(buf)
      end)
    end,
  }
  if vim.fn.has("nvim-0.11") == 1 then
    opts.term = true
    vim.fn.jobstart(cmd, opts)
  else
    vim.fn.termopen(cmd, opts) ---@diagnostic disable-line: deprecated
  end
end

-- run `args` (a string) with the detected build tool, remember it per project
local function run_args(build, root, args)
  args = vim.trim(args or "")
  if args == "" then
    return
  end
  settings.write_project("build-last", args)
  local cmd = { build.runner }
  vim.list_extend(cmd, vim.split(args, "%s+", { trimempty = true }))
  term_run(cmd, root)
end

local function with_build(fn)
  local root = find_root()
  local build = detect(root)
  if not build then
    vim.notify("jc: no gradle/maven project found", vim.log.levels.ERROR)
    return
  end
  fn(build, root)
end

-- :JCbuildRun [args] — run given args, or prompt (defaulting to the last run)
function M.run(args)
  with_build(function(build, root)
    if args and vim.trim(args) ~= "" then
      run_args(build, root, args)
      return
    end
    local default = settings.read_project("build-last", build.tool == "gradle" and "build" or "verify")
    vim.ui.input(
      { prompt = build.tool .. " " .. (build.runner:match("[^/\\]+$")) .. " ", default = default },
      function(input)
        if input then
          run_args(build, root, input)
        end
      end
    )
  end)
end

-- :JCbuildLast — repeat the last task
function M.last()
  with_build(function(build, root)
    local last = settings.read_project("build-last")
    if not last or last == "" then
      vim.notify("jc: no previous build task", vim.log.levels.WARN)
      return
    end
    run_args(build, root, last)
  end)
end

local function read_file(path)
  local fd = io.open(path)
  if not fd then
    return ""
  end
  local s = fd:read("*a")
  fd:close()
  return s or ""
end

-- maven plugin goal prefix from its artifactId (spring-boot-maven-plugin ->
-- spring-boot, maven-surefire-plugin -> surefire)
local function plugin_prefix(artifact_id)
  return artifact_id:match("^(.-)%-maven%-plugin$") or artifact_id:match("^maven%-(.-)%-plugin$") or artifact_id
end

-- collect picker entries from one pom's text into `entries` (deduped by `seen`):
-- profiles (-P<id>), configured execution goals (<prefix>:<goal>) and a
-- per-plugin drill-down entry
local function parse_pom(pom, entries, seen)
  for profile in pom:gmatch("<profile>(.-)</profile>") do
    local id = profile:match("<id>%s*(.-)%s*</id>")
    local arg = id and ("-P" .. id)
    if arg and not seen[arg] then
      seen[arg] = true
      entries[#entries + 1] = { label = "profile: " .. id, run = arg }
    end
  end
  for block in pom:gmatch("<plugin>(.-)</plugin>") do
    local artifact_id = block:match("<artifactId>%s*(.-)%s*</artifactId>")
    if artifact_id then
      local prefix = plugin_prefix(artifact_id)
      for goal in block:gmatch("<goal>%s*(.-)%s*</goal>") do
        local arg = prefix .. ":" .. goal
        if not seen[arg] then
          seen[arg] = true
          entries[#entries + 1] = { label = "goal: " .. arg, run = arg }
        end
      end
      local dkey = "describe:" .. prefix
      if not seen[dkey] then
        seen[dkey] = true
        entries[#entries + 1] = { label = "plugin \226\150\184 " .. prefix .. " (all goals)", describe = prefix }
      end
    end
  end
end

local function maven_entries(root)
  local entries, seen = {}, {}
  for _, phase in ipairs(MAVEN_LIFECYCLE) do
    entries[#entries + 1] = { label = "phase: " .. phase, run = phase }
    seen[phase] = true
  end
  local poms = { root .. "/pom.xml" }
  for module in read_file(root .. "/pom.xml"):gmatch("<module>%s*(.-)%s*</module>") do
    poms[#poms + 1] = root .. "/" .. module .. "/pom.xml"
  end
  for _, p in ipairs(poms) do
    parse_pom(read_file(p), entries, seen)
  end
  return entries
end

-- `mvn help:describe` for a plugin prefix -> its full goal list (async)
local function describe_goals(runner, root, prefix, on_goals)
  vim.notify("jc: describing " .. prefix .. "...", vim.log.levels.INFO)
  vim.system(
    { runner, "-q", "--batch-mode", "help:describe", "-Dplugin=" .. prefix },
    { cwd = root, text = true },
    function(res)
      local goals, seen = {}, {}
      for line in ((res.stdout or "") .. (res.stderr or "")):gmatch("[^\n]+") do
        local g = line:match("(" .. prefix .. ":[%w._%-]+)")
        if g and not seen[g] then
          seen[g] = true
          goals[#goals + 1] = g
        end
      end
      vim.schedule(function()
        on_goals(goals)
      end)
    end
  )
end

-- gradle task list for the whole build (scope nil) or one subproject
local function gradle_tasks(runner, root, scope)
  local cmd = { runner, "-q", "--console=plain" }
  if scope then
    table.insert(cmd, scope .. ":tasks")
  else
    vim.list_extend(cmd, { "tasks", "--all" })
  end
  local res = vim.system(cmd, { cwd = root, text = true }):wait(120000)
  local tasks = {}
  local seen = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local name = line:match("^([%w:_%-]+) %- ")
    -- whole project: collapse :sub:task into the base name so picking
    -- "compileJava" runs it across every subproject (gradle <task> at the root)
    if name and not scope then
      name = name:match("([^:]+)$")
    end
    if name and not seen[name] then
      seen[name] = true
      tasks[#tasks + 1] = name
    end
  end
  table.sort(tasks)
  return tasks
end

-- gradle subproject paths (":a", ":a:b") from settings.gradle include(...)
local function gradle_modules(root)
  local text = read_file(root .. "/settings.gradle") .. "\n" .. read_file(root .. "/settings.gradle.kts")
  local mods, seen = {}, {}
  for line in text:gmatch("[^\n]+") do
    if line:match("^%s*include") then
      for tok in line:gmatch("[\"']([:%w%._%-]+)[\"']") do
        local path = ":" .. tok:gsub("^:", "")
        if not seen[path] then
          seen[path] = true
          mods[#mods + 1] = path
        end
      end
    end
  end
  return mods
end

-- maven module relative paths ("a", "a/b") from nested <modules>
local function maven_modules(root)
  local out, seen = {}, {}
  local function walk(dir, rel)
    for module in read_file(dir .. "/pom.xml"):gmatch("<module>%s*(.-)%s*</module>") do
      local mrel = rel == "" and module or (rel .. "/" .. module)
      if not seen[mrel] then
        seen[mrel] = true
        out[#out + 1] = mrel
        walk(dir .. "/" .. module, mrel)
      end
    end
  end
  walk(root, "")
  return out
end

-- a function that runs a task/goal scoped to the chosen module (nil = whole
-- project): gradle ":mod:task", maven "-pl mod -am goal"
local function scoped_runner(build, root, scope)
  return function(arg)
    if scope and build.tool == "gradle" then
      arg = scope .. ":" .. arg
    elseif scope and build.tool == "maven" then
      arg = "-pl " .. scope .. " -am " .. arg
    end
    run_args(build, root, arg)
  end
end

local function pick_maven(build, root, run)
  local entries = maven_entries(root)
  vim.ui.select(entries, {
    prompt = "Maven",
    format_item = function(e)
      return e.label
    end,
  }, function(entry)
    if not entry then
      return
    end
    if entry.describe then
      describe_goals(build.runner, root, entry.describe, function(goals)
        if #goals == 0 then
          vim.notify("jc: no goals found for " .. entry.describe, vim.log.levels.WARN)
          return
        end
        vim.ui.select(goals, { prompt = entry.describe .. " goal" }, function(goal)
          if goal then
            run(goal)
          end
        end)
      end)
    else
      run(entry.run)
    end
  end)
end

local function pick_gradle(build, root, scope, run)
  vim.notify("jc: listing gradle tasks...", vim.log.levels.INFO)
  local tasks = gradle_tasks(build.runner, root, scope)
  if #tasks == 0 then
    vim.notify("jc: no gradle tasks found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(tasks, { prompt = "Gradle task" }, function(choice)
    if choice then
      run(choice)
    end
  end)
end

-- :JCbuildTask — pick a module (or the whole project), then a task/goal
function M.task()
  with_build(function(build, root)
    local modules = build.tool == "maven" and maven_modules(root) or gradle_modules(root)
    local function with_scope(scope)
      local run = scoped_runner(build, root, scope)
      if build.tool == "maven" then
        pick_maven(build, root, run)
      else
        pick_gradle(build, root, scope, run)
      end
    end
    if #modules == 0 then
      return with_scope(nil)
    end
    local choices = { "(whole project)" }
    vim.list_extend(choices, modules)
    vim.ui.select(choices, { prompt = "Module" }, function(choice)
      if not choice then
        return
      end
      with_scope(choice ~= "(whole project)" and choice or nil)
    end)
  end)
end

return M
