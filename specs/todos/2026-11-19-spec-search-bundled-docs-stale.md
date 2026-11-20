# The bundled spec-search docs are stale (2026-11-19)

Found by the ocap phase 4 PR B final review. `.claude/skills/spec-search/docs/`
and `spec-search.db` are a manual snapshot of specs/lang, specs/impl and
specs/features. They predate ocap phase 4: for example
`docs/lang/capabilities.md` still says the `random_bytes` builtin is dead and
has no run-time authority section, so an agent searching it is told things the
compiler no longer does.

`scripts/build-spec-index.sh` rebuilds it. What to do: run it, review the diff,
commit; and consider a doc-lint check (like Check F for `docs/`) that fails when
the snapshot's source commit falls too far behind.
