# jc.nvim

jc.nvim – successor of [vim-javacomplete2](https://github.com/artur-shaik/vim-javacomplete2) which use neovim's built-in LSP client and [Eclipse JDT Language Server](https://github.com/eclipse/eclipse.jdt.ls).

Read my [blog post](https://shaik.link/posts/javacomplete-to-jc.nvim/) about it.

Main goal of this project is to migrate functionallty of jc2.

In addition to autocompletion it can:

- organize imports with smart selection regular classes;
- generate code (`toString`, `hashCode`, `equals`, constructors, accessors) with field selection;
- add abstract methods to implementing class;
- execute [vimspector](https://github.com/puremourning/vimspector) debug session;
- automatic installation of jdt.ls and java-debug extension;
- class creation methods from `jc2`.

## Installation

Minimal setup using `LazyVim`:

```lua
return {
  {
    "mfussenegger/nvim-jdtls",
    config = function() end,
  },
  {
    "puremourning/vimspector",
    keys = {
      {
        "<leader>vr",
        "<Cmd>VimspectorReset<cr>",
      },
      {
        "<leader>vb",
        "<Cmd>VimspectorBreakpoints<cr>",
      },
    },
    init = function()
      vim.g.vimspector_enable_mappings = "HUMAN"
    end,
  },
  {
    dir = "artur-shaik/jc.nvim",
    name = "jc.nvim",
    dependencies = {
      "puremourning/vimspector",
      "mfussenegger/nvim-jdtls",
      "williamboman/mason.nvim",
    },
    ft = { "java" },
    opts = {
      java_exec = "/path/to/candidates/java/17.0.7-oracle/bin/java",
      keys_prefix = "'j",
      settings = {
        java = {
          configuration = {
            runtimes = {
              {
                name = "JavaSE-11",
                path = "/path/to/candidates/java/11.0.12-open/",
                default = true,
              },
            },
          },
        },
      },
    },
  },
}
```

lspconfig:

```lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        jdtls = {},
      },
      setup = {
        jdtls = function()
          return true
        end,
      },
    },
```

For triggering autocompletion automatically consider [configure nvim-cmp](https://github.com/hrsh7th/nvim-cmp/#recommended-configuration).

## Configurations

`g:jc_default_mappings` – apply default mappings (default: 1)

`g:jc_autoformat_on_save` – execute code autoformatting on file save (default: 1)

## Commands

- `JCdebugAttach` – start debug session with vimspector attaching to debug port;
- `JCdebugLaunch` – start debug session with vimspector executing main class;
- `JCdebugWithConfig` – start debug session using predefined vimspector's configuration;
- `JCimportsOrganizeSmart` – automatically organize imports using regular classes list;
- `JCimportsOrganize` – automatically organize imports choosing from available classes list;
- `JCgenerateToString` – choose fields and method to generate `toString`;
- `JCgenerateHashCodeAndEquals` – choose fields to generate `hashCode` and `equals`;
- `JCgenerateAccessors` – choose fields for accessors generation;
- `JCgenerateAccessorGetter` – generate getter for a field;
- `JCgenerateAccessorSetter` – generate setter for a field;
- `JCgenerateAccessorSetterGetter` – generate getter and setter for a field;
- `JCgenerateConstructorDefault` – generate constructor with no arguments;
- `JCgenerateConstructor` – choose fields for constructor;
- `JCgenerateAbstractMethods` – generate abstract methods;
- `JCgenerateClass` – start class generation user input prompt;
- `JCtoggleAutoformat` – enable/disable autoformat file on save;

Using `nvim-jdtls`:

- `JCrefactorExtractVar` – extract variable;
- `JCrefactorExtractMethod` – extract method;
- `JCutilJshell` – execute java shell;
- `JCutilBytecode` – extract bytecode for class;
- `JCutilJol` – analyze object layout scheme using `jol.jar`;
- `JCutilUpdateConfig` – update current project's configuration.

## Default mappings

```lua
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>ji", "<cmd>lua require('jc.jdtls').organize_imports(true)<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jI", "<cmd>lua require('jc.jdtls').organize_imports(false)<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>i", "<cmd>lua require('jc.jdtls').organize_imports()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jts", "<cmd>lua require('jc.jdtls').generate_toString()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jeq", "<cmd>lua require('jc.jdtls').generate_hashCodeAndEquals()<CR>", opts)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jA", "<cmd>lua require('jc.jdtls').generate_accessors()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>js", "<cmd>lua require('jc.jdtls').generate_accessor('s')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jg", "<cmd>lua require('jc.jdtls').generate_accessor('g')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>ja", "<cmd>lua require('jc.jdtls').generate_accessor('gs')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>s", "<cmd>lua require('jc.jdtls').generate_accessor('s')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>g", "<cmd>lua require('jc.jdtls').generate_accessor('g')<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>a", "<cmd>lua require('jc.jdtls').generate_accessor('sg')<CR>", opts)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jc", "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = false})<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jcc", "<cmd>lua require('jc.jdtls').generate_constructor(nil, nil, {default = true})<CR>", opts)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jam", "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>am", "<cmd>lua require('jc.jdtls').generate_abstractMethods()<CR>", opts)
  
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jda", "<cmd>lua require('jc.vimspector').debug_attach()<CR>", opts)

-- using `jdtls`
  vim.api.nvim_buf_set_keymap(bufnr, "v", "<leader>jre", "<Esc><Cmd>lua require('jdtls').extract_variable(true)<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>jre", "<Cmd>lua require('jdtls').extract_variable()<CR>", opts)
  vim.api.nvim_buf_set_keymap(bufnr, "v", "<leader>jrm", "<Esc><Cmd>lua require('jdtls').extract_method(true)<CR>", opts)
```

## Class creation

Prompt scheme, for class creation:

    template:[subdirectory]:/package.ClassName extends SuperClass implements Interface(String str, public Integer i):contructor:toString:equals

A: (optional) template - which will be used to create class boilerplate. Some existed templates: junit, interface, exception, servlet, etc;

B: (optional) subdirectory in which class will be put. For example: test, androidTest;

C: class name and package. With `/` will use backsearch for parent package to put in it. Without `/` put in relative package to current;

D: (optional) extends and implements classes will be automatically imported;

E: (optional) private str variable, and public i variable will be added to class;

F: (optional) contructor using all fields and toString will be created. Also hashCode and equals can be used.
