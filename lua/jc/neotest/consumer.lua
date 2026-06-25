-- Optional neotest consumer that auto-closes the summary after an all-green
-- run. Wire it:
--   neotest.setup({ consumers = { jc = require("jc").neotest_consumer() } })
--
-- Auto-close is scoped to focused runs (cursor / file / class). A whole-suite
-- run (:JCtestSuite) is split by neotest into several independent sub-runs with
-- gaps between them (each module precompiles and spawns its own JVM), so no
-- event reliably means "the entire suite finished" — and you usually want to
-- read a suite's summary anyway. jc.test sets `suppressed` while a suite runs.
local M = {}

-- set by jc.test: true around a :JCtestSuite run, false for focused runs
M.suppressed = false

-- delay (ms) before closing after an all-green run, or nil when disabled. On by
-- default; setup{ test = { autoclose_summary = false } } keeps it open.
local function autoclose_delay()
  local ok, jc = pcall(require, "jc")
  local v = ok and jc.config and jc.config.test and jc.config.test.autoclose_summary
  if v == false then
    return nil
  end
  return type(v) == "number" and v or 2000
end

function M.consumer(client)
  client.listeners.results = function(_adapter_id, results, partial)
    if partial then
      return -- the final call carries this run's complete results
    end
    if M.suppressed then
      return -- suite run: leave the summary open
    end
    local delay = autoclose_delay()
    if not delay then
      return
    end
    -- count this run's results (the event arg is scoped to this run, unlike
    -- get_results which accumulates across runs); any failure keeps it open
    local passed, failed = 0, 0
    for _, result in pairs(results) do
      if result.status == "failed" then
        failed = failed + 1
      elseif result.status == "passed" then
        passed = passed + 1
      end
    end
    if failed == 0 and passed > 0 then
      vim.defer_fn(function()
        pcall(function()
          require("neotest").summary.close()
        end)
      end, delay)
    end
  end
  return client
end

return M
