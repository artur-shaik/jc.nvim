-- extract refactorings over the jdtls protocol (java/inferSelection +
-- java/getRefactorEdit); nvim-jdtls is not required
local lsp = require("jc.lsp")

local M = {}

local function code_action_params(client, visual)
  local encoding = client.offset_encoding
  local params
  if visual then
    params = vim.lsp.util.make_given_range_params(nil, nil, 0, encoding)
  else
    params = vim.lsp.util.make_range_params(0, encoding)
  end
  params.context = { diagnostics = {} }
  return params
end

local function apply_refactor_edit(err, result, ctx)
  if err then
    vim.notify("jc: refactor failed: " .. err.message, vim.log.levels.ERROR)
    return
  end
  if not result then
    return
  end
  if result.edit then
    local client = ctx and vim.lsp.get_client_by_id(ctx.client_id)
    vim.lsp.util.apply_workspace_edit(result.edit, client and client.offset_encoding or "utf-16")
  end
  -- jdtls may ask for a follow-up command (e.g. rename of the new symbol)
  if result.command then
    lsp.executeCommand(result.command, function() end)
  end
end

local function refactor(cmd, visual)
  local client = lsp.get_jdtls_client()
  if not client then
    vim.notify("jc: no jdtls client attached", vim.log.levels.ERROR)
    return
  end
  local action_params = code_action_params(client, visual)
  local params = {
    command = cmd,
    context = action_params,
    options = {
      tabSize = vim.lsp.util.get_effective_tabstop(),
      insertSpaces = vim.bo.expandtab,
    },
  }
  local bufnr = vim.api.nvim_get_current_buf()
  local range = action_params.range
  local has_selection = range.start.character ~= range["end"].character or range.start.line ~= range["end"].line
  if has_selection then
    client:request("java/getRefactorEdit", params, apply_refactor_edit, bufnr)
    return
  end
  -- cursor position only: let jdtls infer what can be extracted here
  client:request("java/inferSelection", params, function(err, selections)
    if err or not selections or #selections == 0 then
      vim.notify("jc: nothing to extract at cursor", vim.log.levels.WARN)
      return
    end
    local function run(selection)
      params.commandArguments = { selection }
      client:request("java/getRefactorEdit", params, apply_refactor_edit, bufnr)
    end
    if #selections == 1 then
      run(selections[1])
    else
      vim.ui.select(selections, {
        prompt = "Extract:",
        format_item = function(s)
          return s.name
        end,
      }, function(selection)
        if selection then
          run(selection)
        end
      end)
    end
  end, bufnr)
end

-- run a jdtls "java.action.applyRefactoringCommand" code-action command
-- (arguments = { refactoring_kind, context_params }) by asking for the edit
-- and applying it. `on_done(true)` runs after the edit. Returns false if the
-- command isn't a refactoring command.
function M.apply_command(command, on_done)
  local client = lsp.get_jdtls_client()
  if not client or type(command) ~= "table" or command.command ~= "java.action.applyRefactoringCommand" then
    return false
  end
  local kind, context = command.arguments[1], command.arguments[2]
  client:request("java/getRefactorEdit", {
    command = kind,
    context = context,
    options = {
      tabSize = vim.lsp.util.get_effective_tabstop(),
      insertSpaces = vim.bo.expandtab,
    },
  }, function(err, result, ctx)
    apply_refactor_edit(err, result, ctx)
    if on_done then
      -- let the edit apply and the tree refresh before the caller continues
      vim.defer_fn(function()
        on_done(true)
      end, 300)
    end
  end, vim.api.nvim_get_current_buf())
  return true
end

function M.extract_variable(visual)
  refactor("extractVariable", visual)
end

function M.extract_variable_all(visual)
  refactor("extractVariableAllOccurrence", visual)
end

function M.extract_constant(visual)
  refactor("extractConstant", visual)
end

function M.extract_method(visual)
  refactor("extractMethod", visual)
end

-- Climb from the cursor to the nearest method call `receiver.name(arg)` that has
-- a receiver and exactly one argument.
local function call_at_cursor()
  local node = vim.treesitter.get_node()
  while node do
    if node:type() == "method_invocation" then
      local object = node:field("object")[1]
      local args = node:field("arguments")[1]
      if object and args and args:named_child_count() == 1 then
        return object, args:named_child(0)
      end
    end
    node = node:parent()
  end
end

-- Swap the receiver and the single argument of the call at the cursor:
-- `a.equals(b)` -> `b.equals(a)`. Treesitter-based (jdtls has no such
-- refactoring); works for any one-argument call — equals, compareTo, etc.
-- A surrounding `!` or the method name are left untouched.
function M.flip_call_args()
  local object, arg = call_at_cursor()
  if not object then
    vim.notify("jc: no one-argument call at the cursor to flip", vim.log.levels.WARN)
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local object_text = vim.treesitter.get_node_text(object, buf)
  local arg_text = vim.treesitter.get_node_text(arg, buf)

  local function replace(node, text)
    local sr, sc, er, ec = node:range()
    vim.api.nvim_buf_set_text(buf, sr, sc, er, ec, vim.split(text, "\n"))
  end
  -- edit the argument first (it sits later in the buffer) so the receiver's
  -- range stays valid for the second edit
  replace(arg, object_text)
  replace(object, arg_text)
end

