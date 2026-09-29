-- Locates the JUnit Platform Console Standalone jar and builds the launch
-- command. The jar bundles the JUnit engines, so we only need to add the
-- project's test classpath to run any test without relying on gradle/maven.
local M = {}

-- absolute path to the console-standalone jar; resolved from ~/.m2 lazily,
-- overridable via setup{ test = { console_launcher_path = ... } }
M.console_launcher_path = nil

-- used when the project's junit version can't be determined
local DEFAULT_VERSION = "1.11.3"
local ARTIFACT = "org.junit.platform:junit-platform-console-standalone:" .. DEFAULT_VERSION

local REPO = "~/.m2/repository/org/junit/platform/junit-platform-console-standalone/"
local GLOB = REPO .. "*/junit-platform-console-standalone-*.jar"

-- The standalone jar carries its own junit engines, and they win over the
-- project's copies (the jar is the app classloader, the test classpath is
-- loaded below it). Running a junit 6 project on the 1.x jar therefore blows up
-- inside the test framework - spring-test calls jupiter 6 API that 5.x lacks.
-- So pick the jar matching the junit on the classpath. Numbering: junit 5.x
-- ships as platform 1.x (5.11.3 <-> 1.11.3); junit 6 unified the two.
function M.launcher_version(classpath)
  for _, entry in ipairs(classpath or {}) do
    local major, minor, patch = entry:match("junit%-jupiter%-api%-(%d+)%.(%d+)%.(%d+)")
    if major then
      local prefix = tonumber(major) >= 6 and major or "1"
      return prefix .. "." .. minor .. "." .. patch
    end
  end
  -- no jupiter (vintage-only project?): the platform version is what we need
  for _, entry in ipairs(classpath or {}) do
    local version = entry:match("junit%-platform%-engine%-(%d+%.%d+%.%d+)")
    if version then
      return version
    end
  end
  return nil
end

function M.artifact(version)
  return "org.junit.platform:junit-platform-console-standalone:" .. (version or DEFAULT_VERSION)
end

