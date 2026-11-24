# ocap: compile-time check of a literal target against a scoped function `needs` or literal `restrict`

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 2).

A function `needs` clause may carry scopes (`needs IO.FileRead("/etc/myapp/")`). The compiler
checks only the clause's kinds; the scopes are enforced at run time (design §8: "a computed
scope is checked at run time only"), which is complete on its own. But a call with a literal
target outside the scope, `File.read("/etc/passwd")` inside that function, is only reported
when it runs, whereas a module whose `needs` line carries a name or host scope gets such a
call reported at compile time (`cap_scope_violation`, `lib/typecheck/typecheck_caps.ml`:
`check_name_scopes` and the host-scope check).

What to do: run the module-scope literal checks (names, hosts, and a path check) for each function with
a scoped clause, against that clause, for the calls in its own body and the direct calls it
reaches. Report it as `cap_scope_violation` naming the function's clause.

**Widened 2026-11-19 to `restrict` (ocap phase 5, specs/plans/2026-11-19-ocap-p5-restrict-plan.md,
decision 10).** A literal `restrict` with a scoped entry (`restrict IO.FileRead("/srv/") do`)
is checked at compile time by kind only (`cap_restrict`, the `Restrict_block` bound in
`lib/typecheck/typecheck_caps.ml`); `File.read("/etc/passwd")` inside it is refused at run time
(`ByRestrict`), not reported. Run the same literal-target checks over the block's own body and
the direct calls it reaches, against the restrict's scopes, and report them naming the restrict
(`the restrict at <file>:<line>`). A computed restrict stays run-time only (design §8).

**Built for dependency grants 2026-11-22 (ocap phase 6, specs/plans/2026-11-22-ocap-p6-grants-plan.md,
Q3 and decision 14).** `lib/typecheck/scoped_literal_check.ml` is the helper this item asks
for, written to take any scoped bound: literal hosts (a literal URL or a literal-prefix `++` at
the network entry points, judged with `Host_scope`), literal paths (`Cap_scope.within`) and
literal names (`Name_scope.admits`), definite violations only. Only `Typecheck.check_dep_grants`
calls it today, reporting `dep_grant_scope`. Turning it on for a scoped function `needs` clause
and a literal `restrict` is a call per bound point with its own diagnostic, plus the
error-corpus churn of the programs it newly rejects; this item stays open for that. Its URL
entry-point list is hand-written (`specs/todos/2026-11-23-grant-url-entry-points-hardcoded.md`).
