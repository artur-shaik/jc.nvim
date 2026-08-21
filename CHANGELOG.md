# Changelog

All notable changes to jc.nvim are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Type completion ranks what you typed first** — in the class-creation DSL,
  the wizard and the `extends`/`implements` steps, names starting with the typed
  prefix now come before jdtls' fuzzy matches, shortest first (`RiType` before
  `RiTypeRegistryFactory`, both before `SomeRiTypeFactory`); the fuzzy remainder
  keeps the previous package ordering.

### Fixed

- **Precompiled test runs on an older gradle** — the build tool now runs on the
  project's own JDK (the one the tests launch with) instead of whatever
  `JAVA_HOME` nvim inherited, which made e.g. gradle 6.x on a JDK 17 fail with
  `IllegalAccessError: ... jdk.compiler does not export com.sun.tools.javac.*`.
  Override with `test.build_java_home`, or set it to `false` to keep nvim's
  environment.
- **Build failures now say what actually failed** — warnings (lombok's
  `@EqualsAndHashCode` note, deprecations) are no longer counted as errors and
  no longer hide the cause; when no `file:line` error was parsed, jc reports the
  javac `error:` lines (including ones without a location) or gradle's
  "What went wrong" block.
- A run stopped by a failed build no longer blames the classpath ("jdtls
  couldn't resolve the test classpath"), and reports once per run instead of
  once per node of the test tree.

## [1.3.0]

### Added

- **Import commands that don't reorder** — `:JCimportsRemoveUnused` (`<p>ru`)
  and `:JCimportsAddMissing` (`<p>ri`) apply jdtls' bulk code actions, and
  `:JCimportsOrganizeNoSort` (`<p>I`) chains both, so missing imports are added
  and unused ones dropped while the existing list keeps its order. Ambiguous
  names still go through the smart-import chooser.
- **Class-creation wizard command** — `:JCgenerateClassWizard` runs the
  step-by-step wizard regardless of the `class_prompt` setting (previously only
  reachable through `<p>N`).
- **Narrowed annotation search** — in `:JCannotateClass` / `:JCannotateMethod`
  the first word is the type name and any further words filter the candidates by
  package, so `Service spring` goes straight to
  `org.springframework.stereotype.Service`. The jdtls symbol query is cached
  while only the narrowing words change.
- **Import-sort styles** — `:JCimportsStyle` (`<p>ro`) picks a named IDE preset
  (Eclipse / IntelliJ IDEA / VS Code / Google) for the import order, static
  position and wildcard thresholds. The choice is remembered per project and
  applied on every organize-imports.

### Fixed

- `:JCannotateClass` now also annotates enums, interfaces, records and
  annotation types (it only recognised plain classes before).
- The source-set picker shown when a package exists in several source roots no
  longer lists the same root twice, and labels the choices by their path
  (`src/main/java` / `src/test/java`) instead of repeating the project name.

### Changed

- The demo GIFs in the README were re-recorded on a light theme, and previews
  for go-to-FQN, annotations, import replacement and the test runner were
  added. The vhs `.tape` scripts are no longer kept in the repository.

## [1.2.0]

### Added

- **Move-class refactoring** — `:JCrefactorMove` / `<p>rM` moves the current
  class to another package (or a new sub-package, created on the fly), updating
  every reference.
- **Debug tests** — `:JCtestDebug` (`<p>Td`) debugs the test at the cursor.
  By default jc runs its own debugger (launches the JUnit console launcher under
  a JDWP agent and attaches nvim-dap), which works on any junit version because
  the launcher is standalone. `test.debug = "external"` delegates to
  nvim-jdtls/nvim-java instead (their report UI, but their eclipse runner can
  discover 0 tests when the project's junit differs from its bundled ~5.11).
  Fixes #15.

### Fixed

- Generated code (constructors, `toString`, override stubs, …) now follows the
  current buffer's indentation (tabs vs spaces) instead of jdtls' tab default.

## [1.1.1]

### Fixed

- The annotation picker (`:JCannotateMethod` / `:JCannotateClass`) now sorts
  types already imported in the buffer or remembered as a regular-import
  preference to the top, instead of a plain alphabetical order. The telescope
  path keeps the finder order (uses `highlighter_only`) so the priority is
  visible.

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

[1.3.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.3.0
[1.2.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.2.0
[1.1.1]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.1.1
[1.1.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.1.0
[1.0.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.0.0
