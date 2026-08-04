# forge cap audit — phases 1–2 shipped (dead-strip + markers + audit CLI)

Design: `specs/2026-08-03-forge-cap-audit-design.md` (v2 — capability-by-absence).
Plan: `specs/plans/2026-08-03-forge-cap-audit-plan.md` (Tasks 1–6 of 10).

## What shipped

- **Dead-strip for executables** (`bin/main.ml`): `-Wl,-dead_strip` (macOS) /
  `-ffunction-sections -fdata-sections -Wl,--gc-sections` (Linux), carved out for
  `--compile-so` and `--hot-reload` builds (dlsym boundary,
  `runtime/march_reload.c:318-351`). `capstrip` registered in `cas_flags` at BOTH
  compilation-hash sites. Binaries: ~269KB → 56–75KB. The security property: a
  binary that never uses a capability does not contain its runtime entry point —
  under-claiming requires deleting the functionality.
- **Cap→symbol table** (`lib/caps/cap_symbols.ml`): mechanically joined from
  `builtin_cap_table` × `llvm_builtins` c_names + hand-verified special lowerings
  (unprefixed `dns_resolve`, `march_signal_*`, spawn thunks). Total-accounting
  drift test (`test/test_cap_symbols.ml`): every cap-bearing builtin must resolve
  through the table, the special-lowerings map, or the justified
  `uncompiled_builtins` list.
- **Capability markers** (`lib/tir/llvm_builtins.ml`, `llvm_toplevel.ml`):
  recorded at the `mangle_extern` choke point (per-emit reset), NEVER from the
  declare preamble (unconditional for every builtin — deriving from it would mark
  every cap in every binary, the app-invariance trap that sank three prior
  detection strategies, design §3). `@__march_cap_<Cap>` globals pinned via
  `@llvm.used`; verified surviving `-dead_strip` (macOS) and `--gc-sections`
  (Linux, `SHF_GNU_RETAIN`, clang 18). `tm_externs` ≠ [] additionally emits
  `IO.Foreign` (+`.Blocking`) so FFI presence is readable from the artifact.
- **`forge cap audit`** (`forge/lib/cap_binary.ml`, `cmd_cap.ml`): reads markers +
  cap-bearing symbols + embedded-manifest blobs (multiplicity rejected). Build
  classification is fail-honest: all-cap-symbols-present ⇒ `UNSTRIPPED`, cap list
  withheld; names stripped ⇒ `symbols-removed`; gate (`--deny`/`--allow-only`,
  lattice-subsuming both directions) fails closed on any coverage below full,
  `--allow-foreign` excusing exactly the FFI case.

## Verification highlights

- Pure vs direct-call vs closure-routed file read discriminate correctly under
  strip — the closure route was the false negative that killed design v1.
- Full suite green (2269 tests) except `adversarial-regressions #39` — confirmed
  pre-existing machine-wide ASAN hang (trivial C ASAN program hangs; documented in
  project memory 2026-07-27, reconfirmed today).
- Actor program under dead-strip: correct output; HCR manifest suite green
  (carve-out honored).

## Not yet done (plan Tasks 7–10)

- Registry notarization (`forge publish` caps field, `--notarized`).
- Opt-in sandbox (`--cap-sandbox`, `forge run --enforce`).
- Embedded JSON manifest (attribution witnesses at March-fn level) — markers
  supply the cap list; manifest adds `declared` vs `effective` and per-fn
  witnesses. File as its own todo when picked up.

## Related todos filed during implementation

- `specs/todos/2026-08-03-compiler-bug-builtin-as-value-sigbus-compiled.md`
- `specs/todos/2026-08-03-runtime-symbol-naming-and-uncompiled-cap-builtins.md`
- `specs/todos/2026-08-03-forge-deps-upgrade-cap-diff.md`
- `specs/todos/2026-08-03-forge-wide-artifact-signing.md`
