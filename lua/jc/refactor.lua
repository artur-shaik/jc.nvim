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

return M
