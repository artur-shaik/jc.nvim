describe("setup", function()
  local jc = require("jc")

  it("merges config with defaults", function()
    jc.setup({ keys_prefix = "'j" })
    assert.are.equal("'j", jc.config.keys_prefix)
  end)

  it("keeps default prefix when not overridden", function()
    jc.setup({})
    assert.are.equal("<leader>j", jc.config.keys_prefix)
  end)

  it("bridges opts to legacy g: variables", function()
    jc.setup({ debug_backend = "dap", autoformat_on_save = true, default_mappings = false })
    assert.are.equal("dap", vim.g.jc_debug_backend)
    assert.is_true(vim.g.jc_autoformat_on_save)
    assert.is_false(vim.g.jc_default_mappings)
  end)

  it("ensure_setup doesn't clobber explicit setup", function()
    jc.setup({ keys_prefix = "'x" })
    jc.ensure_setup()
    assert.are.equal("'x", jc.config.keys_prefix)
  end)

  it("LspAttach with unknown client id is a no-op", function()
    jc.setup({})
    assert.has_no.errors(function()
      vim.api.nvim_exec_autocmds("LspAttach", { data = { client_id = 9999 } })
    end)
  end)
end)

describe("initialize_configuration", function()
  local config = require("jc.config")

  local function keymap_count(bufnr)
    return #vim.api.nvim_buf_get_keymap(bufnr, "n")
  end

  it("installs buffer mappings once", function()
    vim.g.jc_default_mappings = nil
    local bufnr = vim.api.nvim_create_buf(false, true)
    config.initialize_configuration({ keys_prefix = "'j" }, bufnr)
    assert.is_true(vim.b[bufnr].jc_mappings_installed)
    local count = keymap_count(bufnr)
    assert.is_true(count > 0)
    -- second attach on the same buffer must not duplicate anything
    config.initialize_configuration({ keys_prefix = "'j" }, bufnr)
    assert.are.equal(count, keymap_count(bufnr))
  end)

  it("respects default_mappings = false", function()
    vim.g.jc_default_mappings = false
    local bufnr = vim.api.nvim_create_buf(false, true)
    config.initialize_configuration({ keys_prefix = "'j" }, bufnr)
    assert.is_nil(vim.b[bufnr].jc_mappings_installed)
    assert.are.equal(0, keymap_count(bufnr))
    vim.g.jc_default_mappings = nil
  end)
end)
