local lsp = require("jc.lsp")
local regular_imports = require("jc.regular_imports")
local apply_edit = require("jc.lsp").apply_edit

local M = {}

-- make_range_params with the jdtls client's offset encoding
-- (calling it without one is deprecated since nvim 0.11)
local function make_range_params()
  local client = lsp.get_jdtls_client()
  local encoding = client and client.offset_encoding or "utf-16"
  return vim.lsp.util.make_range_params(0, encoding)
end

-- run a code-generation status request, retrying while jdtls hasn't finished
-- building the model for a just-created class (the request errors until then,
-- which would silently skip the generator buffer); `build` re-creates params
-- per attempt so the cursor encoding stays current
local function request_status(method, build, on_ok, tries)
  tries = tries or 10
  lsp.jdtls_request(0, method, build(), function(err, resp)
    if resp then
      on_ok(resp)
    elseif tries > 1 then
      vim.defer_fn(function()
        request_status(method, build, on_ok, tries - 1)
      end, 200)
    else
      vim.notify("jc: " .. method .. " failed: " .. vim.inspect(err), vim.log.levels.WARN)
    end
  end)
end

local function choose_imports(params, _)
  local candidates = params.arguments[2][1].candidates
  local regulars = regular_imports()
  local known = regulars:load()
  local to_forget = {}
  local prompt = "Choose candidate:\n"
  for i, candidate in ipairs(candidates) do
    prompt = prompt .. i .. ". " .. candidate.fullyQualifiedName .. "\n"
    for _, value in ipairs(known) do
      if value == candidate.fullyQualifiedName then
        if M.organize_imports_smart then
          return { candidate }
        else
          table.insert(to_forget, candidate.fullyQualifiedName)
        end
      end
    end
  end
  for _, name in ipairs(to_forget) do
    regulars:remove(name)
  end
  -- blocking input is intentional: this runs inside the synchronous
  -- workspace/executeClientCommand handler and must return the chosen
  -- candidate to jdtls; async vim.ui.select can't do that
  local choice = tonumber(vim.fn.input(prompt .. "Your choice: "))

  if candidates[choice] ~= nil then
    regulars:add(candidates[choice].fullyQualifiedName)
  end
  return { candidates[choice] }
end

local function set_configuration(settings)
  -- didChangeConfiguration is a notification, and only jdtls should get it
  lsp.jdtls_notify("workspace/didChangeConfiguration", { settings = settings })
end

local client_commands = {
  ["java.action.organizeImports.chooseImports"] = choose_imports,
}

vim.lsp.handlers["workspace/executeClientCommand"] = function(_, params, ctx)
  if client_commands[params.command] ~= nil then
    return client_commands[params.command](params, ctx)
  end

  return ""
end

local function document_symbols(callback)
  lsp.jdtls_request(
    0,
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params() },
    function(err, resp)
      if resp then
        callback(resp)
      elseif err then
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
    end
  )
end

local function filter_fields(symbols)
  local fields = {}
  for _, node in ipairs(symbols[2].children) do
    if node.kind == 8 then
      table.insert(fields, node)
    end
  end

  return fields
end

function M.generate_accessor(accessor)
  document_symbols(function(symbols)
    require("jc.generators").accessor(filter_fields(symbols), accessor)
  end)
end

