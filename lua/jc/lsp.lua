local config = require("jc.config")
local chains = require("jc.chains")()

local M = {}

function M.on_attach(_, bufnr)
  config.initialize_configuration(bufnr)
end

function M.executeCommand(command, callback, on_failure)
  local clients = vim.lsp.buf_get_clients()
  local capableClient = nil

  for _, client in ipairs(clients) do
    for _, serverCommand in ipairs(client.server_capabilities.executeCommandProvider.commands) do
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
    capableClient.request("workspace/executeCommand", command, function(error, response)
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
  local clients = vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == "jdtls" then
      return client
    end
  end
  return nil
end

function M.apply_edit(err, response)
  if response then
    local edit = response
    if response.edit then
      edit = response.edit
    end
    vim.lsp.util.apply_workspace_edit(edit, "utf-16")
  elseif err then
    vim.notify(vim.inspect(err), vim.log.levels.ERROR)
  end
  vim.defer_fn(function()
    chains:execute_next_if_exists()
  end, 600)
end

return M
