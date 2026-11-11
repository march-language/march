# The raw builtins become stdlib-only, and handle uses charge nothing (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 10. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- Add the raw Int-descriptor builtins (`file_*`, `tcp_*`, `udp_*`, `tls_*`, `ws_*`, `process_*` uses) to `stdlib_only`; drop the use builtins from `builtin_cap_table`, `lib/caps/cap_symbols.ml` and `lib/refinecheck/cap_infer.ml`; opens stay charged.
- Migrate `control_wiring.march`, `test/native` (~23 files), `test/two_node` (~14), bench and the OCaml tests off raw descriptors.
- Enable the deferred "a handle needs no capability" tests (`test/stdlib/test_file_handle.march`, commented out; Task 7's too) using a per-function `needs ()` bound (module-level `needs ()` does not parse).
- Phase 2a already made the three new raw file builtins (`file_open_write`, `file_write_handle`, `file_seek`) stdlib-only.
