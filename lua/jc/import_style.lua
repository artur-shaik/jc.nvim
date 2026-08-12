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

-- flat dotted jdtls settings for a preset, or nil for an unknown name
function M.settings_for(name)
  local p = M.presets[name]
  if not p then
    return nil
  end
  return {
    ["java.completion.importOrder"] = p.import_order,
    ["java.sources.organizeImports.starThreshold"] = p.star,
    ["java.sources.organizeImports.staticStarThreshold"] = p.static_star,
  }
end

local function filename()
  return paths.get_workspace_dir() .. ".import_style"
end

-- the remembered preset name for this project, or nil
function M.load()
  local file = filename()
  if vim.fn.filereadable(file) == 1 then
    local line = (vim.fn.readfile(file)[1] or ""):gsub("%s+$", "")
    if M.presets[line] then
      return line
    end
  end
  return nil
end

function M.save(name)
  if not M.presets[name] then
    return
  end
  local dir = paths.get_workspace_dir()
  if vim.fn.isdirectory(dir) ~= 1 then
    pcall(vim.fn.mkdir, dir, "p")
  end
  vim.fn.writefile({ name }, filename())
end

return M
