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
  local choice = tonumber(vim.fn.input(prompt .. "Your choice: "))

  if candidates[choice] ~= nil then
    regulars:add(candidates[choice].fullyQualifiedName)
  end
  return { candidates[choice] }
end

local function set_configuration(settings)
  vim.lsp.buf_request(0, "workspace/didChangeConfiguration", {
    settings = settings,
  }, function() end)
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
  vim.lsp.buf_request(
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
    vim.fn["generators#GenerateAccessor"](filter_fields(symbols), accessor)
  end)
end

function M.generate_accessors(fields)
  if not fields then
    local params = make_range_params()
    params.kind = 2
    vim.lsp.buf_request(0, "java/resolveUnimplementedAccessors", params, function(err, resp)
      if resp then
        vim.fn["generators#GenerateAccessors"](resp)
      else
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
    end)
  else
    set_configuration({
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    vim.lsp.buf_request(0, "java/generateAccessors", {
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
  if #diagnostics > 0 then
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
    vim.lsp.buf_request(curbuf, "textDocument/codeAction", params, function(err, actions)
      if actions then
        local add_method_action = nil
        for _, action in ipairs(actions) do
          if action.title == "Add unimplemented methods" then
            add_method_action = action
            break
          end
        end
        if add_method_action then
          vim.lsp.buf_request(curbuf, "codeAction/resolve", add_method_action, apply_edit)
        else
          vim.notify("No action found", vim.log.levels.INFO)
        end
      elseif err then
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
    end)
  end
end

function M.generate_constructor(fields, params, opts)
  if fields == nil then
    vim.lsp.buf_request(0, "java/checkConstructorsStatus", make_range_params(), function(err, resp)
      if resp then
        vim.fn["generators#GenerateConstructor"](resp.fields, resp.constructors, opts)
      else
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
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
    vim.lsp.buf_request(0, "java/generateConstructors", {
      context = context,
      fields = fields,
      constructors = params.constructors,
    }, apply_edit)
  end
end

function M.generate_hashCodeAndEquals(fields)
  if not fields then
    vim.lsp.buf_request(0, "java/checkHashCodeEqualsStatus", make_range_params(), function(err, resp)
      if resp then
        vim.fn["generators#GenerateHashCodeAndEquals"](resp.fields)
      else
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
    end)
  else
    set_configuration({
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    vim.lsp.buf_request(0, "java/generateHashCodeEquals", {
      context = make_range_params(),
      fields = fields,
      regenerate = true,
    }, apply_edit)
  end
end

function M.generate_toString(fields, params)
  if not fields then
    vim.lsp.buf_request(0, "java/checkToStringStatus", make_range_params(), function(err, resp)
      if resp then
        vim.fn["generators#GenerateToString"](resp.fields)
      else
        vim.notify(vim.inspect(err), vim.log.levels.ERROR)
      end
    end)
  else
    set_configuration({
      ["java.codeGeneration.toString.codeStyle"] = params.code_style,
      ["java.codeGeneration.insertionLocation"] = "lastMember",
    })

    vim.lsp.buf_request(0, "java/generateToString", {
      context = make_range_params(),
      fields = fields,
    }, apply_edit)
  end
end

function M.organize_imports(bn, smart)
  M.organize_imports_smart = smart
  vim.lsp.buf_request(bn, "java/organizeImports", make_range_params(), apply_edit)
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
