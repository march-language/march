# Registry capability notarization (cap-audit plan Tasks 7–8)

Design: `specs/2026-08-03-forge-cap-audit-design.md` §4.3 mechanism D.
Phases 1–2 shipped 2026-08-03 (`specs/progress/2026-08-03-forge-cap-audit-phases-1-2.md`).

**Compiler half is DONE.** `march caps <files...>` prints a package's *inferred*
own-capability set as JSON (`{"caps":["IO.Console","IO.FileRead"]}`), filtered to the
file's own functions. Verified to report `IO.FileRead` for a module that declares no
`needs` but calls `file_read` in a body — the case where `--check` exits 0 (the F1
warning-only gap). Notarizing the *declared* set instead would manufacture a false
`registry-MISMATCH` against that module's own honest binary.

**Blocked on the registry server, which lives in a different repo (forgepm).**
`forge publish` does not build a JSON payload in-process: `Registry_client.run_action`
compiles and runs an embedded March client (`forge/tasks/registry.march`) that speaks
the forgepm publish HTTP API, passing data via environment variables. Shipping
notarization needs, in order:

- [ ] **forgepm server**: accept and store a `caps` string array on the publish
  endpoint, and return it from the package-metadata endpoint. Until this exists the
  client half is unverifiable — do not land a client that sends a field the server
  silently drops.
- [ ] **`forge/tasks/registry.march`**: send the caps array on publish; expose it on
  metadata fetch.
- [ ] **`forge/lib/cmd_publish.ml`**: `cap_set_of_project` — run `march caps`
  over the package's `.march` files (mirroring `Cmd_build.check_all`'s shell-out and
  `lib_path_env` handling), union and `Cap_lattice.normalize`, pass via `extra_env`.

  **Measured 2026-08-03 — per-file invocation does NOT work, and the obvious fix
  makes it worse.** Running the extractor file-by-file over real packages analyzed
  only conduit 9/43, depot 14/32, bastion 36/60: most files reference sibling
  modules and fail standalone (`I don't know a constructor called
  ConduitExponential`). Setting `MARCH_LIB_PATH` to the package's own `lib/` made
  conduit *worse* — 0/25 — because module resolution is per-source-directory
  (`Module 'Pool' not found (looked for 'pool.march' in the source directory)`)
  and the entry file's own tree then collides. So a naive union over per-file runs
  silently under-reports a package's capabilities, which is the wrong direction for
  a notarization record: it would certify a package as needing less than it does.
  The implementation must reuse `forge build`'s real per-entry lib-path
  construction, and must **fail loudly when any file in the package cannot be
  analyzed** rather than unioning whatever happened to typecheck.
- [ ] **`forge cap inspect --notarized`**: compare the binary's caps against the
  registry record using `Cap_lattice.cap_subsumes`, NOT string equality — a binary
  needing `IO.FileRead` is consistent with a record of `IO`, but not the reverse.
  Verdicts: `registry-match` / `registry-MISMATCH <caps>` / `not-published` /
  `registry-unreachable`. **`registry-unreachable` must never render as a match**;
  the audit's verdict line already reserves the slot.

Once this lands, the highest-value follow-on is
`specs/todos/2026-08-03-forge-deps-upgrade-cap-diff.md` — surfacing per-package cap
widening at dependency-upgrade time, which catches the xz/event-stream shape that the
whole-binary gate structurally cannot.
