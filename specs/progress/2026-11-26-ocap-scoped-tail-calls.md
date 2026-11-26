# Scoped tail calls loop instead of growing the stack (2026-11-26)

Plan unit U1 steps 6 and 7 (stage A1.3). Closes
`progress/2026-11-26-ocap-restrict-tail-calls.md` and, for function frames,
`progress/2026-11-26-ocap-framed-mutual-tail-recursion.md`.

## What was wrong

A frame's restore follows the body it wraps, so a call in the body's tail position was
not a tail call:

- **A restrict as a function's whole body.** `fn countdown(n) do restrict
  IO.FileRead("/srv/") do ... countdown(n - 1) end end` grew the native stack one frame per
  call, although re-entering the block pushes nothing. 100,000 deep died with SIGBUS
  compiled (`--opt 0` and `--opt 2`, checked on main before the change).
- **Mutual tail calls between framed functions.** A call of framed `g` from the body of
  framed `f` goes through `g`'s wrapper; ping/pong 100,000 deep died with SIGBUS compiled.
  Self tail calls were already retargeted to `f$auth`.

## Fix (lib/tir/auth_rt.ml)

1. `outline_restrict_body`, run by `Auth_rt.restricts` after it drops the frames it can:
   when a function's whole body is a kept frame of a literal restrict, the block's body
   moves to `f$restrict_body` and `f`'s own self calls in it are retargeted there
   (`retarget_unframed`, which does not look under a frame the body enters itself). The
   skipped entry is of the frame already on top, which pushes nothing. A computed
   restrict builds a different layer per entry and is left alone.
2. `hop_tail_calls`, run by `Auth_rt.frames`: in `f$auth`, a tail call of another framed
   `g` becomes a test of `Authority.frame_in_force(g$auth_layer())` (new, at the end of
   stdlib/authority.march): when `g`'s frame is anywhere in the chain the call goes to
   `g$auth` as a tail call, otherwise to `g`'s wrapper as before. Only the first hop into
   each frame enters it; after that the recursion loops. The authority is unchanged: it is
   the intersection of its layers, and `g`'s is already one of them. The layer list and
   the runtime are unchanged (no new builtin; the test is March code over `cap_layers`).

The plan sketched step 7 as an entry that pushes without saving, with the outermost
wrapper's restore releasing the chain. That leaves the pushed layers in force when the
outermost entry was itself a re-entry (whose restore is a no-op), so it was not done.

## What a CapError names

The skipped entries cannot change whether an operation is admitted. They can change
which layer a refusal names when several refuse: a refusal names the topmost refusing
layer, and a skipped re-entry no longer puts that function's layer back on top. The
fixtures name the same function interpreted and compiled.

## Tests

- `test/cap_conformance/restrict_reenter_noop.march`: 1,000 -> 100,000 deep. Passes in all
  five modes (interpreted, JIT, compiled, JS, REPL).
- `test/cap_conformance/frame_mutual_tail.march` (new): ping/pong with different scoped
  clauses, 100,000 and 100,001 deep, and a refusal by the narrower clause. Interpreted,
  JIT, compiled and JS; not the REPL mode, whose preload cannot load mutually recursive
  functions at all (`todos/2026-11-26-repl-preload-mutual-recursion-unbound.md`).
- `test/snapshots/src/auth_tail_hop.march` (new): pins both shapes. The other auth and
  stdlib-heavy snapshots renumber (two new Authority functions).

## Not done

- Granted packages: a call into a kept grant frame is still never a tail position, and
  `test/cap_conformance/grant_callback_reentry.march` stays at 1,000 deep. `hop_tail_calls`
  skips granted functions because their wrappers also enter the grant.
- A mutual recursion through two restrict blocks in different functions, and through a
  restrict and a framed function, still grows the stack; only the self case of a whole-body
  restrict is outlined.
- A tail call in a lambda or local function inside a framed body is not rewritten (it may
  run outside the frame).
