# jc.nvim

jc.nvim – successor of [vim-javacomplete2](https://github.com/artur-shaik/vim-javacomplete2) which use built-in LSP client in neovim and [Eclipse JDT Language Server](https://github.com/eclipse/eclipse.jdt.ls).

Main goal of this project is to migrate functionallty of jc2.

In addition to autocompletion it can:

- organize imports;
- generate code (`toString`, `hashCode`, `equals`, constructors, accessors) with field selection;
- add abstract methods to implementing class;
- execute [vimspector](https://github.com/puremourning/vimspector) debug session;
- automatic installation of jdt.ls and java-debug extension;
- class creation methods from `jc2` (WIP).

## Installation

Minimal setup:

```
call plug#begin('~/.vim/plugged')

Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/nvim-cmp' 
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'williamboman/nvim-lsp-installer'
Plug 'puremourning/vimspector'
Plug 'artur-shaik/jc.nvim'

call plug#end()

lua require('jc').setup{}
```

For triggering autocompletion automatically consider [configure nvim-cmp](https://github.com/hrsh7th/nvim-cmp/#recommended-configuration).

## Commands

`JCdebugAttach` – start debug session with vimspector attaching to debug port;
`JCdebugLaunch` – start debug session with vimspector executing main class;
`JCdebugWithConfig` – start debug session using predefined vimspector's configuration;
`JCimportsOrganize` – automatically organize imports;
`JCgenerateToString` – choose fields and method to generate `toString`;
`JCgenerateHashCodeAndEquals` – choose fields to generate `hashCode` and `equals`;
`JCgenerateAccessors` – choose fields for accessors generation;
`JCgenerateAccessorGetter` – generate getter for a field;
`JCgenerateAccessorSetter` – generate setter for a field;
`JCgenerateAccessorSetterGetter` – generate getter and setter for a field;
`JCgenerateConstructorDefault` – generate constructor with no arguments;
`JCgenerateConstructor` – choose fields for constructor;
`JCgenerateAbstractMethods` – generate abstract methods;
`JCgenerateClass` – generate new class.

## Default mappings

```lua
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>ji", "<cmd>lua require('jc.jdtls').organize_imports()<CR>", opts)
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
```

## Class creation

Prompt scheme, for class creation:

    template:[subdirectory]:/package.ClassName extends SuperClass implements Interface(String str, public Integer i):contructor(*):toString(1)

A: (optional) template - which will be used to create class boilerplate. Some existed templates: junit, interface, exception, servlet, etc;

B: (optional) subdirectory in which class will be put. For example: test, androidTest;

C: class name and package. With `/` will use backsearch for parent package to put in it. Without `/` put in relative package to current;

D: (optional) extends and implements classes will be automatically imported;

E: (optional) private str variable, and public i variable will be added to class;

F: (optional) contructor using all fields and toString override method with only `str` field will be created. Also hashCode and equals can be used.

There is autocompletion in command prompt that will try to help you. Your current opened file shouldn't have dirty changes or `hidden` should be set.

## Troubleshooting

### java-debug compilation may fail

You need `JDK-11` in your `$JAVA_HOME` to compile java-debug. Consider using [sdkman](https://sdkman.io/) to switch your runtime java version or set it manually on first run.
