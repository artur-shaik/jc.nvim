local Job = require("jc.jobs")
local path = require("jc.path")
local M = {}

local function build_plugin(name)
  local mvn_exec = { "mvn", "-Dmaven.javadoc.skip=true", "-Dmaven.test.skip=true", "-f", path.get_vendor_dir() .. name, "clean", "install" }
  local env = vim.loop.os_environ()
  env["LC_CTYPE"] = "C"
  Job
    :new(
      { exec = mvn_exec, title = "COMPILING " .. name .. " plugin" },
      { env = env, cwd = path.get_vendor_dir() .. name },
      function(_)
        vim.notify(name .. " successfully installed")
        M.jdtls_setup(M.config)
      end,
      function(job, ec)
        job.output:append("JC ERROR: couldn't build " .. name .. " plugin. Exit code: " .. ec)
        job.output:append("JC ERROR: consider to report an issue, please.")
      end
    )
    :execute()
end

local function install_from_git(command, name, url)
  if not command then
    command = "clone"
  end

  local git_exec = function()
    if command == "clone" then
      return { "git", command, url, path.get_vendor_dir() .. name }
    else
      return { "git", "pull" }
    end
  end

  local cwd = function()
    if command == "pull" then
      return path.get_vendor_dir() .. name
    end
    return path.get_vendor_dir()
  end

  Job
    :new(
      { exec = git_exec(), title = command:upper() .. " " .. name .. " repository" },
      { env = vim.loop.os_environ(), cwd = cwd() },
      function(_)
        vim.defer_fn(function()
          build_plugin(name)
        end, 0)
      end,
      function(job, exit_code)
        if exit_code == 128 then
          install_from_git("pull", name, url)
        else
          job.output:append("JC ERROR: couldn't clone " .. name .. " plugin. Exit code: " .. exit_code)
          job.output:append("JC ERROR: consider to report an issue, please.")
        end
      end
    )
    :execute()
end

local function download_jdtls()
  local ok, installer = pcall(require, "nvim-lsp-installer")
  assert(ok, "nvim-lsp-installer is not installed")

  local servers = require("nvim-lsp-installer.servers")

  vim.notify("Installing JDTLS language server...", vim.log.levels.INFO)
  installer.install("jdtls")

  local timer = vim.loop.new_timer()
  timer:start(2000, 1500, function()
    if servers.is_server_installed("jdtls") then
      timer:close()
      installer.info_window.close()
      vim.defer_fn(function()
        M.jdtls_setup(M.config)
        vim.notify("JDTLS language server installed, completion should work now", vim.log.levels.INFO)
      end, 100)
    end
  end)
end

local function resolve_jdtls()
  local ok, servers = pcall(require, "nvim-lsp-installer.servers")
  assert(ok, "nvim-lsp-installer is not installed")

  if servers.is_server_installed("jdtls") then
    local jdtls_path = servers.get_server_install_path("jdtls")
    return {
      jar = vim.fn.expand(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"),
      config = vim.fn.expand(jdtls_path .. "/config_" .. vim.g["utils#OS"]),
      lombok = vim.fn.expand(jdtls_path .. "/lombok.jar"),
    }
  else
    vim.defer_fn(download_jdtls, 1)
    return false
  end
end

local function resolve_java_debug()
  local java_debug = vim.fn.expand(
    "~/.m2/repository/com/microsoft/java/com.microsoft.java.debug.plugin/*/com.microsoft.java.debug.plugin-*.jar"
  )
  local skip_flag = path.get_workspace_dir() .. ".skip-java-debug"
  if vim.fn.filereadable(java_debug) == 0 and vim.fn.filereadable(skip_flag) == 0 then
    local answer = vim.fn.input(
      "No java debug plugin installed. Would you like to install?\n1: Yes\n2: No\nYour answer: "
    )
    if answer == "1" then
      install_from_git(nil, "java-debug", "https://github.com/microsoft/java-debug/")
    elseif answer == "2" then
      io.open(skip_flag, "w"):close()
    end
    return false
  end
  return java_debug
end

local function resolve_jol()
  local jol_path = vim.fn.expand("~/.m2/repository/org/openjdk/jol/jol-cli/*/jol-cli-*-full.jar")
  local skip_flag = path.get_workspace_dir() .. ".skip-jol"
  if vim.fn.filereadable(jol_path) == 0 and vim.fn.filereadable(skip_flag) == 0 then
    local answer = vim.fn.input("Jol is not installed. Would you like to install it?\n1: Yes\n2: No\nYour answer: ")
    if answer == "1" then
      install_from_git(nil, "jol", "https://github.com/openjdk/jol")
    elseif answer == "2" then
      io.open(skip_flag, "w"):close()
    end
    return false
  end
  return jol_path
end

local function resolve_path()
  local jdtls_path = resolve_jdtls()
  if not jdtls_path then
    return false
  end
  local java_debug_path = resolve_java_debug()
  if not java_debug_path then
    return false
  end
  local jol_path = resolve_jol()
  if not jol_path then
    return false
  elseif pcall(require, "jdtls") then
    require("jdtls").jol_path = jol_path
  end
  return {
    workspace_dir = path.get_project_dirs().workspace_dir,
    jdtls = jdtls_path,
    java_debug = java_debug_path,
  }
end

local function lspconfig_setup(paths)
  if not paths then
    return
  end

  local settings = {
    java = {},
  }

  if M.config["settings"] ~= nil then
    settings = M.config["settings"]
  end

  -- stylua: ignore
  local cmd = {
    M.config.java_exec,
    "-javaagent:" .. paths.jdtls.lombok,
    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
    "-Dosgi.bundles.defaultStartLevel=4",
    "-Declipse.product=org.eclipse.jdt.ls.core.product",
    "-Dlog.protocol=true",
    "-Dlog.level=ALL",
    "-Xms1g",
    "--add-modules=ALL-SYSTEM",
    "--add-opens", "java.base/java.util=ALL-UNNAMED",
    "--add-opens", "java.base/java.lang=ALL-UNNAMED",
    "-jar", paths.jdtls.jar,
    "-configuration", paths.jdtls.config,
    "-data", paths.workspace_dir,
  }

  local bundles = {
    paths.java_debug,
  }

  require("lspconfig").jdtls.setup({
    name = "jdtls",
    root_dir = function()
      return vim.fn.getcwd()
    end,
    on_attach = M.config.jc_on_attach,
    cmd = cmd,
    settings = settings,
    init_options = {
      bundles = bundles,
      extendedClientCapabilities = {
        progressReportProvider = true,
        classFileContentsSupport = true,
        generateToStringPromptSupport = true,
        hashCodeEqualsPromptSupport = true,
        advancedExtractRefactoringSupport = true,
        advancedOrganizeImportsSupport = true,
        generateConstructorsPromptSupport = true,
        generateDelegateMethodsPromptSupport = true,
        moveRefactoringSupport = true,
        overrideMethodsPromptSupport = true,
        inferSelectionSupport = { "extractMethod", "extractVariable", "extractConstant" },
      },
      workspace = path.get_project_dirs().workspace_dir,
    },
  })
  require("lspconfig.configs")["jdtls"].launch()
end

function M.jdtls_setup(config)
  M.config = config
  lspconfig_setup(resolve_path())
end

return M
