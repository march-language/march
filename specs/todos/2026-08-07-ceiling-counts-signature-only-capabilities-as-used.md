# The ceiling counts a signature-only capability as an unattributable use

Found 2026-08-07 while fixing indirect-call attribution
(`specs/progress/2026-08-07-cap-attrib-table-agreement.md`). It is the last
remaining `--cap-strict` false positive in `examples/` + `bench/` — 1 of 72.

- [ ] **A capability that appears only in a SIGNATURE is reported as
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
