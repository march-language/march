# HCR Phase 5C — Capability-Safe Hot Deploys

**Date:** 2026-06-25
**Updated:** 2026-06-27
**Status:** Draft / proposed — none of Parts A/B/C have landed yet
**Depends on:** HCR Phases 1–10 complete (CAS `impl_hash` Merkle, versioned dispatch, native reload server, `forge deploy hot` CAS-native + ed25519 signing, actor state migration, cross-module ABI gating, coordinated upgrade gate, epoch-tagged dispatch via `__march_init`, cluster-aware rolling deploy); the Phase 1 capability system (permission IO caps, `needs`, transitive closure, proof caps). Also assumes `ACTIVATE2` landed (c9e2e86c) which extended the signed payload to cover `epoch:N callers:<csv>`.
**Spec parents:** `specs/plans/2026-06-24-hcr-phase5-design.md`, `specs/capability-system-design.md`, `docs/capabilities.md`

### Landed since this plan was written (context delta)

The following related work landed after 2026-06-25 and affects this plan:

| Commit | What landed | Impact on Phase 5C |
|--------|------------|-------------------|
| c9e2e86c | **ACTIVATE2** — signed payload now covers `epoch:N callers:<csv>` | Part C must extend ACTIVATE2, not the old ACTIVATE. `cap_root` becomes the next field added to the signed message. |
| 1ad76ca2 | **`cap pure`, `cap no_extern`, `cap deterministic`** — new non-IO cap types | The cap manifest (Part A) and monotonicity gate (Part B) must cover all cap kinds, not just `IO.*` caps. The widening check applies to `pure`, `no_extern`, `deterministic`, `no_alloc` too. |
| bc500f47 | **`cap no_alloc`** — ban heap allocation in no-alloc modules | Same: Part B monotonicity applies. Additionally, `migrate_state` could be bounded by `no_alloc` in the follow-on (see Out of Scope). |
| 2627f597 | **Z3 division-safety pass for `cap no_panic` modules** | `no_panic` is now live; IR-level bounds in migrate_state context (currently Out of Scope) are closer than when this plan was written. |
| 0566c52c | **`needs` capability inference hints** | Complements Part A; inference can auto-populate `needs` declarations from body analysis. |
| 8e3e4850 | **Phase 8: callers per slot + coordinated upgrade gate** | `.hcr_manifest` now has `callers:` field per `FN` line (see format below). `cap_root` and `caps=` fields must come after `callers:` in the updated format. |
| f86f9b66 | **Phase 9: epoch-tagged dispatch via `__march_init`** | Epoch is now baked at server; ACTIVATE2 carries `epoch:N` as a mandatory field. Part C extends this. |
| a7588911 | **Phase 10: cluster-aware rolling deploy** | `forge deploy hot` orchestrates multi-node; the monotonicity gate (Part B) runs once on the deployer side before any per-node ACTIVATE2. Node admission (Part C) runs independently on each node. |

**Key structural change:** `io_cap_hierarchy` is now **duplicated** — it exists in both `lib/typecheck/typecheck.ml:933` and `lib/refinecheck/cap_infer.ml` (with a comment "Same hierarchy as..."). The `lib/caps/cap_lattice.ml` factoring (Part A) is therefore more urgent, not less: it now needs to absorb the refinecheck copy too and serve as the single source for all three consumers (typecheck, forge deploy, C runtime table).

---

## Goal

Make hot deploys *authorized*, not merely *authenticated*. Phase 4 made a hot deploy **authentic** — `forge deploy hot` signs each `ACTIVATE` with ed25519 and the server verifies before `dlopen` (`runtime/march_reload.c:320`). But it does not make a deploy **authorized**: static permission capabilities are erased to `null` at compile time (`lib/typecheck/typecheck.ml` Phase 1), so a *signed* patch can call `file_delete`, `tcp_connect`, or spawn a process even if the running version never touched the filesystem or network. The trusted key answers "is this code from us?" — nothing answers "is this code allowed to do what it does?"

