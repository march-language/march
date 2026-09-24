# `[P2]` Distributed deploys, build step 7: the topology file, what is left

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 4, II.6, D6, D7, D18, D22, D25, D26.

**The static half landed 2026-09-22:**
[../progress/2026-09-22-dd-step07-topology-file-static.md](../progress/2026-09-22-dd-step07-topology-file-static.md)
(`forge/lib/topology.ml`; `forge topology check|export|gen`; the gate in
`forge build`/`run`/`deploy hot`; `march --topology` as a version-and-names stub;
`docs/topology.md`, `specs/features/topology.md`).

## Deferred from step 7

- **Delivered by step 3 (2026-09-23,
  [../progress/2026-09-22-dd-step03-level0-generated-main.md](../progress/2026-09-22-dd-step03-level0-generated-main.md)):**
  the compiler derives each pool's `caps` and typed `initiates` (`march --topology
  --emit-core-ast`'s `topology` object) and `forge topology export`/`gen` print them;
  a written `caps` is enforced against role grants, hook signatures and the pool's
  reach; body and actor `init` shapes against the hook's `Env`; `IO.Foreign` outside an
  isolated pool behind `--topology-isolate-foreign`.
- **The widening gate (D26).** `forge deploy hot --grant-cap` still does not see pool
  capabilities, and `forge build` does not warn when a pool's derived caps widen. The
  derived values now exist; what is missing is recording the previous deploy's and
  comparing.
- **Derived `initiates` through a closure value or an interface method.** The typed
  derivation follows the typechecker's reference graph (`fn_refs`), which records
  names referenced as values too, but a call through a closure received as a parameter
  is still not followed. forge's by-name fallback (`"source": "names"`) has the same
  limit.
- **LSP support for the TOML** (go-to-definition and completion on the `body`,
  `actor`, `start`, `serves` and `initiates` strings; unknown-key diagnostics in
  the editor). Not started.
- **`k8s` generator** comes with its backend (step 10 onwards), per II.6.
- **`replicas`** is parsed and exported but no backend consumes it.

**Acceptance for the rest:** a code change that widens a pool's derived caps stops
`forge deploy hot` at the monotonicity gate unless `--grant-cap` names it; the LSP
resolves a `body` string to its declaration.
