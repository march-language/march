# Actor-handler capability attribution charges the entry module, not the declaring module

Found 2026-08-08 while defaulting the capability ceiling
(`specs/progress/2026-08-08-cap-strict-default.md`).

- [ ] **A capability used inside an actor handler declared in a NESTED module
  is attributed to the entry module.** Reproducer is the HCR-manifest fixture
  in `test/test_stdlib_suite.ml` (`hcr_manifest_actor_handler_caps_fixture_src`):
  `mod Outer` containing `mod Inner` with `needs IO.Console` and an actor
  whose `on Zorp` handler calls `println`. The ceiling reports:

  ```
  module `Outer` uses `IO.Console` but does not declare `needs IO.Console`
  ```

  even though `Inner` — the module that declares the actor — declares the
  capability.

  **Mechanism.** The handler's synthesized TIR fn name is BARE
  (`Weeble_Zorp`: actor short name + `_` + message name), not qualified by
  its declaring module — the fixture's own comment documents this as the HCR
  manifest convention, and `check_module_needs`'s DActor branch keys
  `record_fn_caps` the same bare way. `Cap_attrib.attribute`'s `owner_of`
  resolves an unprefixed name to the entry module, so the console use inside
  the handler lands on `Outer`.

  **Consequence under the default-on ceiling:** a user with actors in nested
  modules must put the `needs` line on the ENTRY module even when the nested
  module already declares it. One line, and the error names the module to
  edit, so it is a paper cut rather than a blocker — but the attribution is
  wrong, and per-dependency capability budgets
  (`specs/todos/2026-08-04-cap-ceiling-follow-ups.md`) would inherit the
  mis-ownership: an actor-using dependency's capability would be charged to
  the APP.

  **Likely fix shape:** lower/mono should record the declaring module for
  synthesized handler names (a side table, or qualify then strip for the
  manifest), so `owner_of` can consult it before falling back to the entry
  module. Renaming the synthesized fn itself is the riskier route — the HCR
  manifest format asserts the bare spelling.

  When fixed: remove `needs IO.Console` from `Outer` in the fixture (the
  comment above it says so) and un-skip nothing — the ceiling default already
  exercises the route.
