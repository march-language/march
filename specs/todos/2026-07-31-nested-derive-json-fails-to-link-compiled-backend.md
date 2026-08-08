- [ ] **Nested `derive Json` types fail to LINK in the compiled/LLVM backend — `undefined symbols for architecture arm64: "_to_json"`/`"_from_json"`.** Reproduces with two types, one nesting the other (e.g. `type Outer = {label:String, inner:Inner}`, both `derive Json`) — works fine interpreted, but `--compile` fails to link. Root cause: the compiled backend's general interface-dispatch path, `lib/tir/lower_state.ml`'s `resolve_iface_method`, resolves a method call to a mangled per-type symbol using the typechecker's SPAN-KEYED `type_map` — but every node `derive Json` generates carries `dummy_span`, so span-keyed lookups collide across derived types/calls. Confirmed present and byte-identical regardless of the interpreter-side `to_json` dispatch fix (a codegen-independent bug). Blocks any compiled use of `JsonStream.each_typed` or a bare `from_json`/`to_json` call over a nested derive-Json shape. Full root-cause writeup: `specs/progress/2026-07-31-typed-json-decoding-task-2-to-json-impl-tbl-dispatch-fix.md`.

  **Failure-mode update, 2026-08-08:** the compiled backend now rejects this
  shape with a clean "ambiguous interface-method call to `to_json`" diagnostic
  (exit 1) instead of the raw `_to_json` linker error (see
  `specs/progress/2026-08-08-from-json-native-ice-single-impl-and-diagnostic.md`).
  The call is not genuinely ambiguous, though — `to_json(o)` with `o : Outer`
  should resolve by first-arg dispatch; it misses because the call site's
  structural record type carries nested records structurally expanded
  (`{ inner : { id : Int }, label : String }`) while `Mono`'s
  `record_to_typename` keys on the declared field shapes (`inner : TCon
  "Inner"`), so the mangle-string keys never match. A deep-normalized
  (TCon-record-expanded, recursion-guarded) secondary key in
  `record_to_typename` is the candidate fix. Item remains open.
