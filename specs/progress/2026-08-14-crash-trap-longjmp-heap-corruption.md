`[P1]` # Crash-trap `longjmp` corrupts the heap when a restarted actor re-registers 2+ names

**RESOLVED 2026-08-14.** The two-names-on-one-actor case is now part of
`test/native/actor_registry_restart.march` (the acceptance criterion below) and
passes; it was exit 138 on every run before.

**It was not a malloc-state bug.** The hypothesis this file records — a
`longjmp` past a held allocator lock, or a poisoned thread-local malloc cache —
was wrong, and the "more allocation makes it appear" evidence pointed the wrong
way. malloc was the victim. What actually happened: the dispatch loop clobbered
the actor record's refcount to `1` for the duration of a message, and the crash
trap's `longjmp` skipped the restore, so the record claimed one owner while the
registry's forward table and others still held references. The registry's
retire then dropped what looked like the last reference and freed a live,
still-reachable record; the second name's carry-forward allocated on top of the
freed block. One name never crashed because nothing touched the record again
before exit — it was never safe there either, only quiet.

That makes this the deterministic, single-threaded face of the SAME defect as
`specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md`, which this file
explicitly ruled out as distinct. The two symptoms differ (deterministic in
`march_respawn_child` vs ~20% inside a churn loop) because the RC lie can escape
its window two ways: a concurrent `march_decrc` on another scheduler thread
reading the forced `1`, or a `longjmp` that skips the restore entirely. Deleting
the clobber (that entry's fix) closes both.

Evidence and full write-up:
`specs/progress/2026-08-13-actor-crash-trap-epilogue.md`, which also lands the
one thing deleting the clobber did not fix — the `march_dispatch_leave` pin a
hot-reload actor leaks on the same `longjmp`.

---

## Original report (kept as filed; the analysis below is superseded above)


**Pre-existing bug in `actor_green_thread`'s `setjmp`/`longjmp` crash trap. It
is NOT registry logic** — the registry is only what allocates enough afterwards
to make the corruption visible.

Found while adding a two-names case to
`test/native/actor_registry_restart.march` during the named-registry work
(`specs/progress/2026-08-12-named-registry.md`). The test addition was reverted
rather than shipped crashing; the bug was not fixed, because it needs an
investigation into the crash-trap mechanism rather than a registry patch.

## Symptom

A `one_for_one`-supervised actor holding **two or more** registry names, which
dies via `panic()` inside a handler, crashes with heap corruption during the
automatic restart's name carry-forward:

```
EXC_BAD_ACCESS in strdup
  ← meta_add_name
  ← march_actor_register
  ← march_respawn_child
```

Exit code 138 (SIGBUS class). **Deterministic** — every run, not intermittent.

## Minimal reproduction

```march
-- a one_for_one-supervised actor `a`
Actor.register(a, "name-one")
Actor.register(a, "name-two")
send(a, SomeMsgThatPanics())
run_until_idle()
```

## Isolation — four controls, all run

| variant | result |
|---|---|
| 2 names, supervised, dies via `panic()` (the crash trap) | **crashes, every time** |
| 2 names, supervised, dies via `kill()` — same capture/retire/respawn/consume chain | clean |
| 2 names, **unsupervised**, `kill()`, then re-register both to a fresh actor | clean |
| 1 name, supervised, dies via `panic()` | clean |

Also reproduces identically on the pre-`e5a64520` runtime (restaged by hand and
rebuilt), so it predates both of that commit's fixes — it is latent in the
original Task 6 capture/consume mechanism only in the sense that nothing before
this ever allocated twice on that path.

**The discriminator is "died via the `longjmp` crash trap" vs "died via
`kill()`"**, with the identical downstream code either way. That points at
`actor_green_thread`'s `setjmp`/`longjmp` crash recovery interacting badly with
malloc's internal state — a `longjmp` that skips past code holding the allocator
lock, or that leaves a thread-local allocator cache inconsistent, is a known bug
class. One name's worth of post-`longjmp` allocation is apparently not enough to
trip it; two names' worth is.

## Why this matters beyond the registry

Nothing here is registry-specific except the *volume* of allocation after the
`longjmp`. Any code path that allocates enough on a green thread that has just
recovered from a `panic()` through the crash trap is exposed. The registry
carry-forward just happens to be the first thing in the tree that allocates
twice there.

## Distinct from the dispatch-window UAF

Not the same bug as `a9032530`
(`specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md`), and the two were
not conflated: that one is intermittent, multi-scheduler-only, and dies inside
the churn loop; this one is deterministic, single-name-immune, and dies inside
`march_respawn_child`. This bug was never hit during that investigation.

## Acceptance

`test/native/actor_registry_restart.march` can carry a two-names-on-one-actor
case (crashed via `panic()`, restarted, **both** names resolvable afterwards)
without crashing. Add that case as the regression test when the fix lands — it
is already written and reverted once, so re-deriving it should be cheap.
