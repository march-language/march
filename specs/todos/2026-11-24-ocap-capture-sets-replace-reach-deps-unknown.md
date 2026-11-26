`[P2]` Replace the reach solver's `deps` and `unknown` with capture sets (2026-11-24)

The capture-checking design (`specs/2026-11-11-ocap-capture-checking-design.md` §6.3) says
capture sets replace `Cap_rows`' parameter dependencies (`deps`) and its untraceable-call
flag (`unknown`): an untraceable value now has a type, and the type has a set. Phase 8a left
`lib/caps/cap_rows.ml` and `check_fn_bounds` untouched on purpose, because 8a may change no
accepted or rejected program, and `unknown` under a narrow function bound is a rejection
today.

Do this with or after phase 8c. It changes which programs are rejected, so it needs its own
types-oracle review and a `### Changed` changelog entry.
