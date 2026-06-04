-- nvim-dap backend, parallel to jc.vimspector. Remembers the last host/port
-- per project (shares the "debug-host"/"debug-port" keys with jc.vimspector).
--
-- Note: we do NOT reuse nvim-java's `java` dap adapter for attach — it always
-- enriches the config and asserts a mainClass (launch-only). Instead, like
-- jc.vimspector, we ask jdtls for the java-debug adapter port via
-- `vscode.java.startDebugSession` and connect a plain `server` adapter, then
-- send a JDWP attach (hostName/port = the running JVM).
local M = {}
local lsp = require("jc.lsp")
local ui = require("jc.ui")

local ADAPTER = "jc_java_attach"

-- register an adapter that resolves the java-debug session port on demand
local function ensure_adapter(dap)
  dap.adapters[ADAPTER] = function(callback)
    lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(port)
      if type(port) == "number" then
        callback({ type = "server", host = "127.0.0.1", port = port })
      else
        vim.notify("jc.dap: startDebugSession failed: " .. vim.inspect(port), vim.log.levels.ERROR)
      end
    end, function()
      vim.notify("jc.dap: no jdtls client for startDebugSession", vim.log.levels.ERROR)
    end)
  end
end

local do_attach

-- best-effort project name (java-debug needs it to bind breakpoints/sources)
local function resolve_project(callback)
  lsp.executeCommand({ command = "vscode.java.resolveMainClass" }, function(response)
    if type(response) == "table" and response[1] and response[1].projectName then
      callback(response[1].projectName)
    else
      callback(nil)
    end
  end, function()
    callback(nil)
  end)
end

function M.debug_attach()
  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify("jc.dap: nvim-dap not found", vim.log.levels.ERROR)
    return
  end
  ensure_adapter(dap)
  ui.ask_for("host", "127.0.0.1", function(host)
    if not host:match("^[%w%.%-_]+$") then
      vim.notify("jc.dap: invalid host: " .. host, vim.log.levels.ERROR)
      return
    end
    ui.ask_for("port", "5005", function(port_input)
      local port = tonumber(port_input)
      if not port or port < 1 or port > 65535 then
        vim.notify("jc.dap: invalid port: " .. port_input, vim.log.levels.ERROR)
        return
      end
      do_attach(dap, host, port)
    end)
  end)
end

function do_attach(dap, host, port)
  resolve_project(function(project_name)
    dap.run({
      type = ADAPTER,
      request = "attach",
      name = "jc: attach " .. host .. ":" .. tostring(port),
      hostName = host,
      port = port,
      projectName = project_name,
      -- keep stepping inside mappable user code; skip JDK/synthetic frames that
      -- a version-mismatched debugger (jdtls JDK17 vs app JDK11) can't map and
      -- that otherwise crash the adapter on step-in
      stepFilters = {
        skipClasses = { "$JDK", "junit.*" },
        skipSynthetics = true,
        skipStaticInitializers = true,
        skipConstructors = true,
      },
    })
  end)
end

return M
