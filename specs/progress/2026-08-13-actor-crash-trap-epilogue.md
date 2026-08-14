# Actor crash trap: `panic()` in a supervised handler skipped the dispatch epilogue

**Filed:** 2026-08-13 (found while adding a "two names on one actor" case to the
named-registry restart golden — the failure is in the crash trap, not the registry).
**Closed:** 2026-08-14. The RC half of this was fixed independently and better
by PR #275, which deleted the clobber entirely instead of repairing it on the
crash path (see "Superseded" below); what lands here is the code-version-pin
leak #275 left, plus the regression test that pins the RC invariant.

## Symptom as reported

A `one_for_one`-supervised actor registered under TWO names, then crashed via
`panic(...)` inside a handler, killed the process with `EXC_BAD_ACCESS`
(exit 138), deterministically, during the automatic restart:

```
mfm_alloc  ←  strdup  ←  meta_add_name  ←  march_actor_register  ←  march_respawn_child
```

The discriminator was narrow and looked mysterious: the SAME
`do_actor_death → capture → retire → notify → respawn` chain driven by `kill()`
(supervised or not) never crashed; only the `setjmp`/`longjmp` crash-trap path
did. One registered name did not crash, two did. That shape — "corruption only
after enough post-crash allocation" — reads like a `longjmp` leaving libc's
allocator inconsistent. It isn't. malloc was the victim, not the culprit.

## Root cause

`actor_green_thread` (`runtime/march_runtime.c`) brackets every message with:

```c
int64_t saved_rc = a[0];
a[0] = 1;            /* FBIP: force RC=1 for in-place reuse */
   ...dispatch...
a[0] = saved_rc;     /* restore the real owner count */
```

`march_panic` `longjmp`s from the middle of the dispatch straight back to the
`setjmp` at the top of the function, so **the restore never runs**. The crashed
actor's record is left claiming exactly one owner while all of its real owners
still hold references. The next drop by any of them takes the count to zero and
`free()`s a record that is still live and still reachable — a use-after-free
whose first visible casualty is whatever allocation happens next.

Instrumented runtime, unmodified repro (`[FREE]` is a real `free()`):

```
[DISPATCH] actor=0x102506800 rc=6 msg=0x102508f30    ← 6 real owners
[CRASH]    actor=0x102506800 rc=1 alive=1            ← restore skipped
[RETIRE]   actor=0x102506800 name=fragile  cur=0x102506800
[FREE]     0x102506800 tag=0                         ← live actor freed (vault drop, 1→0)
[RETIRE]   actor=0x102506800 name=fragile2 cur=0x102506800   ← reads freed memory
```

Guard Malloc pins the first illegal access one step earlier than the reported
stack, inside the *first* name's retire, confirming the ordering:

```
march_incrc  ←  march_vault_get  ←  registry_retire_actor  ←  do_actor_death  ←  actor_green_thread
```

Everything the isolation had already established falls out of this:

- **`kill()` never crashes** — it runs `do_actor_death` from *outside* the
  dispatch window, so the RC was never clobbered.
- **Two names crash, one does not** — the free happens either way; with one
  name nothing touches the freed record again before exit, so the corruption is
  silent. The one-name case was never safe, only quiet.
- **The registry is innocent** — it merely supplied the second owner (the
  forward table's reference) and the post-crash `strdup`s that met the damage.
  On plain `main`, a supervised child measures `rc=2`, so the same clobber is
  present today, latent, waiting for any owner to drop first.

## Superseded, in part, by #275

While this was being written up, PR #275 ("Named actor registry, and a
use-after-free in actor message dispatch") landed on `main` with a strictly
better fix for the RC half: it **deletes the clobber outright**. Two reasons,
both of which this investigation missed by starting from the crash path:

1. It is unnecessary. `llvm_emit.ml`'s `EReuse` arm already special-cases actor
   structs and mutates them in place unconditionally — nothing in the emitted
   handler reads `a[0]` at all.
2. It is unsafe *without any panic*. `a[0]` is RMW'd atomically by
   `march_incrc`/`march_decrc` on other threads; the plain stores are not
   atomic with those and publish a false `rc == 1` for the whole dispatch, so a
   concurrent drop frees a multiply-owned record on a purely happy path. #275
   measured that directly (6 of 30 spawn-churn runs failing, 0 of 60 after).

The `longjmp`-skips-the-restore path documented above is a real second way the
same lie escaped the window — single-threaded and fully deterministic, which is
why it reproduced 100% of the time rather than ~20%. With the clobber gone,
there is no restore left to skip, and this file's root-cause analysis is kept
because the *evidence* (which owner freed what, and when) is what pinned the
mechanism.

## Fix

What remains after taking #275's version of the dispatch loop:

- `march_dispatch_leave` the code-version pin a hot-reload actor took in
  `march_dispatch_enter`. The `longjmp` skips it, so every crash leaves that
  version's `refs` permanently above zero and its ring slot unreclaimable — a
  crash-looping hot-reload actor burns one slot per crash. Not an ordinary
  leak: it is a live counter that blocks a runtime mechanism.
- The pin's state (`pinned_version`, `dispatch_pinned`) is hoisted above the
  `setjmp` as `volatile` — an automatic modified between `setjmp` and `longjmp`
  is indeterminate in the branch the `longjmp` lands in (C17 7.13.2.1p3).
  `dispatch_pinned` also covers a `longjmp` arriving from *outside* a dispatch
  (e.g. out of a `migrate_fn`) and the non-hot-reload actor that never pins.

**Not** repaired: the message. The dispatch function owns and consumes `msg`,
and a `longjmp` out of its middle leaves no way to know whether it already did,
so `msg` leaks on this path rather than risking a double free.

## Test

`test/native/actor_crash_rc_restore.march` asserts the RC is unchanged across a
crash, read through a test-only runtime probe (`ffi_test_actor_rc`, in
`runtime/march_ffi.c` beside the other `ffi_test_*` helpers). The RC is the
invariant; every March-level *symptom* of the bug is undefined behavior and
would make for a flaky test. Its first line — "victim is multiply owned" — is a
non-vacuity guard: the assertion only means something while the crashed child
genuinely has more than one owner.

Against the pre-#275 runtime the second line printed `false`; it prints `true`
both with the crash-path restore this investigation first wrote and with #275's
deletion of the clobber. That is the point of keeping it: the test now guards
the invariant `main` relies on — reintroducing an RC lie around the dispatch
fails a test instead of corrupting a heap — and it probes it from the crash
path, which skips whatever epilogue a future clobber might add to protect
itself.

The originally-reported two-names crash was also re-run against the
named-registry branch with only the crash-path restore applied — 5/5 clean where
it had been 100% exit 138, and clean under Guard Malloc — confirming the
mechanism before #275 landed.
