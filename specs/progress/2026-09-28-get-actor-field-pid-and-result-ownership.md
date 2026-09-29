# `get_actor_field` borrows its Pid (fixed 2026-09-28)

**Fix.** Following steps 2 and 3 of the sketch below; step 1 was already moot
after the 2026-09-25 update. `get_actor_field` (and its C name
`march_get_actor_field`) moved from `extern_owned_builtins` to
`extern_borrow_table` as `[true; true]` in `lib/tir/borrow.ml`.
`march_get_actor_field` only reads the pid's record shape and the name's
bytes, and it returns an immediate field or None, never a heap value, so no
reference is handed back.

**RED/GREEN.** `test/native/pid_to_int_leak_probe.march` gains a probe. It
reads the supervisor's refcount, calls `get_actor_field` three times (two
hits and one miss), and reads the refcount again. `boss` is used afterwards
(`kill`), so the program's own reference is still held at the second read.
- With origin/main's `borrow.ml`: `get_actor_field leaves the count alone:
  false`.
- With the change: `true`.

The first draft measured after `boss`'s last use and saw Perceus's own
release (2 -> 1), so the probe now keeps `boss` alive past the measurement.

**ASAN.** The probe compiled with `MARCH_SANITIZE=1` in the Linux
container (arm64) ran 5/5 clean.

---

Original report:

# `[P3]` `get_actor_field` leaks its Pid, and returns a field without a reference

Found 2026-09-24 while fixing [[2026-09-24-pid-to-int-leak]] (specs/progress/).

## Symptom

`get_actor_field(pid, "name")` is still in `lib/tir/borrow.ml`'s `extern_owned_builtins`,
so every call leaks one reference to `pid`'s actor record (measured: a supervisor probed
once with `get_actor_field` sits at refcount 2 instead of 1;
`test/native/pid_to_int_leak_probe.march` shows it as the one remaining extra
reference). A record ever probed is never freed.

## Why it was not simply moved to the borrow table

`march_get_actor_field` (runtime/march_extras.c) only reads the pid and the name, but for a
non-Int field it returns the field's raw pointer verbatim, with no `march_incrc`, while the
caller treats the returned `Option` as owned. Today the leaked pid is what keeps a dead
actor's record (and therefore that field) alive. Borrowing the pid alone would let the
record be freed right after the call on a dead actor while the caller still holds the field
pointer.

## Fix sketch

1. Make the runtime return an owned reference for a boxed field (`march_incrc` the raw
   pointer before returning it; the `'i'` kinds are immediates and need nothing).
2. Then move `get_actor_field` to `extern_borrow_table` as `[true; true]` (the name is only
   read too).
3. Extend `pid_to_int_leak_probe` with a boxed-field probe and an rc assertion after
   `get_actor_field`, and run it under ASAN in the Linux container.

**Update 2026-09-25.** `get_actor_field` now returns only immediate (Int-like) fields
(`specs/progress/2026-09-25-dd-review-get-actor-field-unchecked-cast.md`), so the
"returns a field without a reference" half is gone: no boxed field is handed back.
Step 1 of the fix sketch is moot; steps 2 (borrow the pid) and 3 (the rc probe) remain.
