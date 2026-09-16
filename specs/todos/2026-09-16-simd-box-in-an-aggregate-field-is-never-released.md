`[P2]` # A SIMD vector stored in an aggregate field leaks its box when the aggregate dies

Found 2026-09-16 while closing the non-TCO vector-parameter leak
(`specs/progress/2026-09-16-simd-vector-box-released.md`), measured by the third
leg of `test/native/simd_nontco_leak_probe.march`.

```march
pfn keep(v : F32x4, k : Int) : List(F32x4) do
  if k <= 0 do Nil else Cons(v, keep(v, k - 1)) end
end
-- build a 3-element list per iteration, read its length, drop it: 20,000
-- iterations grow live_allocs by 60,000 — exactly the three boxes per list
```

The escaping shape is the one the call site must NOT release: the `Cons` cell
owns the box (`test/native/simd_vector_escape_arg.march` pins that direction,
and the 2026-09-16 fix keeps it). But when the list itself dies, the box is not
released either — so the value has an owner on paper and none in practice.

Unchanged by that fix: `main` leaks all three legs, the fix makes the first two
flat and leaves this one at 60,000.

## Where to look

`Drop.run` synthesizes `__drop$List_F32x4` and the arm releases each field
through `drop_fn_for` / a bare `EDecRC`. Two candidates, and the first is
cheap to check:

- `Kind`'s classification of a SIMD type. `layout_of` answers `Vec n` and
  `llvm_ty` deliberately answers `ptr` ("boxed at rest, native in kernels"),
  so a field release has to go through the `ptr` spelling. If
  `may_be_non_heap` or `needs_rc_of` answers the "native" half for a type that
  is boxed AT REST, the field is skipped and the box leaks.
- The generated drop's field op itself — read `__drop$List_F32x4` in
  `--emit-llvm` and see whether a `march_decrc` is emitted for the head field
  at all.

## Verification bar

The probe's third leg goes flat, `simd_vector_escape_arg` and
`simd_vector_core`/`simd_vector_mem` stay green, and the ASAN gate (which now
sweeps the two-node scenarios) is clean — an over-eager field release is a
use-after-free, not a leak.
