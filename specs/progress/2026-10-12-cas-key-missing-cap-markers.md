# CAS post-TIR key missing the capability-marker inputs (module name, `needs`)

**Filed and fixed:** 2026-10-12. Sibling of
`2026-10-11-path-scope-forge-cap-run.md`, which added the path-scope manifest
to the same key for the same reason.

## Symptom

Compile `mod Alpha do needs IO.Console … end`, then the identical program
renamed `mod Beta`, in the same project and HOME. The second compile printed
`compiled Beta.bin (cached)` and `nm Beta.bin` showed
`__march_capfrom_IO_Console__Alpha` / `__march_capdecl_IO_Console__Alpha`.
Every reader of those markers (`forge cap inspect`/`run`, `forge audit`,
`march caps`, `forge cap inspect --strict`'s ceiling re-check) then reported
the wrong module. Same with two programs that differ only in a `needs` line:
the second binary lacked its extra `__march_capdecl_*` rows.

## Root cause

`emit_module` (`lib/tir/llvm_toplevel.ml`, capability-marker block) writes one
marker per `(cap, owner)` row of `cap_attrib` / `cap_decls`, and the entry
module's rows are owned by `tm_name`. The post-TIR key in `bin/main.ml` was the
concatenated per-SCC impl hashes, which cover function bodies and type layouts
only. The entry module's own functions are unprefixed in TIR, so the module
name reached the key nowhere, and the `needs` declarations never do (they are
erased). A post-TIR hit also back-fills the source-level entry, so the wrong
binary then sat under the second program's source key as well.

The source-level key is a digest of the source bytes and so already differed;
it was only poisoned through that back-fill.

## Fix

`bin/main.ml`, post-TIR key: `mod_hash` now also folds in `module:<tm_name>`
and the sorted `capfrom:`/`capdecl:` rows of `cap_attrib` and `cap_decls`.
The markers `emit_module` emits are a pure function of those lists plus the
already-keyed code (it only filters the rows against the flat caps of the
emitted code), so this covers exactly what is emitted. `tm_name` also covers
the WASM island exports, which are found through it.

## Test

`test/test_post_tir_cache.ml` (run_compiler, `Slow`): two cases, module name
and an extra `needs` line. Each compiles A then B in one hermetic project dir
and HOME, asserts with `nm` that B carries B's markers (and not A's), and that
an unchanged rebuild of B is still a hit. Both fail before the fix.
