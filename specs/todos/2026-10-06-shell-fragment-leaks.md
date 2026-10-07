`[P2]` **Shell fragments leak ~16 KB per session on the node.**

Found by LeakSanitizer (Linux, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`) running
`test/shell/session.txt` against `test/native/shell_node.march`, after the
shell landed ([progress](../progress/2026-10-06-shell-client-march-shell.md)).
There were no ASAN errors, but 16 286 bytes in 287 allocations stayed on the
node:

- 24-32-byte closures and cells from fragment code: `go$apply$N`,
  `Show$List.show$List_*`, `List.map$dps…`, `List.filter…`;
- ~3 KB of indirect leaks under one `go$apply`, likely a `let`-bound list;
- string literals from `march_string_lit`;
- the `march_ctor_table_ensure` table, which is the same on main for any
  program that prints a variant.

Likely sources, to separate before fixing:

1. **Panic paths.** `panic` long-jumps out of the fragment, skipping every
   drop. The session test panics twice.
2. **Perceus differences.** Fragment code is lowered by the REPL pipeline
   (`Repl_jit.lower_module`, `~repl:true`), not the native one; compare the
   post-Perceus TIR of one fragment with the same code compiled natively.
3. **Slot values.** `let`-bound values are released when the session closes
   (`slot_range_release`); check that an init fragment does not also keep a
   reference.

Measure per input (`live_allocs` before and after `EVAL`s of a non-panicking
input in a loop) rather than per session, so a fix can be shown flat.
