# Changelog

All notable changes to jc.nvim are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0]

### Added

- **Flip call arguments** — a treesitter refactoring that swaps the receiver
  and the single argument of the call at the cursor (`a.equals(b)` →
  `b.equals(a)`), leaving a surrounding `!` and the method name untouched.
  `:JCrefactorFlipArgs` / `<p>rf`.
- **Create a class from a reference** — with the cursor on a class name the code
  refers to but that doesn't exist yet, pick a package (and module) and land in
  the DSL prompt pre-filled with the name. `:JCgenerateClassFromCursor` /
  `<p>nc`.
- **Add annotations by search** — add an annotation to the enclosing method or
  class by searching jdtls for matching types by name prefix (`Get` → `Getter`),
  inserting `@Name` and importing it (remembered for smart organize-imports).
  A live telescope picker when available, otherwise a prompt + `vim.ui.select`.
  `:JCannotateMethod` / `:JCannotateClass`, `<p>am` / `<p>ac`.
- **Optional snippet set** — a VS Code-format Java snippet bundle
  (`snippets/java.json`): field/modifier combos (`psfL` → `private static final
  Long`, …) and NetBeans-style abbreviations (`fori`, `soutv`, `ife`, …). jc
  doesn't run a snippet engine; point your own at the folder.

## [1.0.0]

First stable release. jc.nvim is now a **pure layer on top of an externally
managed [jdtls](https://github.com/eclipse/eclipse.jdt.ls)** — it never starts
or installs the language server. You run jdtls however you like (nvim-java,
nvim-jdtls or a plain lspconfig setup) and jc.nvim hooks into whatever `jdtls`
client attaches.

### Added

- **Class creation** — a one-line DSL
  (`template:[subdir]:/pkg.Name extends X implements Y (fields):flags`) with
  `<Tab>` completion for templates, project packages, `[module]` targeting and
  jdtls-resolved supertypes; a step-by-step wizard (`class_prompt = "wizard"`)
  with validation and an editable DSL preview.
- **Declarative templates** and a built-in library: `record`, spring
  stereotypes (`@Service`/`@Component`/`@RestController`), JUnit 5, a JPA
  `entity` (`@Id`/`@Column`), plus a user `templates_dir`.
- **Lombok flags** in the DSL (`:lombokData`, `:lombokBuilder`, …), `enum`
  constants via the fields slot, cross-module package resolution with a
  target-module prompt.
- **Code generation** — `toString`, `hashCode`/`equals`, constructors and
  accessors with interactive field selection; unimplemented (abstract) methods
  added automatically on class creation.
- **Imports** — smart organize-imports that remembers the preferred class per
  ambiguous name, per project; replace the import of the type under the cursor;
  static-import conversion without the code-action menu.
- **Test runner** (optional) — a [neotest](https://github.com/nvim-neotest/neotest)
  adapter with the classpath resolved from jdtls, per-project JDK selection, an
  optional gradle/maven precompile (async, cmdline progress, errors to the
  quickfix list), auto-close of the summary on an all-green focused run, and
  `:JCtestPick`.
- **Build runner** — gradle/maven tasks with a module + task picker; compile
  errors parsed into the quickfix list.
- **Navigation** — FQN-aware `gf`; jump between a class and its test,
  scaffolding the test from a template.
- **Debugging** — attach/launch via
  [nvim-dap](https://github.com/mfussenegger/nvim-dap) or
  [vimspector](https://github.com/puremourning/vimspector) with per-project
  host/port memory.
- **Utilities** — classpath-aware `javap` / `jshell` / `jol`, a decompiled
  `jdt://` class view, and `:JCutilWipeWorkspace` (works even with no client
  attached).

### Changed

- **BREAKING:** jc.nvim no longer bootstraps jdtls — a running `jdtls` client is
  now required (nvim-java, nvim-jdtls or lspconfig, started with
  `extendedClientCapabilities`).
- **BREAKING:** the nvim-jdtls dependency is dropped; protocol calls are
  implemented natively.
- **BREAKING:** configuration is unified under a single `setup(opts)`.
- The class generator, code generators and templates were rewritten from
  vimscript to Lua.

[1.1.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.1.0
[1.0.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.0.0
