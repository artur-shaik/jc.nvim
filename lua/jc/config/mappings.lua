local M = {}

function M.install_mappings(conf, bufnr)
  local opts = { noremap = true, silent = true }
  local prefix = conf.keys_prefix

  -- routes to dap or vimspector (see jc.debug.backend / vim.g.jc_debug_backend)
  vim.api.nvim_set_keymap("n", prefix .. "da", "<cmd>lua require('jc.debug').debug_attach()<CR>", opts)
  vim.api.nvim_set_keymap("n", prefix .. "dl", "<cmd>lua require('jc.debug').debug_launch()<CR>", opts)

  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "i",
    "<cmd>lua require('jc.jdtls').organize_imports(" .. bufnr .. ", true)<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "I",
    "<cmd>lua require('jc.jdtls').organize_imports(" .. bufnr .. ", false)<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "i",
    "<C-j>i",
    "<cmd>lua require('jc.jdtls').organize_imports(" .. bufnr .. ", false)<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "ts", "<cmd>lua require('jc.jdtls').generate_toString()<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "eq",
    "<cmd>lua require('jc.jdtls').generate_hashCodeAndEquals()<CR>",
    opts
  )

  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "A", "<cmd>lua require('jc.jdtls').generate_accessors()<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "s",
    "<cmd>lua require('jc.jdtls').generate_accessor('s')<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "g",
    "<cmd>lua require('jc.jdtls').generate_accessor('g')<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<leader>ja",
    "<cmd>lua require('jc.jdtls').generate_accessor('gs')<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>s", "<cmd>lua require('jc.jdtls').generate_accessor('s')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>g", "<cmd>lua require('jc.jdtls').generate_accessor('g')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>a", "<cmd>lua require('jc.jdtls').generate_accessor('sg')<CR>", opts)

  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "c",
    "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = false})<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "cc",
    "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = true})<CR>",
    opts
  )

  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "m",
    "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>m", "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "n",
    "<cmd>lua require('jc.class_generator').generate_class()<CR>",
    opts
  )
  -- always the step-by-step wizard, regardless of the class_prompt option
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "N",
    "<cmd>lua require('jc.class_generator').generate_class_wizard()<CR>",
    opts
  )
  -- create a class referenced under the cursor but missing from the project
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "nc",
    "<cmd>lua require('jc.class_generator').generate_class_from_cursor()<CR>",
    opts
  )

  -- extract variable defaults to all occurrences
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "v",
    prefix .. "re",
    "<Esc><Cmd>lua require('jc.refactor').extract_variable_all(true)<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "re",
    "<Cmd>lua require('jc.refactor').extract_variable_all()<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "v",
    prefix .. "rm",
    "<Esc><Cmd>lua require('jc.refactor').extract_method(true)<CR>",
    opts
  )
  -- convert the call at the cursor to a static import (all occurrences)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    prefix .. "rs",
    "<Cmd>lua require('jc.jdtls').convert_static_import(true)<CR>",
    opts
  )
  -- convert every constant of the enum under the cursor to a static import
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "rS", "<Cmd>lua require('jc.jdtls').static_import_enum()<CR>", opts)
  -- replace the import of the type under the cursor (pick among same-named types)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "rp", "<Cmd>JCimportsReplace<CR>", opts)
  -- flip the receiver and argument of the call at the cursor: a.equals(b) -> b.equals(a)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "rf", "<Cmd>JCrefactorFlipArgs<CR>", opts)
  -- jump to the test class of the current production class (or back)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "t", "<Cmd>lua require('jc.class_generator').goto_test()<CR>", opts)

  -- test runner (neotest, optional). Capital T to avoid the lowercase t
  -- (goto_test) and ts (toString) bindings.
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Tr", "<Cmd>lua require('jc.test').run_at_cursor()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Tf", "<Cmd>lua require('jc.test').run_file()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Ta", "<Cmd>lua require('jc.test').run_all()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Tp", "<Cmd>lua require('jc.test').pick()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Tl", "<Cmd>lua require('jc.test').run_last()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "Ts", "<Cmd>lua require('jc.test').summary()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "To", "<Cmd>lua require('jc.test').output()<CR>", opts)

  -- gradle/maven task runner
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "b", "<Cmd>JCbuildRun<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", prefix .. "B", "<Cmd>JCbuildTask<CR>", opts)
end

return M
