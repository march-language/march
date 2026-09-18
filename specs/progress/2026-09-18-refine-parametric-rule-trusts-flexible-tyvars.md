# The parametric element rule no longer trusts type variables the body fixed

**Landed 2026-09-18.** Design: `specs/2026-09-18-parametric-element-flow-design.md` §1.
Plan: `specs/plans/2026-09-18-parametric-element-flow-plan.md`, Phase 0.

## The bug

`Refine_check.parametric_return` (P3 design §2c) reads a callee's **declared**
signature and reasons from parametricity: `List(a) -> List(a)` cannot make an
`a`, so its result keeps the argument's element refinement. Annotation type
variables are not rigid in March:

```march
fn bad(xs : List(a)) : List(a) do [0 - 5] end      -- typechecks, a := Int
fn g(xs : List({Int | _ > 0})) : Int do
  let ys = bad(xs)
  sum_pos(ys)                                      -- was reported PROVED
end
```

`cap verified` accepted it. The shipped rule's own guard, `safe`, had two more
holes of the same kind, both also proved before this change:

- `fn sw(xs : List(a), ys : List(b)) : List(b) do xs end`: the body unifies
  `a` with `b`, so `sw(unrefined, pos)` returned the unrefined list;
- `fn ins(xs : List(a), y) : List(a) do Cons(y, xs) end`: `y` is
  unannotated, so `safe` never saw it as a source of `a`;
- `append(pos, neg)` with `neg : List({Int | _ < 0})`: `slot_of_var` took the
  FIRST source's slot, so the whole result was assumed positive.

## The fix

`lib/refinecheck/refine_param.ml`, a new link in the include chain between
`Refine_post` and `Refine_check`. `parametric_return`'s `safe v` now also
requires `parametric_ok ctx fname [v]`:

- **P1, `generic_in_inferred`.** Reads the typechecker's parameter-binder
  types from `call_type_map` (the same table `if_arm_admitted` reads) and
  aligns each declared parameter type with its inferred one. `v`'s witnesses
  must all be one unbound type variable, and that variable must occur nowhere
  else in any parameter's inferred type (another declared variable's
  resolution, or an unannotated parameter recorded whole). A pattern
  parameter, a missing record, or a misaligned shape answers no.
- **P2, `parametric_safe`.** A greatest fixpoint over the call graph, per
  module. A body is tainted by a call to a builtin or builtin interface method
  whose scheme's result mentions a type variable its parameters do not
  (computed from `Typecheck_builtins.builtin_bindings` /
  `builtin_interface_bindings`, so there is no list to drift; `panic`,
  `panic_`, `todo_`, `unreachable_` are exempt as diverging), a user interface
  method of the same shape, an FFI extern, or an unresolvable global name. A
  call to another definition taints it only when that definition's declared
  return mentions a type variable and it is itself unsafe.
- A callee with a type-level bound on the variable (`fn_bounds`) never
  qualifies. Neither does a callee the definition table does not know (a
  callback parameter, a local `fn`).
- Every source of the variable must carry the SAME element slot (compared by
  rendering); disagreeing sources lend nothing. (Phase 3 later replaced `safe`
  itself with the source analysis; see
  `2026-09-18-refine-demand-driven-element-instantiation.md`.)

`resolve_call` became an instance of `resolve_call_gen`, which is polymorphic
in the table's value type, so `Refine_param.resolve_key` answers *which*
definition a call reaches by exactly the rule every other lookup uses.

The creating builtins as of this change: `Chan.new/send/recv/choose`,
`Supervisor.start_child`, `actor_call`, `actor_whereis`, `cap_dict`,
`cap_narrow`, `cap_ops_empty`, `from_json`, `from_json_events`,
`get_actor_field`, `logger_get_fields`, `mint_cap`, `pid_of_int`,
`process_spawn_lines`, `receive`, `record_entries`, `record_from_list`,
`record_get`, `record_values`, `ring_buf_make`, `to_json`, `vault_new`,
`vault_ns_get`, `vault_whereis`. The unsafe stdlib definitions are the
`Actor`, `Config`, `Logger`, `Vault`, `Session*`, `NodeQueue`, `JsonStream`
and IO/System surfaces. No `List`, `Option`, `Result`, `Map`, `Set`, `Array`
or `Seq` function is tainted.

## Tests

`test/test_refinecheck.ml`, group `parametric-soundness` (7 cases, typed
harness): a generic control that proves; `bad` (ledger `(0,0,1)`, and an error
under `cap verified`); `sw`; `ins`; a body that creates through `from_json`,
directly and through a helper; `cat(pos, neg)` with a `cat(pos, pos)` control;
and "no type table answers no". With the test file copied onto an untouched
`HEAD` checkout every case but the generic control fails; with `parametric_ok`
forced to `true` cases 1–4 fail too.

The six §2c cases in `container-subtyping-2` now run typed, because an
untyped fixture has no type table and P1 answers no there.

## Measurements

- `stdlib/list.march`: 43 proved / 40 skipped before and after, and the
  per-site skip list is identical.
- `List.take`/`List.drop` into a refined consumer still proves in the driver,
  so P1 reads stdlib parameter types on the production path.
- `scripts/refine-oracle.sh check` against a baseline recorded before the
  change: diagnostics identical, 7193 lines over 359 fixtures.
- `test_refinecheck.exe`: 906/906 with Phase 0 alone.

## Not done here

Whether annotation type variables should be rigid is a language question,
filed as `specs/todos/2026-09-18-typecheck-annotated-tyvars-flexible.md`.
