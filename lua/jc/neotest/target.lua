-- Which neotest adapter a run goes to. neotest resolves a path by walking an
-- unordered table of adapters and taking the first whose root is a prefix of
-- it, so a checkout nested inside another project (a git worktree under
-- `.claude/worktrees`, say) is served by the outer project's adapter: the run
-- then shows up in the outer tree, under the worktree's path. jc names the
-- owning adapter instead of leaving the choice to that iteration order.
local M = {}

function M._id(root)
  return "jc:" .. root
end

-- the id of the adapter that owns `path`, registered or not
function M.adapter_id(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local root = require("jc.project").root(path)
  if type(root) ~= "string" or root == "" then
    return nil
  end
  return M._id(root)
end

-- true when the client already knows `id` AND its tree holds `position`.
-- Pinning a run to an adapter without that position runs nothing at all, and
-- jc never registers an adapter itself: one with an empty tree matches every
-- test path in neotest's own lookup.
function M._pinnable(client, id, position)
  if not client or type(client._adapters) ~= "table" or not client._adapters[id] then
    return false
  end
  if not position then
    return true
  end
  local ok, tree = pcall(function()
    return client._state:positions(id, position)
  end)
  return ok and tree ~= nil
end

-- args for neotest.run.run: `position` to run (nil = nearest to the cursor)
-- and the adapter that owns `path`, when neotest can serve it
function M.run_args(position, path, client)
  local args = {}
  if position then
    args[1] = position
  end
  client = client or require("jc.neotest.consumer").client
  local id = M.adapter_id(path or position)
  if id and M._pinnable(client, id, position) then
    args.adapter = id
  end
  return args
end

return M
