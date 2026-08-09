# The ceiling counts a signature-only capability as an unattributable use

Found 2026-08-07 while fixing indirect-call attribution
(`specs/progress/2026-08-07-cap-attrib-table-agreement.md`).

**CLOSED 2026-08-08, with the default flip
(`specs/progress/2026-08-08-cap-strict-default.md`).** What forced it: the
false positive fired on `fn main(cap : Cap(IO))` — the DOCUMENTED entry-point
shape (`test/native/main_cap_io.march` exists to pin exactly that pattern) —
so once the ceiling became the default, the bug rejected the sanctioned way
to write `main`, not just a demo file. The fix is the "likely right answer"
recorded below: the strict check's used-set is now the attributed (body-
derived) set alone, and `own_caps_of_this_module` no longer feeds it — it
still feeds `--cap-sandbox`, where the signature reading is correct. The
drift-detector value the union provided (it is what surfaced the 2026-08-07
attribution bug) is carried by `test_cap_attrib_agreement` instead. The
`Cap_ceiling.describe` reason-carrying improvement below remains unbuilt;
with no remaining feeder for `Unattributed` it is a dormant backstop, and the
misleading message matters correspondingly less.

The original filing follows.

- [x] **A capability that appears only in a SIGNATURE is reported as
  "cannot be attributed to any module".** Reproducer is in the tree:

  ```
  $ march --compile --cap-strict -o /tmp/x examples/capabilities.march
  -- CAPABILITY CEILING --
  `IO` is used but cannot be attributed to any module — it is reached only
  through indirect calls, whose callee is not statically known
  ```

  The module declares `needs IO` and the only thing naming the root is a
  parameter type — `fn demo_narrowing(cap : Cap(IO)) : Unit` at
  `examples/capabilities.march:60`, which exists to demonstrate narrowing.

  **Mechanism, and note it is NOT the indirect-call gap the message names.**
  `--cap-strict` compares two sets:

  - `flat_caps` — the union of attribution's caps and
    `own_caps_of_this_module` (`bin/main.ml`), the latter derived from
    typecheck's per-function closures, which record SIGNATURE capabilities;
  - `attribution` — `Cap_attrib.attribute` over emitted TIR, which produces a
    row only for a capability reached by an emitted CALL.

  A signature type is not emitted code, so attribution can never produce a row
  for it, while `own_caps_of_this_module` always contributes one to
  `flat_caps`. `Cap_ceiling.check` computes "flat minus attributed" and reports
  the difference as `Unattributed`, whose `describe` blames indirect calls
  because that was the only cause it was written for.

  **Do not fix by treating "declared by some module" as attributed** — that
  would mask a genuine unattributed use whenever any module in the program
  declares the same capability, which is the case the fail-closed rule in
  `cap_ceiling.mli` exists for.

  The likely right answer is that the unattributed check should compare
  against BODY-derived uses only, since its stated purpose is "a capability
  nobody can be held responsible for" and a capability sitting in a type is
  not routed anywhere. That needs `own_caps_of_this_module` to distinguish
  signature-derived from body-derived caps, which it currently does not.

  Whatever lands should also fix `Cap_ceiling.describe`: a single
  `Unattributed` constructor that always blames indirect calls produced a
  diagnostic that misdescribed its own cause for the whole of the
  `task_spawn` bug, and would do so again here. Carrying a reason on the
  constructor is cheap and would have shortened both investigations
  considerably.
