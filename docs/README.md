# Demo recordings

The GIFs in the main README are generated from the [vhs](https://github.com/charmbracelet/vhs)
`.tape` scripts here — declarative, so they re-record identically.

## Recording

1. Install vhs: `go install github.com/charmbracelet/vhs@latest` (or a package
   manager).
2. Have a small java project that starts jdtls on open (nvim-java) and, for the
   test demo, the neotest adapter wired in (see the main README).
3. Edit the `cd /path/to/java-project` path in each `.tape` to point at that project, and
   tune the `Sleep` durations to how fast jdtls indexes on your machine.
4. Record:

   ```sh
   vhs docs/class-creation.tape
   vhs docs/test-runner.tape
   ```

   Each writes its `.gif` next to the script (`docs/*.gif`).

## Scripts

| Script | Shows | Recorded |
|---|---|---|
| `class-creation.tape` | `:JCgenerateClass` — the DSL creating an interface, enum and exception | ✅ `class-creation.gif` |
| `code-generation.tape` | `:JCgenerateConstructor` / `:JCgenerateToString` — the field/style picker windows | ✅ `code-generation.gif` |
| `test-runner.tape` | `:JCtestFile` — running a test class through neotest | ⬜ record on a built project (junit on the classpath) |