-- Strip a destination's package segments off one of its location strings (its
-- workspace `path` or its absolute `uri`) to get the source root. Both end with
-- the package rendered as a path; the default package is already the root.
function M._strip_package(location, display_name)
  if not location then
    return nil
  end
  local rel = (display_name or ""):gsub("%.", "/")
  if rel == "" then
    return location
  end
  return (location:gsub("/" .. vim.pesc(rel) .. "$", ""))
end

-- Build a destination for a not-yet-existing package by deriving both the
-- workspace path and the absolute uri from `base` (they strip to different
-- roots, so keep them separate). Returns nil when they can't be derived.
function M._derive_destination(pkg, base)
  local root_path = M._strip_package(base.path, base.displayName)
  local root_uri = M._strip_package(base.uri, base.displayName)
  if not root_path or not root_uri then
    return nil
  end
  local seg = pkg == "" and "" or ("/" .. pkg:gsub("%.", "/"))
  return {
    project = base.project,
    displayName = pkg,
    path = root_path .. seg,
    uri = root_uri .. seg,
    isDefaultPackage = pkg == "",
    isParentOfSelectedFile = false,
  }
end

-- Move the current file (class) to another package/source root, updating every
-- reference. jdtls' two-step protocol: getMoveDestinations -> pick -> move.
-- This is the moveResource kind; nvim-jdtls handled it before jc dropped that
-- dependency, so it's reimplemented natively here. A package that doesn't exist
-- yet is created on disk (and announced to jdtls) first, since java/move only
-- targets existing folders.
function M.move()
  local client = lsp.get_jdtls_client()
  if not client then
    vim.notify("jc: no jdtls client attached", vim.log.levels.ERROR)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufnr)
  local dest_params = {
    moveKind = "moveResource",
    sourceUris = { uri },
    params = vim.NIL,
  }
  client:request("java/getMoveDestinations", dest_params, function(err, result)
    if err or not result or type(result.destinations) ~= "table" or #result.destinations == 0 then
      vim.schedule(function()
        vim.notify("jc: no move destinations available", vim.log.levels.WARN)
      end)
      return
    end
    local destinations = result.destinations
    local by_name = {}
    local items = {}
    for _, d in ipairs(destinations) do
      local name = d.isDefaultPackage and "" or (d.displayName or "")
      by_name[name] = d
      local label = d.isDefaultPackage and "(default package)" or (name ~= "" and name or d.path)
      items[#items + 1] = string.format("%s  [%s]", label, d.project or "?")
    end

    local filename = vim.fn.fnamemodify(vim.uri_to_fname(uri), ":t")

    local function send_move(destination)
      local move_params = {
        moveKind = "moveResource",
        sourceUris = { uri },
        params = code_action_params(client, false),
        destination = destination,
        updateReferences = true,
      }
      client:request("java/move", move_params, function(merr, mresult, mctx)
        if merr then
          vim.notify("jc: move failed: " .. (merr.message or vim.inspect(merr)), vim.log.levels.ERROR)
        elseif mresult and mresult.errorMessage then
          vim.notify("jc: move failed: " .. mresult.errorMessage, vim.log.levels.ERROR)
        elseif not mresult or not mresult.edit then
          vim.notify("jc: move returned no changes", vim.log.levels.WARN)
        else
          apply_refactor_edit(nil, mresult, mctx)
          -- open the moved file at its new path and refresh its module's config
          -- so it's treated as a project file, not a standalone one
          local new_uri = destination.uri .. "/" .. filename
          vim.schedule(function()
            vim.cmd.edit(vim.uri_to_fname(new_uri))
            client:notify("java/projectConfigurationUpdate", { uri = new_uri })
          end)
        end
      end, bufnr)
    end

    -- java/move only targets folders jdtls already models. Create the package
    -- dir on disk, announce it, and force a project-configuration update so the
    -- new folder becomes a real source package (otherwise the moved file lands
    -- as a "non-project file"); only then move.
    local function create_then_move(destination)
      local dir = vim.uri_to_fname(destination.uri)
      if vim.fn.isdirectory(dir) == 0 and vim.fn.mkdir(dir, "p") == 0 then
        vim.notify("jc: could not create package folder " .. dir, vim.log.levels.ERROR)
        return
      end
      client:notify("workspace/didChangeWatchedFiles", {
        changes = { { uri = destination.uri, type = 1 } }, -- 1 = Created
      })
      -- update the config of the source project (the current file's module) so
      -- jdtls rescans and picks up the freshly-created package
      client:notify("java/projectConfigurationUpdate", { uri = uri })
      vim.defer_fn(function()
        send_move(destination)
      end, 600)
    end

    vim.schedule(function()
      vim.ui.select(items, { prompt = "Move to package:" }, function(_, idx)
        if not idx then
          return
        end
        -- let the user retype the package or append a new sub-package to it
        vim.ui.input({ prompt = "Package: ", default = destinations[idx].displayName or "" }, function(input)
          if not input then
            return
          end
          local pkg = vim.trim(input)
          if by_name[pkg] then
            send_move(by_name[pkg])
            return
          end
          local destination = M._derive_destination(pkg, destinations[idx])
          if not destination then
            vim.notify("jc: could not resolve destination package", vim.log.levels.WARN)
            return
          end
          create_then_move(destination)
        end)
      end)
    end)
  end, bufnr)
end

return M
