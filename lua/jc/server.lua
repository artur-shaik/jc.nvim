local Job = require("jc.jobs")
local M = {}
local data_dir = vim.fn["project_root#get_basedir"]("data")
local vendor_dir = vim.fn["project_root#get_basedir"]("vendor")
local project_name = vim.fn.substitute(vim.fn["project_root#find"](), "[\\/:;.]", "_", "g")
local workspace_dir = vim.fn["project_root#get_basedir"]("workspaces") .. project_name

local function build_java_debug_plugin()
  local mvn_exec = { "mvn", "-f", vendor_dir .. "java-debug", "clean", "install" }
  local env = vim.loop.os_environ()
  env["LC_CTYPE"] = "C"
  Job
    :new(
      { exec = mvn_exec, title = "COMPILING java-debug plugin" },
      { env = env, cwd = vendor_dir .. "java-debug" },
      function(_)
        vim.notify("java-debug successfully installed")
        M.jdtls_setup(M.config)
      end,
      function(job, ec)
        job.output:append("JC ERROR: couldn't build java-debug plugin. Exit code: " .. ec)
        job.output:append("JC ERROR: consider to report an issue, please.")
      end
    )
    :execute()
end

local function install_java_debug_plugin(command)
  if not command then
    command = "clone"
  end

  local git_exec = function()
    if command == "clone" then
      return { "git", command, "https://github.com/microsoft/java-debug/", vendor_dir .. "java-debug" }
    else
      return { "git", "pull" }
    end
  end

  local cwd = function()
    if command == "pull" then
      return vendor_dir .. "java-debug"
    end
    return vendor_dir
  end

  Job
    :new(
      { exec = git_exec(), title = command:upper() .. " java-debug repository" },
      { env = vim.loop.os_environ(), cwd = cwd() },
      function(_)
        vim.defer_fn(build_java_debug_plugin, 0)
      end,
      function(job, exit_code)
        if exit_code == 128 then
          install_java_debug_plugin("pull")
        else
          job.output:append("JC ERROR: couldn't clone java-debug plugin. Exit code: " .. exit_code)
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
      config = vim.fn.expand(jdtls_path .. "/config_linux"),
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
  local skip_flag = data_dir .. ".skip-java-debug"
  if vim.fn.filereadable(java_debug) == 0 and vim.fn.filereadable(skip_flag) == 0 then
    local answer = vim.fn.input(
      "No java debug plugin installed. Would you like to install?\n1: Yes\n2: No\nYour answer: "
    )
    if answer == "1" then
      install_java_debug_plugin()
    elseif answer == "2" then
      io.open(skip_flag, "w"):close()
    end
    return false
  end
  return java_debug
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
  return {
    workspace_dir = workspace_dir,
    jdtls = jdtls_path,
    java_debug = java_debug_path,
  }
end

local function lspconfig_setup(paths)
  if not paths then
    return
  end

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
    "--add-opens",
    "java.base/java.util=ALL-UNNAMED",
    "--add-opens",
    "java.base/java.lang=ALL-UNNAMED",
    "-jar",
    paths.jdtls.jar,
    "-configuration",
    paths.jdtls.config,
    "-data",
    paths.workspace_dir,
  }

  local bundles = {
    paths.java_debug,
  }

  require("lspconfig").jdtls.setup({
    root_dir = function()
      return vim.fn.getcwd()
    end,
    on_attach = M.config.on_attach,
    cmd = cmd,
    settings = {
      java = {},
    },
    init_options = {
      bundles = bundles,
    },
  })
end

function M.jdtls_setup(config)
  M.config = config
  lspconfig_setup(resolve_path())
end

return M
