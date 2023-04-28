local M = {}

function M.install_mappings(bufnr)
  local opts = { noremap = true, silent = true }

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jda", "<cmd>lua require('jc.vimspector').debug_attach()<CR>", opts)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>ji", "<cmd>lua require('jc.jdtls').organize_imports(true)<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<leader>jI",
    "<cmd>lua require('jc.jdtls').organize_imports(false)<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>i", "<cmd>lua require('jc.jdtls').organize_imports()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jts", "<cmd>lua require('jc.jdtls').generate_toString()<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<leader>jeq",
    "<cmd>lua require('jc.jdtls').generate_hashCodeAndEquals()<CR>",
    opts
  )

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jA", "<cmd>lua require('jc.jdtls').generate_accessors()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>js", "<cmd>lua require('jc.jdtls').generate_accessor('s')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jg", "<cmd>lua require('jc.jdtls').generate_accessor('g')<CR>", opts)
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
    "<leader>jc",
    "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = false})<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<leader>jcc",
    "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = true})<CR>",
    opts
  )

  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<leader>jm",
    "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>",
    opts
  )
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>m", "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>", opts)
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<Leader>jn",
    "<cmd>lua require('jc.class_generator').generate_class()<CR>",
    opts
  )

  if pcall(require, "jdtls") then
    vim.api.nvim_buf_set_keymap(
      bufnr,
      "v",
      "<leader>jre",
      "<Esc><Cmd>lua require('jdtls').extract_variable(true)<CR>",
      opts
    )
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jre", "<Cmd>lua require('jdtls').extract_variable()<CR>", opts)
    vim.api.nvim_buf_set_keymap(
      bufnr,
      "v",
      "<leader>jrm",
      "<Esc><Cmd>lua require('jdtls').extract_method(true)<CR>",
      opts
    )
  end
end

return M
