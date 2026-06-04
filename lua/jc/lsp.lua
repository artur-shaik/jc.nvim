local config = require("jc.config")
local chains = require("jc.chains")()

local M = {}

-- delay between chained code-gen commands (see apply_edit)
M.chain_delay_ms = 600

function M.on_attach(conf, _, bufnr)
  config.initialize_configuration(conf, bufnr)
end

function M.executeCommand(command, callback, on_failure)
  local clients = vim.lsp.get_clients()
  local capableClient = nil

  for _, client in pairs(clients) do
    local provider = client.server_capabilities.executeCommandProvider
    for _, serverCommand in ipairs(provider and provider.commands or {}) do
      if serverCommand == command.command then
        capableClient = client
        break
      end
    end
    if capableClient then
      break
    end
  end

  if not capableClient then
    callback({ error = "No capable client found for this command" }, nil)
  else
    capableClient:request("workspace/executeCommand", command, function(error, response)
      if error then
        if on_failure then
          on_failure()
        else
          vim.notify(vim.inspect(error), vim.log.levels.ERROR)
        end
      else
        callback(response)
      end
    end)
  end
end

function M.get_jdtls_client()
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if client.name == "jdtls" then
      return client
    end
  end
  return nil
end

function M.apply_edit(err, response, ctx)
  if response then
    local edit = response
    if response.edit then
      edit = response.edit
    end
    local encoding = "utf-16"
    if ctx and ctx.client_id then
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      if client then
        encoding = client.offset_encoding
      end
    end
    vim.lsp.util.apply_workspace_edit(edit, encoding)
  elseif err then
    vim.notify(vim.inspect(err), vim.log.levels.ERROR)
  end
  -- jdtls needs time to apply the edit and refresh diagnostics before the
  -- next chained command (e.g. generate_abstractMethods reads diagnostics)
  vim.defer_fn(function()
    chains:execute_next_if_exists()
  end, M.chain_delay_ms)
end

return M
