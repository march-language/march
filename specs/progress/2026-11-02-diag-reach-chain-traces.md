`[P3]` Diagnostics: render "reached from `main`: main → step" chains (caps, role grants, no_panic,
pure, deterministic, no_alloc) as a span-per-hop trace with the USE as the primary span, via one shared helper.
specs/plans/2026-11-02-diagnostics-depth-plan.md §X7.

2026-11-03: `cap_grant_exceeded` traces and the `cap_needs` chain fold landed
(`specs/progress/2026-11-03-diag-x3-x4-finish-x7-traces.md`). Open: role grants, `no_panic`, `pure`,
`deterministic`, `no_alloc` chains on the same helper.

2026-11-03: the rest of §X7.
- `role_grant_exceeded`: `Typecheck.cap_chain_trace` takes an optional root expression, the callback
  passed to the runner front, so the error points at the use and labels the callback ("the body passed
  to `Stream_Run.run_Cons` is granted only `Cap(IO.Console)`") and each call. A chain through a local
  closure or a let-bound body (role_grant_exceeded_2) keeps the prose chain.
- `no_panic`: a function that only reaches a panic through another of the module's functions was a
  separate "transitively calls" error per function; now the panic site is reported once, with a label
  on each caller and a line naming them. The "transitively calls" text remains only for a chain whose
  end is not a direct panic site.
- `pure`, `deterministic`: these checks report direct uses only (a call to a module-local function is
  that function's own error), so there is no chain to render.
- `no_alloc`: judged on TIR, whose allocation reasons carry no source spans; it stays prose until TIR
  keeps spans per allocation.
