---
layout: docs
title: Upgrading to 0.4.0
nav_order: 2.4
permalink: /docs/upgrading-to-0-4-0/
---

# Upgrading from 0.3.x to 0.4.0

**0.4.0 has no breaking source changes.** Code that compiles on 0.3.x compiles
on 0.4.0. This guide is therefore short, and it is mostly about *behaviour that
changes underneath working code* — three defaults moved, and several programs
that used to crash or print garbage now work.

Read § 1 if you run March in production, in a container, or on a machine with
many cores: the parallelism default changed, and that is the one item most
likely to surprise you.

If you hit something not covered here, check `CHANGELOG.md` for the full list.

---

## 1. The default scheduler-thread count now tracks the machine

**This is the change most likely to affect you.**

March previously ran **4** OS scheduler threads by default on every machine —
four on a four-core laptop, four on a 96-core server. That made 4 the de-facto
parallelism limit of any program that had not set `MARCH_NUM_SCHEDULERS`, and
nothing said so.

The default is now **one scheduler per online CPU**, clamped to
`MARCH_MAX_SCHEDULERS` (64).

### What you'll see

More OS threads, and more parallelism, with no source or flag change. Measured
on a 14-core M3 Max, the same CPU-bound `pmap_n` program went from 5 OS threads
and 4499 ms to 15 threads and 2487 ms.

### If you want the old behaviour

```
MARCH_NUM_SCHEDULERS=4
```

`MARCH_NUM_SCHEDULERS=N` pins a count and `=auto` asks for one-per-CPU
explicitly; both behave exactly as they did. A build may still pin the default
with `-DMARCH_NUM_SCHEDULERS=N`, and a pin wins over auto.

### In containers

The count follows the **container**, not the host. `sysconf` reports the
machine's CPUs and ignores both ways a container narrows them, so the default is
derived from the smallest of: the online CPU count, the CPU affinity mask
(`docker --cpuset-cpus`, k8s CPU pinning), and the cgroup CPU quota
(`docker --cpus`, k8s CPU limits, cgroup v2 and v1).

Verified in Docker: `--cpuset-cpus=0` and `--cpus=1` each resolve to 1
scheduler while `sysconf` still reports 14. Without that, a program pinned to
one CPU would have started one thread per *host* core — worse than the flat 4 it
replaced.

### Related: `MARCH_NUM_SCHEDULERS` was a silent ceiling

It is now a setting rather than a cap. If you set it and observed fewer threads
than you asked for, you will now get what you asked for.

---

## 2. Tail-recursion-modulo-cons is on by default

A recursive call that is the direct argument of a constructor in tail position —
the natural way to write `map`, `filter`, or a tree rebuild — now compiles to a
loop that reuses list cells in place, instead of one stack frame and one
retained cell per element.

**This is a correctness change as much as a speed one.** Such a function
previously overflowed the stack on a long list when compiled: a 500k-element
natural-style `map` exited 138. It now runs. On a 20k-element list mapped 2000
times it is 4.8× faster than the same source compiled without the transform.

### If you need the old behaviour

```
march --compile --no-trmc …      # or: MARCH_NO_TRMC=1
```

### Will this change my existing code?

Almost certainly not. The stdlib's list producers are hand-written in
accumulator form, which the transform does not touch, and every benchmark in
`bench/` emits byte-identical code either way. The transform only fires on
constructor-wrapped tail recursion, which previously did not compile reliably at
scale — so the code most affected is code that did not work before.

---

## 3. String interpolation is linear at every operand size

An interpolation with four or more operands now compiles to a single
`string_concat_n` that sums every part's length once, allocates once, and copies
each byte once — instead of a fold of three-way concats that re-copied the
accumulated prefix at every step.

That fold was quadratic with large operands: with 4 KB operands, 32 of them went
from 0.54s to 0.06s. Short operands — the case the fold was originally chosen
for — got *faster* too, from 0.23s to 0.07s at the same count, rather than
regressing. Nothing changes below four operands.

