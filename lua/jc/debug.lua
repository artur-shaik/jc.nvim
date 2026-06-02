-- Debug backend dispatcher: routes the debug keymaps/commands to either
-- nvim-dap (jc.dap) or vimspector (jc.vimspector).
--
-- Selection order:
--   1. vim.g.jc_debug_backend ("dap" | "vimspector") if set
--   2. auto: nvim-dap available AND vimspector absent -> "dap"
--   3. fallback -> "vimspector"
local M = {}

function M.backend()
  local b = vim.g.jc_debug_backend
  if b == "dap" or b == "vimspector" then
    return b
  end
  if pcall(require, "dap") and vim.fn.exists(":VimspectorReset") == 0 then
    return "dap"
  end
  return "vimspector"
end

function M.debug_attach()
  if M.backend() == "dap" then
    require("jc.dap").debug_attach()
  else
    require("jc.vimspector").debug_attach()
  end
end

function M.debug_launch()
  if M.backend() == "dap" then
    -- nvim-java provides launch configs for the `java` adapter; let dap pick.
    local ok, dap = pcall(require, "dap")
    if ok then
      dap.continue()
    end
  else
    require("jc.vimspector").debug_launch()
  end
end

return M
