-- jc-native test debugging: launch the JUnit Platform Console Launcher under a
-- JDWP agent and attach nvim-dap to it. Unlike the eclipse RemoteTestRunner that
-- nvim-jdtls/nvim-java drive, ConsoleLauncher is standalone (its own consistent
-- junit-platform in the jar), so it debugs any project regardless of the
-- vscode-java-test bundle's junit version — which is what breaks the delegated
-- path on projects whose junit differs from the bundle's.
local M = {}

local ts = require("jc.treesitter")

-- The `--select-...` selector for the test at the cursor, built from treesitter:
-- `--select-method=<pkg.Class>#<method>` inside a method, else
-- `--select-class=<pkg.Class>` inside a class. Returns selector, label or nil.
function M.selector_at_cursor()
  local class_node = ts.enclosing_declaration("class_declaration")
  if not class_node then
    return nil
  end
  local pkg = ts.get_package()
  local function decl_name(node)
    local name = node and node:field("name")[1]
    return name and vim.treesitter.get_node_text(name, 0) or nil
  end
  local class = decl_name(class_node)
  if not class then
    return nil
  end
  local fqn = (pkg and pkg ~= "" and (pkg .. ".") or "") .. class
  local method_node = ts.enclosing_declaration("method_declaration")
  local method = method_node and decl_name(method_node)
  if method then
    return "--select-method=" .. fqn .. "#" .. method, fqn .. "#" .. method
  end
  return "--select-class=" .. fqn, fqn
end

-- Launch ConsoleLauncher under a JDWP agent for `selector`, attach dap once the
-- agent is listening, and report results from the JUnit XML afterwards. Needs
-- nvim-dap and the java-debug adapter (jc.dap registers it via startDebugSession).
function M.run(selector, label)
  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap then
    vim.notify("jc: nvim-dap not found — test debugging needs it", vim.log.levels.ERROR)
    return
  end
  local launcher = require("jc.neotest.launcher")
  local adapter = require("jc.neotest")
  local jar = launcher.resolve_jar()
  if not jar then
    vim.notify("jc: junit console launcher jar not found — run :JCtestInstall", vim.log.levels.ERROR)
    return
  end
  local file = vim.fn.expand("%:p")
  local classpath = adapter.resolve_classpath(file, false)
  if not classpath then
    vim.notify("jc: couldn't resolve the test classpath from jdtls", vim.log.levels.ERROR)
    return
  end
  local java = adapter.resolve_java(file, false)
  local reports_dir = vim.fn.tempname()
  vim.fn.mkdir(reports_dir, "p")
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local cp = jar .. sep .. table.concat(classpath, sep)

  -- suspend=y so the JVM waits for our attach; address=0 lets the OS pick a
  -- free port, which the agent prints on stderr
  local cmd = {
    java,
    "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=127.0.0.1:0",
    "-cp",
    cp,
    "org.junit.platform.console.ConsoleLauncher",
    "execute",
    selector,
    "--reports-dir",
    reports_dir,
    "--details",
    "none",
    "--disable-banner",
  }

  M._register_attach_adapter(dap)
  local attached = false
  local function on_output(_, data)
    for _, line in ipairs(data or {}) do
      local port = line:match("Listening for transport dt_socket at address:%s*(%d+)")
      if port and not attached then
        attached = true
        vim.schedule(function()
          dap.run({
            type = "jc_java_test",
            request = "attach",
            name = "jc: debug " .. (label or "test"),
            hostName = "127.0.0.1",
            port = tonumber(port),
            stepFilters = {
              skipClasses = { "$JDK", "junit.*", "org.junit.*" },
              skipSynthetics = true,
            },
          })
        end)
      end
    end
  end

  vim.notify("jc: debugging " .. (label or "test") .. " …", vim.log.levels.INFO)
  M._job = vim.fn.jobstart(cmd, {
    on_stderr = on_output,
    on_stdout = on_output,
    on_exit = function()
      M._report(reports_dir, label)
    end,
  })
end

-- register a dap adapter that connects to a plain JDWP server. Reuses jc.dap's
-- java-debug session-port resolution (the adapter bridges DAP<->JDWP).
function M._register_attach_adapter(dap)
  if dap.adapters.jc_java_test then
    return
  end
  local lsp = require("jc.lsp")
  dap.adapters.jc_java_test = function(callback)
    lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(port)
      if type(port) == "number" then
        callback({ type = "server", host = "127.0.0.1", port = port })
      else
        vim.notify("jc: startDebugSession failed", vim.log.levels.ERROR)
      end
    end, function()
      vim.notify("jc: no jdtls client for startDebugSession", vim.log.levels.ERROR)
    end)
  end
end

-- parse the JUnit XML in `reports_dir` and toast a pass/fail summary
function M._report(reports_dir, label)
  local ok, report = pcall(require, "jc.neotest.report")
  local xmls = vim.fn.glob(reports_dir .. "/*.xml", false, true)
  if not ok or #xmls == 0 then
    return
  end
  local passed, failed = 0, 0
  for _, xml in ipairs(xmls) do
    for _, case in ipairs(report.parse(table.concat(vim.fn.readfile(xml), "\n"))) do
      if case.status == "failed" then
        failed = failed + 1
      elseif case.status == "passed" then
        passed = passed + 1
      end
    end
  end
  vim.schedule(function()
    local level = failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
    vim.notify(("jc: %s — %d passed, %d failed"):format(label or "test", passed, failed), level)
  end)
end

function M.debug_at_cursor()
  local selector, label = M.selector_at_cursor()
  if not selector then
    vim.notify("jc: cursor is not inside a test class/method", vim.log.levels.WARN)
    return
  end
  M.run(selector, label)
end

return M
