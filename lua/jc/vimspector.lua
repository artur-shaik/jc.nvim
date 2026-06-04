local M = {}
local lsp = require("jc.lsp")
local ui = require("jc.ui")

local function resolve_main_class(callback)
  lsp.executeCommand({ command = "vscode.java.resolveMainClass" }, function(response)
    if #response == 1 then
      callback(response[1].mainClass, response[1].projectName)
    elseif #response > 1 then
      vim.ui.select(response, {
        prompt = "Select the main class to be launched:",
        format_item = function(cls)
          return cls.mainClass
        end,
      }, function(cls)
        callback(cls.mainClass, cls.projectName)
      end)
    else
      callback()
    end
  end)
end

local function resolve_classpaths(main_class, project_name, callback)
  lsp.executeCommand({
    command = "vscode.java.resolveClasspath",
    arguments = {
      main_class,
      project_name,
    },
  }, callback, callback)
end

function M.debug_launch()
  resolve_main_class(function(main_class, project_name)
    resolve_classpaths(main_class, project_name, function(classpaths)
      if not classpaths then
        classpaths = { "${workspaceRoot}/" }
      else
        classpaths = classpaths[2]
      end
      ui.ask_for("arguments", "", function(arguments)
        lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(response)
          vim.fn["vimspector#LaunchWithConfigurations"]({
            attach = {
              adapter = {
                name = "vscode-java",
                port = response,
              },
              configuration = {
                request = "launch",
                mainClass = main_class,
                args = arguments,
                classPaths = classpaths,
                console = "integratedTerminal",
              },
              breakpoints = {
                exception = {
                  caught = "N",
                  uncaught = "N",
                },
              },
            },
          })
        end)
      end)
    end)
  end)
end

function M.debug_attach()
  ui.ask_for("host", "127.0.0.1", function(host)
    ui.ask_for("port", "9000", function(port)
      lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(response)
        if type(response) == "number" then
          vim.fn["vimspector#LaunchWithConfigurations"]({
            attach = {
              adapter = {
                name = "vscode-java",
                port = response,
              },
              configuration = {
                request = "attach",
                host = host,
                port = port,
              },
              breakpoints = {
                exception = {
                  caught = "N",
                  uncaught = "N",
                },
              },
            },
          })
        else
          vim.notify(vim.inspect(response), vim.log.levels.WARN)
        end
      end)
    end)
  end)
end

function M.debug_choose_configuration()
  local configs = vim.fn["vimspector#GetConfigurations"]()
  vim.ui.select(configs, { prompt = "Choose vimspector configuration:" }, function(choice)
    if not choice then
      return
    end
    lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(response)
      vim.fn["vimspector#LaunchWithSettings"]({ configuration = choice, AdapterPort = response })
    end)
  end)
end

return M
