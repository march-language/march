# `Entry`: an alias for a role's entry state

Shipped 2026-09-21. Filed 2026-09-20 by the choreography UX pass
([[2026-09-20-choreography-ux-hardening]]).

## The problem

Every role body's signature had to spell the role's first state, and the only way to
learn it was to work out `S_` plus the first step of that role's own projection
(`Fan_C.S_recv_Msg_A_C_1`). The generator already knows the name: `role_module` returns
it so `<P>_Run` can type the role's body by it.

## What shipped

`lib/desugar/desugar_endpoints.ml`'s `role_module` now also emits
`type Entry = <that state>` in each role module, so a body reads
`st : Fan_C.Entry`. The `S_` spellings are unchanged and keep working.

That alias had to be made to mean something. March has no surface alias syntax at all:
the parser builds every `type` declaration as `TDVariant` or `TDRecord` and never
constructs `Ast.TDAlias` (the note at `lib/refinecheck/refine_audit.ml:282` says so,
and is right). The `TDAlias` node existed but was inert in the typechecker, whose
`DType` arm registered a name and an arity and then returned the environment unchanged
for it. Emitting the alias on its own therefore produced an opaque nominal type, and
the first attempt failed with `expected \`Entry\` but got \`S_send_Msg_Prod_Cons_1\``.

So `TDAlias` was made transparent, which is a small addition and, since nothing else
constructs one, affects only the generated aliases:

- `ty_aliases : (string list * Ast.ty) StrMap.t` on `env`
  (`lib/typecheck/typecheck_env.ml`, plus both interface files).
- Registration in `check_decl`'s `TDAlias` arm and in both copies of
  `prebind_mod_members` (`lib/typecheck/typecheck.ml`), so a sibling module checked
  before the declaring one still resolves the name.
- Expansion in `surface_ty` (`lib/typecheck/typecheck_unify.ml`): the arguments are
  substituted for the parameters and the right-hand side is resolved in place of
  building a `TCon`.

Aliases are registered under their **qualified** name only, never the bare one. Every
role module of a protocol declares `Entry` and types share one flat namespace, so a
bare `Entry` key would resolve to whichever role happened to be registered first.
A bare `Entry` in a signature is now an unknown type, which is the safe answer.

## The two checks the todo asked for

**1. Linearity survives the alias — yes, and it was measured, not assumed.** A program
that consumes a state reached through `Stream_Prod.Entry` twice is rejected, and the
diagnostic is byte-identical (after normalising the file name) to the same program with
the state spelled `Stream_Prod.S_send_Msg_Prod_Cons_1`: "The linear value `st` is used
more than once here", with the same two spans. This falls out of the implementation:
`surface_ty` returns the state's own `TCon`, and `always_linear` is read off that name,
so there is no alias left by the time linearity is decided. Pinned by
`specs/lang/types/reject/t282_endpoints_entry_alias_linear.march` and by
`entry_keeps_linearity` in `test/test_endpoints.ml`.

A second witness guards the other way the alias could have gone wrong: annotating one
role's body with the *other* role's `Entry` is still rejected
(`expected S_send_Msg_Prod_Cons_1 but got S_recv_Msg_Prod_Cons_1`), so `Entry` did not
become one nominal type shared by every role.

**2. `Entry` cannot collide.** Generated state names all begin with `S_`. The other
names a role module emits are `Secret`, `Yield`, `Cancelled_<Role>`, `Crashed_<Role>`,
`Parked_<Role>` with its `Idle_<Role>`/`Awaiting_<state>`/`Closed_<Role>`
constructors, `Received_<Role>` with its `Got_`/`Crashed_` constructors, and the
functions (`register`, `cancelled`, `send_`/`recv_`/`choose_`/`offer_`/`leave_`,
`close`, `idle`, `take_idle`, `take_closed`, `cancel`, `await_`, `finish`, `resume`).
None is `Entry`.

A protocol whose ROLE is literally named `Entry` is not a collision either, and this
was checked by compiling one rather than by reading the generator: role names appear
only as a suffix, so the module is `Gate_Entry` and holds a type `Entry` aliasing
`S_send_Msg_Entry_Exit_1`, beside `Parked_Entry` and `Cancelled_Entry`. A body written
as `st : Gate_Entry.Entry` typechecks. Pinned by `role_named_entry_shape` and
`role_named_entry_ok` in `test/test_endpoints.ml`.

## Witnesses

- `test/test_endpoints.ml`: `entry_alias_shape` (each role module aliases `Entry` to
  that role's own first state, including a three-role protocol where the entry is a
  receive from a third party), `entry_roles_ok`, `entry_wrong_role`,
  `entry_keeps_linearity`, `role_named_entry_shape`, `role_named_entry_ok`.
- `specs/lang/types/accept/t281_endpoints_entry_alias.march` (both roles of `Stream`
  written against `Entry`, the `t190` bodies) and
  `specs/lang/types/reject/t282_endpoints_entry_alias_linear.march` (the double use).
- `docs/choreography.md` and its twin `specs/lang/choreography.md`: the role bodies in
  "Writing a role" now start from `Fan_C.Entry` / `Fan_A.Entry`, and `register` is
  introduced as giving the state `Entry` names. `after_a`'s mid-conversation
  `S_recv_Second` stays spelled out: `Entry` is the first state only.
