# `[P3]` `Session.ip_step`'s crash-handler arm may leak its `st` record

**Logged:** 2026-10-08, noticed while fixing
`specs/progress/2026-10-07-perceus-releases-parent-before-field-use.md`.

In the post-Perceus TIR of `Session.ip_step` (`stdlib/session.march`), the arm
that finds a crash handler (`Some(h)` after `Vault.get(st.crash_hs, ...)`) does
`inc_rc st; Session.ip_forget(st, ep)`, reads `st.trace`, calls the trace and
the handler, and returns `()`. Nothing on that path releases the function's own
reference to `st`; the other arms do (`dec_rc st`, or a consuming call without
an `inc_rc`).

If that reading is right, every crash-handled step leaks one session-state
record (13 fields, most of them Vault handles). Not confirmed at run time.

## Next step

Count live objects around a crash-handled step (`scripts/gc-trace-report.py`
with `--rc-trace`), or read `query fn Session.ip_step --at tir-perceus` and
check whether a later pass (drop, elide) adds the release.
