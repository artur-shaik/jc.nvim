-- Where the build root is. Shared by the build commands, the test picker and
-- the neotest adapter so they all run gradle from the same directory.
local M = {}

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return ""
  end
  local text = fd:read("*a")
  fd:close()
  return text or ""
end

-- the subproject paths a settings file declares, as a set of ":a:b"
function M._parse_includes(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    if line:match("^%s*include") then
      for tok in line:gmatch("[\"']([:%w%._%-/]+)[\"']") do
        out[":" .. tok:gsub("^:", ""):gsub("[/\\]", ":")] = true
      end
    end
  end
  return out
end

-- true when a build whose settings is `text` owns the directory `rel` below it
function M._includes_project(text, rel)
  if rel == "" then
    return true
  end
  local path = ":" .. rel:gsub("^[/\\]", ""):gsub("[/\\]", ":")
  return M._parse_includes(text)[path] == true
end

-- Root at the OUTERMOST gradle settings so a multi-module build is one tree
-- rather than one per submodule, but only while each settings up the chain
-- actually includes the one below it. A nested checkout carries its own
-- settings.gradle (a git worktree under .claude/worktrees, say), and climbing
-- past it made gradle look up ":.claude:worktrees:..." in the outer build.
function M.gradle_root(dir)
  local dirs, seen = {}, {}
  local found = vim.fs.find(
    { "settings.gradle", "settings.gradle.kts" },
    { path = dir, upward = true, type = "file", limit = math.huge }
  )
  for _, path in ipairs(found) do
    local d = vim.fs.dirname(path)
    if not seen[d] then
      seen[d] = true
      dirs[#dirs + 1] = d
    end
  end
  if #dirs == 0 then
    return nil
  end
  local root = dirs[1]
  for i = 2, #dirs do
    local outer = dirs[i]
    local text = read_file(outer .. "/settings.gradle") .. "\n" .. read_file(outer .. "/settings.gradle.kts")
    if not M._includes_project(text, root:sub(#outer + 2)) then
      break
    end
    root = outer
  end
  return root
end

-- The project root for `dir`: the gradle build root, else the nearest build
-- file or repository. jc runs builds and groups neotest trees by this.
function M.root(dir)
  return M.gradle_root(dir) or vim.fs.root(dir, { "build.gradle", "build.gradle.kts", "pom.xml", ".git" }) or dir
end

return M
