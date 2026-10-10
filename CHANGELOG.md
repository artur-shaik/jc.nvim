# Changelog

All notable changes to jc.nvim are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.2]

### Fixed

- **Creating a record no longer offers to generate accessors** - the follow-up
  code generation skipped that step for the `interface` template only, by name,
  so a record (whose components are final and already have accessors) got the
  accessor picker anyway. The step now goes by the declaration kind the
  template produces, which also covers `@interface` and the interface-shaped
  templates `sealed` and `repository`. A `constructor`, `equals`, `hashCode` or
  `toString` flag on a record is skipped for the same reason, with one message
  naming what was skipped so the flag does not just look broken.
- **A test written to disk from outside the editor needed a manual `:w`** -
  neotest rediscovers a file only on `BufAdd`/`BufWritePost`, so a test an
  agent or a checkout wrote behind nvim's back was missing from a rerun (and
  `precompile` did not help: the stale part was the position tree, not the
  bytecode). `:JCtestRun`, `:JCtestFile` and `:JCtestLast` now reload the
  target file, tell jdtls it changed and have neotest reparse it before the
  run. Buffers with unsaved changes are left untouched.
- **Creating a class kept asking which import to use** - the import pass that
  follows a create ran as a plain organize, which does not apply a remembered
  pick, and worse, forgets it. So every new class asked again about the same
  ambiguous name (`javax` vs `jakarta` and friends) and wiped the answer, which
  also left `:JCimportsOrganizeSmart` with nothing to go on. That pass is a
  smart organize now, so the pick is made once per project.
