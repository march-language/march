# Conditional impl bounds are checked at use sites

Impl registration now retains `when` bounds alongside the head, with shared
type-variable identities. Constraint discharge matches the head using a local
substitution and recursively checks each specialised bound without mutating
the registered type variables. Concrete declaration bounds and superclass
checks use the same resolver.

Regressions cover satisfied and missing payload interfaces, nested wrappers,
forward declarations, circular bounds, and expanding bounds. Proof search
rejects repeated obligations and limits proof depth to 128, terminating even
for expanding bounds. Failed obligations are memoised by type, depth and active
proof path to
avoid exponential retries through duplicate registered heads. Finite proofs
may revisit the same implementation with a different, equally sized target.

Validation: all 226 typechecker tests pass with the expanding-bound guard,
including the three focused conditional-bound cases.
The native Diagnose fixture also typechecks. Tuple `Ord` remains open in
[the original TODO](../todos/2026-10-06-tuple-ord.md).
