`[P3]` A diagnostic's type-variable letter depends on whether the typecheck cache is warm:
`test/errors/type_mismatch_14.march` reports "expected `Pid(b)` but got `Int`" from a cold `HOME`
and "expected `Pid(a)`" from a warm one, with the same compiler (checked on main at `0a2077574` and
on the X1 branch). `run_errors` passes only because a full run happens to see it warm; a partial run
(`ERRORS_ONLY=type_mismatch_`) regenerated the golden cold and the next full run failed.

Likely cause: the printer letters variables in an order influenced by which stdlib types were
loaded from the `~/.cache/march` tcenv cache versus re-inferred. Fix: letter variables by first
appearance within the one diagnostic (the message plus its notes and labels), independent of
global state. `scripts/determinism-oracle.sh` compares cold vs warm `.ll` only; extend it to
`--check` text, or add this case to it.
