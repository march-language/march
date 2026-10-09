# Option(Float) deep drop + Json.parse float-box leak (two fixes)

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

## Fix 2 — emit_reuse_ctor: FBIP cross-type slot orphans + a misfiring niche-skip guard

`Json.parse_number`'s `reuse $opt as JsonValue.Number(f)` reached `emit_reuse_ctor`
through the **niche-skip guard** (`is_niche_shaped reuse_atom_parent_type`),
which classifies `Option` by its declaration and fires even at
`Option(Float)` — a BOXED value at runtime. The arm allocated fresh and
deliberately touched no RC, orphaning the dying Some cell's own reference and
its float-box slot content (one leaked `march_alloc_float` per parsed
number, `grow=101` over 100 parses of `"3.5"`).

Two changes:

1. **Narrowed the niche-skip guard** to a payload that is genuinely
   niche-safe at runtime: `niche_repr_of_concrete` (non-generic decl) or a
   non-Boxed `repr_of` (generic instantiation). `Option(Float)` now falls
   through to the real FBIP branch.
2. **FBIP cross-type slot orphans**: `same_arity` matches field COUNT, never
   slot convention, so the reuse branch stores a raw `double` over a
   pointer-convention slot. On both rc==1 paths (reuse + fresh), each old slot
   the new ctor stores a raw double over is loaded and released
   (`march_decrc` is IS_HEAP_PTR-guarded, so a tagged immediate/null is a
   no-op). Same-type raw-double reuse (`Number` reusing a `Number`) is
   excluded — releasing raw double bits would sniff garbage.

**The load-bearing trap:** Perceus rewrites the freed scrutinee's type to the
FBIP arity marker `$fbip$Option.Some(Unit)` before codegen, so the reuse
atom's `v_ty` at emit time is NOT `Option(Float)`. The slot-convention
predicate strips the marker (`Perceus_fbip.is_fbip_encoded`) before the
variant lookup — without this the whole fix ships dead, which is exactly what
the first build did until the marker was traced in the emitted IR.

Measured: `Json.parse("[1.5, 2]")` and `Json.parse("3.5")` loops went
`grow=201`/`101` → `grow=1` (the residual 1 is a constant warm-up one-off,
not a rate).

## Verification

- All probe legs flat (`probe_*` scratch programs over records, nested
  aggregates, `Option(Int)`/`Option(String)` controls, list legs).
- `test/run_compiler.exe -e`, `test/run_codegen.exe -e` green.
- `march query verify` reports no findings across 42 stages.
