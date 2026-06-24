-- classpath-aware terminal tools (javap, jshell, jol) driven by jdtls
-- project commands; nvim-jdtls is not required
local lsp = require("jc.lsp")

local M = {}

-- absolute path to the jol jar; resolved from ~/.m2 lazily, can be
-- overridden by the user
M.jol_path = nil

local JOL_ARTIFACT = "org.openjdk.jol:jol-cli:0.17:jar:full"

local function find_jol_jar()
  local jol = vim.fn.glob(vim.fn.expand("~/.m2/repository/org/openjdk/jol/jol-cli/*/jol-cli-*-full.jar"))
  if jol ~= "" then
    return vim.split(jol, "\n")[1]
  end
  return nil
end

function M.resolve_jol()
  if not M.jol_path then
    M.jol_path = find_jol_jar()
  end
  return M.jol_path
end

local function install_jol(on_done)
  if vim.fn.executable("mvn") ~= 1 then
    vim.notify(
      "jc: mvn not found — install jol manually: mvn dependency:get -Dartifact=" .. JOL_ARTIFACT,
      vim.log.levels.ERROR
    )
    return
  end
  vim.notify("jc: downloading jol-cli via maven...", vim.log.levels.INFO)
  vim.system({ "mvn", "-q", "dependency:get", "-Dartifact=" .. JOL_ARTIFACT }, {}, function(out)
    vim.schedule(function()
      if out.code == 0 and M.resolve_jol() then
        vim.notify("jc: jol installed: " .. M.jol_path, vim.log.levels.INFO)
        on_done()
      else
        vim.notify("jc: jol installation failed: " .. (out.stderr or ("exit " .. out.code)), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function term_run(cmd, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart(cmd, vim.tbl_extend("force", opts or {}, { term = true }))
  else
    vim.fn.termopen(cmd, opts) ---@diagnostic disable-line: deprecated
  end
end

-- fully qualified name of the class in the current buffer
local function resolve_classname()
  local classname
  if vim.startswith(vim.fn.expand("%"), "jdt://") then
    classname = require("jc.treesitter").get_class_name()
    if not classname then
      return nil
    end
  else
    classname = vim.fn.expand("%:t:r")
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, true)) do
    local pkg = line:match("package ([a-z0-9_%.]+);")
    if pkg then
      return pkg .. "." .. classname
    end
  end
  return classname
end

-- project classpaths for an arbitrary file uri. Exported so the test runner
-- can resolve a classpath for a file that isn't the current buffer. Pass
-- force_scope ("test"/"runtime") to skip the isTestFile probe — the test
-- runner always wants the test scope (it only ever launches test files, and a
-- runtime classpath omits the test output, so the test class itself wouldn't
-- be found).
-- on_error (optional): called instead of notifying when jdtls can't resolve
-- the classpath (e.g. the project isn't imported yet) so callers can fail fast
function M.classpaths_for(uri, fn, force_scope, on_error)
  local function fail()
    if on_error then
      on_error()
    else
      vim.notify("jc: couldn't resolve project classpaths", vim.log.levels.ERROR)
    end
  end
  local function get(scope)
    lsp.executeCommand({
      command = "java.project.getClasspaths",
      arguments = { uri, vim.fn.json_encode({ scope = scope }) },
    }, function(resp)
      if type(resp) == "table" and resp.classpaths then
        fn(resp.classpaths)
      else
        fail()
      end
    end, on_error and fail or nil)
  end
  if force_scope then
    get(force_scope)
  elseif vim.startswith(uri, "jdt://") then
    get("runtime")
  else
    lsp.executeCommand({ command = "java.project.isTestFile", arguments = { uri } }, function(is_test)
      get(is_test == true and "test" or "runtime")
    end)
  end
end

-- project classpaths for the current buffer
local function with_classpaths(fn)
  M.classpaths_for(vim.uri_from_bufnr(0), fn)
end

-- java executable of the project runtime; falls back to PATH
local function with_java_executable(classname, fn)
  lsp.executeCommand({
    command = "vscode.java.resolveJavaExecutable",
    arguments = { classname or "", "" },
  }, function(java_exec)
    fn(type(java_exec) == "string" and java_exec or "java")
  end, function()
    fn("java")
  end)
end

function M.javap()
  local classname = resolve_classname()
  if not classname then
    vim.notify("jc: couldn't resolve class name", vim.log.levels.ERROR)
    return
  end
  with_classpaths(function(classpaths)
    term_run({ "javap", "-c", "--class-path", table.concat(classpaths, ":"), classname })
  end)
end

function M.jshell()
  with_classpaths(function(classpaths)
    local existing = vim.tbl_filter(function(path)
      return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
    end, classpaths)
    with_java_executable(resolve_classname(), function(java_exec)
      local jshell = java_exec ~= "java" and (vim.fn.fnamemodify(java_exec, ":p:h") .. "/jshell") or "jshell"
      term_run(jshell, { env = { CLASSPATH = table.concat(existing, ":") } })
    end)
  end)
end

function M.jol(mode, classname)
  mode = mode or "estimates" -- estimates | footprint | externals | internals
  if not M.resolve_jol() then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "jol jar not found. Download via maven (" .. JOL_ARTIFACT .. ")?",
    }, function(choice)
      if choice == "Yes" then
        install_jol(function()
          M.jol(mode, classname)
        end)
      end
    end)
    return
  end
  local resolved = classname or resolve_classname()
  if not resolved then
    vim.notify("jc: couldn't resolve class name", vim.log.levels.ERROR)
    return
  end
  with_classpaths(function(classpaths)
    with_java_executable(resolved, function(java_exec)
      term_run({
        java_exec,
        "-Djdk.attach.allowAttachSelf",
        "-jar",
        M.jol_path,
        mode,
        "-cp",
        table.concat(classpaths, ":"),
        resolved,
      })
    end)
  end)
end

return M
