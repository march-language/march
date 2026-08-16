# Unify the two capability-chain renderers under one (capped) implementation

Filed during Task 8 fix round 1 of `specs/2026-08-13-capability-ux-plan.md`.
The task-8 brief asserted that the grant-violation chain
(`check_main_grant`, `lib/typecheck/typecheck.ml`) should render "exactly
like" the sibling missing-`needs` body-scan chain
(`Cap_infer.chain_note`, `lib/refinecheck/cap_infer.ml:365-372`). That
assertion was wrong and went uncaught: the two diagnostics are the only two
places in the compiler that print a capability call chain to a user, and
until this round they rendered it three different ways between them (one
truncated past 4 frames with `… -> ` and dropped `main` from the shown
chain, joined with ASCII `->`; the other prints the full chain, includes
`main`, joined with `→`).

**Current state, as of this filing:** both call sites now render a chain the
same way — full chain, `main` included as the first frame, `" → "`
separator, no truncation. `check_main_grant` was changed to match
`Cap_infer.chain_note`'s existing behavior (the brief calling this the
"established" one; changing `cap_infer.ml` at that point would have been
scope creep for task 8). **Neither renderer elides today.** A sufficiently
deep call chain (a helper many frames removed from `main`) will print in
full in both diagnostics, with no length cap.

**The gap this file tracks:** there is still no *shared* implementation —
`check_main_grant`'s inline `Printf.sprintf " (reached from \`main\`: %s)"
(String.concat " → " ("main" :: chain))` and `Cap_infer.chain_note`'s
`chain_marker ^ String.concat " → " path` are two independent pieces of
code that happen to agree today by construction, not by sharing a function.
A future edit to either (e.g. adding a frame cap, which is plausible —
Task 8's original brief speculated a 4-frame elision was right, before that
turned out to be unverified) can silently re-diverge them exactly the way
they diverged before this round.

**Proposed fix:** extract a single `render_cap_chain : string list -> string`
(or similar) that both call sites use, in whichever of the two libraries
doesn't create an unwanted dependency (`lib/typecheck` is presumably the
better home, since `refinecheck` likely already depends on or sits next to
`typecheck` in the build graph — verify before committing to a direction).
Decide then whether a frame cap belongs in the shared renderer (e.g. show
first + last N frames with an ellipsis, the way many stack-trace UIs do) —
if so, add it once, in the one place, so both diagnostics move together.

**The two current call sites:**
- `lib/typecheck/typecheck.ml`, `check_main_grant`'s violation branch
  (search for `cap_reach_chain env ~from:"main"`).
- `lib/refinecheck/cap_infer.ml:365-372`, `chain_note` (uses `call_path` and
  `chain_marker`, both defined a few lines above it in the same file).

Not urgent: both diagnostics are `--compile`-only, both correctly attribute
today, and no known real-world call chain has grown long enough to make an
unbounded chain unreadable. Worth doing before either renderer's format
changes again, so the next change is made once instead of twice.
