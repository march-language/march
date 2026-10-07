# The sendability fixtures lose their witness; the language reference says what replaced it (Part C, Phase C4)

**Landed 2026-10-06.** Phase C4 of
`specs/plans/2026-09-25-send-data-race-freedom-plan.md`. Depends on C1
(`2026-10-06-native-arrays-sendable.md`) and C2
(`2026-10-06-ring-buf-always-linear.md`). The todo
`specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md` stays open
until C5.

## Fixtures

`reject/t159`–`t163` used a `RingBuf` payload to prove that every send path
(`send_checked`, `Actor.cast` qualified and bare, `Actor.call` qualified and
bare) ran the sendability check. After C1 and C2 no type fails that check, so
they were rewritten (pulled forward into the C2 commit so its corpus run stayed
green) to move a `RingBuf` through each path and then use it: each rejects with
`` is used more than once here ``, proving the path is a consuming use.
`accept/t40`'s comment no longer names a "`RingBuf`-family constructor".
**Two-repo rule:** the five rewritten `EXPECT-ERROR` lines are mirrored in
`march-lean` together with C2's eight new rejects.

## Language reference (`specs/lang/`, regenerated into `docs/` by `scripts/gen-lang-docs.py`)

- `actors.md`: the "message payload may not carry a mutable-buffer type"
  paragraph is now "a linear value moves on send, and everything else is
  immutable or copy-on-write", with the moving-send example; the empty denylist
  is described as the enforcement point for `memory-model.md`'s rule.
- `linear-types.md`: `RingBuf` named beside `Handle` and `LinearMap` under
  "always_linear Types"; a new section "A Single-Owner Buffer: `RingBuf`" with
  the actor-state example and the corpus pointers; Practical Rules 7 (thread a
  `RingBuf`) and 8 (no module-level `let` of a linear value).
- `memory-model.md`: the acquire-ordering guarantee under "Parallel FBIP needs
  no locks" (C0's change, stated for readers). The rule for future mutable
  primitives lands with C5.
- `parallelism.md`: a captured native array may be read (and written, into its
  own copy) from parallel code; a `RingBuf` cannot be captured at all.
- `core-march-types.md`: the `check_sendable` description in §2.6.4 and the
  finding-19 note describe a zero-entry list rather than a `RingBuf` denylist.
- The `march-lang` agent skill's one-line `RingBuf` mention says the API is
  linear.

`CHANGELOG.md`: the `### Changed` (RingBuf API), `### Added` (native arrays)
and `### Fixed` (C0) bullets landed with their phases; a `### Documentation`
bullet points readers at the three rewritten chapters.
