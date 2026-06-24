-- Locates the JUnit Platform Console Standalone jar and builds the launch
-- command. The jar bundles the JUnit engines, so we only need to add the
-- project's test classpath to run any test without relying on gradle/maven.
local M = {}

-- absolute path to the console-standalone jar; resolved from ~/.m2 lazily,
-- overridable via setup{ test = { console_launcher_path = ... } }
M.console_launcher_path = nil

local ARTIFACT = "org.junit.platform:junit-platform-console-standalone:1.11.3"

local GLOB = "~/.m2/repository/org/junit/platform/junit-platform-console-standalone/"
  .. "*/junit-platform-console-standalone-*.jar"

function M.find_jar()
  local jar = vim.fn.glob(vim.fn.expand(GLOB))
  if jar ~= "" then
    -- prefer the newest when several versions are cached
    local list = vim.split(jar, "\n")
    table.sort(list)
    return list[#list]
  end
  return nil
end

function M.resolve_jar()
  if not M.console_launcher_path then
    M.console_launcher_path = M.find_jar()
  end
  return M.console_launcher_path
end

function M.install_jar(on_done)
  if vim.fn.executable("mvn") ~= 1 then
    vim.notify(
      "jc: mvn not found — install the launcher manually: mvn dependency:get -Dartifact=" .. ARTIFACT,
      vim.log.levels.ERROR
    )
    return
  end
  vim.notify("jc: downloading junit-platform-console-standalone via maven...", vim.log.levels.INFO)
  vim.system({ "mvn", "-q", "dependency:get", "-Dartifact=" .. ARTIFACT }, {}, function(out)
    vim.schedule(function()
      if out.code == 0 and M.resolve_jar() then
        vim.notify("jc: launcher installed: " .. M.console_launcher_path, vim.log.levels.INFO)
        on_done()
      else
        vim.notify("jc: launcher install failed: " .. (out.stderr or ("exit " .. out.code)), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- build the java command. opts:
--   java        java executable (default "java")
--   jar         console-standalone jar path
--   classpath   list of classpath entries
--   selectors   list of "--select-..." strings
--   reports_dir directory for the XML report
function M.build_command(opts)
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local cmd = { opts.java or "java", "-jar", opts.jar, "execute" }
  vim.list_extend(cmd, { "--classpath", table.concat(opts.classpath or {}, sep) })
  vim.list_extend(cmd, opts.selectors or {})
  vim.list_extend(cmd, { "--reports-dir", opts.reports_dir })
  vim.list_extend(cmd, { "--details", "none", "--disable-banner" })
  return cmd
end

M.ARTIFACT = ARTIFACT

return M
