`[P2]` Hot reload: a signature change with "all callers covered" still reaches a RUNNING old caller frame

Found while fixing `specs/progress/2026-10-13-hcr-borrow-mode-not-in-sig-hash.md`.

## Symptom

`forge deploy hot`'s coordinated-upgrade gate accepts a `sig_hash` change when
every recorded caller ships in the same deploy ("Coordinated upgrade: sig_hash
changed, all callers covered."), and with an epoch (every current server) a
missing caller is only a warning, on the grounds that epoch routing keeps old
callers on the old version.  Neither holds for a caller invocation that is
already running at the newest epoch: its frame keeps executing the OLD code
(a self tail call is a direct jump; a running invocation finishes on the
version it started on), and its next call to the changed function resolves to
the NEW version.  The compiled `main` always follows the newest code, so a
request loop on `main` (or anything it calls without returning) is exactly
that frame; so is a loop on an actor past its marker that never returns to
its mailbox.

Measured with a borrow-mode flip (the mechanism is the same for any ABI
change): `count`'s parameter turned owned, `count` and its caller `serve`
activated together (all callers covered), and the server died with SIGSEGV
two seconds later because `serve`'s loop on `main` was still the base's code.
Mode-only changes are now refused outright; a type change (an added or
retyped parameter) still goes through the gate above and would pass the old
arguments to the new code in the same situation.

## Direction

Options: refuse a sig change whose callers include a function that may be
running at the current epoch with no return (needs a call-graph notion of
"long-running", or treat every caller reachable from `main` as one); or keep
the old version reachable for frames that entered before the deploy (a
per-frame version pin, the same machinery closures need for
`specs/todos/2026-10-13-hcr-reclaimed-patch-unmaps-live-closure-code.md`).
Reproduce with `test_hcr_borrow_flip_refused_end_to_end`'s fixture
(test/test_stdlib_suite.ml) and a retyped `count` instead of an owned one.

## Completed 2026-10-31

HCR ABI v5 gives active green-thread frames routing epochs and dispatch references.
Nested calls and baseline main retain compatible versions; escaping closures retain
their creation epoch, and panic/cancellation unwind their references. Startup reserves
the baseline epoch before replay, so the original main still routes to its original ABI.
Actors advance at mailbox markers and use current-version shutdown callbacks.

The compiled `test_hcr_running_frame_signature_change` regression performs v1 → v2 →
v3 → restart of the original executable. Main and its closure keep the old one-argument
ABI, new actor work observes both upgrades, and shutdown sees `migrated-v3:42` after two
state migrations. Runtime frame/replay/unwind and dispatch stress checks pass; the
migration runner passes 102 checks. Closure tests cover captured/function-value calls,
recursive panic, NULL optimized callbacks, deep tail loops and version pressure.

Borrow-mode flips remain conservatively refused by the existing independent gate.
A nonreturning frame or retained closure can prevent reclamation and exhaust bounded
version capacity; a fresh base deployment is then required.
