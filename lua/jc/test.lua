-- Thin command layer over neotest. neotest is an optional dependency: every
-- entry point degrades to a warning when it (or its modules) is absent, so the
-- plugin keeps working for users who don't run tests.
local M = {}

local function neotest()
  local ok, mod = pcall(require, "neotest")
  if not ok then
    vim.notify(
      "jc: neotest not installed — add nvim-neotest/neotest and wire "
        .. "require('jc').neotest_adapter() into its setup",
      vim.log.levels.WARN
    )
    return nil
  end
  return mod
end

-- when the current buffer is a production class (no tests to discover), the
-- paired test file, if it exists on disk; nil when already in a test file or
-- no counterpart found.
local function counterpart_test_file()
  local cur = vim.fn.expand("%:p")
  if cur:match("Test%.java$") or cur:match("Tests%.java$") or cur:find("[/\\]src[/\\]test[/\\]") then
    return nil -- already a test file: run it as-is
  end
  local ok, path = pcall(require("jc.class_generator").test_counterpart, cur)
  if ok and path and vim.fn.filereadable(path) == 1 then
    return path
  end
  return nil
end

-- auto-close is reliable only for a focused run (one neotest run); a suite is
-- split into independent sub-runs, so suppress it there
local function set_suppress_autoclose(on)
  pcall(function()
    require("jc.neotest.consumer").suppressed = on
  end)
end

-- open the neotest summary on a run (unless disabled) and expand the run
-- target so the launched tests are visible without unfolding by hand. target
-- is the file/dir position id; expansion is deferred so the tree is rendered.
local function maybe_open_summary(nt, target)
  local ok, jc = pcall(require, "jc")
  local t = ok and jc.config and jc.config.test
  if t and t.open_summary == false then
    return
  end
  pcall(function()
    nt.summary.open()
  end)
  if target then
    vim.defer_fn(function()
      pcall(function()
        nt.summary:expand(target, true)
      end)
    end, 300)
  end
end

function M.run_at_cursor()
  local nt = neotest()
  if not nt then
    return
  end
  set_suppress_autoclose(false)
  local counterpart = counterpart_test_file()
  if counterpart then
    vim.notify("jc: not a test file — running " .. vim.fn.fnamemodify(counterpart, ":t"), vim.log.levels.INFO)
    nt.run.run(counterpart)
  else
    nt.run.run()
  end
  maybe_open_summary(nt, counterpart or vim.fn.expand("%:p"))
end

function M.run_file()
  local nt = neotest()
  if not nt then
    return
  end
  set_suppress_autoclose(false)
  local file = counterpart_test_file() or vim.fn.expand("%:p")
  nt.run.run(file)
  maybe_open_summary(nt, file)
end

-- run every discovered test under the project root (build file / .git),
-- falling back to the working directory
function M.run_all()
  local nt = neotest()
  if not nt then
    return
  end
  local markers = {
    "settings.gradle",
    "settings.gradle.kts",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    ".git",
  }
  set_suppress_autoclose(true)
  local root = vim.fs.root(0, markers) or vim.fn.getcwd()
  nt.run.run(root)
  maybe_open_summary(nt, root)
end

function M.run_last()
  local nt = neotest()
  if not nt then
    return
  end
  set_suppress_autoclose(false)
  nt.run.run_last()
  maybe_open_summary(nt, vim.fn.expand("%:p"))
end

function M.stop()
  local nt = neotest()
  if nt then
    nt.run.stop()
  end
end

function M.summary()
  local nt = neotest()
  if nt then
    nt.summary.toggle()
  end
end

function M.output()
  local nt = neotest()
  if nt then
    nt.output.open({ enter = true })
  end
end

-- diagnostic: dump the augmented classpath the runner launches with for the
-- current buffer (the same test+runtime union plus CLI build outputs)
function M.debug_classpath()
  local file = vim.api.nvim_buf_get_name(0)
  local cp = require("jc.neotest").resolve_classpath(file) or {}
  local lines = { "jc test classpath for " .. file, "entries: " .. #cp, "" }
  for _, e in ipairs(cp) do
    lines[#lines + 1] = e
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_win_set_buf(0, buf)
end

-- diagnostic: why the runner picks a given JDK — dump the configured jdtls
-- runtimes and what resolveJavaExecutable returns for several arg shapes
function M.debug_java()
  local lsp = require("jc.lsp")
  local file = vim.api.nvim_buf_get_name(0)
  local cls = vim.fn.fnamemodify(file, ":t:r")
  local pkg = ""
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, 50, false)) do
    local p = line:match("^%s*package%s+([%w_%.]+)%s*;")
    if p then
      pkg = p
      break
    end
  end
  local fqn = pkg ~= "" and (pkg .. "." .. cls) or cls
  local module = file:match("^(.*)[/\\]src[/\\][^/\\]+[/\\]java[/\\]")
  local project = module and vim.fn.fnamemodify(module, ":t") or ""

  local lines = { "file: " .. file, "fqn: " .. fqn, "project (guess): " .. project, "" }

  local client = lsp.get_jdtls_client()
  local runtimes = client and vim.tbl_get(client.config or {}, "settings", "java", "configuration", "runtimes")
  lines[#lines + 1] = "configured runtimes in client.config:"
  if type(runtimes) == "table" and #runtimes > 0 then
    for _, r in ipairs(runtimes) do
      lines[#lines + 1] = string.format("  %s -> %s%s", r.name, r.path, r.default and "  (default)" or "")
    end
  else
    lines[#lines + 1] = "  <none — runtimes config did not apply>"
  end
  lines[#lines + 1] = ""

  local function exec_sync(args)
    local done, result
    lsp.executeCommand({ command = "vscode.java.resolveJavaExecutable", arguments = args }, function(r)
      result, done = r, true
    end, function()
      result, done = "<error>", true
    end)
    vim.wait(8000, function()
      return done
    end, 50)
    return vim.inspect(result)
  end

  lines[#lines + 1] = "resolveJavaExecutable results (jdtls default runtime):"
  lines[#lines + 1] = '  ("", project)      = ' .. exec_sync({ "", project })
  lines[#lines + 1] = "  (fqn, project)     = " .. exec_sync({ fqn, project })
  lines[#lines + 1] = '  (fqn, "")          = ' .. exec_sync({ fqn, "" })
  lines[#lines + 1] = ""

  local nt = require("jc.neotest")
  local mod = module and ("module: " .. module) or "module: <unknown>"
  local ver = nt._module_java_version and module and nt._module_java_version(module)
  lines[#lines + 1] = mod
  lines[#lines + 1] = "detected bytecode java version: " .. tostring(ver)
  lines[#lines + 1] = "=> runner launches with: " .. nt.resolve_java(file)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_win_set_buf(0, buf)
end

-- toggle the build-tool precompile step (setup{ test = { precompile } }) for
-- the session: on for projects jdtls can't fully compile, off for the fast
-- jdtls-only path
function M.toggle_precompile()
  local jc = require("jc")
  jc.config.test = jc.config.test or {}
  jc.config.test.precompile = not jc.config.test.precompile
  vim.notify("jc: test precompile " .. (jc.config.test.precompile and "ON (gradle/maven)" or "OFF (jdtls)"))
end

-- download the JUnit Platform Console Standalone jar via maven
function M.install()
  local launcher = require("jc.neotest.launcher")
  if launcher.resolve_jar() then
    vim.notify("jc: launcher already present: " .. launcher.console_launcher_path, vim.log.levels.INFO)
    return
  end
  launcher.install_jar(function() end)
end

return M
