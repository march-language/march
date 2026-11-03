# Option(Float) deep drop + Json.parse float-box leak (drop half; Json.parse half landed in #947)

Closes `specs/todos/2026-10-07-option-float-payload-shallow-drop.md` and
`specs/todos/2026-10-08-json-parse-number-float-leak.md` (same root family,
two distinct release sites).

## Fix 1 — Drop: a niche-capable declaration whose concrete instantiation is Boxed

`Drop.drop_op`'s `may_be_non_heap` arm routed every niche-CAPABLE type through
the null-test payload release, whose `erased_payload` answers `None` for
Boxed-encoded instantiations — and the `None` leg emitted a bare `EDecRC`.
`may_be_non_heap` classifies `Option` by its DECLARATION (payload `TVar` →
niche), but `Kind.repr_of` classifies `Option(Float)` as **Boxed** (0.0
bitcasts to the None niche, so the Some side is a heap cell holding a
`march_alloc_float` box). The bare `EDecRC` freed the Some cell shallowly and
orphaned the float box.

Fix: the `None` leg now falls through to `drop_fn_for`, which synthesizes the
Boxed-convention `__drop$Option_Float` (releasing the float box behind
`march_decrc_freed`'s unique path). Niche-safe scalars (`Option(Int)`,
`Option(Bool)`) still take the bare `EDecRC`: their value is a tagged
immediate, and their `drop_fn_for` memoizes negative. `Option(Unit)` keeps
today's behavior too (no heap child).

Measured (compiled, `live_allocs()` over 200/100 iterations, macOS arm64):

| probe (record `{ o : Option(Float), s : String }` loop) | before | after |
|---|---|---|
| scope-end aggregate drop | 200–201 | 1 (constant) |
| cross-fn record drop (`mk()`) | 201 | 1 |
| nested aggregates | 200 | 0 |

## Fix 2 — Json.parse FBIP slot orphan: landed separately

The `Json.parse` / `Some(f) -> Ok(f)` leg (emit_reuse_ctor releasing the old
pointer-convention slot before a raw double is stored over it) was fixed on
main by the ASAN sweep (#947, commits 5912087fa and 6cf3926ee). This change
therefore carries only Fix 1 (the Drop hunk); the probe keeps the `json_leg`
as a regression guard for the other half.

Narrowing found while landing it: the `drop_fn_for` fall-through is taken for
`Option(Float)` ONLY. `Option(Unit)` is a genuine niche whose None is the raw
word 0 (built C-side in test/native/ffi_codec2), and the synthesized deep drop
dereferences it (SIGSEGV addr=0x8).

## Verification

- All probe legs flat (`probe_*` scratch programs over records, nested
  aggregates, `Option(Int)`/`Option(String)` controls, list legs).
- `test/run_compiler.exe -e`, `test/run_codegen.exe -e` green.
- `march query verify` reports no findings across 42 stages.
