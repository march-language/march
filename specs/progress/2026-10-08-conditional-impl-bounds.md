# Conditional impl bounds are checked at use sites

Impl registration now retains `when` bounds alongside the head, with shared
type-variable identities. Constraint discharge matches the head using a local
substitution and recursively checks each specialised bound without mutating
the registered type variables. Concrete declaration bounds and superclass
checks use the same resolver.

Regressions cover satisfied and missing payload interfaces, nested wrappers,
forward declarations, circular bounds, and expanding bounds. Proof search
rejects repeated obligations and requires a repeated implementation to reduce
the target's structural size, terminating even for expanding bounds.

Validation: all 226 typechecker tests pass with the expanding-bound guard,
including the three focused conditional-bound cases.
The native Diagnose fixture also typechecks. Tuple `Ord` remains open in
[the original TODO](../todos/2026-10-06-tuple-ord.md).
