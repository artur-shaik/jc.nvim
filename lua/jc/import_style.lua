-- Named import-sort presets modelled on popular IDEs. A pick is persisted per
-- project (a one-line file next to the jdtls workspace, like .regular_imports)
-- and pushed to jdtls before organize-imports so `:JCimportsOrganize` sorts the
-- way the chosen IDE would.
--
-- The knobs map straight onto jdtls settings:
--   java.completion.importOrder                     group order ("#" = static)
--   java.sources.organizeImports.starThreshold      classes-per-package -> pkg.*
--   java.sources.organizeImports.staticStarThreshold same, for static imports
local paths = require("jc.path")

local M = {}

-- A threshold no real file reaches, so organize-imports keeps every import a
-- single type: both the ones it adds and the `pkg.*` already in the file,
-- which it rewrites from the types actually referenced.
M.NO_WILDCARDS = 999

-- the second line of the preset file, when wildcards are turned off
local NO_WILDCARDS_MARK = "no-wildcards"

-- keep display order stable and IDE-recognisable
M.order = { "Eclipse", "IntelliJ IDEA", "VS Code", "Google" }

M.presets = {
  -- classic four groups, static on top, never collapse to a wildcard
  ["Eclipse"] = { import_order = { "#", "java", "javax", "org", "com" }, star = 99, static_star = 99 },
  -- other imports first (alphabetical), then javax/java, then static at the
  -- very bottom (IDEA's default layout); IDEA's 5/3 wildcard defaults
  ["IntelliJ IDEA"] = { import_order = { "", "javax", "java", "#" }, star = 5, static_star = 3 },
  -- jdtls/redhat default group order, static on top, no wildcards
  ["VS Code"] = { import_order = { "#", "java", "javax", "com", "org" }, star = 99, static_star = 99 },
  -- static block first, then one alphabetical block, wildcards forbidden
  ["Google"] = { import_order = { "#", "" }, star = 1000, static_star = 1000 },
}

-- flat dotted jdtls settings for a preset, or nil for an unknown name.
-- `no_wildcards` keeps the group order of the preset but raises its thresholds.
function M.settings_for(name, no_wildcards)
  local p = M.presets[name]
  if not p then
    return nil
  end
  return {
    ["java.completion.importOrder"] = p.import_order,
    ["java.sources.organizeImports.starThreshold"] = no_wildcards and M.NO_WILDCARDS or p.star,
    ["java.sources.organizeImports.staticStarThreshold"] = no_wildcards and M.NO_WILDCARDS or p.static_star,
  }
end

local function filename()
  return paths.get_workspace_dir() .. ".import_style"
end

-- the file as written: preset name on the first line, the mark on the second.
-- A file from an older version holds the name alone.
local function read_lines()
  local file = filename()
  if vim.fn.filereadable(file) ~= 1 then
    return {}
  end
  local out = {}
  for i, line in ipairs(vim.fn.readfile(file)) do
    out[i] = (line or ""):gsub("%s+$", "")
  end
  return out
end

-- the remembered preset name for this project, or nil
function M.load()
  local name = read_lines()[1]
  if name and M.presets[name] then
    return name
  end
  return nil
end

-- whether this project asked for single-type imports only
function M.no_wildcards()
  return read_lines()[2] == NO_WILDCARDS_MARK
end

function M.save(name, no_wildcards)
  if not M.presets[name] then
    return
  end
  local dir = paths.get_workspace_dir()
  if vim.fn.isdirectory(dir) ~= 1 then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local lines = { name }
  if no_wildcards then
    lines[2] = NO_WILDCARDS_MARK
  end
  vim.fn.writefile(lines, filename())
end

return M
