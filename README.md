# jc.nvim

jc.nvim – successor of [vim-javacomplete2](https://github.com/artur-shaik/vim-javacomplete2) which use neovim's built-in LSP client and [Eclipse JDT Language Server](https://github.com/eclipse/eclipse.jdt.ls).

Read my [blog post](https://shaik.link/posts/javacomplete-to-jc.nvim/) about it.

Main goal of this project is to migrate functionallty of jc2.

jc.nvim is a **layer on top of an externally managed jdtls**: it never
starts the language server itself. Run jdtls with
[nvim-java](https://github.com/nvim-java/nvim-java),
[nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) or
nvim-lspconfig — jc.nvim hooks into whatever `jdtls` client attaches and
adds:

- organize imports with smart selection regular classes;
- generate code (`toString`, `hashCode`, `equals`, constructors, accessors) with field selection;
- add abstract methods to implementing class;
- debug attach/launch via [nvim-dap](https://github.com/mfussenegger/nvim-dap) or [vimspector](https://github.com/puremourning/vimspector), with per-project host/port memory;
- decompiled `jdt://` class contents view;
- class creation methods from `jc2`.

## Installation

Requirements:

- a running `jdtls` managed by nvim-java, nvim-jdtls or lspconfig. The
  server must be started with `extendedClientCapabilities` (notably
  `executeClientCommandSupport` and `advancedOrganizeImportsSupport`) —
  nvim-java and nvim-jdtls do this out of the box;
- for debug attach: the [java-debug](https://github.com/microsoft/java-debug)
  bundle loaded into jdtls (nvim-java bundles it; with nvim-jdtls add it to
  `init_options.bundles`);
- `JCutilJol` looks for the jol-cli jar in `~/.m2` and offers to download
  it via maven when missing (or set `require("jc.tools").jol_path`).

Minimal setup using `lazy.nvim` (jdtls managed by nvim-java):

```lua
return {
  {
    "artur-shaik/jc.nvim",
    ft = { "java" },
    dependencies = {
      "nvim-java/nvim-java",
    },
    opts = {
      keys_prefix = "'j",
    },
  },
}
```

## Configurations

All options go through `setup(opts)` (or the `opts` table of your plugin
manager):

```lua
require("jc").setup({
  keys_prefix = "<leader>j",   -- prefix for the default mappings
  default_mappings = true,     -- install default mappings on attach
  autoformat_on_save = false,  -- format java buffers on save
  debug_backend = nil,         -- "dap" | "vimspector" | nil (auto-detect)
  basedir = nil,               -- data dir, default ~/.local/share/jc.nvim
  on_attach = nil,             -- function(client, bufnr) extra hook
})
```

The legacy `g:jc_default_mappings`, `g:jc_autoformat_on_save`,
`g:jc_debug_backend` and `g:jc_basedir` variables still work as a
fallback when the corresponding option is not passed to `setup`.

## What it adds over plain nvim-jdtls

| Feature | nvim-jdtls | jc.nvim |
|---|---|---|
| Code generation (toString/equals/hashCode/constructors/accessors) | via code actions | dedicated commands and mappings with field selection |
| Organize imports | code action | smart mode remembering preferred classes per project |
| Debug attach | manual dap config | `JCdebugAttach` with per-project host/port memory, dap or vimspector |
| Class creation from templates | — | `JCgenerateClass` prompt DSL |
| Extract refactorings | yes | built-in (`java/inferSelection` + `java/getRefactorEdit`) |
| Classpath-aware javap/jshell/jol | yes | built-in |

`:checkhealth jc` verifies the setup; `:help jc` for full docs.

## Commands

- `JCdebugAttach` – attach debugger (nvim-dap or vimspector, see `debug_backend`);
- `JCdebugLaunch` – launch debug session;
- `JCdapAttach` / `JCvimspectorAttach` – attach using a specific backend;
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
- `JCutilUpdateConfig` – re-read project configuration (pom/gradle);
- `JCutilWipeWorkspace` – delete the jdtls workspace (eclipse index) and restart the server;
- `JCrefactorExtractVar` – extract variable;
- `JCrefactorExtractMethod` – extract method (visual range);
- `JCutilJshell` – execute java shell with project classpath;
- `JCutilBytecode` – extract bytecode for class (javap);
- `JCutilJol` – analyze object layout scheme using `jol.jar`.

## Default mappings

Installed on jdtls attach when `default_mappings` is enabled. `<p>` is
`keys_prefix` (default `<leader>j`).

| Mode | Keys | Action |
|---|---|---|
| n | `<p>i` | organize imports (smart) |
| n | `<p>I` | organize imports (manual selection) |
| i | `<C-j>i` | organize imports |
| n | `<p>ts` | generate `toString()` |
| n | `<p>eq` | generate `hashCode()` and `equals()` |
| n | `<p>A` | generate accessors (field selection) |
| n | `<p>s` / `<p>g` | generate setter / getter |
| n | `<leader>ja` | generate getter and setter |
| i | `<C-j>s` / `<C-j>g` / `<C-j>a` | accessor generation |
| n | `<p>c` | generate constructor (field selection) |
| n | `<p>cc` | generate default constructor |
| n | `<p>m`, i `<C-j>m` | generate abstract methods |
| n | `<p>n` | new class prompt |
| n | `<p>da` / `<p>dl` | debug attach / launch |
| v | `<p>re` / `<p>rm` | extract variable / method (selection) |
| n | `<p>re` | extract variable (inferred at cursor) |

## Class creation

Prompt scheme, for class creation:

    template:[subdirectory]:/package.ClassName extends SuperClass implements Interface(String str, public Integer i):contructor:toString:equals

A: (optional) template - which will be used to create class boilerplate. Some existed templates: junit, interface, exception, servlet, etc;

B: (optional) subdirectory in which class will be put. For example: test, androidTest;

C: class name and package. With `/` will use backsearch for parent package to put in it. Without `/` put in relative package to current;

D: (optional) extends and implements classes will be automatically imported;

E: (optional) private str variable, and public i variable will be added to class;

F: (optional) contructor using all fields and toString will be created. Also hashCode and equals can be used.
