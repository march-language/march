# REPL: every nullary constructor of a prompt-declared type evaluated as the type's FIRST variant (fixed 2026-08-24)

```
printf 'type Color = Red | Green | Blue\nGreen\nBlue\nRed\n:quit\n' | march
   before:  = Red   = Red   = Red
   after:   = Green = Blue  = Red
```

Not a display bug. The same wrong tag reached `match`, so evaluation was
silently wrong too:

```
type Color = Red | Green | Blue
match Blue do Red -> 1 Green -> 2 Blue -> 3 end   -- answered 1, not 3
```

Only the JIT path (the default). `MARCH_REPL_INTERP=1` was always correct,
which is why the "repl parity" tests never saw it: `Test_helpers.repl_eval_exprs`
drives the tree-walking interpreter directly and never touches the JIT. The
regression test therefore drives a real `march repl` subprocess, next to
`test_repl_renders_desugar_parse_error` which does the same for its own reason.

## Root cause: a REPL-declared type never reached codegen

The REPL loop evaluates a `DType` in the interpreter and hands it to the JIT
only through `Repl_jit.register_user_type_decl`, which registered it in
`ctx.global_type_defs` — the *pretty-printer's* table — and nowhere else.

Each subsequent expression is compiled as its own LLVM module, and
`Llvm_toplevel.build_ctor_info` numbers constructor tags from exactly the
`~types` list handed to that fragment (`ctx.loaded_tir_types @ tir.tm_types`).
`Color` was in neither, so the fragment's `ctor_entry` lookup missed, fell
through the `".<ctor>"` suffix search (also empty), and returned its default:

```ocaml
{ ce_tag = 0; ce_fields = List.init n_args_fallback (fun _ -> Tir.TVar "_") }
```

Tag 0 for *every* constructor. The printer then faithfully rendered tag 0 —
the first variant — and `emit_case` compared against the same 0 for every arm,
so the first arm always won.

`register_user_type_decl` now also appends the lowered `type_def` to
`ctx.loaded_tir_types` (codegen's numbering input) and the AST decl to
`ctx.stdlib_decls` (the lowering context, so a bare `Green` lowers to the
type-qualified `Color.Green` key instead of relying on the suffix search to
break a tie between two prompt-declared types that share a constructor name).
A re-declaration at the prompt *replaces* both entries rather than appending:
`build_ctor_info` is first-wins, so a stale entry would keep handing out the
old variant numbering.

## The second half: the printer assumed the fallback's representation

Registering the type fixes the tag but changes what the fragment *returns*,
and that exposed a printer that had been written against the fallback shape
(always a heap cell, all fields low-bit tagged) rather than against `Repr`:

| value | before this fix | with tags fixed, old printer | now |
|---|---|---|---|
| `X(7)` of `type T = X(Int) \| Y` | `X(7)` (by luck: X *is* tag 0) | `15` | `X(7)` |
| `P1(7)` of `P0 \| P1(Int) \| P2` | `P0` | `P1(3)` | `P1(7)` |
| `Some(1)` | `3` | `3` | `Some(1)` |
| `Some("hi")` | REPL died | REPL died | `Some("hi")` |
| `None` | `null` | `null` | `None` |

Two independent conventions were being ignored:

- **Niche / newtype types are not heap cells.** `X(7)` IS the tagged word 15
  and `Y` IS a raw 0; there is no cell and no tag to read. The printer now
  classifies with `Repr.repr_of_ty`, plus the same two recoveries codegen's own
  decode sites use (`niche_repr_of_concrete` for a params-less TCon, and the
  abstract-arg override that `Llvm_case.effective_repr` applies), and decodes
  the word directly. `run_expr`'s "small word ⇒ print it as an integer"
  fallback and its `ptr = 0 ⇒ null` guard are both skipped for these types —
  they were what turned `X(7)` into `15` and `Y` into `null`.
- **A constructor field is tagged only when its DECLARED type is erased.** A
  field declared `TVar` gets a `ptr` slot, so a scalar stored there is coerced
  to `(v<<1)|1`; a field declared `Int` gets a real `i64` slot and is stored
  raw. The old code passed `~tagged:true` for every ADT field, which was right
  only because the fallback's field types were all `TVar "_"`. Taggedness is
  now decided on the declaration's own type, *before* the TCon's type args are
  substituted in — the substituted type says what the value means, not how it
  is stored.

`pp_field` and the new niche/newtype paths share one `pp_word` decoder so a
field slot and a whole niche value cannot drift apart. `pp_word` also handles
a genuinely erased (`TVar`) word by reading the low bit instead of
dereferencing: a tagged scalar dereferenced as a cell reads unmapped memory.

## Not covered

Stdlib ADT values still print as `#<tag:0>` in the JIT REPL (`Logger.Warn`,
`Http.Post`). Same class of gap — the warm-cache startup path dlopens the
prelude `.so` without ever lowering stdlib to TIR, so no stdlib `type_def`
exists to hand the fragment. Filed as
`specs/todos/2026-08-24-repl-jit-stdlib-adt-ctor-tags.md`; it needs the
`type_def` list cached alongside the `.so`, not a printer change.

## Tests

`test/test_eval.ml` → "repl integration" → *JIT: nullary ctor tags of a
REPL-declared type*. Drives `march repl` over a script covering all three
representations (boxed nullary, boxed-with-payload, niche) plus a `match`, and
asserts the printed forms. Verified to fail on the pre-fix `repl_jit.ml` and
pass after.
