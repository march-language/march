# Dropping a tuple or record leaves its boxed Float fields allocated (compiled)

Found 2026-10-01 while checking `specs/progress/2026-09-28-array-built-then-dropped-leaks-trie.md`
under ASAN.

A `Float` stored in a tuple or record is a boxed cell (`march_alloc_float`). The
synthesized aggregate drop (`Drop.build_aggregate_drop_fn`) releases only the fields for
which `Kind.needs_rc_of` holds, and that is false for `TFloat`, so the box outlives the
aggregate:

```march
fn ret_bf(b : Bool) : (Bool, Float) do (b, 2.5) end
pfn once(i : Int) : Int do
  let (flag, f) = ret_bf(i > 0)
  if flag do string_length(float_to_string(f)) else 0 end
end
```

leaks 1 object per call (`live_allocs()` delta 41 over 40 iterations, `--opt 2`) now that
the pair itself is released (`let (a, b) = ..` used to leak the pair too: 2 per call). LeakSanitizer reports it as
one 24-byte `march_alloc_float` for `test/native/let_tuple_destructure` (it printed no leak
before, presumably because the optimiser removed the tuple; the explicit release now keeps
the allocation, and the float inside is never freed).

An `EField` of a Float field loads the UNBOXED double, so the drop cannot simply `dec_rc`
the projected variable; it needs the raw box pointer. Witness: the program above must
reach delta 0.
