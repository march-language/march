# Boxed ADT cells carry no type identity, so the runtime cannot tell types apart

**Filed:** 2026-08-05
**Priority:** P2 — currently costs correctness (not safety) at polymorphic sites

## The gap

A boxed ADT cell's `march_hdr` is `{ int64_t rc; int32_t tag; int32_t pad; }`
(`runtime/march_runtime.h:12`). `tag` is the constructor index, numbered **per
type** from 0. Nothing in the cell says *which type* it belongs to, so at
runtime `IOList.Str("x")` and `B("x")` are indistinguishable: both are a boxed
cell with `tag == 1` and one pointer field.

That is the root cause of the `~H` misread fixed in
`specs/progress/2026-08-05-h-sigil-adt-misread.md`. That fix works by deciding
from the **static** TIR type in `llvm_emit`, which is the right answer wherever
a static type exists.

## Where it still bites

It does not exist for an unresolved `TVar` — a value reaching a hole through a
closure stored in a container, which mono does not specialise:

```march
let b = Bx(Cons(fn x -> ~H"<p>${x}</p>", Nil))
apply_first(b, some_value)
```

Neither answer is correct there: an `IOList` wants flattening, an ADT must not
be flattened. The `~H` fix resolves it toward safety — stringify — so a genuine
`IOList` partial reaching a polymorphic hole renders `#<tag:2>` instead of its
markup. Pinned as `poly_iolist` in `test/native/h_sigil_adt_interp.march`.

`march_value_to_string` has the same problem from the other side: it cannot
flatten an IOList it is handed generically, because it cannot recognise one.

## Sketch of a fix

`pad` is **free for non-record ADTs** — `march_runtime.c:295` zeroes it, and
only the record path uses it (as an interned shape id, via
`march_record_shape_intern`; see `march_extras.c:1875`). So a per-type id could
be stamped into `pad` at boxed-ADT allocation, letting the runtime answer "is
this an IOList?" directly.

Costs to weigh before committing to this:

- Every boxed ADT allocation gains a store. Measure against
  `bench/binary_trees.march` (allocation-heavy) and `bench/tree_transform.march`
  (Perceus/FBIP), per `specs/benchmarks.md`.
- `pad` is 32 bits shared with the record shape-id space; the two schemes must
  not collide. Records and ADTs are disjoint today, but that is an invariant
  worth asserting rather than assuming.
- Cross-heap copy (`march_message.c:138`) and the WASM runtime
  (`march_runtime_wasm.c:432`) both zero `pad` and would need updating.

If this lands, three things get better together: polymorphic `~H` holes become
correct rather than merely safe, `march_value_to_string` can flatten IOLists,
and the `tag > 2` abort guard in `march_html_auto_escape` can become an exact
check instead of the partial one documented at that site.

Related: `specs/progress/2026-09-08-compiled-to-string-adt-ctor-names.md`
(landed; the constructor-name table took the static route instead of sharing
this type-id mechanism — see the narrowing note at the end of this file).

---

## Narrowed 2026-09-08 — the STATIC half landed; this is the residual

`specs/progress/2026-09-08-compiled-to-string-adt-ctor-names.md` closed the
sibling todo (`to_string` printing `#<tag:N>`) with a COMPILE-TIME constructor
descriptor: the emitter knows the static TIR type at a `to_string`/`~H` site,
so it passes a type id and the runtime walks a table. That charges nothing at
allocation, which is why it was preferred over the header stamp proposed above.

This item stays open for exactly what the static route cannot reach. Each of
these is pinned as a `#<tag:N>` / placeholder line in
`test/native/h_sigil_adt_interp.expected`, with the reason named in that file's
header comment:

1. **An erased (`TVar`) slot** — the original motivation. Still `#<tag:N>`, and
   `march_value_to_string` still cannot recognise an `IOList` handed to it
   generically, so a genuine `IOList` partial reaching a polymorphic `~H` hole
   is stringified rather than flattened.
2. **Niche-encoded types** (`Option`): `Some(x)` IS `x` and `None` is null, so
   there is no wrapper cell and no tag. Note for an implementer: asking
   `Repr.repr_of_ty` about a bare `TCon (name, [])` answers `Boxed` for these,
   because the niche decision needs the type arguments that key does not carry.
   `Llvm_ctor_desc.describable` calls `Repr.is_niche_shaped` directly for that
   reason; getting this wrong prints a confidently WRONG constructor rather
   than a placeholder, which is worse than the bug being fixed.
3. **Newtype-repr types** (one constructor, one field): the value IS the
   payload, so a table lookup would read the payload's header and print the
   payload's constructor under the wrapper's name.
4. **Anonymous record literals and tuples**: no declared type name for the
   table to key on. (Tuples reach `to_string` through `Show$TupleN.show` and
   are fine there; only the `~H` path shows the placeholder.)
5. **Generic fields instantiated at a concrete type**: a `Cons(a, ...)` field
   is described as the generic token `p`, so a `List(Shape)` nested inside
   another value renders its elements through the untyped renderer. The
   element's own top-level `to_string` is unaffected.

A header type id would close 1, 2, 3 and 5 together. It would not close 4.