The thing Phase 5 ships **is mobile code**: a `migrate_state` function and a new handler closure, built on one machine, content-addressed, shipped over the wire, `dlopen`'d on the target node, and run against live actor state. Phase 5C governs that mobile code with the capability discipline March already computes at compile time and currently throws away after checking.

Three slices, continuing the Phase 5 Part-letter convention:

- **Part A — Capability manifest** (compile-time emission): compute each boundary function's transitive capability closure (the data `check_module_needs` already traverses) and emit it into the deploy artifact's manifest, with a `cap_root` digest.
- **Part B — Monotonicity gate** (deploy-time invariant): a hot deploy may *narrow* the live system's authority freely, but *widening* it is rejected unless explicitly authorized by a signed cap-grant. This is the capability dual of Phase 5 Part B's schema variance-duality table.
- **Part C — Node admission + `migrate_state` bound** (runtime trust boundary): the receiving node refuses to activate an artifact whose authority exceeds a node-local policy, and `migrate_state` is compile-time bounded to IO-free data transformation.

### Why this is research-adjacent, not just engineering

- **Part B is a *temporal* capability discipline across code versions** — "your running system's authority can only shrink across hot deploys without a fresh grant." Object-capability monotonicity over a live, hot-reloaded process is not a standard result; March can state and check it because authority is a static, content-addressable fact and code is shipped by content hash.
- **Part C is the static/dynamic bridge.** Permission caps are normally erased at compile time and have no runtime existence; `Cap(Pid)` is a disjoint runtime notion. ACTIVATE is the one point where foreign code crosses into the process, so it is exactly where the erased static discipline gets re-materialized as a runtime checkpoint — unifying the two cap worlds at the boundary where it matters.

Parts A and C are mostly engineering on machinery Phase 5 already shipped (CAS, manifest sidecars, `ABI_QUERY` prior-fetch, signed `ACTIVATE`, the audit log). Part B is the novel piece.

---

## Decisions

