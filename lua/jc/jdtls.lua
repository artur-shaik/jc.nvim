local lsp = require("jc.lsp")
local apply_edit = require("jc.lsp").apply_edit

local M = {}

local function choose_imports(params, _)
  local prompt = "Choose candidate:\n"
  for i, candidate in ipairs(params.arguments[2][1].candidates) do
    prompt = prompt .. i .. ". " .. candidate.fullyQualifiedName .. "\n"
  end
  local choice = tonumber(vim.fn.input(prompt .. "Your choice: "))

  return { params.arguments[2][1].candidates[choice] }
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
    local params = vim.lsp.util.make_range_params()
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
      context = vim.lsp.util.make_range_params(),
      accessors = fields,
    }, apply_edit)
  end
end

function M.generate_abstractMethods()
  local diagnostics = {}
  for _, diagnostic in ipairs(vim.diagnostic.get()) do
    if diagnostic.code == "67109264" then
      diagnostic.range = {
        start = {
          character = diagnostic.col,
          line = diagnostic.lnum,
        },
        ["end"] = {
          character = diagnostic.end_col,
          line = diagnostic.end_lnum,
        },
      }
      table.insert(diagnostics, diagnostic)
    end
  end
  if diagnostics then
    local params = vim.lsp.util.make_range_params()
    params.context = {
      diagnostics = diagnostics,
    }
    vim.lsp.buf_request(0, "textDocument/codeAction", params, function(err, actions)
      if actions then
        local add_method_action = nil
        for _, action in ipairs(actions) do
          if action.title == "Add unimplemented methods" then
            add_method_action = action
            break
          end
        end
        if add_method_action then
          vim.lsp.buf_request(0, "codeAction/resolve", add_method_action, apply_edit)
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
    vim.lsp.buf_request(0, "java/checkConstructorsStatus", vim.lsp.util.make_range_params(), function(err, resp)
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
    local context = vim.lsp.util.make_range_params()
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
    vim.lsp.buf_request(0, "java/checkHashCodeEqualsStatus", vim.lsp.util.make_range_params(), function(err, resp)
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
      context = vim.lsp.util.make_range_params(),
      fields = fields,
      regenerate = true,
    }, apply_edit)
  end
end

function M.generate_toString(fields, params)
  if not fields then
    vim.lsp.buf_request(0, "java/checkToStringStatus", vim.lsp.util.make_range_params(), function(err, resp)
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
      context = vim.lsp.util.make_range_params(),
      fields = fields,
    }, apply_edit)
  end
end

function M.organize_imports()
  vim.lsp.buf_request(0, "java/organizeImports", vim.lsp.util.make_range_params(), apply_edit)
end

function M.read_class_content(params, handler)
  local client = lsp.get_jdtls_client()
  if not client then
    vim.notify("LSP client not found", vim.log.levels.ERROR)
    handler(nil, params.result, params.ctx, params.config)
    return
  end

  local uri = params.result[1].uri
  local bufnr = vim.uri_to_bufnr(uri)
  client.request("java/classFileContents", { uri = uri }, function(err, resp)
    if resp then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(resp, "\n"))
      vim.api.nvim_buf_set_option(bufnr, "filetype", "java")
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

      handler(nil, params.result, params.ctx, params.config)
    elseif err then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end, bufnr)
end

return M
