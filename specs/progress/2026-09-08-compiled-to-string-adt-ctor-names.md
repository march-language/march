# Compiled `to_string` renders user ADTs by constructor name

**Filed:** 2026-08-05 (as `specs/todos/2026-08-05-compiled-to-string-adt-ctor-names.md`)
**Landed:** 2026-09-08

## What was wrong

`march_value_to_string` — the C implementation behind the type-erased
`to_string`, and the normaliser every `~H` interpolation of a non-String value
goes through — had no constructor metadata. It could read a heap cell's tag,
but a tag is numbered PER TYPE from 0, so it carried no name, no arity and no
field types. Every user ADT printed `#<tag:N>`.

```
interpreted : to_string=Point(1, 2)
compiled    : to_string=#<tag:0>
```

The interpreter enforces no `derive Show` requirement, and `forge test`,
`forge run` and `march file.march` all run the interpreter, so a program could
pass its whole test suite and then print garbage once compiled.

## The fix

A per-compilation-unit constructor descriptor, emitted into the LLVM module and
walked by the runtime.

- `lib/tir/llvm_ctor_desc.ml` assigns a local id to every variant/record type
  whose repr is `Boxed` (the only shape with a readable header), writes a
  tab-separated descriptor naming each constructor, its tag and a one-character
  token per field, and emits it as a module global plus an `i32` base cache.
- `march_ctor_table_ensure` / `march_value_to_string_typed`
  (`runtime/march_extras.c`) parse the descriptor once and render a value
  through it, recursing into fields.
- Call sites: the `to_string` arm in `lib/tir/llvm_emit.ml` and all three
  escape paths in `lib/tir/llvm_emit_html.ml` use the table whenever the
  argument's STATIC TIR type names a described type, and fall back to the old
  generic renderer otherwise.

Tags come from `ctor_info`, never from the declaration index: actor-message and
colliding-short-name types are given globally-unique tags, and a table keyed on
the index would misname every one of their constructors.

## Static, not a header stamp

`specs/todos/2026-08-05-boxed-adt-type-id.md` proposes the dynamic answer:
stamp a type id into every boxed cell's `march_hdr.pad`. That answers the
question at a genuinely erased site but charges a store to EVERY boxed
allocation. The static route charges nothing at allocation and covers every
site where the static type is known, which is where `to_string`, `println` and
`~H` actually render ADTs. **That todo stays open** for the residual: a value
reaching a `TVar` hole still renders `#<tag:N>`, and `march_value_to_string`
still cannot recognise an `IOList` handed to it generically.

## Output is the INTERPRETER's, deliberately

Rendering mirrors `March_eval.Eval_runtime.value_to_string` — the interpreter's
Show-less fallback, and what its `~H` path uses via `value_display` — not
`derive Show`'s output. So nested strings are QUOTED, `List` renders in bracket
form, and records render as `{ k: v, ... }`. Matching `derive Show` instead
would have swapped one parity gap for another.

## Anti-drift

The todo asked for the capability lattice's three-part shape (OCaml
source-of-truth, generated C, freshness check in `test/dune`). Two of the three
transfer; the third does not, and the reason is worth recording. The descriptor
is generated at COMPILE time into the LLVM module, not checked in, so there is
no generated file for a freshness check to diff — nothing can go stale.

What CAN silently drift is the meaning of a field token between the OCaml
writer and the C parser, and a drifted token is a MISREAD field (wrong number,
wrong string, a walk off the end) rather than a missing name. The check for
that is behavioural: `test/native/to_string_ctor_names.march` exercises every
token — `i`, `b`, `u`, `f`, `s`, `A` (nested ADT), the record shape and the
`List` bracket form — and its `.expected` is the interpreter's own output, so
the dune rule is an interpreter/compiled parity diff. The field kinds are
exactly `Llvm_ctx.llvm_field_ty`'s slot representations; both files say so at
the top.

## Tests updated

- `test/native/h_sigil_adt_interp.expected` pinned `#<tag:N>` as compiled
  output, annotated in the file as a known defect rather than intended
  behaviour. Regenerated to the interpreter's rendering.
- `test/native/h_sigil_safe_collision.march` renders the wrapper rather than
  the markup under a `Safe` short-name collision; it is now legible.

## Known cost, and the follow-up it deserves

The descriptor covers every describable type the compilation unit lowered,
which after the stdlib is ~13KB of `.rodata` in any binary that uses the table
at all. A binary that never renders a described type carries none of it
([Llvm_ctor_desc.id_for] deliberately emits nothing, so the match guard at a
`to_string` site that answers "no" — a tuple, a `TVar`, a newtype — costs
nothing).

Trimming it to the types actually reached from the call sites is a real
follow-up and was NOT done. It needs the descriptor to be built after all
functions are emitted (which `emit_module` allows — the preamble buffer is
flushed after `ctx.buf`), a transitive closure over nested `A` field
references, and an explicit type-count header so the runtime can size a sparse
array. Left out deliberately rather than attempted late: it is a size
optimisation, and the version here is correct.
