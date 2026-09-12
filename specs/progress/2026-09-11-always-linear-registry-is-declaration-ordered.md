# `[P2]` Linearity: `always_linear` tracking depends on declaration order

**Shipped 2026-09-12.** See "What shipped" at the end.

Found 2026-09-11 while closing out
`specs/progress/2026-09-03-protocol-projector-typed-endpoints.md`, whose
generator inserts its modules before the user's first ordinary declaration
*only* to dodge this. Not recorded in `specs/lang/linear-types.md`'s findings
(L1–L8).

## The bug

`env.always_linear_types` is written in exactly one place — `check_decl`'s
`DAlwaysLinearType` arm (`lib/typecheck/typecheck.ml:5145-5159`, registering
the bare and the module-qualified name) — and `check_decl` runs as a
sequential fold over the declarations. So a function checked **before** the
declaration is reached sees the type as ordinary, and every linearity
guarantee is silently absent for it.

It is **not** nested-module-specific, which is how the progress file described
it. Measured on `main` at `87101987`, `--check`, exit codes read directly:

| shape | order | result |
|---|---|---|
| top-level `always_linear type`, value used twice | type declared **first** | rejected |
| top-level `always_linear type`, value used twice | type declared **after** the fn | **accepted** |
| nested `mod G`, value used twice | module **first** | rejected |
| nested `mod G`, value used twice | module **after** the fn | **accepted** |
| nested `mod G`, value abandoned | module **after** the fn | **accepted** |
| top-level, value abandoned | type declared **after** the fn | **accepted** |

Both halves of linearity are lost — reuse and must-use — and the program that
loses them is silently accepted, so nothing marks it.

```march
mod OB do
  needs IO.Console
  fn main(c : Cap(IO.Console)) do
    let a = S(1)
    let x = step(a)
    let y = step(a)          -- reuse: accepted, no diagnostic
    print_line(int_to_string(x + y))
  end
  fn step(s : S) : Int do match s do S(e) -> e end end
  always_linear type S = S(Int)
end
```

`reorder_decls` does not save it: it reorders runs of `DFn` and runs of `DMod`
among themselves, never moving a type declaration ahead of a function.

**The stdlib is not currently exposed** — `stdlib/handle.march` declares its
`always_linear type Handle` on line 7, before any function — so this is a
latent user-facing hole, not a live miscompile of the stdlib.

## Why the pre-pass does not already cover it

`check_module_core` has a pass-1 prebind that seeds types before the
sequential fold, and it is applied to top-level declarations as well as
nested ones (`typecheck.ml:6239-6241` passes the non-`DMod` declarations
through the same `prebind_mod_members`). But its type arm collapses the two
declaration forms:

```ocaml
| Ast.DType (vis, name, params, typedef, _)
| Ast.DAlwaysLinearType (vis, name, params, typedef, _) when vis = Ast.Public ->
```

— registering arity, bare and qualified names, and constructors, but **never
the linearity**. There are two copies of this: `prebind_mod_members`
(`~:6009`, `check_module_core`) and `prebind_mod_members_inc` (`~:6388`,
`check_module_with_env`, the REPL/LSP/incremental path). The file already
worries about exactly this kind of divergence — see the note on
`prebind_interface_decl`, shared by both "so the two cannot diverge" after the
incremental copy once omitted interfaces entirely.

## The interacting defect: one promotion site bypasses the shadow check

Fixing the ordering naively makes a second, **live** bug fire in more
programs, so the two must be fixed together.

