# `[P3]` A closure capturing an unboxed aggregate leaks the capture's box

**Found** 2026-10-12 by the LSan pass of `scripts/native-sanitize-sweep.sh`
(`or_pattern`: 64 B leaked in `classify_guarded`).

```march
mod C do
  needs IO.Console
  type Pair = Pair(Int, Int)        -- scalar-only: an Unboxed aggregate

  pfn classify_guarded(p : Pair) : Int do
    match p do
      Pair(x, 1 | 2) when x > 0 -> x + 100
      Pair(x, _)                -> x
    end
  end

  pfn spin(n : Int, acc : Int) : Int do
    if n <= 0 do acc
    else spin(n - 1, acc + classify_guarded(Pair(n % 3 - 1, n % 4))) end
  end

  fn main(_c : Cap(IO.Console)) do
    let _ = spin(5, 0)
    let a0 = live_allocs()
    let _ = spin(1000, 0)
    println(int_to_string(live_allocs() - a0))   -- 1000 on main, want 0
  end
end
```

The guarded or-pattern lowers to join-point closures; `$jp6` captures `p`.
`Pair` is `Repr.Unboxed`, so in the closure's 8-byte capture slot it is a BOX
(`Llvm_ctx.llvm_field_ty`). The apply fn copies the struct out of the box
(`Llvm_emit_tcoarm.emit_fv_load`) and frees the closure shallowly; the
closure drop fn synthesized in `lib/tir/drop.ml` (`clo_drops`) and the
apply fn's own environment release (`rewrite_apply_clo_drop`) both filter
captures by `Kind.needs_rc_of`, which is false for an unboxed aggregate. So
nothing releases the box: one 32-byte cell per call.

Likely fix: treat an unboxed-aggregate capture like a tuple's boxed Float
(`Drop.tuple_boxed_float`): read the raw slot word as `Ptr(Unit)` and
`EDecRC` it, in both the clo-drop fn and the apply-fn environment release.
Needs a probe with a capturing lambda over an unboxed aggregate that is called,
dropped uncalled, and called while shared.
