`[P3]` Termination phase 3: where the induction hypothesis is withheld

Filed 2026-10-27 by phase 3 of `specs/2026-10-26-termination-checking-design.md`
(`specs/progress/2026-10-27-termination-phase3.md`). Each gap withholds the induction
hypothesis (IH) where a sound one exists, so a contract stays a skip; none can make the
checker say "proved" wrongly.

- **A parameter with an abstract refinement withholds the IH.** Rule (a) asks for a
  proved precondition obligation at the recursive call when the callee has any refined
  parameter. `Range.filter_list(xs, f : Int -> Bool[p])` files none for `f`, so its
  self-call is not eligible. It still proves through the structural hypothesis. Teach
  rule (a) which refined parameters file no obligation (an abstract definer passed
  through unchanged), and accept those.
- **One certification per module.** `ih_prepare` runs once, after the IH-free rounds
  stall, over the contracts proved so far. A termination or precondition proof that
  needs a contract the IH rounds prove later is not retried.
- **Self-calls only, outside the scalar gate.** Tier 2 (datatype returns), the element
  return (`hyp_applies`) and a local `fn` (`local_elem_hyp`) widen only a call to
  themselves. A mutual SCC's datatype or element contracts get no hypothesis from each
  other. The scalar gate admits mutual SCCs atomically; the other three would need the
  same group admission.
- **The tuple element hypothesis (`tuple_self_hyp`) is not widened.**
- **A local `fn`'s scalar return is not widened** (only its element return, O1).
- **Rule (b) covers a scalar return tail only.** A call nested in arithmetic inside a
  path condition, a record field, or a list tail still does not reflect.
- **No RED control for the resolution-agreement check.** The IH at a span is used only
  when the checker's own name resolution reaches the member the termination graph
  names. No fixture is known where the two disagree; the check is defence in depth.
- **A call through a function value is trusted (review fixes, 2026-10-27).** `g(x)` with
  `g` a parameter has no name to resolve; only a non-positive type blocks it (§3.6). An
  SCC whose member calls a passed-in function value gets the IH even when a caller passes
  a diverging one. Closing it needs the value's provenance (the callers' reference edges)
  attached to the parameter, or withholding the IH from any SCC that calls a function
  value.
- **Interface dispatch on a type variable reaches every impl.** `x < y` in a generalised
  local `fn` reaches every `Ord` impl, so `bigint`'s `compare_digits/cmp_lists/go` lost its
  structural certificate, and the generic `Eq` / `Show` / `Ord` impls in the stdlib form
  uncertified cycles. Any SCC reaching them gets no IH. Instance-level dispatch (the impl
  the call's type actually selects) would recover them.