| Question | Answer |
|---|---|
| Cap granularity | Per-boundary-function transitive capability closure, aggregated to a per-artifact cap set, plus a `cap_root` digest over the sorted set |
| Where caps come from | Reuse the transitive `needs` closure that `check_module_needs` already computes (`typecheck.ml:5159`, Check 4) — today it is checked and discarded; expose it. No new analysis. |
| Cap lattice ownership | Factor `io_cap_hierarchy` + `cap_subsumes` (`typecheck.ml:933`, `:1071`) into a shared `lib/caps/cap_lattice.ml` that typecheck, refinecheck, and forge all depend on — two copies exist today (`typecheck.ml` and `refinecheck/cap_infer.ml`); this removes the duplication and adds the C-table emitter |
| Manifest carrier | Extend the existing `.hcr_manifest` sidecar (already per-fn `impl_hash`/`sig_hash`) with a `caps` list per fn + a top-level `cap_root`; content covered by `cas_hash` |
| Monotonicity rule | Deploy may *narrow* freely; *widening* (a new cap not subsumed by any prior-held cap) aborts before `ACTIVATE` unless an explicit `--grant-cap <C>` authorizes each widened cap |
| Grant authority | A widening grant rides the deployer's ed25519 signature: `cap_root` is added to the signed `ACTIVATE` payload, so the authority claim is tamper-evident and audit-logged |
| Node policy | Optional `MARCH_DEPLOY_POLICY` file (newline-delimited cap paths) caps the node's maximum admissible authority; absent ⇒ permissive (preserves current behavior) |
| Tamper-evidence | Server recomputes `cap_root` from the CAS-received `.hcr_manifest` and checks it equals the signed `cap_root` before the policy check |
| `migrate_state` bound | Compile-time: a recognized `migrate_state` (Phase 5's name+signature recognition) must have an empty IO cap closure — it runs in the migration window ahead of user messages. IO use ⇒ compile error. (NoAlloc/`no_panic` bound deferred to the `policy_dce` follow-on.) |
| Backward compatibility | All gates are opt-in/additive: no manifest caps ⇒ legacy artifact ⇒ permissive admission, unchanged behavior. Strictness is enabled by shipping a policy file. |

---

## Part A: Capability Manifest

### Per-function capability closure

`check_module_needs` (`lib/typecheck/typecheck.ml:5159`) already computes, for every function, the transitive set of IO capabilities it requires: declared `needs` (Check 1), builtin calls in the body via `builtin_cap_table` + `calls_in_expr` (Check 1b, `typecheck.ml:956`/`~:5199`), `extern` ⇒ `IO.Foreign` (Check 1c), and imported-module propagation (Check 4). Today this set is validated and discarded.

Note: since this plan was written, `check_module_needs` has been extended to also handle `cap pure`, `cap no_extern`, `cap deterministic`, and `cap no_alloc` (env fields `no_panic_mod`, `no_extern_mod`, etc., `typecheck.ml:484–495`). The per-fn closure exposed by Part A should therefore include all capability kinds, not only `IO.*`.

**Change:** expose it. Add an accessor that returns, per top-level function, the canonical sorted list of leaf capability paths it needs (after `cap_subsumes` normalization — drop any cap subsumed by another in the same set). This is a read-only projection of the existing analysis; no new traversal.

### Artifact aggregation + `cap_root`

In `--hot-reload --compile-so` mode, `bin/main.ml` (which already writes the `.hcr_manifest` and `.schemas.json` sidecars) computes:

```
artifact_caps = sorted( ⋃ over boundary fns f of caps(f) )      -- normalized, no subsumed dups
cap_root      = blake3( "\n".join(artifact_caps) )              -- deterministic content digest
```

### Manifest format extension

`.hcr_manifest` gains a per-fn `caps` field and a top-level `cap_root`. The current manifest format (after Phase 8 added `callers:`) is:

```
FN   <name> <impl_hash> <sig_hash> callers:<sorted-csv>
```

The extended format adds `caps=` after `callers:` and a new top-level `ROOT` line:

```
CAS  <cas_hash>
ROOT cap_root=<hex>
FN   MyApp.Server.handle   <impl_hash> <sig_hash> callers:MyApp.Router.route caps=IO.Console,IO.NetConnect
FN   MyApp.Server.migrate_state  <impl_hash> <sig_hash> callers: caps=
```

`forge/lib/cmd_deploy_hot.ml` already parses `callers:` from field index 3 (`fn_callers`); `caps=` would be parsed from field index 4.

Caps go in `.hcr_manifest` (per-function) rather than `.schemas.json` (per-actor-state). The manifest is already keyed in the CAS next to the artifact, so `forge deploy hot` and the server both reach it by the path derivation Phase 5 established.

---

## Part B: Monotonicity Gate (deploy time)

In `forge/lib/cmd_deploy_hot.ml`, after the existing `ABI_QUERY` prior-state fetch and `sig_hash` ABI gate (the prior-manifest read already uses the `.hcr_manifest` path derivation established in Phase 5):

1. **Fetch prior caps.** Read the prior deployed artifact's `.hcr_manifest` from the CAS (same path derivation already used to fetch the prior `.schemas.json`). Compute `prior_caps = ⋃ prior fn caps`.
2. **Compute new caps** from the build's own manifest.
3. **Diff.** A new cap `C` is *covered* iff `∃ P ∈ prior_caps. cap_subsumes P C` (shared `Cap_lattice.subsumes`). *Widening* = the set of new caps not covered by any prior cap. *Narrowing* = prior caps no longer present (always fine, logged).
4. **Gate.** If `widening` is nonempty and not every widened cap has a matching `--grant-cap`, abort **before** `ACTIVATE` with an actionable diagnostic.
5. **Authorize granted widenings.** Each `--grant-cap C` removes `C` from the blocking set and is folded into the signed payload (via `cap_root`) and the audit record.

### Capability variance-duality (the dual of Phase 5 Part B's table)

| Capability change in the new version | Allowed in a hot deploy? |
|---|---|
| Drop a capability (narrow authority) | ✅ always |
| Add a cap subsumed by a held one (held `IO.Network` → add `IO.NetConnect`) | ✅ — within existing authority |
| Add a sibling / unrelated leaf the running version never held | ❌ unless `--grant-cap` (+ signed) |
| Widen to a parent (`IO.FileRead` held → now `IO.FileSystem`) | ❌ unless `--grant-cap` |
| Add the `IO` root | ❌ unless `--grant-cap IO` (maximal widening; strongly discouraged) |

### Diagnostic shape

```
error: hot deploy would add authority not held by the running version
  running version caps:  IO.Console, IO.NetConnect
  new version adds:      IO.Process   (from MyApp.Server.handle → builtin `spawn_process`)
  A hot deploy may only narrow authority. To authorize this widening, re-run with:
      forge deploy hot --grant-cap IO.Process
  The grant is signed and recorded in the audit log.
```

The grant is deliberately friction: widening the authority of a *live* system mid-flight is exactly the event an operator should consciously sign for.

---

## Part C: Node Admission + `migrate_state` Bound

### Node deploy policy

The server loads an optional policy at startup (`runtime/march_reload.c`): `MARCH_DEPLOY_POLICY` points to a newline-delimited list of permitted cap paths (subsumption-expanded — listing `IO.Network` permits `IO.NetConnect`, etc.). Absent ⇒ permissive (unchanged behavior). A policy of e.g.

```
IO.Console
IO.FileRead
IO.NetConnect
```

means: this node will never activate code that writes files, spawns processes, or does foreign FFI, regardless of who signed it.

### `ACTIVATE2` extension + admission

**`ACTIVATE` (v1) is still supported for legacy compatibility; `ACTIVATE2` is the active protocol.**  The current `ACTIVATE2` wire format and signed payload are (`march_reload.c:568`):

```
Wire:   ACTIVATE2 <name> <impl_hash> <cas_hash> <sig_b64> <migrate>
                  epoch:<N> callers:<sorted-csv>
Signed: "ACTIVATE2 <name> <impl_hash> <cas_hash> epoch:<N> callers:<sorted-csv>"
```

Phase 5C extends `ACTIVATE2` by adding `cap_root` to both the wire line and the signed message:

```
Wire:   ACTIVATE2 <name> <impl_hash> <cas_hash> <sig_b64> <migrate>
                  epoch:<N> callers:<sorted-csv> cap_root:<hex>
Signed: "ACTIVATE2 <name> <impl_hash> <cas_hash> epoch:<N> callers:<sorted-csv> cap_root:<hex>"
```

`cap_root` is optional on the wire for backward compatibility: absent ⇒ legacy artifact ⇒ permissive admission (same rule as "no `caps`/`cap_root`" in the Failure Modes table). The server's `do_activate()` helper (`march_reload.c:267`) handles both paths.

Server flow on `ACTIVATE2`, after sig-verify + CAS-load (existing) and before `dlopen`:

1. Read the just-received artifact's `.hcr_manifest` from the CAS; recompute `cap_root'` over its `caps`.
2. **Tamper check:** `cap_root' == cap_root` (the signed value). Mismatch ⇒ `ERR cap_tamper`, audit `err_cap_tamper`.
3. **Policy check:** every cap in the artifact set is subsumed by some policy entry. Violation ⇒ `ERR cap_policy <cap>`, audit `err_cap_policy`.
4. Proceed to `dlopen` + `march_dispatch_publish` as today.

This is the single runtime checkpoint that re-materializes the erased static cap discipline at the trust boundary. `march_reload.c` needs a tiny cap-subsumption check; share the lattice as a small generated C table (emitted from `Cap_lattice` so it cannot drift from the OCaml hierarchy — same anti-drift rule as the OCaml/forge split).

### `migrate_state` capability bound

`migrate_state` runs as the actor's next turn, ahead of any pending user messages (Phase 5 Part A, migrate-before-run ordering). It is a pure old→new state transformation; doing IO inside the migration window (or panicking — which already forces supervisor restart) is a smell. Enforce at compile time:

- The typechecker already recognizes `migrate_state` by name + `(old : RawRecord) : State` signature (`hcr-phase5-design.md:170`). Add: its IO cap closure (reusing the same body-scan) must be empty. Any IO builtin or `extern` ⇒ compile error:

```
error: migrate_state must be IO-free
  MyApp.Counter.migrate_state calls `file_write` (needs IO.FileWrite)
  migrate_state runs during the hot-migration window, before user messages.
  Move side effects into a normal handler that runs after migration completes.
```

This is the cleanest first application of "capability-bounded migration sandbox." A stronger `NoAlloc`/`no_panic` bound (machine-checked at the IR level) is the natural follow-on once the `policy_dce` pass lands — noted, not in scope here.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/caps/cap_lattice.ml` (new) | `io_cap_hierarchy` + `subsumes` + `normalize` factored out of `typecheck.ml` **and** `lib/refinecheck/cap_infer.ml` (currently duplicated); covers all cap kinds (IO.*, no_alloc, pure, no_extern, deterministic, no_panic); single source of truth; emits a C table for the runtime |
| `lib/typecheck/typecheck.ml` | Depend on `Cap_lattice`; expose per-fn transitive cap closure (IO + non-IO kinds) accessor; `migrate_state` IO-free check |
| `lib/refinecheck/cap_infer.ml` | Replace local `io_cap_hierarchy` with `Cap_lattice.hierarchy` to remove the existing duplication |
| `bin/main.ml` | Aggregate `artifact_caps` + `cap_root`; emit `caps`/`ROOT` into `.hcr_manifest` in `--hot-reload --compile-so` |
| `forge/lib/cap_lattice` (dep) | forge depends on the shared lattice for deploy-side subsumption |
| `forge/lib/cmd_deploy_hot.ml` | Fetch prior cap manifest; monotonicity diff; `--grant-cap` handling; include `cap_root` in signed `ACTIVATE`; widening diagnostic; cap-change lines in `status` |
| `forge/bin/main.ml` | `--grant-cap <C>` flag (repeatable) on `forge deploy hot` |
| `runtime/march_reload.c` | Parse `cap_root` in `ACTIVATE2` (extend `do_activate()` helper at `:267`); sign over it; load `MARCH_DEPLOY_POLICY`; recompute + tamper-check + policy-check artifact caps; `err_cap_tamper`/`err_cap_policy` audit results |
| `runtime/march_cap_lattice.{h,c}` (new, generated) | C subsumption table emitted from `Cap_lattice` |
| `runtime/march_dispatch.{h,c}` | Optional: per-slot `cap_root` for `VERSIONS_DETAIL` reporting |

---

## Failure Modes

| Situation | Behavior |
|-----------|----------|
| New version widens authority, no `--grant-cap` | `forge deploy hot` aborts before `ACTIVATE`; prints widened caps + their source builtins |
| New version widens, `--grant-cap C` present | Allowed; `C` folded into signed `cap_root`; audit-logged as a granted widening |
| New version narrows authority | Allowed silently (logged) |
| Artifact caps exceed node policy | Server returns `ERR cap_policy <cap>`; no `dlopen`; audit `err_cap_policy` |
| Manifest `cap_root` ≠ signed `cap_root` | Server returns `ERR cap_tamper`; audit `err_cap_tamper` |
| Legacy artifact (no `caps`/`cap_root`) | Permissive admission (back-compat); deploy-side monotonicity skipped with a one-line warning |
| No node policy file | Permissive admission (current behavior) |
| `migrate_state` does IO | Compile error (Part C); never reaches deploy |

---

## End-to-End Example

```march
-- v1 (deployed): console + outbound HTTP only
mod MyApp.Server do
  needs IO.Console
  needs IO.NetConnect
  fn handle(req : Request) : Response do ... end
end
```

`v2` adds a debug log to the filesystem:

```march
mod MyApp.Server do
  needs IO.Console
  needs IO.NetConnect
  needs IO.FileWrite          -- NEW authority
  fn handle(req : Request) : Response do
    file_write("/var/log/debug.log", render(req))   -- needs IO.FileWrite
    ...
  end
end
```

`forge deploy hot` flow:
1. Build v2; manifest records `MyApp.Server.handle caps=IO.Console,IO.FileWrite,IO.NetConnect`; `cap_root` over the set.
2. `ABI_QUERY` + fetch prior manifest: `prior_caps = {IO.Console, IO.NetConnect}`.
3. Monotonicity diff: `IO.FileWrite` is **not** subsumed by any prior cap → widening → **abort** with the Part B diagnostic.
4. Operator decides this is intended: `forge deploy hot --grant-cap IO.FileWrite`. The grant is signed into `cap_root`, the deploy proceeds.
5. Server: verifies sig (covers `cap_root`); recomputes `cap_root'` from the CAS manifest, matches; checks `{IO.Console, IO.FileWrite, IO.NetConnect}` ⊆ node policy. If the node policy omits `IO.FileWrite` → `ERR cap_policy IO.FileWrite`, deploy rejected at the boundary even though it was correctly signed and granted. Otherwise `dlopen` + publish.
6. Audit log records the granted widening with signer + `cap_root`.

A narrowing deploy (v3 drops `IO.FileWrite`) sails through with no grant and no policy friction.

---

## Testing

- `forge/test/test_forge.ml`: `Cap_lattice.subsumes`/`normalize` (hierarchy edges, root, siblings); monotonicity diff (narrow / subsumed-add / sibling-widen / parent-widen / root-add) × (grant present / absent).
- `test/test_cas.ml`: `.hcr_manifest` caps + `cap_root` emit/parse round-trip; `cap_root` determinism vs cap order.
- Typecheck error tests: `migrate_state` doing `file_write`/`println`/`extern` ⇒ IO-free error; pure `migrate_state` ⇒ clean.
- `runtime/march_reload.c` admission tests: artifact within policy ⇒ activate; artifact exceeding policy ⇒ `err_cap_policy`; tampered `cap_root` ⇒ `err_cap_tamper`; no policy ⇒ permissive; legacy artifact ⇒ permissive + warning.
- End-to-end (Slow): v1 (`IO.Console`) → v2 adds `IO.FileWrite`; assert deploy aborts; re-run with `--grant-cap IO.FileWrite` against a node whose policy omits it ⇒ `ERR cap_policy`; against a permissive node ⇒ `49→343`-style success with an audit line recording the grant.

---

## Out of Scope / Follow-ons

- **IR-level `NoAlloc`/`no_panic` bound on `migrate_state`** — `cap no_alloc` (bc500f47) and Z3-backed `cap no_panic` (2627f597) have now landed, so the compile-time machinery exists. What remains is wiring the *recognition* of `migrate_state` as implicitly subject to these caps, and the `policy_dce` IR pass. Closer than when this plan was written but still deferred.
- **Refinement-verified migration totality** — Z3 (`lib/refine/`) discharging that `migrate_state` produces a valid new `State` for every prior `State` (invariants preserved, no partial field maps). This is the second, distinct project the "refinement-verified state migration" framing points at; it layers on top of the capability bound here.
- **Capability leases / epochs across deploys** — tie a granted widening to an epoch so it auto-revokes on the next narrowing deploy; reuse the `Cap(Pid)` epoch-revocation runtime.
- **Proof-cap propagation across nodes** — extend the manifest to carry proof-cap producer identity for cross-node admission.
