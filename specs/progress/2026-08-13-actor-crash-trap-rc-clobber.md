# Actor crash trap: `panic()` in a supervised handler left the actor record's RC clobbered

**Filed:** 2026-08-13 (found while adding a "two names on one actor" case to the
named-registry restart golden — the failure is in the crash trap, not the registry).
**Closed:** 2026-08-13, same commit as the fix.

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

## Fix

Hoist the epilogue's state above the `setjmp` (as `volatile` — an automatic
modified between `setjmp` and `longjmp` is indeterminate in the branch the
`longjmp` lands in, C17 7.13.2.1p3) and complete the skipped epilogue in the
crash branch, before `do_actor_death` and the restart it triggers:

- restore `a[0] = saved_rc` (verbatim, exactly as the normal path does — the
  crash path deliberately does not invent a different RC contract);
- `march_dispatch_leave` the code-version pin a hot-reload actor took in
  `march_dispatch_enter`, which was leaking the same way and would otherwise
  hold a ring slot's `refs` above zero forever, blocking its reclamation;
- an `in_dispatch` flag so a `longjmp` that arrives from *outside* a dispatch
  (e.g. out of a `migrate_fn`) repairs nothing.

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

Verified: `false` on the second line with the pre-fix runtime, `true` with it.
The originally-reported two-names crash was also re-run against the
named-registry branch with only this runtime change applied — 5/5 clean where it
had been 100% exit 138, and clean under Guard Malloc.
