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
- class creation methods from `jc2`;
- run JUnit tests through [neotest](https://github.com/nvim-neotest/neotest)
  with the classpath resolved from jdtls (optional, see below).

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
  update_config_on_new_file = true, -- refresh jdtls build path on new java files
  templates_dir = nil,         -- dir of user class templates (see below)
  class_type_exclude = nil,    -- package prefixes to hide from type completion
  class_prompt = "oneline",    -- "oneline" (DSL) | "wizard" (step-by-step)
  map_gf = true,               -- override gf with FQN-aware go-to-file (see below)
  on_attach = nil,             -- function(client, bufnr) extra hook
})
```

`class_prompt = "wizard"` swaps the one-line DSL prompt for a
step-by-step `vim.ui.select`/`vim.ui.input` flow (template -> module ->
package -> name -> extends/implements/fields/flags). Each step is a short
clean list, which avoids the cmdline-completion truncation of very long
package paths.

`class_type_exclude` adds package prefixes to hide from the `extends`/
`implements`/field-type completion. The prompt resolves types from
jdtls' workspace symbols, which include non-importable ones; nested
classes, shaded jars, `internal`/`impl` packages and a built-in list of
known JDK/library internals (`sun.*`, `com.sun.*`, `jdk.internal`,
jackson `introspect`/`cfg`/…) are dropped automatically. The LSP gives
no visibility, so package-private classes in ordinary packages can still
slip through — add their prefixes here to suppress them, e.g.
`{ "com.example.somelib.internalish" }`.

Built-in class templates: `class`, `interface`, `enum`, `record`,
`annotation`, `exception`, `main`, `singleton`, `servlet`, `junit`,
`junit5`, `entity`, `service`, `component`, `repository`, `controller` and the
`android_*` family.

### Custom templates

Point `templates_dir` at a folder of `<name>.lua` files. Each returns
**either** a declarative spec table (recommended — describe only the
essence, the engine builds the rest) **or** a `function(opts) -> string`
for full control.

Declarative spec — a Lombok DTO is just imports + an annotation, no class
skeleton to repeat:

```lua
-- ~/.config/nvim/jc-templates/dto.lua
return {
  imports = { "lombok.Data" },
  annotations = { "@Data" },
}
```

`dto:/com.app.User(String name, int age)` then produces a `@Data` class
with the package, declaration and fields filled in. Spec fields (all
optional): `kind` (`class`/`interface`/`enum`/`annotation`/`record`),
`modifiers`, `extends`, `implements`, `imports`, `annotations`, `body` —
each of `imports`/`annotations`/`body` may be a string, a list or a
`function(opts)`. User input for `extends`/`implements` overrides the
spec defaults.

`opts`: `name`, `package`, `fields` (`{ mod, type, name }`), `extends`,
`implements`.

The legacy `g:jc_default_mappings`, `g:jc_autoformat_on_save`,
`g:jc_debug_backend` and `g:jc_basedir` variables still work as a
fallback when the corresponding option is not passed to `setup`.

A java file created in-editor isn't on jdtls' build path until the project
configuration is refreshed, so go-to-definition returns nothing on it (while
find-references still works off the search index). With
`update_config_on_new_file` (default `true`), jc.nvim detects such files and
fires `:JCutilUpdateConfig` for them on first write automatically. Set it to
`false` to refresh manually.

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
- `JCimportsReplace` – replace the import of the type under the cursor, picking among same-named classes (e.g. swap `lombok.Value` for spring's `Value`);
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
- `JCgotoTest` – jump to the test class of the current class (or back), creating it if missing;
- `JCgotoFqn` – open the java file for the FQN under the cursor (like `gf` for fully-qualified names);
- `JCtoggleAutoformat` – enable/disable autoformat file on save;
- `JCutilUpdateConfig` – re-read project configuration (pom/gradle);
- `JCutilWipeWorkspace` – delete the jdtls workspace (eclipse index) and restart the server; works even when no jdtls client is attached (i.e. it failed to start — the case a wipe usually fixes);
- `JCrefactorExtractVar` – extract variable (all occurrences);
- `JCrefactorExtractMethod` – extract method (visual range);
- `JCrefactorStaticImport` – convert the call at the cursor to a static import (all occurrences);
- `JCrefactorStaticImportEnum` – static-import every constant of the enum under the cursor;
- `JCtestRun` – run the test at the cursor (neotest);
- `JCtestFile` – run every test in the current file;
- `JCtestSuite` – run every test under the working directory;
- `JCtestLast` – re-run the last test position;
- `JCtestStop` – stop the running test;
- `JCtestSummary` – toggle the neotest summary panel;
- `JCtestOutput` – open the output of the test at the cursor;
- `JCtestPrecompile` – toggle compiling with the build tool before a run;
- `JCtestInstall` – download the JUnit console launcher jar via maven;
- `JCbuildRun [args]` – run gradle/maven with the given args (or prompt, defaulting to the last run); compile errors land in the quickfix list;
- `JCbuildTask` – pick a module (or the whole project), then a task: gradle
  tasks from `gradlew tasks`, or for maven the lifecycle phases, pom
  profiles/plugin goals, and a plugin drill-down (`mvn help:describe` lists
  every goal of the chosen plugin). The module scopes the run (gradle
  `:module:task`, maven `-pl module -am`);
- `JCbuildLast` – repeat the last build task;
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
| n | `<p>n` | new class prompt (DSL or wizard per `class_prompt`) |
| n | `<p>N` | new class — step-by-step wizard |
| n | `<p>t` | jump to the test class (or back), creating it if missing |
| n | `gf` | go to file, or the java file of the FQN under the cursor |
| n | `<p>b` / `<p>B` | run gradle/maven (prompt) / pick a task |
| n | `<p>Tr` / `<p>Tf` / `<p>Ta` / `<p>Tl` | run test at cursor / file / all / last |
| n | `<p>Ts` / `<p>To` | toggle test summary / open test output |
| n | `<p>da` / `<p>dl` | debug attach / launch |
| v | `<p>re` / `<p>rm` | extract variable (all occurrences) / method (selection) |
| n | `<p>re` | extract variable, all occurrences (inferred at cursor) |
| n | `<p>rs` | convert call to static import (all occurrences) |
| n | `<p>rp` | replace the import of the type under the cursor (pick same-named) |
| n | `<p>rS` | static-import every constant of the enum at the cursor |

## Class creation

Prompt scheme, for class creation:

    template:[subdirectory]:/package.ClassName extends SuperClass implements Interface(String str, public Integer i):contructor:toString:equals

A: (optional) template - which will be used to create class boilerplate. Some existed templates: junit, interface, exception, servlet, etc;

B: (optional) source root / subproject. A source-set name places the
class in the current module's `src/<name>/java` (`[test]` mirrors the
package into `src/test/java`). A subproject name (multi-module projects)
targets that module's `src/main/java` directly — `[refunds-model]` or
`[refunds-model/test]` for its test sources. Without it, the class goes
relative to the current file as before;

C: class name and package. A leading `/` means an absolute package: the
class is created at `<current source root>/<package>/Name.java` with that
package exactly (e.g. `/com.foo.Bar` -> `src/main/java/com/foo/Bar.java`).
Without `/` the package is relative to the current file's package;

D: (optional) extends and implements classes will be automatically imported;

E: (optional) private str variable, and public i variable will be added to class. For the `enum` template the same `(...)` slot lists the constants instead, e.g. `enum:/p.Day(MON, TUE, WED)`;

F: (optional) contructor using all fields and toString will be created. Also hashCode and equals can be used.

The prompt has `<Tab>` completion following the scheme: templates and
project packages for the path, `[subdir]` after a template, method flags
(`constructor`/`toString`/...) once the class path is given, and — after
`extends `/`implements ` — class/interface names resolved live from
jdtls.

## Go to file by FQN

`JCgotoFqn` (and an overridden `gf`) opens the java source for a
fully-qualified name under the cursor — handy for jumping out of a terminal,
a neotest output window or a pasted stack trace into the code. It understands

- a bare FQN: `com.foo.Bar` (and `com.foo.Bar$Inner` → the outer file);
- an FQN with a member: `com.foo.Bar.method` → the `Bar` file;
- a line suffix: `com.foo.Bar:42`;
- a stack-trace frame: `at com.foo.Bar.method(Bar.java:25)` → `Bar` at line 25.

The file opens in the **last window that showed a java buffer** (so you can
trigger it from a terminal split and land back in your editing window), or a
new tab when there is none. The FQN is resolved through jdtls' symbol index
(works from any buffer) with a source-tree fallback.

When `default_mappings` is on, `gf` is overridden globally to do this and
falls back to the builtin `gf` when the token under the cursor isn't an FQN
(e.g. a real path). Disable the override with:

```lua
require("jc").setup({ map_gf = false })
```

## Test runner

jc.nvim ships a [neotest](https://github.com/nvim-neotest/neotest) adapter.
**neotest is an optional dependency** — without it the plugin works as
before and the `JCtest*` commands warn instead of erroring. Unlike the
gradle/maven-based adapters, this one resolves the test classpath straight
from jdtls and runs the
[JUnit Platform Console Standalone](https://junit.org/junit5/docs/current/user-guide/#running-tests-console-launcher)
launcher, so there is no build-tool daemon to wait for and gradle/maven/plain
layouts all work the same way.

Add neotest as an optional dependency and wire the adapter into its setup:

```lua
{
  "artur-shaik/jc.nvim",
  ft = { "java" },
  dependencies = {
    "nvim-java/nvim-java",
    {
      "nvim-neotest/neotest",
      optional = true,
      dependencies = { "nvim-neotest/nvim-nio", "nvim-lua/plenary.nvim" },
      opts = function(_, opts)
        opts.adapters = opts.adapters or {}
        table.insert(opts.adapters, require("jc").neotest_adapter())
        -- optional: auto-close the summary on green (see below)
        opts.consumers = opts.consumers or {}
        opts.consumers.jc = require("jc").neotest_consumer()
      end,
    },
  },
  opts = { keys_prefix = "'j" },
}
```

The launcher jar is looked up in `~/.m2`; if it is missing, run
`:JCtestInstall` once (it downloads
`org.junit.platform:junit-platform-console-standalone` via maven) or point
jc at an existing jar:

```lua
require("jc").setup({
  test = { console_launcher_path = "/path/to/junit-platform-console-standalone.jar" },
})
```

Run tests with `:JCtestRun` (at the cursor), `:JCtestFile`, `:JCtestSuite`
(everything under the project root), `:JCtestLast`, or the `<p>T*` mappings;
neotest paints the gutter green/red and a failed test's diagnostic points at
the failing line. The runs open the neotest summary panel (disable with
`setup{ test = { open_summary = false } }`). `:checkhealth jc` reports whether
neotest and the launcher jar are present.

Wire the optional `jc` consumer (shown in the spec above) to auto-close the
summary a moment after an all-green **focused** run (cursor / file / class) —
runs with failures stay open. `:JCtestSuite` never auto-closes: neotest splits
a whole-suite run into several independent sub-runs, so there is no reliable
"the suite finished" moment (and you usually want to read a suite's summary).
Turn the auto-close off with `setup{ test = { autoclose_summary = false } }`,
or set the delay in ms (`autoclose_summary = 1500`).

On a **multi-module** project `:JCtestSuite` is best-effort: neotest reruns
`update_running` over the shared tree per sub-run, which can reset an
already-failed class back to running in the summary. Iterate with the focused
`:JCtestRun`/`:JCtestFile` commands, which run as a single neotest run and
report reliably.

`JCtestRun`/`JCtestFile` work from a production class too: when the current
buffer isn't a test file, jc runs its paired `<Class>Test` file (the same
counterpart `JCgotoTest` uses) if it exists on disk.

### Classpath and freshness

The classpath is built from jdtls and augmented for correctness:

- **test + runtime scopes are unioned** — jdtls' `test` scope omits
  `runtimeOnly` dependencies that ByteBuddy/Mockito need at run time
  (otherwise "green from the CLI but `NoClassDefFoundError` here");
- by default (`precompile = false`) jc forces a jdtls compile
  (`java/buildWorkspace`) before reading the classpath, uses jdtls' `bin`
  output first, and keeps the gradle/maven `build/`-`target/` dirs as a
  fallback. This is fast (no build tool) and fine when jdtls compiles the
  whole project;
- some projects have classes jdtls won't put in `bin` (e.g. certain
  spring-data repositories) — there the run fails with `ClassNotFoundException`
  for a class that exists in the build tool's output. Set
  `setup{ test = { precompile = true } }` (or toggle with `:JCtestPrecompile`):
  jc then runs `gradle :<module>:testClasses` / `mvn test-compile` first and
  uses the complete `build/`-`target/` output (dropping jdtls' `bin`). Slower
  (build-tool latency) but reliable. The compile runs asynchronously (the
  editor stays responsive, with progress in the cmdline) and is cached per
  module for the run; on a compile failure the javac/maven errors are sent to
  the quickfix list (jump to `file:line`) instead of running the tests;
- the run JVM is the configured `java.configuration.runtimes` entry matching
  the **highest** bytecode version among the module's compiled classes (so a
  test compiled to 17 over an 11 `targetCompatibility` main still runs on a
  17 JVM, as gradle would). It falls back to `resolveJavaExecutable`, then
  PATH `java`.

If jdtls keeps dropping classes from `bin`, a `:JCutilWipeWorkspace` +
restart (clean re-import) often makes `bin` complete again, letting you stay
on the fast `precompile = false` path.

The adapter toasts `running...` when a run starts and
`N passed, M failed, K skipped` when it finishes (error level if anything
failed) — neotest itself only updates signs, diagnostics and the summary
panel, so these are the run notifications. The per-class toasts of one run
are debounced into one each. Opt out with:

```lua
require("jc").setup({ test = { notify = false } })
```