Four sites promote a binding to linear because its type is `always_linear`.
Three go through `Typecheck_env.resolves_always_linear`, which implements the
finding-L4 stopgap (a module's own same-named type shadows an imported one).
One does not:

```ocaml
(* typecheck.ml:237, inside the let-binding promotion *)
| TCon (name, _) when List.mem name env.always_linear_types -> Some Ast.Linear
```

Because the registry holds **bare** names too, an unrelated same-named type is
infected. Measured, and rejected today:

```march
mod HZ do
  needs IO.Console
  mod G do always_linear type S = S(Int) end
  type S = S(Int)                    -- an ORDINARY type, unrelated
  fn get(x : S) : Int do match x do S(v) -> v end end
  fn main(c : Cap(IO.Console)) do
    let a = S(1)
    let x = get(a)
    let y = get(a)                   -- exit 1: "used more than once"
    print_line(int_to_string(x + y))
  end
end
```

That is a false positive on ordinary code. Reversing the order (nested module
last) makes it disappear — the same ordering hole, masking the infection.

## What to build

1. **Seed the registry in the pre-pass.** Extract a shared helper, in the
   spirit of `prebind_interface_decl`, that given a prefix and a declaration
   list returns the `always_linear` names to add (bare and `prefix.Name`,
   matching `check_decl:5147-5159`), and call it from **both**
   `prebind_mod_members` and `prebind_mod_members_inc`. One helper, not two
   edits, so the paths cannot drift.
2. **Route `typecheck.ml:237` through `resolves_always_linear`.** Predicted
   outcome, to be verified rather than assumed: `HZ` above becomes accepted
   (`current_module ^ ".S"` is in `env.types`, so the shadow branch consults
   `HZ.S`, which is not registered linear), while a nested type used from its
   parent with no local shadow keeps working (no `OC.S` in `types`, so the
   bare branch applies).
3. Leave `check_decl`'s own registration in place; the pre-pass seeds, the
   fold confirms.

Do **not** try to fix this by reordering declarations. The registry is an
environment fact, and the sequential fold is not going to stop being
sequential.

## Tests

Reject witnesses (`specs/lang/types/reject/`, next free is `t191`), each
`-- EXPECT-ERROR:` pinned:

- top-level `always_linear type` declared **after** the function, value reused
  → `is used more than once`
- same, value abandoned → `was never used`
- nested module declared **after** the function, value reused → `is used more
  than once`

Accept witness (`specs/lang/types/accept/`):

- the `HZ` program above: an ordinary top-level type sharing a name with a
  nested `always_linear` type is **not** infected. This is the guard on fix 2
  and the one that fails if fix 1 lands alone.

Unit (`test/test_compiler.ml`, near the other linearity cases): the same four
through the ordinary harness, so they run outside the corpus sweep.

**Prove each reject RED before trusting it** — three of these are accepted
today, so an unchanged test file means the fix did nothing.

Also re-run `scripts/run-tests.sh` in full: `stdlib/handle.march` and the
generated-endpoint corpus (`accept/t190`, `reject/t186`–`t189`) are the
existing users of `always_linear`, and fix 2 changes promotion for every one
of them.

## Follow-on, once this lands

`lib/desugar/desugar_endpoints.ml` inserts its generated modules before the
user's first ordinary declaration specifically because of this bug (see the
comment at the insertion point in `desugar.ml`). That placement is harmless
and need not change, but the comment's reasoning should be updated to say the
hazard is fixed, or the constraint will be read as load-bearing forever.

Related: [[2026-09-10-linear-lambda-parameter-not-must-use]],
[[2026-09-11-linear-actor-handler-parameter-untracked]] — three holes in the
same subsystem, each found by building something that depended on it.

---

## What shipped (2026-09-12)

Both halves, as specced.

- `Typecheck.always_linear_names ~modname decls` walks the declaration tree
  and returns each `always_linear type`'s bare and module-qualified name,
  spelled as `check_decl` spells them — a nested module qualifies with its own
  bare name, because that is what `check_decl` sets `current_module` to. Pass 1
  seeds it in **both** paths: `check_module_core` (folded into the same
  `{ pre_env with current_module = … }` block) and `check_module_with_env`, the
  incremental/REPL/LSP path.
- The let-binding promotion at `typecheck.ml:237` now goes through
  `resolves_always_linear` instead of reading the registry raw.

Measured before and after on the same six orderings: top-level and nested,
declared before and after the use, reuse and drop. The four that were silently
accepted are now rejected; the two that were already correct still are. The
L4 infection case went the other way, from rejected to accepted, which is the
half that fails if only the seeding lands.

Witnesses: `reject/t191`–`t193`, `accept/t194`, plus four unit cases in
`test_compiler.ml`'s `tag_and_typestate` group. Full suite, corpus (315/315)
and the TIR goldens are green.

**Not done:** `lib/desugar/desugar_endpoints.ml` still inserts its generated
modules ahead of the user's first ordinary declaration. That is now belt and
braces rather than load-bearing; `reject/t193` is the guard either way. The
comment there was left alone deliberately — changing generator placement is a
separate diff from a typechecker fix.
