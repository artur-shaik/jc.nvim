-- JDK facts shared by the test runner and the project diagnostics: reading a
-- class file's level, and mapping a level onto one of jdtls' configured
-- runtimes. Deliberately free of neotest, so :checkhealth can use it.
local M = {}

-- the java feature version a class file was compiled to, or nil
function M.class_major(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local head = fd:read(8)
  fd:close()
  if head and #head >= 8 then
    return head:byte(7) * 256 + head:byte(8) - 44 -- 52 -> 8, 61 -> 17
  end
  return nil
end

-- the highest level among the class files under `dirs` (one probe per dir is
-- enough: a dir is written by one compiler run)
function M.level_of(dirs)
  local max
  for _, dir in ipairs(dirs) do
    local hits = vim.fs.find(function(n)
      return n:match("%.class$")
    end, { path = dir, type = "file", limit = 1 })
    local v = hits[1] and M.class_major(hits[1])
    if v and (not max or v > max) then
      max = v
    end
  end
  return max
end

-- "JavaSE-17" -> 17, "JavaSE-1.8" -> 8
function M.runtime_version(name)
  local v = name and name:match("^JavaSE%-(.+)$")
  if not v then
    return nil
  end
  return v == "1.8" and 8 or tonumber(v:match("^(%d+)"))
end

-- jdtls' java.configuration.runtimes, as { [version] = path }
function M.runtimes()
  local client = require("jc.lsp").get_jdtls_client()
  local configured = client and vim.tbl_get(client.config or {}, "settings", "java", "configuration", "runtimes")
  local out = {}
  if type(configured) ~= "table" then
    return out
  end
  for _, r in ipairs(configured) do
    local v = M.runtime_version(r.name)
    if v and type(r.path) == "string" and r.path ~= "" then
      out[v] = r.path
    end
  end
  return out
end

-- the java executable for `ver`, or the closest newer one (bytecode is
-- forward-compatible, so a newer JVM still runs it)
function M.java_for_version(ver)
  local runtimes = M.runtimes()
  if runtimes[ver] then
    return runtimes[ver] .. "/bin/java"
  end
  local best, best_v
  for v, path in pairs(runtimes) do
    if v > ver and (not best_v or v < best_v) then
      best, best_v = path .. "/bin/java", v
    end
  end
  return best
end

-- the JDK home for `ver`, exactly - no newer substitute. A build has to run on
-- the level it targets: an older gradle on a newer JDK dies in javac internals.
function M.home_for_version(ver)
  return M.runtimes()[ver]
end

return M
