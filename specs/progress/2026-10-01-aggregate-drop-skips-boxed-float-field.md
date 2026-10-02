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

**Also reproduces with `List(Float)` cons cells** (found 2026-10-01 while writing
`test/native/rc_inline_fast_path.march`): building `Cons(int_to_float(k), Cons(0.5, Nil))`,
folding it with `List.fold_left`, and dropping it leaks 2 objects per iteration
(`live_allocs()` delta 4000 over 2000 iterations, `--opt 2`), one per Float element. The
same with `MARCH_NO_INLINE_RC=1`, so it is not the inline refcount fast path; the
interpreter is flat. That fixture's leak check therefore leaves its Float leg out; put it
back when this is fixed.

## Fixed 2026-10-02

Where a Float lives decides whether there is a box to release, and `drop.ml`
now reads it straight from the slot when there is:

- A **tuple** stores every field in the uniform `ptr` slot, so its Float IS a
  `march_alloc_float` box (`ETuple` coerces the double into one). The
  aggregate drop binds that slot as a raw `Ptr(Unit)` (an `EField` with the
  `$fvN` accessor on a `Ptr`-typed binder loads the word without unboxing) and
  releases it on the freed path. A **record** (`ERecord`, nominal or
  structural) stores a declared Float as a raw `double` and owns nothing.
- A **constructor field declared as a type parameter** and instantiated at
  Float (`List(Float)`'s element, `Option(Float)`'s payload) is a box too;
  `boxed_float_slots` finds those by comparing the declared and substituted
  field types, and the variant drop's arm reads the slot word before
  `march_decrc_freed` and releases it in the freed branch. A field declared
  `Float` outright is a raw double. `Llvm_case` binds such a field as a copy of
  the double and only releases the box on its own `strip_scrut_decrc` path,
  which the synthesized drops never take — that is why `__drop$List_Float`
  freed the spine and left every element behind.

Regression: `test/native/aggregate_drop_erased_fields.march` legs 1a/1b (tuple
Float, `List(Float)` through a fold and through a destructuring sum). The Float
leg of `test/native/rc_inline_fast_path.march` is back in its leak check.
