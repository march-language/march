# `[P2]` Distributed deploys, build step 7: the topology file, what is left

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 4, II.6, D6, D7, D18, D22, D25, D26.

**The static half landed 2026-09-22:**
[../progress/2026-09-22-dd-step07-topology-file-static.md](../progress/2026-09-22-dd-step07-topology-file-static.md)
(`forge/lib/topology.ml`; `forge topology check|export|gen`; the gate in
`forge build`/`run`/`deploy hot`; `march --topology` as a version-and-names stub;
`docs/topology.md`, `specs/features/topology.md`).

## Deferred from step 7

- **Derived `caps` (D22) and the widening gate (D26).** A pool's capability closure
  comes from the typechecker, so it waits for `march --topology` to do more than
  validate names (the generated `main` of step 3 and role grants of step 4 give it a
  root to compute from). Until then `export` prints `"caps": null` under `derived`,
  a written `caps` is stored but not enforced, and `forge deploy hot --grant-cap`
  does not see pool capabilities. Do not fake either: the compiler-side value is
  the only honest one.
- **Compiler-side checks of section 4** that need types: a body's first parameter
  type matches its pool's hook return type; an actor's `init` parameter type matches
  the hook's return type; a role's grant against its pool's written `caps`; a hook
  that reaches beyond them; an `IO.Foreign` role in a non-isolated pool. These are
  `march --check --topology`'s, once it typechecks against the digest. The
  `--emit-core-ast` `topology` object that II.6 describes for handing derived values
  back to forge does not exist yet either.
- **Derived `initiates` is by name, not by type.** `Topology.reachable` follows call
  references resolved over the parse (a callee as written, else under each enclosing
  module of the caller). A call through a closure value or an interface method is
  not followed, so a pool that initiates only through such a call derives an empty
  list. The typed version belongs with the compiler-side derivation above.
- **LSP support for the TOML** (go-to-definition and completion on the `body`,
  `actor`, `start`, `serves` and `initiates` strings; unknown-key diagnostics in
  the editor). Not started.
- **`k8s` generator** comes with its backend (step 10 onwards), per II.6.
- **`replicas`** is parsed and exported but no backend consumes it.

**Acceptance for the rest:** `forge topology export` shows a non-null derived `caps`
computed by the compiler; a code change that widens a pool's derived caps stops
`forge deploy hot` at the monotonicity gate unless `--grant-cap` names it; the LSP
resolves a `body` string to its declaration.