function M.generate_accessors(fields)
  if not fields then
    request_status("java/resolveUnimplementedAccessors", function()
      local params = make_range_params()
      params.kind = 2
      return params
    end, function(resp)
      require("jc.generators").accessors(resp)
    end)
  else
    set_configuration({
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    lsp.jdtls_request(0, "java/generateAccessors", {
      context = make_range_params(),
      accessors = fields,
    }, apply_edit)
  end
end

function M.generate_abstractMethods()
  local curbuf = vim.api.nvim_get_current_buf()
  local diagnostics = {}
  local line = 0
  for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
    if diagnostic.code == "67109264" then
      if line == 0 then
        line = diagnostic.lnum
      end
      table.insert(diagnostics, {
        code = diagnostic.code,
        message = diagnostic.message,
        severity = 1,
        source = "Java",
        range = {
          start = {
            character = diagnostic.col,
            line = diagnostic.lnum,
          },
          ["end"] = {
            character = diagnostic.end_col,
            line = diagnostic.end_lnum,
          },
        },
      })
    end
  end
  -- no unimplemented methods -> nothing to do, but keep the chain moving
  if #diagnostics == 0 then
    lsp.advance_chain()
    return
  end
  local params = make_range_params()
  params.context = {
    diagnostics = diagnostics,
  }
  params.range = {
    start = {
      character = 0,
      line = line,
    },
    ["end"] = {
      character = 0,
      line = line,
    },
  }
  lsp.jdtls_request(curbuf, "textDocument/codeAction", params, function(err, actions)
    local add_method_action = nil
    for _, action in ipairs(actions or {}) do
      if action.title == "Add unimplemented methods" then
        add_method_action = action
        break
      end
    end
    if add_method_action then
      lsp.jdtls_request(curbuf, "codeAction/resolve", add_method_action, apply_edit)
    else
      -- nothing applicable; advance the chain instead of stalling it
      if err then
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
      lsp.advance_chain()
    end
  end)
end

function M.generate_constructor(fields, params, opts)
  if fields == nil then
    request_status("java/checkConstructorsStatus", make_range_params, function(resp)
      require("jc.generators").constructor(resp.fields, resp.constructors, opts)
    end)
  else
    set_configuration({
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    if params.default_constructor then
      fields = {}
    end
    local context = make_range_params()
    context.context = {
      diagnostics = {},
      only = nil,
    }
    lsp.jdtls_request(0, "java/generateConstructors", {
      context = context,
      fields = fields,
      constructors = params.constructors,
    }, apply_edit)
  end
end

function M.generate_hashCodeAndEquals(fields)
  if not fields then
    request_status("java/checkHashCodeEqualsStatus", make_range_params, function(resp)
      require("jc.generators").hashCodeEquals(resp.fields)
    end)
  else
    set_configuration({
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    lsp.jdtls_request(0, "java/generateHashCodeEquals", {
      context = make_range_params(),
      fields = fields,
      regenerate = true,
    }, apply_edit)
  end
end

function M.generate_toString(fields, params)
  if not fields then
    request_status("java/checkToStringStatus", make_range_params, function(resp)
      require("jc.generators").toString(resp.fields)
    end)
  else
    set_configuration({
      ["java.codeGeneration.toString.codeStyle"] = params.code_style,
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    lsp.jdtls_request(0, "java/generateToString", {
      context = make_range_params(),
      fields = fields,
    }, apply_edit)
  end
end

-- apply a code action — a direct workspace edit, a jdtls refactoring command
-- (java.action.applyRefactoringCommand), a generic command, or one that still
-- needs codeAction/resolve. `on_result(found)` runs after it's applied.
local function apply_action(action, on_result)
  if action.edit then
    apply_edit(nil, action)
    if on_result then
      vim.defer_fn(function()
        on_result(true)
      end, 300)
    end
    return
  end
  local command = action.command
  if type(command) == "table" then
    if require("jc.refactor").apply_command(command, on_result) then
      return
    end
    lsp.executeCommand({ command = command.command, arguments = command.arguments }, function()
      if on_result then
        on_result(true)
      end
    end)
    return
  end
  -- not resolved yet -> resolve then re-dispatch
  lsp.jdtls_request(0, "codeAction/resolve", action, function(_, resolved)
    if resolved then
      apply_action(resolved, on_result)
    elseif on_result then
      on_result(false)
    end
  end)
end

-- "Convert to static import" at the cursor, picking the action straight from
-- jdtls without the code-action menu. `all` prefers the all-occurrences
-- variant (e.g. Math.max(...) -> import static ...Math.max; max(...)).
-- `on_result(found)` runs after the edit (or when nothing matched).
function M.convert_static_import(all, on_result)
  local params = make_range_params()
  params.context = { diagnostics = {} }
  lsp.jdtls_request(0, "textDocument/codeAction", params, function(err, actions)
    local match
    for _, action in ipairs(actions or {}) do
      local title = (action.title or ""):lower()
      if title:find("static import", 1, true) then
        local is_all = title:find("all occurrences", 1, true) ~= nil
        if all == is_all then
          match = action
          break
        end
        match = match or action -- fall back to the other variant
      end
    end
    if match then
      apply_action(match, on_result)
    else
      if err then
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
      if on_result then
        on_result(false)
      else
        vim.notify("jc: no static-import conversion at the cursor", vim.log.levels.WARN)
      end
    end
  end)
end

-- find a live "qualifier.member" occurrence in code (skipping import lines, so
-- a freshly-added `import static ...` isn't matched) and return the 0-based
-- cursor position on the member
local function find_member_use(qualifier, member)
  local needle = qualifier .. "." .. member
  for ln, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if not line:match("^%s*import%s") then
      local s = line:find(needle, 1, true)
      if s then
        return { ln - 1, s - 1 + #qualifier + 1 } -- on the member, past "qualifier."
      end
    end
  end
  return nil
end

-- convert every constant of the enum under the cursor to a static import. The
-- constant names are collected once; each is converted (all occurrences) in
-- turn, re-locating it by text so buffer edits don't invalidate positions.
function M.static_import_enum()
  local ts = require("jc.treesitter")
  local qualifier = ts.qualifier_at_cursor()
  if not qualifier then
    vim.notify("jc: place the cursor on an enum constant (Enum.CONST)", vim.log.levels.WARN)
    return
  end
  local names = ts.qualified_member_names(qualifier)
  local i = 0
  local function step()
    i = i + 1
    local member = names[i]
    if not member then
      return -- all converted
    end
    local pos = find_member_use(qualifier, member)
    if not pos then
      return step() -- already gone (e.g. fully qualified elsewhere)
    end
    vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
    M.convert_static_import(true, function()
      vim.defer_fn(step, 350)
    end)
  end
  step()
end

function M.organize_imports(bn, smart)
  M.organize_imports_smart = smart
  lsp.jdtls_request(bn, "java/organizeImports", make_range_params(), apply_edit)
end

-- jdt.ls declares java/projectConfigurationUpdate as a JsonNotification:
-- there is never a response, so send a notification (nvim-jdtls sends a
-- request and its success therefore looks like "nothing happened")
function M.update_project_config(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local client = lsp.get_jdtls_client()
  if not client then
    if not opts.silent then
      vim.notify("jc: no jdtls client attached", vim.log.levels.ERROR)
    end
    return
  end
  client:notify("java/projectConfigurationUpdate", { uri = vim.uri_from_bufnr(bufnr) })
  if not opts.silent then
    vim.notify("jc: project configuration update requested", vim.log.levels.INFO)
  end
end

local function data_dir_from_args(args)
  for i, arg in ipairs(args) do
    if arg == "-data" then
      return args[i + 1]
    end
  end
  return nil
end

local function data_dir_from_cmdline_string(s)
  return s:match('%-data%s+"([^"]+)"') or s:match("%-data%s+(%S+)")
end

-- jdtls runs as a child process of nvim; its cmdline contains -data even
-- when the client config builds the command with a function (nvim-java)
local function data_dir_from_proc()
  local my_pid = tostring(vim.fn.getpid())
  if vim.fn.has("linux") == 1 then
    -- /proc cmdline is NUL-separated, lossless even with spaces in paths
    for _, pid in ipairs(vim.fn.systemlist({ "pgrep", "-P", my_pid })) do
      local f = io.open("/proc/" .. pid .. "/cmdline", "r")
      if f then
        local cmdline = f:read("*a")
        f:close()
        local data_dir = data_dir_from_args(vim.split(cmdline, "\0"))
        if data_dir then
          return data_dir
        end
      end
    end
  elseif vim.fn.has("mac") == 1 or vim.fn.has("bsd") == 1 then
    for _, pid in ipairs(vim.fn.systemlist({ "pgrep", "-P", my_pid })) do
      local data_dir = data_dir_from_cmdline_string(vim.fn.system({ "ps", "-o", "command=", "-p", pid }))
      if data_dir then
        return data_dir
      end
    end
  elseif vim.fn.has("win32") == 1 then
    local out = vim.fn.system({
      "powershell",
      "-NoProfile",
      "-Command",
      "(Get-CimInstance Win32_Process -Filter 'ParentProcessId=" .. my_pid .. "').CommandLine",
    })
    return data_dir_from_cmdline_string(out)
  end
  return nil
end

-- nvim-java derives the workspace path from cwd deterministically; ask its
-- util as a portable last resort (approximate: assumes cwd didn't change
-- since the server started)
local function data_dir_from_nvim_java()
  local ok, java_lsp = pcall(require, "java-core.utils.lsp")
  if ok and java_lsp.get_jdtls_cache_data_path then
    return java_lsp.get_jdtls_cache_data_path(vim.fn.getcwd())
  end
  return nil
end

-- delete the jdtls workspace (-data dir, i.e. the eclipse index — the
-- usual fix for a corrupted project state) and restart the server with
-- the same configuration, whoever owns it (nvim-java, lspconfig, ...)
function M.wipe_workspace()
  local client = lsp.get_jdtls_client()
  if not client then
    vim.notify("jc: no jdtls client attached", vim.log.levels.ERROR)
    return
  end
  local data_dir
  if type(client.config.cmd) == "table" then
    data_dir = data_dir_from_args(client.config.cmd)
  end
  data_dir = data_dir or data_dir_from_proc() or data_dir_from_nvim_java()
  if not data_dir or vim.fn.isdirectory(data_dir) ~= 1 then
    vim.notify("jc: couldn't determine jdtls workspace (-data) directory", vim.log.levels.ERROR)
    return
  end
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete jdtls workspace " .. data_dir .. " and restart LSP?",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end
    local config = client.config
    local client_id = client.id
    local bufnr = vim.api.nvim_get_current_buf()
    client:stop()
    local tries = 0
    local timer = vim.uv.new_timer()
    timer:start(
      100,
      100,
      vim.schedule_wrap(function()
        tries = tries + 1
        if not vim.lsp.get_client_by_id(client_id) then
          timer:stop()
          timer:close()
          vim.fn.delete(data_dir, "rf")
          vim.api.nvim_buf_call(bufnr, function()
            vim.lsp.start(config)
          end)
          vim.notify("jc: workspace wiped, jdtls restarted", vim.log.levels.INFO)
        elseif tries == 30 then
          client:stop(true) -- graceful shutdown is taking too long
        elseif tries > 50 then
          timer:stop()
          timer:close()
          vim.notify("jc: jdtls didn't stop, workspace not deleted", vim.log.levels.ERROR)
        end
      end)
    )
  end)
end

function M.read_class_content(uri)
  local client = lsp.get_jdtls_client()
  if not client then
    vim.notify("LSP client not found", vim.log.levels.ERROR)
    return
  end

  local response = client:request_sync("java/classFileContents", { uri = uri })
  if not response or response.err or not response.result then
    vim.notify("jc: couldn't load class contents: " .. vim.inspect(response and response.err), vim.log.levels.ERROR)
    return
  end
  local bufnr = vim.uri_to_bufnr(uri)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(response.result, "\n"))
  vim.bo[bufnr].filetype = "java"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  vim.lsp.buf_attach_client(bufnr, client.id)
end

return M
