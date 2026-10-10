-- Re-read a test file before it is run. neotest rediscovers a file only on
-- BufAdd/BufWritePost, so a test written straight to disk (an agent, a git
-- checkout, a sibling editor) stays invisible to a rerun until the buffer is
-- saved by hand. Two things go stale: the loaded buffer, which is what
-- treesitter parses when there is one, and neotest's position tree.
local M = {}

-- reload the buffer for `path`, if one is loaded and has nothing unsaved
-- (checktime on a modified buffer prompts about the conflict)
function M._reload_buf(path)
  local buf = vim.fn.bufnr(path)
  if buf == -1 or vim.fn.bufloaded(buf) == 0 or vim.bo[buf].modified then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! checktime")
  end)
end

-- jdtls tracks the files it was told about, so without this its `bin` output
-- (the classpath source when precompile is off) keeps the stale class
local function notify_jdtls(paths)
  local changes = {}
  for _, path in ipairs(paths) do
    changes[#changes + 1] = { uri = vim.uri_from_fname(path), type = 2 } -- Changed
  end
  if #changes > 0 then
    pcall(function()
      require("jc.lsp").jdtls_notify("workspace/didChangeWatchedFiles", { changes = changes })
    end)
  end
end

-- the paths worth refreshing: readable files, no duplicates
function M._targets(paths)
  local seen, out = {}, {}
  for _, path in ipairs(paths or {}) do
    if type(path) == "string" and path ~= "" and not seen[path] and vim.fn.filereadable(path) == 1 then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

-- how long to wait for the reparse before starting the run anyway. Discovery
-- of a single known file is quick; anything slower is not worth a stalled run.
local TIMEOUT_MS = 2000

-- Only reparse for a client neotest has already started. On a cold client
-- _update_positions runs _ensure_started, which spawns neotest's child process
-- over a blocking rpcrequest - and when that child cannot load its plugins the
-- run hangs instead of starting. A cold client discovers the file on its own
-- when the run asks for it.
local function can_reparse(client)
  return client ~= nil and client._started == true
end

-- reload `paths`, have neotest reparse them, then call `done`. `done` runs
-- right away when there is nothing to do, when the jc consumer is not wired
-- into neotest (that is where the client comes from), or when nio is missing;
-- and after TIMEOUT_MS regardless. The run must start either way.
function M.before_run(paths, done)
  paths = M._targets(paths)
  for _, path in ipairs(paths) do
    M._reload_buf(path)
  end
  notify_jdtls(paths)

  local client = require("jc.neotest.consumer").client
  local ok_nio, nio = pcall(require, "nio")
  if #paths == 0 or not can_reparse(client) or not ok_nio then
    return done()
  end

  local fired = false
  local function start_run()
    if fired then
      return
    end
    fired = true
    done()
  end
  vim.defer_fn(start_run, TIMEOUT_MS)

  local ok = pcall(nio.run, function()
    for _, path in ipairs(paths) do
      pcall(function()
        client:_update_positions(path)
      end)
    end
  end, function()
    vim.schedule(start_run)
  end)
  if not ok then
    start_run()
  end
end

return M
