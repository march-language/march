# `test/native/actor_enumeration.march` was a use-after-free under ASAN, on main

**Closed 2026-09-14, the same day, by a different session that met it as the
ubuntu CI leg's `tcache_thread_shutdown(): unaligned tcache chunk detected`
abort:** the diagnosis below was right. The 40-byte object is the actor
record; `main` releasing its unused `a` freed a running actor because the
runtime held no reference of its own. Fix and reproduction in
[[2026-09-14-live-actor-freed-by-dropping-its-last-pid]]; the ownership
question the last paragraph raises is settled in
[[2026-09-14-pid-ownership-settled-send-borrows-self-owned]]. The original
note follows.

---


Found 2026-09-14 while sweeping this branch's ASAN corpus
(`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`). It is
**not** caused by that change: the same program built from `origin/main`
61d5f167 fails identically, 3 runs of 3, in the `march-sbx-test-ubuntu`
container (linux/arm64, `MARCH_SANITIZE=1`, `ASAN_OPTIONS=detect_leaks=0`).

## Signature

```
ERROR: AddressSanitizer: heap-use-after-free on address 0x504000000028
    #0 actor_green_thread march_runtime.c
    #1 proc_trampoline march_scheduler.c
freed by thread T0 here:
    #0 free
    #1 march_decrc
    #2 march_decrc_local
    #3 march_main
previously allocated by thread T0 here:
    #0 calloc
    #1 march_alloc
    #2 march_main
```

A 40-byte object allocated and released by `main`'s own code is read by an
actor's green thread afterwards. 40 bytes and allocated in `march_main` fits an
actor record (`spawn(W)` allocates the record in the caller). `main` releases
its pid variable at the last use, and an actor thread still dispatching or
dying reads the record. Unconfirmed; the next step is to name the object
(`--emit-llvm`, match the alloc site's size to `spawn` / `kill(b)` / the
`Actor.stop(c, 5000)` call).

The native golden passes on macOS and Linux CI because the freed block is not
reused before the read. ASAN quarantines freed blocks, so it reports the read
every time.

## Why it matters

It is the same shape as the actor-record frees in
`specs/todos/2026-09-13-send-leaks-a-reference-to-a-live-pid.md`: nobody has
settled who owns an actor record's reference across `spawn`, `kill`, `stop`,
and the runtime's own dispatch loop. Adding this program to
`specs/lang/golden/sanitize.sh`'s native corpus is the guard, once it is clean.
