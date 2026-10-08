`[P2]` A dropped `Option(Float)` held inside another value leaks its Float box (compiled)

Found 2026-10-07 while fixing
[../progress/2026-10-07-nested-option-float-match.md](../progress/2026-10-07-nested-option-float-match.md).
Present on main before that fix.

```march
pfn typed(o : Option(Option(Float))) : Float do
  match o do
    Some(Some(f)) -> f
    Some(None) -> 0.5
    None -> 0.0
  end
end
-- 200 calls of typed(Some(Some(int_to_float(3) + 0.5))): live_allocs() grows by 200
```

The caller releases the argument with `__drop$Option_Option_Float`, which is
`case x of Some(p) -> dec_rc p | _ -> ()`: the inner `Option(Float)` cell is freed
shallowly and its Float box is orphaned. The same holds for `Result(Option(Float), _)`'s
`Ok` field and any other `Option(Float)`-typed child.

Cause: `Drop.may_be_non_heap` answers true for every Option-shaped type, args or not
(`Kind.niche_repr_of_concrete "Option"` classifies by the declaration, whose payload is a
type variable), so `drop_op` gives an `Option(Float)` child a bare `EDecRC` instead of the
`__drop$Option_Float` its Boxed representation needs. That fallback is deliberate (leak,
never crash): some runtime and FFI paths build niche (null) Options over niche-unsafe
payloads (`test/native/ffi_codec2`'s `Option(Unit)` field), and a deep drop would
dereference the null. A fix needs a deep drop that is safe on a non-heap word (an
IS_HEAP_PTR / null test before the tag switch), or one representation for these Options.
