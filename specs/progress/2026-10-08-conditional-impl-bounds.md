# Conditional impl bounds are checked at use sites

Impl registration now retains `when` bounds alongside the head, with shared
type-variable identities. Constraint discharge matches the head using a local
substitution and recursively checks each specialised bound without mutating
the registered type variables. Concrete declaration bounds and superclass
checks use the same resolver.

Regressions cover satisfied and missing payload interfaces, nested wrappers,
forward declarations, circular bounds, and expanding bounds. Proof search
rejects repeated obligations and limits proof depth to 128 and each obligation
to 4096 type nodes (checked before rendering memo keys), terminating even
for expanding bounds. Failed obligations are memoised by type, depth and active
proof path to
avoid exponential retries through duplicate registered heads. Finite proofs
may revisit the same implementation with a different, equally sized target.

Validation: all 226 typechecker tests pass with the expanding-bound guard,
including the three focused conditional-bound cases.
The native Diagnose fixture also typechecks. Tuple `Ord` remains open in
[the original TODO](../todos/2026-10-06-tuple-ord.md).

SessionNode's three payload-independent presence checks now use
`Option.is_none` / `Option.is_some`, avoiding an unnecessary `Eq` requirement
for process and queue handles. Its focused entry-module check is clean,
as is ClusterNode's.

The full stdlib internal-error ratchet also exposed payload-independent
emptiness checks in Control, Topology and NetKernel. Those now use
`List.is_empty` / `Option.is_some`. The ratchet passes with its unchanged
four pre-existing unknown-constructor errors; no error count was raised.

CI's heterogeneous Config-key fixture also compared a `Result` with a
non-`Eq` error payload to `Ok`. Its assertion now matches the variants and
compares only the success String, preserving the original test without
requiring equality for `Config.Error`.

CI follow-up: generated control-plane wiring and nineteen native/session/two-node
fixtures also used payload-independent variant checks. They now use presence,
emptiness, or success predicates. The backpressure fixture still checks the
specific `Err(Backpressure)` variant by matching it, rather than accepting any
error. All nineteen changed fixtures typecheck; the three focused generated
control-wiring tests (`topology_flag` 17–19) pass. No two-node processes or
full local suites were run for this follow-up.

The LSP analysis projection also accepts the added bounds metadata while
retaining its existing head-type-only model.
