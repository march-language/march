# `proof cap X with T` only accepts a MONOMORPHIC dictionary type

`[P3]` Filed 2026-09-02. Limitation of the `with` clause shipped in PR #388.

## What is broken

`Cap_dict_resolve.dict_ty_of_cap` (`lib/typecheck/cap_dict_resolve.ml`) resolves
the `with` clause's type name and builds it with **zero type arguments**:

```ocaml
match resolve_cap_dict_type env cap_path with
| Some rec_name -> Some (TCon (rec_name, []))
```

So a parameterised dictionary record can never be satisfied: the required type
is the bare `TCon ("Ops", [])`, while the record literal at the `cap_impl` site
infers `Ops('a)`. Those do not unify, and there is no surface syntax on the
`with` clause to supply the argument.

## Repro

Rejected — parameterised dictionary:

```march
mod P do
  needs IO
  type SessionOps(m) = { emit : (m) -> Int }
  proof cap Live with SessionOps
  fn boot(c : Cap(IO)) : Cap(P.Live) do
    cap_impl(mint_cap(c), { emit: fn ep -> 1 })
  end
end
```

```
-- ERROR --
expected `{ emit : a -> Int }` but got `SessionOps`.

    `SessionOps` is declared with 1 type parameter (`SessionOps(m)`), but here
    it is used with none. A bare `SessionOps` never unifies with
    `SessionOps(m)`; supply the argument, or declare the type without
    parameters.
```

Before 2026-09-02 the same program reported `expected `SessionOps` but got
`SessionOps`.` with a note blaming a global-namespace collision that does not
exist here; the arity is now rendered (`report_mismatch` in
`lib/typecheck/typecheck_unify.ml`), so the limitation is at least visible.

Accepted — the monomorphic form works (exit 0):

```march
mod Q do
  needs IO
  type SessionOps = { emit : (Int) -> Int }
  proof cap Live with SessionOps
  fn boot(c : Cap(IO)) : Cap(Q.Live) do
    cap_impl(mint_cap(c), { emit: fn ep -> ep })
  end
end
```

## Why it matters

This currently blocks the session-transport dictionary in
`specs/todos/2026-08-31-cap-runtime-dictionaries.md`, which is that design's
stated payoff case and is still "not started".

That design requires the dictionary to be **protocol-agnostic**, and says so in
the strongest terms it uses anywhere: "Protocol-agnostic / transport-level. This
is the most consequential decision in the design." The reason given is that a
per-protocol dictionary would force a code generator to emit a new dictionary
type per protocol, coupling a future protocol projector to the runtime
representation. No field in the pinned `SessionOps` shape is named after a
protocol, a role, or a label.

A protocol-agnostic dictionary needs the message type erased or abstracted, and
a type parameter (`SessionOps(m)`) is the obvious way to abstract it. That is
exactly the spelling the `with` clause rejects.

## Options (not a decision)

1. **Erase the message type** at the dictionary boundary, keeping the record
   monomorphic — consistent with the design's existing note that `AccessPoint`,
   `Role`, `Msg`, `Endpoint`, `State` and `Suspended` are opaque and
   `ptr`-shaped at that boundary. Watch the erased-i64 convention.
2. **Make the `with` clause accept a parameterised type.** Note what this buys:
   the capability would then name one instantiation, so the dictionary becomes
   protocol-specific — which is the coupling the design explicitly rejects.

Neither is chosen here; this file records the limitation and the constraint it
collides with.

## Where a fix would land

`lib/typecheck/cap_dict_resolve.ml` (the zero-argument `TCon` is built there)
and `lib/tir/cap_passing.ml` (the dictionary's TIR-side passing).
