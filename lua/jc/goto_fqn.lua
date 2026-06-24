-- Jump to a java source file by its fully-qualified name, like `gf` but for
-- FQNs found in terminals, neotest output, stack traces, etc. The file opens
-- in the last window that showed a java buffer (or a new tab when none),
-- honouring a line number when the token carries one.
local M = {}

-- window id of the most recently focused java buffer; updated by an autocmd
-- registered from jc.setup
M.last_java_win = nil

function M.remember_win(win)
  M.last_java_win = win
end

-- a dotted token is an FQN candidate only if every segment is a java
-- identifier and at least one looks like a class (starts uppercase); this
-- keeps real paths (slashes) and lowercase-only dotted words out.
local function looks_like_fqn(s)
  if not s or s == "" or s:find("/") or not s:find("%.") then
    return false
  end
  local has_class = false
  for seg in (s .. "."):gmatch("([^.]*)%.") do
    if seg == "" or not seg:match("^[%a_$][%w_$]*$") then
      return false
    end
    if seg:match("^%u") then
      has_class = true
    end
  end
  return has_class
end

-- reduce an FQN to the top-level class FQN: drop a "$Nested" suffix and any
-- trailing member segments after the last class (uppercase-initial) segment.
local function class_fqn(fqn)
  fqn = fqn:gsub("%$.*$", "")
  local segs = vim.split(fqn, ".", { plain = true })
  local keep = #segs
  for i = #segs, 1, -1 do
    if segs[i]:match("^%u") then
      keep = i
      break
    end
  end
  return table.concat({ unpack(segs, 1, keep) }, ".")
end

-- parse a token into (class_fqn, line?) or nil. Handles stack frames
-- "at p.C.m(C.java:25)", explicit "p.C:25", and bare "p.C".
function M.parse(token)
  token = token and vim.trim(token) or ""

  local frame, fline = token:match("([%w_%.$]+%.[%w_$<>]+)%([%w_$]+%.java:(%d+)%)")
  if frame and looks_like_fqn(frame) then
    return class_fqn(frame), tonumber(fline)
  end

  local fqn, line = token:match("([%w_%.$]+):(%d+)")
  if fqn and looks_like_fqn(fqn) then
    return class_fqn(fqn), tonumber(line)
  end

  local bare = token:match("[%w_%.$]+")
  if bare and looks_like_fqn(bare) then
    return class_fqn(bare), nil
  end

  return nil
end

-- the FQN-ish token at the cursor: the WORD, falling back to the whole line
-- (a stack frame may sit past the cursor's WORD).
local function token_at_cursor()
  local word = vim.fn.expand("<cWORD>")
  if M.parse(word) then
    return word
  end
  return vim.api.nvim_get_current_line()
end

-- filesystem fallback: map the FQN onto <source-root>/<pkg>/Class.java
local function fs_resolve(fqn)
  local rel = fqn:gsub("%.", "/") .. ".java"
  for _, root in ipairs(require("jc.class_generator").source_roots()) do
    local path = root .. "/" .. rel
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

-- resolve an FQN to a file path, preferring jdtls' symbol index (works from any
-- buffer, including terminals) and falling back to the filesystem.
local function resolve(fqn, on_done)
  local simple = fqn:match("([^.]+)$")
  local client = require("jc.lsp").get_jdtls_client()
  if not client then
    return on_done(fs_resolve(fqn))
  end
  client:request("workspace/symbol", { query = simple }, function(err, res)
    if not err and type(res) == "table" then
      for _, s in ipairs(res) do
        local container = s.containerName or ""
        local cand = container ~= "" and (container .. "." .. s.name) or s.name
        if cand == fqn and s.location and s.location.uri then
          return on_done(vim.uri_to_fname(s.location.uri))
        end
      end
    end
    on_done(fs_resolve(fqn))
  end)
end

-- open path (in the last java window, or a new tab) and place the cursor
local function open(path, line)
  if M.last_java_win and vim.api.nvim_win_is_valid(M.last_java_win) then
    vim.api.nvim_set_current_win(M.last_java_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    vim.cmd("tabedit " .. vim.fn.fnameescape(path))
  end
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
  end
end

-- main entry: resolve the FQN at the cursor and jump. Returns false when no
-- FQN was recognised (so callers can fall back to builtin behaviour).
function M.goto_fqn()
  local fqn, line = M.parse(token_at_cursor())
  if not fqn then
    vim.notify("jc: no java FQN under cursor", vim.log.levels.WARN)
    return false
  end
  resolve(fqn, function(path)
    if path then
      vim.schedule(function()
        open(path, line)
      end)
    else
      vim.schedule(function()
        vim.notify("jc: couldn't resolve " .. fqn, vim.log.levels.ERROR)
      end)
    end
  end)
  return true
end

-- gf replacement: FQN jump when the token is an FQN, builtin gf otherwise.
function M.gf()
  if not M.parse(token_at_cursor()) then
    local ok = pcall(vim.cmd, "normal! gf")
    if not ok then
      vim.notify("jc: no file or FQN under cursor", vim.log.levels.WARN)
    end
    return
  end
  M.goto_fqn()
end

local gf_installed = false

-- global gf override (works in java, terminal-normal and neotest buffers);
-- installed once from jc.setup when mappings are enabled
function M.install_gf()
  if gf_installed then
    return
  end
  gf_installed = true
  vim.keymap.set("n", "gf", M.gf, { desc = "jc: go to file / java FQN" })
end

return M
