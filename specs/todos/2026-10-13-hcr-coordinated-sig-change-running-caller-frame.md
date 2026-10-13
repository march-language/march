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
