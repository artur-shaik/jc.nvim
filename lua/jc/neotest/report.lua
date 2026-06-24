-- Pure parser for the JUnit XML reports written by the JUnit Platform
-- Console Launcher (--reports-dir). Kept free of any neotest/vim.lsp
-- dependency so it can be unit-tested headless.
local M = {}

local function unescape(s)
  if not s then
    return s
  end
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function attr(tag, key)
  return tag:match(key .. '="(.-)"')
end

-- the JUnit Jupiter writer appends "()" to method names and may carry a
-- parameterized suffix ("foo(int)[1]"); the bare method name is everything
-- before the first "(".
local function base_method(name)
  if not name then
    return name
  end
  return (name:gsub("%(.*$", ""))
end

-- first stack frame that points at the test class's own source file, as
-- {file, line}; falls back to the first *.java frame. classname is the FQN
-- so its simple name gives the expected File.java.
local function locate_failure(trace, classname)
  if not trace then
    return nil
  end
  local simple = classname and classname:match("([^.]+)$") or nil
  if simple then
    local file, line = trace:match("%((" .. simple .. "%.java):(%d+)%)")
    if file then
      return { file = file, line = tonumber(line) }
    end
  end
  local file, line = trace:match("%(([%w$_]+%.java):(%d+)%)")
  if file then
    return { file = file, line = tonumber(line) }
  end
  return nil
end

-- parse the whole report into a flat list of test cases:
-- { name, method, classname, status = passed|failed|skipped, message, trace,
--   failure = { file, line } }
function M.parse(xml)
  local cases = {}
  if not xml then
    return cases
  end
  local pos = 1
  while true do
    local s = xml:find("<testcase", pos, true)
    if not s then
      break
    end
    local open_end = xml:find(">", s, true)
    if not open_end then
      break
    end
    local opentag = xml:sub(s, open_end)
    local self_close = opentag:sub(-2) == "/>"
    local body, case_end = "", open_end
    if not self_close then
      local close = xml:find("</testcase>", open_end, true)
      if close then
        body = xml:sub(open_end + 1, close - 1)
        case_end = close + #"</testcase>"
      end
    end

    local case = {
      name = unescape(attr(opentag, "name")),
      classname = attr(opentag, "classname"),
      time = attr(opentag, "time"),
      status = "passed",
    }
    case.method = base_method(case.name)

    local kind = body:match("<(failure)") or body:match("<(error)") or body:match("<(skipped)")
    if kind == "skipped" then
      case.status = "skipped"
      case.message = unescape(body:match('<skipped[^>]-message="(.-)"'))
    elseif kind then
      case.status = "failed"
      local tag = body:match("<" .. kind .. "(.-)>")
      case.message = unescape(attr(tag or "", "message"))
      case.trace = unescape(vim.trim(body:match("<" .. kind .. "[^>]->(.-)</" .. kind .. ">") or ""))
      case.failure = locate_failure(case.trace, case.classname)
    end
    cases[#cases + 1] = case
    pos = case_end + 1
  end
  return cases
end

-- key under which a case is indexed for lookup against tree positions
function M.key(classname, method)
  return (classname or "") .. "#" .. base_method(method)
end

-- index parsed cases by classname#method for O(1) position lookup
function M.index(cases)
  local idx = {}
  for _, c in ipairs(cases) do
    idx[M.key(c.classname, c.method)] = c
  end
  return idx
end

return M
