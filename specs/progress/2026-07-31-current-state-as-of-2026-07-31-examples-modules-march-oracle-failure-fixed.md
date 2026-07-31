# Current State (as of 2026-07-31, `examples/modules.march` oracle failure fixed)

**Counts:** differential oracle sweep (`dune build --root . @test/oracle`) —
100 MATCH, 0 known-divergence, 0 un-triaged failures, 153 total programs,
exit 0 (previously 1 un-triaged `INTERP_FAIL` from `examples/modules.march`).

`examples/modules.march`'s Part 3 (`pfn`-vs-`fn` visibility demo) declared
`mod Crypto`, which collides with stdlib's own `mod Crypto`
(`stdlib/crypto.march`) in March's flat, global module namespace — so its
bare calls to `scramble`/`add_checksum`/`remove_checksum` resolved against
the stdlib module instead of the file's own, failing to typecheck
(`Module 'Crypto' does not export '...'`) under both the interpreter and the
oracle sweep. This had previously been misdiagnosed in `specs/todos.md` as a
nested-module-specific `pfn`-export bug — retesting the same nested shape
with a genuinely unique module name compiles and runs correctly, confirming
the real cause is the ordinary global-namespace collision (same class as the
existing stdlib-collision guidance for app **types**), not nesting or `pfn`
adjacency. **Fix:** renamed the example's module to `mod SecretCode`; no
compiler change. Verified interpreted (exit 0) and compiled
(`--compile --opt 2`, exit 0) with correct output, and the full oracle sweep
re-run clean.
