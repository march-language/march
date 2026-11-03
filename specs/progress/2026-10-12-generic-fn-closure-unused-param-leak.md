# A generic named fn called through a closure leaked the parameter it ignores

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `generic_fn_float_closure` reported
`march_alloc_float < call2`.

## The bug

`pfn ksnd(_p, x) do x end` passed where a `Float -> Float -> Float` is expected
is not specialised: its parameters stay erased (`TVar`). Kind's `borrowable`
is false for a bare `TVar`, so borrow inference makes both parameters OWNED.
Perceus drops an owned parameter at its last use; one the body never mentions
has no last use, and the entry drop for that case
(`Perceus.insert_dead_apply_param_drops`) runs for lambda apply fns only. The
`$clo_wrap` trampoline that makes `ksnd` callable as a closure hands it a
reference to every argument (the closure-call convention: the callee consumes
them; a Float box gets its own via `march_clo_param_own`), so the ignored
argument leaked once per call: a Float box, or a whole String.

## The fix

`Perceus.perceus`'s Phase 0b, which publishes each function's parameter modes
to `Clo_flags` for the trampolines, now also reports an erased parameter of a
non-apply fn that the body never mentions as BORROWED. The trampoline then
releases it after forwarding (its existing `releases` path), so the reference
it handed over is spent. Only the trampoline reads these modes for this case;
Perceus's own RC insertion is unchanged. A direct (non-closure) call to such a
function is not affected and still leaks the same way; it only arises when a
generic function is called from code mono could not specialise.

## Verification

- `test/native/generic_fn_closure_unused_param_leak_probe.march`: ignoring the
  first and the second parameter, over Floats and over Strings, 2,000 calls
  each: 2,000 leaked objects per leg before, 0 after. The returned parameter
  is the double-free witness; output matches the interpreter.
- Linux arm64 ASAN error pass and LSan pass on the probe and
  `generic_fn_float_closure`: clean.
