# Snapshot harness runs the post-Perceus RC verifier

`test/test_snapshots.ml` constructs a TIR pipeline directly.  It now mirrors
the production pipeline at Perceus: compute one kind table and borrow map
before RC insertion, then pass those same instances to both Perceus and the
post-Perceus verifier.

A focused harness test constructs a double release and verifies that the
post-Perceus check reports the RC-balance failure, preventing the check from
being silently skipped when the harness changes.

Wiring the check uncovered and corrected an ownership gap for defunctionalized
TRMC destination-passing helpers: both Perceus and its RC verifier now treat
the final destination argument of an indirect `$dps` call as borrowed.