No action needed. If you hand-rolled a `String.concat`-based workaround for
large interpolations, you can drop it.

---

## 4. Records and tuples are now reference-counted and freed

Previously they were not. If you have been tracking memory usage, expect it to
**drop**, and expect `march_live_allocs` figures to differ from 0.3.x.

This is a fix, not a regression — but if you have a test asserting a specific
live-object count, it will need updating.

---

## 5. Things that used to be broken and now work

No migration needed for any of these. They are listed because you may have
written a workaround worth removing.

- **`to_string` and `println` on a user ADT.** Compiled builds rendered
  `#<tag:0>` — silently, with the payload dropped — while the interpreter
  printed the constructor. Both now render the constructor and its fields. If
  you added a hand-written `show` purely to work around this, it is no longer
  needed.
- **A missing `Show` implementation** used to be reported as an ambiguity
  listing twenty unrelated types. It now says what is actually wrong and names
  the `derive Show` that fixes it.
- **`from_json` return-type dispatch.** A bare `from_json` used to resolve to
  whichever type derived `Json` last in the module. It now dispatches on the
  target type. This also fixes `derive Json`'s auto-generated
  `update_json`/`render_json` island bridges, which were silently returning
  their input unchanged.
- **`file_*` / `dir_*` error payloads.** Thirteen builtins were typed as
  returning `FileError` but returned a bare string at the C level, so a compiled
  program that destructured the error read a string header as a `FileError`
  cell. They now return real `FileError` values.
- **Linux release binaries are genuinely statically linked**, and
  `march --compile` works on musl (Alpine).

---

## 6. New things worth knowing about

- **`Actor.stop(pid, timeout_ms)`** — graceful shutdown. A stopped actor
  refuses new sends, works off its queued messages until the mailbox empties or
  the deadline passes, then ends in a normal death. A supervisor stops children
  in reverse declaration order, each with its own budget. This is the piece that
  makes a rolling deploy lossless; `kill` still drops whatever was queued.
- **Per-child restart types on `supervise`** — a child may be `permanent`
  (default, unchanged), `transient` (restart only on abnormal exit) or
  `temporary` (never restarted).
- **`backoff base <ms> cap <ms> jitter <n>%`** on a `supervise` block tunes the
  restart curve. The default curve is unchanged.
- **`Actor.list()`** — enumerate every live actor. Monitoring code can now find
  the actor that is behind, rather than needing a `Pid` it already holds.
- **`@[no_alloc]` and `@[no_alloc(transient)]`** — per-function allocation
  contracts, checked at compile time.
- **`--refine-audit`** — answers "does the checker even look at this declared
  refinement?", separately from whether an obligation was proved.

---

## Known issues in 0.4.0

- **An intermittent SIGSEGV in the actor monitor/death path on Linux.**
  Observed twice in CI, in a 100-iteration stress fixture, after all expected
  output was produced. Roughly one CI run in ten; not reproduced in 8,500 local
  runs across macOS arm64 and Linux aarch64. Tracked in
  `specs/todos/2026-09-04-actor-monitor-down-reason-sigsegv-on-linux.md`.
- **`march --compile` on a module with no `main`** can fail the default
  capability ceiling, charging the prelude's `IO.Console` to your module.
  `--no-cap-strict` works around it. `forge build` on a library is unaffected
  (it uses `--check`). Tracked in
  `specs/todos/2026-09-09-cap-ceiling-charges-prelude-io-to-mainless-module.md`.

---

## Quick checklist

- [ ] Decide whether you want the new CPU-tracking scheduler default, or pin
      `MARCH_NUM_SCHEDULERS=4` to keep 0.3.x behaviour.
- [ ] If you run in containers, confirm your CPU limits are what you expect —
      the default now follows them.
- [ ] Update any test asserting a specific live-object count.
- [ ] Remove `show` workarounds written for `#<tag:N>` rendering.
- [ ] Remove any `String.concat` workaround for large interpolations.
