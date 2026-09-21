# DONE 2026-09-21: the HCR audit log records each deploy's capability set

One bullet of `specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md` (the
other two, Phase 0 and Model B, stay open there and were not touched).

## What changed

`write_audit_log` (`runtime/march_reload.c`) now writes `caps` (JSON array)
and `cap_root` on every line:

- ACTIVATE4 (the only protocol that carries capability data): the received
  `caps:<csv>` split into an array (`[]` for a capless artifact) and the signed
  `cap_root`. Values are recorded AS RECEIVED, so they are verified exactly when
  the tamper check has passed: `ok`, `err_cap_policy`, and post-admission errors
  (`err_cas_miss`, `err_dlopen`, ...). On `err_sig`/`err_cap_tamper` they are what
  the rejected request claimed, which is the useful forensic record there.
- ACTIVATE / ACTIVATE2 / ACTIVATE3: `"caps":null,"cap_root":null`, distinct
  from an empty v4 set.
- Batched ACTIVATE4 (BEGIN_BATCH ... COMMIT_BATCH): staged entries now carry
  heap copies of caps/cap_root (freed on commit, rollback and disconnect), so the
  audit line written at commit time has them too. Heap, not inline buffers: the
  256-entry staged array is on the reload thread's stack (~395 KB already), and
  +1 KB inline per entry would overflow a 512 KB macOS secondary-thread stack.
- Cap tokens are JSON-escaped (the other fields are hex/identifiers as before).

A `--grant-cap` widening becomes part of the signed cap set, so it shows up in
`caps`. Which `--grant-cap` flags the client passed is client-side knowledge
the server never receives; recording that would need a protocol field and was
not done.

`docs/hot-code-reload.md` now documents the line format, the null-vs-[]
distinction, the as-received caveat, and a `jq` query for "when did this node
last gain capability X" (checked against sample lines).

## Verification

`test/test_reload_activate4.c` (real reload server over a Unix socket, both the
default and `MARCH_DEPLOY_POLICY` runs) now points `$MARCH_AUDIT_LOG` at a
per-run temp file (it previously appended to the real
`~/.local/share/march/audit.jsonl` of whoever ran the suite) and asserts the
last line after each request: matching root (caps + root, `err_cas_miss`),
tamper (claimed caps, `err_cap_tamper`), empty set (`[]`), ACTIVATE3 (`null`),
policy violation (`err_cap_policy`), and a new batch case (caps survive
staging to the COMMIT_BATCH line).

Red control: `write_audit_log` forced to ignore its caps argument (what main
records today): every caps/cap_root assertion FAILs except the ACTIVATE3
`null` case, as expected. With the change: both runs pass.

---

## Original bullet (filed 2026-07-24)

- [ ] **Audit log doesn't record capability data (found reviewing `docs/hot-code-reload.md` for accuracy, 2026-07-24)** — `write_audit_log` (`runtime/march_reload.c`) writes one JSON line per `ACTIVATE` with `ts/type/fn/impl_hash/signer/cas_hash/result` (per Phase 7 above) — no capability field at all. So today the audit log answers "who deployed this function, when, and did it succeed," but not "what capabilities did this deploy touch" — a `--grant-cap`-authorized widening isn't distinguishable, after the fact, from an ordinary same-authority redeploy, and there's no way to reconstruct a capability-history timeline for an actor/function from the log alone (the granted/declared caps live only in the signed `.hcr_manifest`/wire payload at deploy time, not in any durable per-activation record). Add a `caps`/`cap_root` field (and, for the client-side gate, which `--grant-cap` flags were used) to the audit line so an operator can answer "when did this system last gain capability X" from the audit log directly instead of needing the manifest from that specific deploy.
