`[P4]` The editor's hover for a lemma call shows the lemma's theorem and whether it was proved
(`Analysis.query_lemma_hover_at`, `Refine_diag.lemma_admitted`), but not the `uses:` note: which
reflected definitions and lemmas a proof at that site used. Hover has no per-site verdict
channel yet; the compiler prints `uses:` only under `--refine-report-sites=all`
(reflection design §2.4, §10 phase 2 scope).

Done when hovering a refined call whose obligation was proved shows its `uses:` list, read from
the same check the LSP already runs.