- **Choosing an import in the picker did not replace the remembered one** - the
  picker appended the pick, leaving the class remembered before under the same
  simple name (`lombok.Value` next to spring's, two `Query`, two `NonNull`) and
  letting the stale one win a later smart organize. It now goes through the
  same bookkeeping as `:JCimportsReplace`, which drops the competitor. Where a
  file already holds several, the most recently picked one wins, and a class is
  no longer remembered twice.

## [1.5.1]

### Fixed

- **Projects on JUnit 5.9 and older could not run tests** - picking the launcher
  off the classpath (1.5.0) brought back jars older than Platform 1.10, which
  have no subcommands: the run died with `Error parsing command-line arguments:
  Unmatched argument at index 0: 'execute'`. The `execute` subcommand is now
  added only for launchers that know it, and older jars get the flat option list
  they expect. Same for `:JCtestDebug`.

## [1.5.0]

### Fixed

- **Installing the launcher shows progress and no longer depends on maven** -
  `:JCtestInstall` echoes the download in the cmdline instead of going quiet,
  and when maven cannot fetch the jar (a corporate mirror in `settings.xml`
  intercepts every request and often lags behind on new artifacts) it falls back
  to a direct download from Maven Central with curl or wget.
- **JUnit 6 projects could not run at all** - the console launcher was pinned to
  `1.11.3`, and since the jar's own engines take precedence over the project's,
  a Spring Boot 4 / JUnit 6 project died inside the framework with
  `NoSuchMethodError: ExtensionContext$Store.computeIfAbsent` from
  `SpringExtension`, reporting zero tests started. jc now picks the launcher
  version off the test classpath (junit 5.11.3 -> jar 1.11.3, junit 6.0.3 ->
  6.0.3) and refuses to substitute another one; `:JCtestInstall` fetches what the
  current project needs and takes an optional version argument.
- **Remembered imports broke in a second project** - the workspace directory was
  created once, when the module was first used, but the file path is resolved
  per project. Opening a file from another project in the same session then
  failed with `E482: Can't open file .../.regular_imports for writing`, and
  since that happens inside the synchronous `choose_imports` handler, jdtls got
  a -32603 instead of the picked candidate. The directory is now created at
  write time, and a failed write warns instead of throwing.
- **A run that cannot start now says why, in plain words** - when the precompile
  failed (or jdtls had no classpath), the adapter returned nothing and neotest
  answered with "jc returned no data to run tests" over a lua traceback. The
  tests are now reported as failed with the real cause and what to do about it:
  fix the quickfix errors, or - when the failing task needs something you don't
  have at hand, such as a live database for a code generator - turn the
  build-tool precompile off with `:JCtestPrecompile` and let jdtls compile.
- **A class name was mistaken for a template** - `MyDto:lombokGetter` parsed as
  the template `MyDto` with `lombokGetter` as the class, and was rejected with
  "no class name given (looks like a package)". A leading `word:` is now read as
  a template only when that template exists and the word is not capitalised, so
  a relative class name with flags works like the absolute form already did.
- **Move-class always landed in the test source root** - when a package existed
  in both `src/main/java` and `src/test/java`, the picker entries looked
  identical and the destination was looked up by package name alone, so the
  entry picked in the list was discarded in favour of whichever root jdtls
  listed last. The pick is now honoured, an edited package name resolves within
  the same source root (and is created there when missing), and every entry says
  which root it belongs to: `com.example  [app/src/test/java]`.

### Added

- **Sealed types** - `sealed` and `sealed_class` templates, plus a `permits`
  slot in the DSL next to `extends`/`implements`
  (`sealed:/com.app.Shape permits Circle, Square`). `permits` on a plain
  interface or class adds the `sealed` modifier by itself, and the wizard asks
  for the subtypes when a sealed template is chosen. Completion covers the
  keyword and the type names after it.
- **`serializable` template** - a class implementing `Serializable` with a
  freshly generated 18-digit `serialVersionUID` declared above the fields.
- Members a template puts before the prompt fields (an entity's `@Id`, the
  serialVersionUID) now sit directly under the class declaration instead of
  after a blank line.
- A template's own `implements` is now merged with the one given in the DSL
  instead of being replaced, so
  `serializable:/com.app.Money implements Comparable<Money>` keeps
  `Serializable` (duplicates are dropped, generics with commas survive).

## [1.4.1]

### Fixed

- **Templates that produced code javac rejects** — an `interface`/`@interface`
  given fields emitted `private String name();` (an interface method may not be
  private without a body, and an `@interface` takes elements, not fields); it is
  now `String name();`. `android_activity` passed `savedInstanceBundle` to
  `super.onCreate` (the parameter is `savedInstanceState`), and
  `android_broadcast_receiver` returned `null` from a `void onReceive`.
- **Thin templates filled out** — `junit` now scaffolds an actual `@Test` (and
  imports `org.junit.Test`/`Before`) instead of only `setUp`; `exception` gets
  the four conventional constructors, so it can wrap a cause; `controller` adds
  `@RequestMapping` for the path its name implies (`UserController` → `/user`);
  `servlet` drops the page of `out.println` HTML (with its unclosed
  `<!DOCTYPE HTML`) for empty `doGet`/`doPost` handlers, and maps
  `MyFileServlet` to `/my-file`.
- **The `repository` template makes a spring-data interface** — it used to be a
  plain class carrying `@Repository`. It is now
  `public interface UserRepository extends JpaRepository<User, Long>`, deriving
  the entity from the class name (a trailing `Repository`/`Repo` is stripped)
  and leaving the import to organize-imports; the redundant `@Repository` is
  gone. An `extends` given in the DSL still wins.

## [1.4.0]

### Added

- **Field names derived from the type** — a class-creation field written with no
  name is named after its type, the way an IDE would:
  `(final RiTypeEvent, final DictionaryService)` becomes
  `private final RiTypeEvent riTypeEvent;` / `private final DictionaryService
  dictionaryService;`. Acronyms (`URLHandler` → `urlHandler`), generics, arrays,
  FQNs and java keywords are handled, and repeated types get a numeric suffix.
  A field with no visibility modifier is now `private` (`final X` → `private
  final X`).

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

[1.5.2]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.5.2
[1.5.1]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.5.1
[1.5.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.5.0
[1.4.1]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.4.1
[1.4.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.4.0
[1.3.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.3.0
[1.2.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.2.0
[1.1.1]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.1.1
[1.1.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.1.0
[1.0.0]: https://github.com/artur-shaik/jc.nvim/releases/tag/v1.0.0
