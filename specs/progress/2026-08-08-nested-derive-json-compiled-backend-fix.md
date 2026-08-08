- [x] **Nested `derive Json` types now compile natively — `to_json`/`from_json` dispatch resolved.**
  Filed 2026-07-31 as a LINK failure (`undefined symbols ... "_to_json"`); by
  2026-08-08 an unrelated `from_json`-ICE fix had turned the compiled-only
  failure into a clean, but wrong, "ambiguous interface-method call to
  `to_json`" diagnostic — the call was never actually ambiguous, first-arg
  dispatch should have resolved it uniquely.

  Root cause: `lib/tir/mono.ml`'s `record_to_typename` reverse-map (structural
  `TRecord` mangle-string → nominal type name, used to resolve interface
  dispatch for a first argument whose static type is a record) was keyed only
  on each type's DECLARED field shape. A record LITERAL at a call site is
  fully structural all the way down — `{ inner : { id : Int }, label :
  String }` for `type Outer = { label : String, inner : Inner }` — so a
  nested field keeps its declared nominal `TCon("Inner")` in the map's key
  but arrives structural at the call site. The two mangle strings never
  matched, the lookup missed, dispatch fell through, and the bare `to_json`
  call reached either the linker (pre-fix) or the "ambiguous" diagnostic
  (post from_json-ICE fix) unresolved.

  Fix: also register a second, DEEP-normalized key per record type — every
  nominal record field recursively expanded to its own structural form —
  alongside the existing declared-shape key (which is tried first and never
  overwritten, so a type whose declared shape happens to collide with
  another's expanded shape keeps its own name). Expansion only follows
  parameterless `TCon`s that name a known record type, and a `seen`-set cuts
  recursion at the first revisit so a self-referential record (`{ next :
  Option(Node) }`) still resolves via its nominal `TCon`.

  Verified non-vacuous: an env-var-gated ablation of the new key reproduced
  the original link failure on the new fixture; with the key in place the
  fixture compiles and its output matches the interpreter's. Full suite
  (`scripts/run-tests.sh`, 833 tests) green.

  New regression coverage: `test/native/nested_derive_json.march` +
  `.expected` (three-level nesting, `Top -> Mid -> Leaf`, native
  compile-and-run diffed against interpreter output), wired via `test/dune`.
