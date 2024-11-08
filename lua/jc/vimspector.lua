local M = {}
local settings = require("jc.settings")
local lsp = require("jc.lsp")

local function ask_for(name, default)
  local default_result = settings.read_project("debug-" .. name, default)
  local result = vim.fn.input("Debug " .. name .. " (" .. default_result .. "): ")
  if #result == 0 then
    result = default_result
  elseif result ~= default_result then
    settings.write_project("debug-" .. name, result)
  end
  return result
end

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
              args = ask_for("arguments", ""),
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
end

function M.debug_attach()
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
            host = ask_for("host", "127.0.0.1"),
            port = ask_for("port", "9000"),
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
end

function M.debug_choose_configuration()
  local prompt = "Choose vimspector configuration:\n"
  local configs = vim.fn["vimspector#GetConfigurations"]()
  for i, config in ipairs(configs) do
    prompt = prompt .. i .. ". " .. config .. "\n"
  end
  prompt = prompt .. "Your choice: "
  local choice = tonumber(vim.fn.input(prompt))
  lsp.executeCommand({ command = "vscode.java.startDebugSession" }, function(response)
    vim.fn["vimspector#LaunchWithSettings"]({ configuration = configs[choice], AdapterPort = response })
  end)
end

return M