-- the jar for `version`, or the newest cached one when no version is asked for
function M.find_jar(version)
  if version then
    local jar = vim.fn.expand(REPO .. version .. "/junit-platform-console-standalone-" .. version .. ".jar")
    return vim.fn.filereadable(jar) == 1 and jar or nil
  end
  local found = vim.fn.glob(vim.fn.expand(GLOB))
  if found ~= "" then
    -- prefer the newest when several versions are cached
    local list = vim.split(found, "\n")
    table.sort(list)
    return list[#list]
  end
  return nil
end

-- An explicit console_launcher_path always wins. Otherwise a requested version
-- is honoured exactly: falling back to another one is what caused the version
-- clash in the first place.
function M.resolve_jar(version)
  if M.console_launcher_path then
    return M.console_launcher_path
  end
  if version then
    return M.find_jar(version)
  end
  M.console_launcher_path = M.find_jar()
  return M.console_launcher_path
end

local CENTRAL = "https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/"
local MVN_TIMEOUT_MS = 90000

-- Where the jar lands when we fetch it ourselves: the same layout maven uses,
-- so find_jar() sees it either way.
function M.jar_path(version)
  return vim.fn.expand(REPO .. version .. "/junit-platform-console-standalone-" .. version .. ".jar")
end

-- Download straight from Maven Central. A corporate mirror configured in
-- settings.xml swallows every request maven makes, and such mirrors routinely
-- lag behind on new artifacts - that must not stop a test run, since this one
-- jar has no dependencies to resolve.
local function download(version, progress, on_done)
  local url = CENTRAL .. version .. "/junit-platform-console-standalone-" .. version .. ".jar"
  local dest = M.jar_path(version)
  vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
  local cmd
  if vim.fn.executable("curl") == 1 then
    cmd = { "curl", "-fL", "--progress-bar", "--max-time", "300", "-o", dest, url }
  elseif vim.fn.executable("wget") == 1 then
    cmd = { "wget", "--progress=dot:mega", "-O", dest, url }
  else
    on_done(nil, "neither curl nor wget is available")
    return
  end
  local errors = {}
  local function on_data(_, data)
    if data then
      progress.note(data)
      errors[#errors + 1] = data
    end
  end
  vim.system(cmd, { text = true, stdout = on_data, stderr = on_data }, function(out)
    if out.code == 0 and vim.fn.filereadable(dest) == 1 then
      on_done(dest)
    else
      vim.fn.delete(dest)
      on_done(nil, vim.trim(table.concat(errors)))
    end
  end)
end

function M.install_jar(version, on_done)
  local artifact = M.artifact(version)
  if vim.fn.executable("mvn") ~= 1 then
    vim.notify("jc: mvn not found, downloading " .. artifact .. " from Maven Central...", vim.log.levels.INFO)
    local direct = require("jc.ui").progress("jc download")
    download(version or DEFAULT_VERSION, direct, function(path, err)
      direct.stop()
      vim.schedule(function()
        if path then
          vim.notify("jc: launcher installed: " .. path, vim.log.levels.INFO)
          if on_done then
            on_done(path)
          end
        else
          vim.notify("jc: could not download the launcher: " .. (err or "failed"), vim.log.levels.ERROR)
        end
      end)
    end)
    return
  end
  vim.notify("jc: downloading " .. artifact .. " via maven...", vim.log.levels.INFO)
  -- not -q: the download is the slow part, and its output is what makes the
  -- cmdline progress meaningful
  local progress = require("jc.ui").progress("jc maven")
  local tail = {}
  local function on_data(_, data)
    if data then
      progress.note(data)
      tail[#tail + 1] = data
    end
  end
  vim.system(
    { "mvn", "dependency:get", "-Dartifact=" .. artifact },
    -- an unreachable mirror does not fail, it stalls mid-download; give up and
    -- go to Central rather than hanging the run forever
    { text = true, timeout = MVN_TIMEOUT_MS, stdout = on_data, stderr = on_data },
    function(out)
      progress.stop()
      vim.schedule(function()
        local jar = out.code == 0 and M.find_jar(version or DEFAULT_VERSION)
        if jar then
          vim.notify("jc: launcher installed: " .. jar, vim.log.levels.INFO)
          if on_done then
            on_done(jar)
          end
          return
        end
        -- maven could not get it (an unreachable or out-of-date mirror is the
        -- usual reason): take it from Central ourselves
        vim.notify("jc: maven could not fetch it, downloading from Maven Central...", vim.log.levels.INFO)
        local direct = require("jc.ui").progress("jc download")
        download(version or DEFAULT_VERSION, direct, function(path, err)
          direct.stop()
          vim.schedule(function()
            if path then
              vim.notify("jc: launcher installed: " .. path, vim.log.levels.INFO)
              if on_done then
                on_done(path)
              end
            else
              vim.notify(
                "jc: could not install the launcher.\nmaven: exit "
                  .. out.code
                  .. "\ndirect download: "
                  .. (err or "failed"),
                vim.log.levels.ERROR
              )
            end
          end)
        end)
      end)
    end
  )
end

-- Subcommands arrived in Platform 1.10; older launchers take their options flat
-- and reject "execute" as an unmatched argument.
function M.supports_execute(version)
  local major, minor = tostring(version or ""):match("^(%d+)%.(%d+)")
  if not major then
    return true
  end
  major, minor = tonumber(major), tonumber(minor)
  return major > 1 or minor >= 10
end

function M.version_of(jar)
  return tostring(jar or ""):match("junit%-platform%-console%-standalone%-([%d%.]+)%.jar")
end

-- build the java command. opts:
--   java        java executable (default "java")
--   jar         console-standalone jar path
--   classpath   list of classpath entries
--   selectors   list of "--select-..." strings
--   reports_dir directory for the XML report
--   version     the jar's version (defaults to the one in its filename)
function M.build_command(opts)
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local cmd = { opts.java or "java", "-jar", opts.jar }
  if M.supports_execute(opts.version or M.version_of(opts.jar)) then
    cmd[#cmd + 1] = "execute"
  end
  vim.list_extend(cmd, { "--classpath", table.concat(opts.classpath or {}, sep) })
  vim.list_extend(cmd, opts.selectors or {})
  vim.list_extend(cmd, { "--reports-dir", opts.reports_dir })
  vim.list_extend(cmd, { "--details", "none", "--disable-banner" })
  return cmd
end

M.ARTIFACT = ARTIFACT
M.DEFAULT_VERSION = DEFAULT_VERSION

return M
