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
end

function M.run_file()
  local nt = neotest()
  if not nt then
    return
  end
  nt.run.run(counterpart_test_file() or vim.fn.expand("%:p"))
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
end

function M.run_last()
  local nt = neotest()
  if nt then
    nt.run.run_last()
  end
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

-- diagnostic: dump the test-scope classpath jdtls resolves for the current
-- buffer (entry count + whether the buffer's own class dir is present)
function M.debug_classpath()
  local uri = vim.uri_from_bufnr(0)
  require("jc.tools").classpaths_for(uri, function(cp)
    local lines = { "jc test classpath for " .. uri, "entries: " .. #cp, "" }
    for _, e in ipairs(cp) do
      lines[#lines + 1] = e
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_win_set_buf(0, buf)
  end, "test")
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
