# The unused-capability warning can demand the opposite of the ceiling

Found 2026-08-08, minutes after the ceiling became the default (#225), on the
first file the default forced a migration of.

`specs/lang/golden/g43_parallel_determinism.march` reaches `IO.Spawn` only
through the stdlib `Parallel` module. The ceiling (emitted-code attribution)
correctly charges `Main` and fails the build until `needs IO.Spawn` is added.
Adding it then produces, from the SOURCE-level analysis:

```
module `Main` declares `needs IO.Spawn` but no function requires
`Cap(IO.Spawn)` or a sub-capability.
help: remove the unused capability declaration.
```

So the two channels give contradictory instructions for the same line: the
error says add it, the warning says remove it, and a user who follows the
warning's `help:` gets the error back. Every stdlib-mediated capability use —
exactly the route the ceiling exists to catch — produces this pair, so the
default flip promoted it from a curiosity to the FIRST experience of
migrating a file.

## Why

The unused-`needs` warning is computed from the typechecker's source-level
capability closure (signature `Cap(X)` flows plus direct builtin calls). A
stdlib-mediated use is invisible there by design — that is the severity-flip
caveat — but the warning's wording assumes its own analysis is complete.

## Fix directions (pick one, don't do both)

- Suppress the unused warning for a capability the CEILING attributes to this
  module (requires the attributed set where the warning is emitted — it lives
  in typecheck, attribution in TIR, so this likely means moving the warning
  to bin/main.ml's post-attribution point for the compile path).
- Or keep the warning but make it honest: "no SIGNATURE or DIRECT-CALL use;
  the capability may still be reached through the stdlib (the ceiling decides
  that)" and drop the `help: remove` autofix in that case. Cheaper, and does
  not move code across the phase boundary.

Note the interpreter path (`march file.march`) has no attribution pass at
all, so option 1 silences the warning only under `--compile`; option 2 is
consistent everywhere.

## Witness

`march specs/lang/golden/g43_parallel_determinism.march` (interpret) prints
the warning on stderr; `march --compile` on the same file with the line
REMOVED fails the ceiling. Both cannot be right.

---

## RESOLVED 2026-08-08 — a third direction, better than either proposed

Neither option above was taken. Typecheck already computes the per-function
TRANSITIVE capability closure (`fn_transitive_capability_closures_tbl`, the
table Check 4 uses for imports) — and that closure sees straight through a
stdlib wrapper to the builtin. Check 2 now consults it: a `needs` reached by
any function THIS module declares (DFn, stdlib-span decls excluded, keyed by
`cap_qname` — never by key SHAPE, since at the entry module prelude functions
are keyed bare exactly like the user's own) is used, so the warning and its
`remove` autofix simply do not fire on a stdlib-mediated use. Consistent
across interpret and compile, because it is all inside typecheck — the
option-1 asymmetry never arises.

Pinned by `cap_propagation` tests "stdlib-mediated needs is not unused"
(RED first: warning fired on `needs IO.Clock` used only via `DateTime.now()`)
and "unrelated needs warns with stdlib loaded" (the closure consult must not
degenerate into never-warn). Witness: `march g43_parallel_determinism.march`
now runs with zero warnings.

Same commit: `Cap_ceiling.describe`'s `Unattributed` arm no longer asserts
"reached only through indirect calls" — the one cause it could imagine, and
wrong for every unattributable capability actually diagnosed in 2026-08 (all
four had different causes; each investigation began by disbelieving the
message). It now states what the check knows, lists indirect calls as one
likely cause, and says to report it if adding `needs` does not resolve it.
