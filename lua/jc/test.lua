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
  local root = vim.fs.root(0, markers) or vim.fn.getcwd()
  nt.run.run(root)
  maybe_open_summary(nt, root)
end

function M.run_last()
  local nt = neotest()
  if not nt then
    return
  end
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
