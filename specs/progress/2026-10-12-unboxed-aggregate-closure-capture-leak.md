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

## Fixed (2026-10-12)

The cause was as filed, with one widening: the box is the environment's own
cell in EVERY closure, not only the ones whose environment owns its heap
captures (`Drop.owning_apply_fns`). `classify_guarded`'s join-point closures
are ELet-bound and non-escaping, so they are not "owning" and got neither a
`$clodrop$` fn nor the apply-fn rewrite at all.

`lib/tir/drop.ml`:
- `unboxed_capture_fields` lists a closure type's `$fvN` slots that hold an
  unboxed aggregate (same `Kind.unboxed_of_type_name` test as
  `Llvm_ctx.llvm_field_ty`, so the two cannot disagree on which slots are boxes).
- `rewrite_apply_clo_drop` takes `~heap` (release heap captures: the old
  `owning` gate) and `~boxes`. At the spliced `dec_rc $clo` (and at a
  self-alias's release) it loads each box's raw slot word as `Ptr(Unit)`
  BEFORE the release, turns the release into `march_decrc_freed`, and
  `dec_rc`s the boxes right there when it freed the environment. No tail
  placement is needed: the prefix already copied the struct out of the box.
  The apply rewrite now runs for an apply fn that is owning OR has boxes.
- `clo_drops` builds `$clodrop$<clo>` for a closure type that is owning (heap
  captures, as before) OR has boxes (always released), so a closure dropped
  uncalled through `march_clo_release` frees its boxes too.

Closures are never stack-promoted (`Escape`'s clo-candidates rule), so the
box is never reached through a stack environment.

Probe: `test/native/unboxed_capture_leak_probe.march` (guarded or-pattern join
point; factory closure called; dropped uncalled; called three times while
shared; one closure in a list four times alongside another; heap + unboxed
captures; local lambda). Every leg prints its computed value too, so a box
released while still shared shows as a wrong value. Base compiler: all seven
legs `flat: false`; fixed: all `flat: true`, values unchanged.

Sanitizers (Docker `march-ci-ubuntu-step6b`, arm64, `scripts/native-sanitize-sweep.sh -l`,
schedulers 1 and 14): `unboxed_capture_leak_probe`, `or_pattern`,
`closure_capture_release_probe`, `closure_capture_hof_loop_probe`,
`closure_call_arg_ownership_probe` all OK. Control with the base `drop.ml` in
the same container: `unboxed_capture_leak_probe` and `or_pattern` LSAN.

Full ASAN sweep (no leak pass, schedulers 1 and 14, both fixes in): 346
fixtures, no ASAN/UBSAN/LSAN/RCCHECK/SIGNAL verdict; the 10 EXITs are the
panic-by-design fixtures. Bench A/B on an M3 (`--compile --opt 2`, base
compiler+runtime vs branch, 5 runs after one warmup): `list_ops` 55-69 ms vs
56-68 ms, `binary_trees` 79-87 ms vs 73-86 ms, i.e. no change.
