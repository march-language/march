# HCR Phase 5C — Capability-Safe Hot Deploys

**Date:** 2026-06-25
**Updated:** 2026-07-03 (revised against the codebase — see Revision note)
**Status:** Draft / proposed — none of Parts A/B/C have landed yet
**Depends on:** HCR Phases 1–10 complete (CAS `impl_hash` Merkle, versioned dispatch, native reload server, `forge deploy hot` CAS-native + ed25519 signing, actor state migration, cross-module ABI gating, coordinated upgrade gate, epoch-tagged dispatch via `__march_init`, cluster-aware rolling deploy); the Phase 1 capability system (permission IO caps, `needs`, transitive closure, proof caps). Also assumes `ACTIVATE3` landed (df4fec3f), which extended the signed payload to cover `<migrate> epoch:N callers:<csv>`.
**Spec parents:** `specs/plans/2026-06-24-hcr-phase5-design.md`, `specs/capability-system-design.md`, `docs/capabilities.md`

### Revision note (2026-07-03)

A code-verification review found the 2026-06-27 draft stale or wrong on five points; this
revision fixes them in place:

1. **Protocol:** the active protocol is now `ACTIVATE3` (df4fec3f), not `ACTIVATE2`. Part C
   defines a new `ACTIVATE4` verb rather than appending to `ACTIVATE3` — any change to the
   signed message breaks old servers' signature reconstruction, and the server parses the
   `callers:` CSV to end-of-line, so a field appended after it would be swallowed into the
   CSV. New verb = clean unknown-command error on old servers, matching the 1→2→3 house style.
2. **Part A is a refactor, not an accessor.** `check_module_needs` computes per-function
   usage sets transiently and discards them; nothing per-fn is stored or exported. The
   traversal machinery is reusable, but Part A must restructure it to accumulate and return
   per-fn sets.
3. **`migrate_state` recognition is not in the typechecker.** It is a name-suffix heuristic
   (`{actor_lower}_migrate_state`) in `bin/main.ml` (`find_migrate_fn`, used by
   `--check-migration`). Part C adds the same suffix recognition to typecheck, where the cap
   closure lives.
4. **Scope narrowed to IO authority caps.** The guarantee caps (`pure`, `no_extern`,
   `deterministic`, `no_alloc`, `no_panic`) have *inverted polarity* — dropping one widens
   behavior — and aggregate by intersection, not union. Running them through the authority
   widening check gives the wrong answer in both directions. Guarantee-cap variance moves to
   Out of Scope with the polarity rule written down.
5. **`cap_root` uses BLAKE3, matching `cas_hash`.** Correction to an earlier draft of this
   revision (which specified SHA-512/digestif): `bin/main.ml` already depends on `march_cas`,
   which vendors its own BLAKE3 (`lib/cas/blake3.ml`, C stubs) — the same hash already used
   for `cas_hash`/`impl_hash`/`sig_hash` throughout this manifest. Using a second hash
   algorithm in the same manifest file would be needless inconsistency; `Blake3.hash_string`
   needs no new dependency for Parts A/B. Part C's server-side recompute (out of scope here)
   can link the existing `lib/cas/blake3_stubs.c` into the runtime build rather than vendor
   SHA-512 from `tweetnacl.c` — a build-wiring choice for whoever picks up Part C, noted but
   not decided here.

### Landed since this plan was written (context delta)

The following related work landed after 2026-06-25 and affects this plan:

| Commit | What landed | Impact on Phase 5C |
|--------|------------|-------------------|
| c9e2e86c | **ACTIVATE2** — signed payload covers `epoch:N callers:<csv>` | Superseded by ACTIVATE3 below. |
| df4fec3f | **ACTIVATE3** — `migrate_required` folded into the signed payload | Part C's baseline. Phase 5C defines `ACTIVATE4` = ACTIVATE3 + `cap_root` in wire and signed message. |
| 1ad76ca2 | **`cap pure`, `cap no_extern`, `cap deterministic`** — new non-IO cap types | These are *guarantee* caps (per-module booleans, `typecheck.ml:484–498`) with polarity opposite to IO authority caps. **Excluded from Parts A/B** — see Out of Scope for the inverted variance rule. |
| bc500f47 | **`cap no_alloc`** — ban heap allocation in no-alloc modules | Same: guarantee cap, excluded from the authority gate. `migrate_state` could be bounded by `no_alloc` in the follow-on (see Out of Scope). |
| 2627f597 | **Z3 division-safety pass for `cap no_panic` modules** | `no_panic` is now live; IR-level bounds in migrate_state context (currently Out of Scope) are closer than when this plan was written. |
| 0566c52c | **`needs` capability inference hints** | Complements Part A; inference can auto-populate `needs` declarations from body analysis. |
| 8e3e4850 | **Phase 8: callers per slot + coordinated upgrade gate** | `.hcr_manifest` now has `callers:` field per `FN` line (see format below). `caps=` comes after `callers:` in the manifest (the manifest parser tolerates extra fields); on the *wire*, `cap_root:` comes **before** `callers:` (the server's callers parse consumes to end-of-line). |
| f86f9b66 | **Phase 9: epoch-tagged dispatch via `__march_init`** | Epoch is baked at server; ACTIVATE3 carries `epoch:N` as a mandatory signed field. Part C extends this. |
| a7588911 | **Phase 10: cluster-aware rolling deploy** | `forge deploy hot` orchestrates multi-node; the monotonicity gate (Part B) runs once on the deployer side before any per-node activation. **Correction (2026-07-03):** the prior-caps baseline is a **local file**, not a remote fetch — mirrors the existing `prev_schemas_path` pattern (`<project>/.march/<name>_hot.so.schemas.json.prev`, computed once in `deploy_env`/`deploy` and passed unchanged to every server via `deploy_one`). There is no epoch-master CAS fetch for schemas or manifests anywhere in the current code; an earlier draft of this revision incorrectly assumed one by analogy with the shared-epoch fetch. Node admission (Part C) runs independently on each node. |

**Key structural change:** `io_cap_hierarchy` is now **duplicated** — it exists in both `lib/typecheck/typecheck.ml:933` and `lib/refinecheck/cap_infer.ml:26` (identical modulo whitespace, with a "Same hierarchy as..." comment). The `lib/caps/cap_lattice.ml` factoring (Part A) is therefore more urgent, not less: it needs to absorb the refinecheck copy too and serve as the single source for all three consumers (typecheck, forge deploy, C runtime table).

---

## Goal

Make hot deploys *authorized*, not merely *authenticated*. Phase 4 made a hot deploy **authentic** — `forge deploy hot` signs each activation with ed25519 and the server verifies before `dlopen` (`crypto_sign_open` in `runtime/march_reload.c`). But it does not make a deploy **authorized**: static permission capabilities are erased to `null` at compile time (`lib/typecheck/typecheck.ml` Phase 1), so a *signed* patch can call `file_delete`, `tcp_connect`, or spawn a process even if the running version never touched the filesystem or network. The trusted key answers "is this code from us?" — nothing answers "is this code allowed to do what it does?"

The thing Phase 5 ships **is mobile code**: a state-migration function and a new handler closure, built on one machine, content-addressed, shipped over the wire, `dlopen`'d on the target node, and run against live actor state. Phase 5C governs that mobile code with the capability discipline March already computes at compile time and currently throws away after checking.

Three slices, continuing the Phase 5 Part-letter convention:

- **Part A — Capability manifest** (compile-time emission): compute each boundary function's transitive IO capability closure (the data `check_module_needs` already traverses) and emit it into the deploy artifact's manifest, with a `cap_root` digest.
- **Part B — Monotonicity gate** (deploy-time invariant): a hot deploy may *narrow* the live system's authority freely, but *widening* it is rejected unless explicitly authorized by a signed cap-grant. This is the capability dual of Phase 5 Part B's schema variance-duality table.
- **Part C — Node admission + `migrate_state` bound** (runtime trust boundary): the receiving node refuses to activate an artifact whose declared authority exceeds a node-local policy, and state-migration functions are compile-time bounded to IO-free data transformation.

**Scope: IO authority caps only** (`IO.*`, including `IO.Foreign`/`IO.Foreign.Blocking` from `extern`). The guarantee caps (`pure`, `no_alloc`, `no_extern`, `deterministic`, `no_panic`) are per-module booleans with inverted variance polarity and are deliberately out of scope for the v1 gate — see Out of Scope.

### Why this is research-adjacent, not just engineering

- **Part B is a *temporal* capability discipline across code versions** — "your running system's authority can only shrink across hot deploys without a fresh grant." Object-capability monotonicity over a live, hot-reloaded process is not a standard result; March can state and check it because authority is a static, content-addressable fact and code is shipped by content hash.
- **Part C is the static/dynamic bridge.** Permission caps are normally erased at compile time and have no runtime existence; `Cap(Pid)` is a disjoint runtime notion. Activation is the one point where foreign code crosses into the process, so it is exactly where the erased static discipline gets re-materialized as a runtime checkpoint — unifying the two cap worlds at the boundary where it matters.

Parts A and C are mostly engineering on machinery Phase 5 already shipped (CAS, manifest sidecars, `ABI_QUERY` prior-fetch, signed activation, the audit log). Part B is the novel piece.

---

## Decisions

| Question | Answer |
|---|---|
| Cap scope (v1) | IO authority caps only (`IO.*` incl. `IO.Foreign`). Guarantee caps (`pure`, `no_alloc`, …) have inverted polarity and are deferred — see Out of Scope. |
| Cap granularity | Per-boundary-function transitive **inferred body usage** (not the module's declared `needs`), aggregated to a per-artifact cap set, plus a `cap_root` digest over the sorted set |
| Where caps come from | The traversal `check_module_needs` already performs (`typecheck.ml:5160`) — declared `needs`, `builtin_cap_table` + `calls_in_expr` body scan, `extern` ⇒ `IO.Foreign`, import propagation. Today the per-fn sets are computed transiently and discarded; Part A **restructures the checks to accumulate a per-fn map and exports it via the `.mli`**. Reuses the machinery; no new analysis, but it is a refactor, not a one-line accessor. |
| Cap lattice ownership | Factor `io_cap_hierarchy` + `cap_subsumes` (`typecheck.ml:933`, `:1071`) into a shared `lib/caps/cap_lattice.ml` that typecheck, refinecheck, and forge all depend on — two identical copies exist today (`typecheck.ml:933` and `refinecheck/cap_infer.ml:26`); this removes the duplication and adds the C-table emitter |
| Manifest carrier | Extend the existing `.hcr_manifest` sidecar (already per-fn `impl_hash`/`sig_hash`/`callers:`) with a `caps=` field per fn + a top-level `cap_root`; content covered by `cas_hash` |
| `cap_root` hash | **BLAKE3, hex** — same algorithm as `cas_hash`/`impl_hash`/`sig_hash`. OCaml side: `March_cas.Blake3.hash_string` (`lib/cas/blake3.ml`), already a transitive dependency of `bin/main.ml` via `march_cas` — no new dependency. Part C's server-side recompute (out of scope here) can link the existing `lib/cas/blake3_stubs.c` C source into the runtime build. |
| Protocol | New verb **`ACTIVATE4`** = ACTIVATE3 + `cap_root:<hex>` (signed) + `caps:<csv>` (unsigned, integrity-checked by recomputing `cap_root` over it) in the wire message, both before `callers:`. A new verb, not an appended field: (a) adding anything to the signed message makes old servers reconstruct a different message and fail with a misleading `bad_signature`; (b) the server parses `callers:` to end-of-line, so a trailing field would be swallowed into the CSV. Old servers answer `ACTIVATE4` with a clean unknown-command error. The cap *set* rides the wire (not the CAS) because the manifest is a client-side per-function sidecar never stored in the CAS; the union it digests is tiny (~11 caps measured). |
| Monotonicity rule | Deploy may *narrow* freely; *widening* (a new cap not subsumed by any prior-held cap) aborts before activation unless an explicit `--grant-cap <C>` authorizes each widened cap |
| Grant authority | A widening grant rides the deployer's ed25519 signature: `cap_root` is added to the signed activation payload, so the authority claim is tamper-evident and audit-logged |
| Multi-node baseline | The prior-caps baseline is a **local file** (`<project>/.march/<name>_hot.so.hcr_manifest.prev`, mirroring the existing `prev_schemas_path` pattern) — not a network fetch. Computed once per `deploy`/`deploy_env` call and passed unchanged to every server via `deploy_one`, so the gate runs exactly once per deploy regardless of fleet size. Updated to the new manifest after a successful deploy (mirroring `save_schemas_baseline`). |
| Node policy | Optional `MARCH_DEPLOY_POLICY` file (newline-delimited cap paths) caps the node's maximum admissible authority; absent ⇒ permissive (preserves current behavior) |
| Tamper-evidence | Server recomputes `cap_root` from the CAS-received `.hcr_manifest` and checks it equals the signed `cap_root` before the policy check. (Integrity, not truthfulness — see Threat model.) |
| `migrate_state` bound | Compile-time: a recognized migration function (the `{actor_lower}_migrate_state` suffix convention, today implemented as `find_migrate_fn` in `bin/main.ml:1005`) must have an empty IO cap closure — it runs in the migration window ahead of user messages. IO use ⇒ compile error. Part C adds the same suffix recognition to **typecheck**, where the cap closure lives; `bin/main.ml` keeps its copy for the `--check-migration` SMT mode. (`no_alloc`/`no_panic` bound deferred to the `policy_dce` follow-on.) |
| Backward compatibility | All gates are opt-in/additive: no manifest caps ⇒ legacy artifact ⇒ permissive admission, unchanged behavior. New forge against an old server gets a clean unknown-command error and aborts with guidance (no silent fallback). Strictness is enabled by shipping a policy file. |

---

## Part A: Capability Manifest

### Per-function capability closure

`check_module_needs` (`lib/typecheck/typecheck.ml:5160`) already traverses, for every function, the IO capabilities it requires: declared `needs` (Check 1), builtin calls in the body via `builtin_cap_table` + `calls_in_expr` (Check 1b, `typecheck.ml:956`/`:5125`), `extern` ⇒ `IO.Foreign` (Check 1c), and imported-module propagation (Check 4).

**What exists today vs what Part A needs.** The per-function usage sets are computed *transiently* inside the checks and discarded once validated; the only persisted structure (`module_caps`, `typecheck.ml:451`) holds a module's *declared* needs and is not exported in any `.mli`. Part A therefore:

1. Restructures Checks 1b/1c to **accumulate** a `fn_name → cap set` map as they validate (same traversal, now recording).
2. Normalizes each set with `Cap_lattice.normalize` (drop any cap subsumed by another in the same set).
3. Exports an accessor in `typecheck.mli` returning, per top-level function, the canonical sorted list of leaf capability paths.

The manifest records **inferred body usage** per function, not the module's declared `needs` — declared needs are module-granular and would coarsen every function to the module's full authority. (The deploy-time gate operates on the artifact aggregate either way; per-fn caps in the manifest are what make the widening diagnostic actionable — "which function grew authority, via which builtin".)

Guarantee caps (`pure_mod`, `no_alloc`, `no_extern_mod`, `deterministic_mod`, `no_panic_mod` — per-module booleans at `typecheck.ml:484–498`) are **not** included: they are module-level facts with inverted polarity and don't fit a per-fn authority set. See Out of Scope.

### Artifact aggregation + `cap_root`

In `--hot-reload --compile-so` mode, `bin/main.ml` (which already writes the `.hcr_manifest` and `.schemas.json` sidecars) computes:

```
artifact_caps = sorted( ⋃ over boundary fns f of caps(f) )      -- normalized, no subsumed dups
cap_root      = blake3_hex( "\n".join(artifact_caps) )          -- deterministic content digest, same algorithm as cas_hash
```

Union is the correct aggregation for *authority* (the artifact can do anything any of its functions can do). This is exactly why guarantee caps don't belong in the same set — they hold by intersection.

### Manifest format extension

`.hcr_manifest` gains a per-fn `caps=` field and a top-level `ROOT` line. **Corrected to match the actual writer** (there is no literal `FN`/`CAS` prefix token on each line — that was illustrative prose in an earlier draft; the real format is bare space-delimited fields, one function per line, plus comment/`ROOT` lines). The format, as implemented by Task 3 (`bin/main.ml`, writer around `:2158`, after Phase 8 added `callers:`), is:

```
# march-hcr-manifest v1
# cas_hash <64-char blake3 hex>
ROOT cap_root=<64-char blake3 hex>
<name> <impl_hash> <sig_hash> [callers:<sorted-csv>] caps=<sorted-csv>
```

Example:

```
# march-hcr-manifest v1
# cas_hash 9f2a...
ROOT cap_root=7c1e...
MyApp.Server.handle   <impl_hash> <sig_hash> callers:MyApp.Router.route caps=IO.Console,IO.NetConnect
MyApp.Server.server_migrate_state  <impl_hash> <sig_hash> caps=
```

(Note the migration function's real name follows the implemented `{actor_lower}_migrate_state` suffix convention, not a bare `migrate_state`.)

`forge/lib/cmd_deploy_hot.ml` already parses `callers:` from field index 3 (`fn_callers`, `cmd_deploy_hot.ml:51`) and its match pattern ends in a wildcard, so **old parsers tolerate the new field** (the trailing `caps=` token is silently absorbed into the discarded `_` tail). New parsing must not assume `caps=` sits at a fixed field index, though: `callers:` is only present when the function has callers, so `caps=` is field index 3 for a caller-less function and field index 4 otherwise — scan the tail for a token with a `caps=` prefix rather than indexing positionally.

**A parsing landmine the new code must handle:** the current `parse_manifest`'s line dispatch only special-cases lines starting with `#` (comments) and falls through everything else to the FN-line splitter. The new `ROOT cap_root=<hex>` line does **not** start with `#`, so `String.split_on_char ' ' "ROOT cap_root=<hex>"` yields exactly `["ROOT"; "cap_root=<hex>"]` — a 2-element list that matches the existing `[name; impl_h]` fallback pattern, silently fabricating a phantom function named `"ROOT"` with `impl_hash = "cap_root=<hex>"`. The line-dispatch must recognize and consume `ROOT cap_root=` lines *before* falling through to FN-line parsing.

Caps go in `.hcr_manifest` (per-function) rather than `.schemas.json` (per-actor-state). The manifest is already keyed in the CAS next to the artifact, so `forge deploy hot` and the server both reach it by the path derivation Phase 5 established.

---

## Part B: Monotonicity Gate (deploy time)

In `forge/lib/cmd_deploy_hot.ml`, after the existing `ABI_QUERY` prior-state fetch and `sig_hash` ABI gate (the prior-manifest read already uses the `.hcr_manifest` path derivation established in Phase 5):

1. **Fetch prior caps.** Read the prior deployed artifact's `.hcr_manifest` from a **local baseline file** (`<project>/.march/<name>_hot.so.hcr_manifest.prev`), mirroring the existing `prev_schemas_path`/`save_schemas_baseline` pattern exactly — computed once per `deploy`/`deploy_env` call, so the gate runs exactly once per deploy even on a multi-node fleet, regardless of server count. Compute `prior_caps = ⋃ prior fn caps`. Absent baseline file (first deploy) ⇒ no prior caps, no gate (permissive), matching the schemas-baseline precedent.
2. **Compute new caps** from the build's own manifest.
3. **Diff.** A new cap `C` is *covered* iff `∃ P ∈ prior_caps. cap_subsumes P C` (shared `Cap_lattice.subsumes`). *Widening* = the set of new caps not covered by any prior cap. *Narrowing* = prior caps no longer present (always fine, logged).
4. **Gate.** If `widening` is nonempty and not every widened cap has a matching `--grant-cap`, abort **before** any activation with an actionable diagnostic.
5. **Authorize granted widenings.** Each `--grant-cap C` removes `C` from the blocking set and is folded into the signed payload (via `cap_root`) and the audit record.

`--grant-cap` is a repeatable flag: forge's CLI is Cmdliner (`forge/bin/main.ml`), so this is `Arg.(value & opt_all string [] & info ["grant-cap"] ...)` — note the existing forge flags are all single-value; `opt_all` is the first repeatable one, which is why it's called out here.

### Capability variance-duality (the dual of Phase 5 Part B's table)

| Capability change in the new version | Allowed in a hot deploy? |
|---|---|
| Drop a capability (narrow authority) | ✅ always |
| Add a cap subsumed by a held one (held `IO.Network` → add `IO.NetConnect`) | ✅ — within existing authority |
| Add a sibling / unrelated leaf the running version never held | ❌ unless `--grant-cap` (+ signed) |
| Widen to a parent (`IO.FileRead` held → now `IO.FileSystem`) | ❌ unless `--grant-cap` |
| Add the `IO` root | ❌ unless `--grant-cap IO` (maximal widening; strongly discouraged) |

This table is for *authority* caps only. Guarantee caps (`pure`, `no_alloc`, …) obey the **mirror-image** rule — *dropping* one is the widening event — and are deferred; see Out of Scope.

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

### Threat model — what admission does and does not prove

The capability manifest is **self-reported by the compiler on the deployer's machine**. The
server's checks prove *integrity* (the manifest in the CAS is the one the signer signed —
`cap_root` matches) and *policy* (the declared authority fits the node), **not truthfulness**
(that the `.so`'s machine code actually stays within the declared caps — the server cannot
recompute caps from a shared object). Concretely:

- **Defends against:** accidental authority creep by an honest toolchain (the common case);
  a compromised deploy *pipeline* that still builds with the real March compiler; operator
  error shipping the wrong build to a restricted node; post-signing tampering with the
  manifest in transit or in the CAS.
- **Does not defend against:** an attacker holding the signing key who hand-crafts a
  `.so` + lying manifest. Capability admission is authorization *on top of* authentication,
  not a sandbox. (OS-level sandboxing of the reload server is the complementary control.)

The earlier draft's phrase "regardless of who signed it" was too strong; the policy binds
what a node will *admit as declared*, and the declaration is only as honest as the toolchain
that produced it.

**A deeper caveat than adversarial honesty: the manifest's completeness is bounded by the
completeness of Part A's *AST-level* cap inference, and nothing structurally guards it.** The
final whole-branch review's C1 finding is the existence proof — actor handlers were hashed as
boundary functions but their caps were silently dropped, with *no adversary involved*, just a
desync between "functions the CAS hashes" and "constructs `check_module_needs` walks". Empirically
(measured 2026-07-03 on a stdlib-using actor app): **7202 of 7340 boundary functions carry an
empty `caps=` field**, because the CAS hashes post-lowering/mono/defun TIR (monomorphized
specializations like `List.filter_map$List_Result…`, defunctionalized closures like `$jp…$apply`,
actor glue like `_dispatch`/`_spawn`), while cap inference runs on the surface AST and sees only
user-level `DFn`/`DActor`-handler/`DExtern` constructs. The artifact-wide `cap_root` *union* is
still complete in practice because a synthesized function's IO is attributed to its enclosing
user construct at the AST level — but this means:

- A naive "every boundary function must have a non-empty cap entry" check is **wrong** — it would
  fire on 7000+ legitimately-empty synthesized functions. (This corrects an earlier hardening
  idea.) The tractable invariant is narrower: *every user-level AST construct that becomes a
  hashed boundary function (`DFn`, each actor handler, `DExtern`) has a recorded cap closure* —
  which is what the C1 fix restored, and which is worth locking in as a regression guard so the
  next new construct or codegen path that synthesizes a boundary function trips a loud failure at
  emit time instead of silently under-reporting authority. That guard is a real (if small) design
  item, not the cheap assert the earlier draft imagined, because it requires enumerating "AST
  constructs that become boundary functions" independently of the recording pass.
- The gate's soundness ceiling is: **it is a same-toolchain integrity check whose completeness
  equals `check_module_needs`'s coverage of authority-bearing AST constructs.** Every new IO
  builtin, `extern` form, or lowering path that manufactures a boundary function is a potential
  silent under-report until that guard exists.

**Good news on granularity (measured, same run):** the cap union of a full stdlib-using app is
*fine-grained* (`IO.NetConnect.TLS`, `IO.NetListen`, `IO.Random`, `IO.Clock`, `IO.FileWrite`, …,
11 distinct caps) and does **not** collapse to a blanket `IO.Foreign` — bare `extern` declarations
have no lowered body, so their `IO.Foreign` never enters the union, while the FFI-using stdlib
modules declare specific `needs`. So a node policy is genuinely discriminating; an earlier concern
that FFI would flood every artifact with `IO.Foreign` and nullify the policy check does not bear
out.

### Node deploy policy

The server loads an optional policy at startup (`runtime/march_reload.c`): `MARCH_DEPLOY_POLICY` points to a newline-delimited list of permitted cap paths (subsumption-expanded — listing `IO.Network` permits `IO.NetConnect`, etc.). Absent ⇒ permissive (unchanged behavior). A policy of e.g.

```
IO.Console
IO.FileRead
IO.NetConnect
```

means: this node will not admit code that *declares* file-write, process-spawn, or foreign-FFI authority, regardless of signature (see Threat model above for what "declares" means).

### `ACTIVATE4` + admission

**Protocol history:** `ACTIVATE` (v1, signs `<name> <impl_hash> <cas_hash>`), `ACTIVATE2` (c9e2e86c, adds `epoch:N callers:<csv>` to the signed message), `ACTIVATE3` (df4fec3f, adds `<migrate>` to the signed message) — all three remain supported for legacy clients. The current active protocol is `ACTIVATE3` (`march_reload.c:787`):

```
Wire:   ACTIVATE3 <name> <impl_hash> <cas_hash> <sig_b64> <migrate> epoch:<N> callers:<sorted-csv>
Signed: "ACTIVATE3 <name> <impl_hash> <cas_hash> <migrate> epoch:<N> callers:<sorted-csv>"
```

Phase 5C defines **`ACTIVATE4`**, which inserts `cap_root:<hex>` and `caps:<sorted-csv>` **before** `callers:`:

```
Wire:   ACTIVATE4 <name> <impl_hash> <cas_hash> <sig_b64> <migrate> epoch:<N> cap_root:<hex> caps:<sorted-csv> callers:<sorted-csv>
Signed: "ACTIVATE4 <name> <impl_hash> <cas_hash> <migrate> epoch:<N> cap_root:<hex> callers:<sorted-csv>"
```

**Why the cap set rides the wire (design correction, 2026-07-03).** An earlier draft had the
server *read the `.hcr_manifest` from the CAS* to recover the cap set. That is not possible as
written: the CAS stores the `.so` keyed by `cas_hash`; the `.hcr_manifest` is a **client-side
sidecar** that is never put in the CAS, and it is the full **per-function** manifest (7000+
lines for a stdlib-using app — see below), not the artifact cap set. The clean fix falls out
of how `cap_root` is actually computed: Part A's `cap_root = blake3(sorted artifact_caps)` is a
digest of the **artifact-wide cap union**, which is *tiny* — an empirically-measured 11 distinct
caps for a full stdlib-using app. So `ACTIVATE4` carries that union inline as `caps:<sorted-csv>`
(a handful of entries, not the whole manifest). The set is **not** in the signed message — only
`cap_root` is — because the server *recomputes* `cap_root` over the received `caps:` set and
checks it against the signed `cap_root`; tampering with the wire cap set is therefore detected
by the tamper check (recomputed root ≠ signed root). This removes the entire "server reads +
parses a manifest from the CAS" surface the earlier draft proposed — **no CAS manifest read, no
manifest line-parser in the C runtime** (and hence no attacker-influenced-input parser on the
receiving side, which was a real attack surface). The server still needs BLAKE3 (to recompute
`cap_root`) and the generated lattice table (to `normalize` the received set identically to the
compiler before hashing, and to subsumption-check the policy).

Two wire-format constraints force this shape (both verified against `march_reload.c`):

- **New verb, not a new field on ACTIVATE3.** The server reconstructs the canonical signed
  message from parsed values (`march_reload.c:759` pattern); any field added to the signed
  payload makes an old server reconstruct a *different* message and fail with a misleading
  `ERR bad_signature`. An unknown `ACTIVATE4` verb instead yields a clean unknown-command
  error, which forge turns into an actionable diagnostic. This matches how 2 and 3 were
  introduced.
- **`cap_root:` and `caps:` before `callers:`.** The server's callers parse consumes from
  `callers:` to end-of-line (`march_reload.c:716–720`) — the CSV is definitionally "the rest
  of the line". Any field placed after it would be silently absorbed into the callers set and
  corrupt the canonical form. Both new fields go before `callers:`; `callers:` stays last.
  (`caps:` is itself a CSV; parse it by the same bounded-token scan `callers:` would use if it
  weren't last, i.e. read to the next ` <key>:` boundary, not to end-of-line.)

**Compatibility matrix (explicit, no silent fallback):**

| Client | Server | Behavior |
|---|---|---|
| new forge, caps in manifest | new server | `ACTIVATE4`, full admission |
| new forge, legacy artifact (no caps) | new server | `ACTIVATE3`; permissive admission + one-line warning |
| new forge, caps in manifest | old server | server: unknown command; forge aborts with "server predates capability admission (Phase 5C); upgrade the server or re-run with `--no-cap-gate`" — the downgrade is an explicit operator choice, never automatic |
| old forge | new server | `ACTIVATE3` (or older); legacy path, permissive admission |

Server flow on `ACTIVATE4`, after sig-verify + CAS-load (existing) and before `dlopen`:

1. Take the `caps:<csv>` set from the wire message (no CAS read — see the design correction above); `normalize` it via the generated lattice table and recompute `cap_root'` over the sorted result (BLAKE3, via `lib/cas/blake3_stubs.c` linked into the runtime build). **New C code**, but far smaller than the earlier draft: a CSV split, a `normalize`/sort against the lattice table, and one BLAKE3 call — no manifest path derivation, no `FN`/`ROOT` line parser.
2. **Tamper check:** `cap_root' == cap_root` (the signed value). Mismatch ⇒ `ERR cap_tamper`, audit `err_cap_tamper` (naming follows the existing `err_abi`/`err_cas_miss`/`err_sig` convention in `write_audit_log`). This is what makes the unsigned wire `caps:` set trustworthy — a forged set produces a different root.
3. **Policy check:** every cap in the received set is subsumed by some policy entry. Violation ⇒ `ERR cap_policy <cap>`, audit `err_cap_policy`.
4. Proceed to `dlopen` + `march_dispatch_publish` as today (extend the shared `do_activate()` helper, `march_reload.c:377`).

This is the single runtime checkpoint that re-materializes the erased static cap discipline at the trust boundary. The subsumption check in C works off a **generated table** emitted from `Cap_lattice` so it cannot drift from the OCaml hierarchy. Note there is currently **no precedent** in this repo for OCaml-generated C sources — this needs a dune rule that runs the emitter and a CI freshness check (regenerate + diff) as the anti-drift mechanism. The generated file lives in `runtime/`, so the existing CAS cache key (which digests `runtime/*.c` and `*.h`) automatically invalidates cached binaries when the lattice changes.

### `migrate_state` capability bound

State-migration functions run as the actor's next turn, ahead of any pending user messages (Phase 5 Part A, migrate-before-run ordering). A migration is a pure old→new state transformation; doing IO inside the migration window (or panicking — which already forces supervisor restart) is a smell. Enforce at compile time.

**Where recognition actually lives today** (correcting the earlier draft): the typechecker does *not* recognize migration functions. Recognition is a name-suffix heuristic in `bin/main.ml:1005` (`find_migrate_fn`): a `DFn` whose name ends in `_migrate_state` and whose prefix equals `lowercase(actor_name)`, used by the `--check-migration` SMT mode. The parent design's "function named exactly `migrate_state` with return-type disambiguation" (`hcr-phase5-design.md:170`) is what TIR/llvm_emit implemented as the `{actor_lower}_migrate_state` convention.

**Change:** teach **typecheck** the same suffix convention and require the recognized function's IO caps to be empty. Any IO builtin or `extern` ⇒ compile error.

**Do not use `fn_capability_closures` for this check (design correction, 2026-07-03).** Part A's `record_fn_caps` records `module_wide_caps @ own_caps` — it *merges the module's declared `needs` and import-propagated caps into every function's closure*, deliberately, so the artifact-wide `cap_root` union is complete. That makes the exposed closure **wrong for the "is this one function IO-free" question**: a `migrate_state` living in an actor module that declares `needs IO.Console` for its *handlers* — the common case, since any actor doing IO in a handler declares it at module level — would carry `IO.Console` in its merged closure and **falsely fail** the IO-free check even though the migration body touches nothing. Part A therefore needs a **second projection** exposing each function's *own* inferred caps (sig + body scan, pre-module-merge); the migrate_state check uses that. Recording the own-caps map is a small addition alongside the existing merged one (the `own_caps` value is already computed at each `record_fn_caps` call site — it just needs storing in a parallel table and an accessor), and should land in the same task as the migrate_state check that consumes it, not speculatively ahead of it.

`bin/main.ml`'s `find_migrate_fn` stays as-is for the SMT mode; the shared predicate belongs in **`lib/tir/tir_names.ml`** — Wave 3's designated single home for cross-pass name contracts (W3.1). Note the `_migrate_state` suffix is currently name-sniffed in four places (`dce.ml`, `llvm_emit.ml`, `mono.ml`, `bin/main.ml`) and not yet in `Tir_names`; 5C should add the predicate there and convert its own uses to it. **Wave 3 chunk 2 is now merged** (the `llvm_emit`/`lower` restructure landed on `main`), so the four-site conversion no longer needs coordination — it's a straightforward sweep against the settled module layout.

```
error: migrate_state must be IO-free
  MyApp.Counter.counter_migrate_state calls `file_write` (needs IO.FileWrite)
  migrate_state runs during the hot-migration window, before user messages.
  Move side effects into a normal handler that runs after migration completes.
```

This is the cleanest first application of "capability-bounded migration sandbox." A stronger `no_alloc`/`no_panic` bound (machine-checked at the IR level) is the natural follow-on once the `policy_dce` pass lands — noted, not in scope here.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/caps/cap_lattice.ml` (new) | `io_cap_hierarchy` + `subsumes` + `normalize` factored out of `typecheck.ml:933` **and** `lib/refinecheck/cap_infer.ml:26` (currently duplicated, identical modulo whitespace); IO authority caps only in v1; single source of truth; emits the C table for the runtime |
| `lib/tir/tir_names.ml` | `is_migrate_fn` suffix predicate (the `_migrate_state` name contract) — joins the existing cross-pass name contracts; typecheck + `bin/main.ml` use it; converting the four existing sniff sites (`dce`/`llvm_emit`/`mono`/`bin/main`) is coordinated with Wave 3 chunk 2 |
| `lib/typecheck/typecheck.ml` + `.mli` | Depend on `Cap_lattice`; **restructure `check_module_needs` Checks 1b/1c to accumulate a per-fn cap map** (today computed transiently and discarded) and export an accessor; `_migrate_state` suffix recognition + IO-free check |
| `lib/refinecheck/cap_infer.ml` | Replace local `io_cap_hierarchy` with `Cap_lattice.hierarchy` to remove the existing duplication |
| `bin/main.ml` | Aggregate `artifact_caps` + `cap_root` (BLAKE3 via `March_cas.Blake3.hash_string`, no new dependency); emit `caps=`/`ROOT` into `.hcr_manifest` in `--hot-reload --compile-so` (writer at `:2158`) |
| `forge/lib/dune` | Add the shared caps lib (forge already depends on `march_ast`/`march_parser`/etc., so this is routine) |
| `forge/lib/cmd_deploy_hot.ml` | Parse `caps=`/`ROOT cap_root=` lines; maintain a local `.hcr_manifest.prev` baseline (mirroring `prev_schemas_path`/`save_schemas_baseline`); monotonicity diff; `--grant-cap` handling; emit `ACTIVATE4` with `cap_root` in the signed message; explicit old-server diagnostic + `--no-cap-gate`; widening diagnostic; cap-change lines in `status` |
| `forge/bin/main.ml` | `--grant-cap` via Cmdliner `Arg.opt_all` (first repeatable flag in forge); `--no-cap-gate` |
| `lib/cas/dune` / `runtime/dune` (Part C, out of scope here) | Link `lib/cas/blake3_stubs.c` into the runtime build so the server can recompute `cap_root` with the same BLAKE3 the compiler used |
| `runtime/march_reload.c` | New `ACTIVATE4` branch (extend `do_activate()` at `:377`); parse the inline `caps:<csv>` set (no CAS read, no manifest parser — see the ACTIVATE4 design correction); `normalize` + BLAKE3 recompute of `cap_root` + tamper check; load `MARCH_DEPLOY_POLICY`; subsumption policy check; `err_cap_tamper`/`err_cap_policy` audit results |
| `runtime/march_cap_lattice.{h,c}` (new, generated) | C subsumption table emitted from `Cap_lattice`; needs a dune emit rule + CI regenerate-and-diff freshness check (no generated-C precedent exists in the repo); covered by the existing `runtime/*` CAS cache key |
| `runtime/march_dispatch.{h,c}` | Optional: per-slot `cap_root` field on `MarchDispatchSlot` (alongside the existing `signer_hex`/`callers_str`) for `VERSIONS_DETAIL` reporting |

---

## Failure Modes

| Situation | Behavior |
|-----------|----------|
| New version widens authority, no `--grant-cap` | `forge deploy hot` aborts before any activation; prints widened caps + their source builtins |
| New version widens, `--grant-cap C` present | Allowed; `C` folded into signed `cap_root`; audit-logged as a granted widening |
| New version narrows authority | Allowed silently (logged) |
| Artifact caps exceed node policy | Server returns `ERR cap_policy <cap>`; no `dlopen`; audit `err_cap_policy` |
| Manifest `cap_root` ≠ signed `cap_root` | Server returns `ERR cap_tamper`; audit `err_cap_tamper` |
| Legacy artifact (no `caps`/`cap_root`) | `ACTIVATE3` path; permissive admission (back-compat); deploy-side monotonicity skipped with a one-line warning |
| New forge (caps present) → old server | Unknown-command error; forge aborts with upgrade guidance; `--no-cap-gate` is the explicit escape hatch (never automatic) |
| No node policy file | Permissive admission (current behavior) |
| Signed-but-lying manifest (attacker holds key) | **Not detected** — admission checks integrity + policy of the *declared* caps, not the `.so`'s actual behavior; see Threat model |
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
2. `ABI_QUERY` + read the local `.hcr_manifest.prev` baseline: `prior_caps = {IO.Console, IO.NetConnect}`.
3. Monotonicity diff: `IO.FileWrite` is **not** subsumed by any prior cap → widening → **abort** with the Part B diagnostic.
4. Operator decides this is intended: `forge deploy hot --grant-cap IO.FileWrite`. The grant is signed into `cap_root`, the deploy proceeds via `ACTIVATE4`.
5. Server: verifies sig (covers `cap_root`); recomputes `cap_root'` from the CAS manifest, matches; checks `{IO.Console, IO.FileWrite, IO.NetConnect}` ⊆ node policy. If the node policy omits `IO.FileWrite` → `ERR cap_policy IO.FileWrite`, deploy rejected at the boundary even though it was correctly signed and granted. Otherwise `dlopen` + publish.
6. Audit log records the granted widening with signer + `cap_root`.

A narrowing deploy (v3 drops `IO.FileWrite`) sails through with no grant and no policy friction.

---

## Testing

- `forge/test/test_forge.ml`: `Cap_lattice.subsumes`/`normalize` (hierarchy edges, root, siblings); monotonicity diff (narrow / subsumed-add / sibling-widen / parent-widen / root-add) × (grant present / absent); repeatable `--grant-cap` parsing.
- `test/test_cas.ml`: `.hcr_manifest` `caps=` + `ROOT` emit/parse round-trip; old parser tolerates `caps=` field (wildcard match); `cap_root` determinism vs cap order (same BLAKE3 primitive already used for `cas_hash`, so no cross-implementation agreement test is needed for Parts A/B — that only becomes relevant if Part C's C-side recompute uses a different binding of the same `blake3_stubs.c`).
- Typecheck tests: per-fn cap map accessor returns inferred body usage (builtin, extern, import-propagated); `{actor_lower}_migrate_state` recognition; migration fn doing `file_write`/`println`/`extern` ⇒ IO-free error; pure migration fn ⇒ clean.
- `runtime/march_reload.c` admission tests: `ACTIVATE4` within policy ⇒ activate; exceeding policy ⇒ `err_cap_policy`; tampered `cap_root` ⇒ `err_cap_tamper`; no policy ⇒ permissive; `ACTIVATE3` legacy artifact ⇒ permissive + warning; `ACTIVATE4` against a pre-5C server build ⇒ clean unknown-command error (compat-matrix row).
- Generated-table freshness: CI check that regenerating `march_cap_lattice.{h,c}` from `Cap_lattice` produces no diff.
- End-to-end (Slow): v1 (`IO.Console`) → v2 adds `IO.FileWrite`; assert deploy aborts; re-run with `--grant-cap IO.FileWrite` against a node whose policy omits it ⇒ `ERR cap_policy`; against a permissive node ⇒ `49→343`-style success with an audit line recording the grant.

---

## Out of Scope / Follow-ons

- **Guarantee-cap variance (`pure`, `no_alloc`, `no_extern`, `deterministic`, `no_panic`).**
  These have *inverted polarity* relative to authority caps: for authority, **adding** a cap
  widens; for guarantees, **dropping** one widens (a v2 that removes `cap no_alloc` gains
  freedom the running version's operators may depend on). They also aggregate by
  **intersection** across modules (a guarantee holds only if every module holds it), not
  union, and are per-module booleans (`typecheck.ml:484–498`), not per-fn closures. The
  follow-on rule is the mirror image of Part B: *guarantees may be added freely; dropping a
  guarantee held by the running version requires an explicit signed grant
  (`--grant-drop no_alloc`)*. Deferred so the v1 gate ships with one polarity and cannot
  silently give the wrong answer for the other.
- **IR-level `no_alloc`/`no_panic` bound on `migrate_state`** — `cap no_alloc` (bc500f47) and Z3-backed `cap no_panic` (2627f597) have now landed, so the compile-time machinery exists. What remains is wiring the *recognition* of migration functions as implicitly subject to these caps, and the `policy_dce` IR pass. Closer than when this plan was written but still deferred.
- **Refinement-verified migration totality** — Z3 (`lib/refine/`) discharging that a migration produces a valid new `State` for every prior `State` (invariants preserved, no partial field maps). This is the second, distinct project the "refinement-verified state migration" framing points at; it layers on top of the capability bound here. The `--check-migration` SMT mode (`bin/main.ml:574`) is its seed.
- **Capability leases / epochs across deploys** — tie a granted widening to an epoch so it auto-revokes on the next narrowing deploy; reuse the `Cap(Pid)` epoch-revocation runtime.
- **Proof-cap propagation across nodes** — extend the manifest to carry proof-cap producer identity for cross-node admission.
- **Behavior-level enforcement** — closing the Threat-model gap (a lying manifest from a key-holding attacker) requires either server-side sandboxing (seccomp/pledge around the dlopen'd code) or verifiable compilation; both are separate projects.

---

## Implementation Tasks — Parts A & B

**Scope of this task breakdown:** Parts A and B only (Part C — `ACTIVATE4`, node
policy, server-side admission, `migrate_state` bound — is separate follow-on work,
not covered by these tasks). Task 5 computes the widening/grant decision and the
`cap_root` value; it does not wire `cap_root` into any signed wire message, since
that wiring is Part C's `ACTIVATE4`.

### Global Constraints (apply to every task below)

- **IO authority caps only.** Do not touch `pure_mod`/`no_alloc`/`no_extern_mod`/
  `deterministic_mod`/`no_panic_mod` — those are guarantee caps with inverted
  variance polarity, explicitly out of scope (see Out of Scope / Follow-ons).
- **No new traversal.** Every task reuses the existing `check_module_needs`
  traversal (`typecheck.ml:5160`), `builtin_cap_table` (`typecheck.ml:956`), and
  `calls_in_expr` (`typecheck.ml:5125`). Restructure to *accumulate*, don't
  duplicate the walk.
- **Behavior-preserving for existing diagnostics.** Restructuring
  `check_module_needs` must not change any existing error message, order, or
  span for code that has no capability manifest concerns — run
  `scripts/run-tests.sh` (full, not `-q`) after each task and diff any
  unexpected typecheck-test output.
- **`cap_root` hash is BLAKE3, hex-encoded** — via `March_cas.Blake3.hash_string`
  (`lib/cas/blake3.ml`), the same primitive already used for `cas_hash` in this
  manifest. `bin/main.ml` already depends on `march_cas`; no new dune dependency
  needed for this task.
- **Determinism:** `cap_root` must be identical across builds regardless of
  traversal/hashtable iteration order — always sort the cap list before joining
  and hashing.
- Standard gates before each commit: `dune build`, `scripts/run-tests.sh`
  (full), and for forge-side tasks also whatever forge test runner
  `forge/test/test_forge.ml` uses.
- One commit per task, `refactor(caps): ...` / `feat(caps): ...` prefix.

### Task 1: `lib/caps/cap_lattice.ml` — factor out the duplicated hierarchy

**Files:** Create `lib/caps/cap_lattice.ml` (+ `.mli`) and `lib/caps/dune`; modify
`lib/typecheck/typecheck.ml`, `lib/refinecheck/cap_infer.ml`, and their dune
`libraries` stanzas.

- [ ] **Step 1:** Move `io_cap_hierarchy` (`typecheck.ml:933`) and `cap_subsumes`
      (`typecheck.ml:1071`) verbatim into `Cap_lattice`, adding a `normalize : string
      list -> string list` function (drop any cap subsumed by another already in
      the list — no such function exists today; this is new, small code, not
      extracted).
- [ ] **Step 2:** Replace `typecheck.ml`'s local `io_cap_hierarchy`/`cap_subsumes`
      with calls into `Cap_lattice`; confirm every existing call site
      (`cap_subsumes` is used in checks throughout typecheck.ml) still compiles
      unchanged.
- [ ] **Step 3:** Replace `lib/refinecheck/cap_infer.ml`'s duplicate hierarchy
      (`cap_infer.ml:26`, currently identical modulo whitespace to
      `typecheck.ml:933`) with `Cap_lattice.hierarchy`. Delete the local copy —
      do not leave it as dead code or a re-export shim.
- [ ] **Step 4:** Add a unit test module (`test/test_caps.ml` or alongside
      existing typecheck tests — check `test/dune` for the existing driver
      pattern before creating a new one) covering: subsumption along the
      hierarchy, the root cap, sibling caps (neither subsumes the other),
      and `normalize` dropping a subsumed entry.
- [ ] **Step 5:** Standard gates. **Commit**
      `refactor(caps): factor io_cap_hierarchy + cap_subsumes into lib/caps/cap_lattice (Phase5C-A.1)`.

### Task 2: Per-function capability closure — restructure `check_module_needs`

**Files:** Modify `lib/typecheck/typecheck.ml` and `lib/typecheck/typecheck.mli`.
**Depends on:** Task 1 (`Cap_lattice.normalize`).

- [ ] **Step 1:** Read `check_module_needs` (`typecheck.ml:5160`) end to end.
      Identify exactly where Check 1 (declared `needs`), Check 1b (builtin calls
      via `builtin_cap_table` + `calls_in_expr`), Check 1c (`extern` ⇒
      `IO.Foreign`), and Check 4 (imported-module propagation) each determine a
      function's required caps — today these are validated against `needs` and
      the sets are not retained.
- [ ] **Step 2:** Introduce an accumulator (e.g. `(string, string list) Hashtbl.t`
      keyed by fully-qualified function name) threaded through the same checks,
      recording each function's cap set as it's computed — same traversal, now
      also recording. Do not add a second pass over the AST.
- [ ] **Step 3:** Normalize each function's accumulated set with
      `Cap_lattice.normalize` before storing.
- [ ] **Step 4:** Export an accessor from `typecheck.mli`, e.g.
      `val fn_capability_closures : env -> (string * string list) list` (adjust
      the exact signature to whatever `env`/module-checking entry point already
      exists — the accessor must be reachable by whatever calls
      `check_module_needs` today, i.e. the top-level module-check driver, not by
      re-invoking typecheck).
- [ ] **Step 5:** Add typecheck tests asserting the accessor returns the correct
      per-fn set for: a function with only declared `needs`, a function calling
      an IO builtin with no declared `needs` (inferred via `builtin_cap_table`),
      a function with `extern` (⇒ `IO.Foreign`), and a function that imports a
      module needing IO (Check 4 propagation) — confirm the returned set is the
      union, normalized.
- [ ] **Step 6:** Confirm no existing typecheck error test changes output
      (`scripts/run-tests.sh`, full run, diff `run_compiler`/`run_eval` output
      against pre-task baseline).
- [ ] **Step 7:** Standard gates. **Commit**
      `refactor(typecheck): expose per-fn IO capability closure from check_module_needs (Phase5C-A.2)`.

### Task 3: Manifest emission — `caps=` + `ROOT cap_root=` in `.hcr_manifest`

**Files:** Modify `bin/main.ml` (writer at `:2158`, `--hot-reload --compile-so`
mode). **Depends on:** Task 2 (the accessor).

- [ ] **Step 1:** In the `--hot-reload --compile-so` manifest-writing path,
      after computing each `FN` line's existing fields (`impl_hash`, `sig_hash`,
      `callers:`), look up that function's cap set via Task 2's accessor and
      append ` caps=<sorted-csv>` (empty string if the set is empty — the field
      is still present, e.g. `caps=`).
- [ ] **Step 2:** Aggregate `artifact_caps = sorted(⋃ boundary-fn caps)`
      (normalized — reuse `Cap_lattice.normalize` on the union, not just
      per-fn), compute `cap_root = March_cas.Blake3.hash_string (String.concat
      "\n" artifact_caps)` — `bin/main.ml` already depends on `march_cas`
      (it's how `ch`/`cas_hash` is computed a few lines above, via
      `March_cas.Cas.compilation_hash`), so no new dune dependency is needed.
      Same hash algorithm as `cas_hash`, avoiding two digest algorithms in one
      manifest file.
- [ ] **Step 3:** Emit a new manifest line `ROOT cap_root=<hex>` (placement:
      alongside the existing `CAS <cas_hash>` line, per the manifest format in
      the "Manifest format extension" section of this plan).
- [ ] **Step 4:** Add a round-trip test: compile a fixture module with a mix of
      declared-`needs` and inferred-builtin-cap functions in `--hot-reload
      --compile-so` mode, parse the emitted `.hcr_manifest`, assert the `caps=`
      fields and `cap_root` match a hand-computed expected value. Also assert
      `cap_root` is stable across two builds of the same source (determinism —
      catches iteration-order bugs).
- [ ] **Step 5:** Standard gates. **Commit**
      `feat(hcr): emit caps= and ROOT cap_root= into .hcr_manifest (Phase5C-A.3)`.

### Task 4: Monotonicity diff — fetch prior caps, compute widening/narrowing

**Files:** Modify `forge/lib/cmd_deploy_hot.ml`, `forge/lib/dune`.
**Depends on:** Task 1 (`Cap_lattice.subsumes`), Task 3 (manifest format).

- [ ] **Step 1:** Add `Cap_lattice` (via `lib/caps`; confirm the library's
      actual public name, e.g. `march_caps`, by checking `lib/caps/dune` —
      Task 1 created it) to `forge/lib/dune`'s `libraries` stanza.
- [ ] **Step 2:** Extend the existing `.hcr_manifest` parser (`cmd_deploy_hot.ml`,
      the `parse_manifest` function, `name :: impl_h :: sig_h :: callers_field
      :: _` match around `:51`) to also extract a `caps=` field. **Do not
      assume `caps=` sits at a fixed field index** — it's field 3 for a
      caller-less function (no `callers:` token present) or field 4 otherwise;
      scan the trailing token list for one with a `caps=` prefix instead of
      indexing positionally. **Also fix a real parsing landmine**: the line
      dispatch currently only special-cases lines starting with `#`; a new
      `ROOT cap_root=<hex>` line does not start with `#` and would otherwise
      fall through to the FN-line splitter, where `String.split_on_char ' '
      "ROOT cap_root=<hex>"` produces `["ROOT"; "cap_root=<hex>"]` — matching
      the existing `[name; impl_h]` fallback and silently fabricating a
      phantom function named `"ROOT"`. Add an explicit check for a `ROOT
      cap_root=` prefix *before* falling through to FN-line parsing, storing
      the extracted hex in the `manifest` type (add a `cap_root : string`
      field, empty string when absent — legacy manifest).
- [ ] **Step 3:** In the deploy flow, after the existing `ABI_QUERY`/sig_hash
      gate: fetch the prior deployed artifact's `.hcr_manifest` from a
      **local baseline file**, mirroring the existing `prev_schemas_path` /
      `save_schemas_baseline` pattern exactly (grep `cmd_deploy_hot.ml` for
      both — `prev_schemas_path` is computed once per `deploy`/`deploy_env`
      call at a path like `<project_root>/.march/<name>_hot.so.schemas.json.prev`
      and threaded unchanged into every `deploy_one` call in a multi-server
      fleet; `save_schemas_baseline` rewrites it after a successful deploy).
      Add a parallel `<name>_hot.so.hcr_manifest.prev` baseline file and a
      `save_manifest_baseline` following the same shape. There is **no**
      remote/CAS fetch involved — an earlier draft of this plan incorrectly
      assumed a network fetch from an "epoch-master node" by false analogy
      with the shared-epoch fetch; the actual prior-schemas mechanism has
      always been this local file, and caps should follow the identical
      pattern for consistency with the existing code. Absent baseline file
      (first deploy) ⇒ no prior caps, no gate (permissive), matching the
      schemas-baseline precedent (`old_schemas_path <> ""` checks in `run`).
- [ ] **Step 4:** Compute `prior_caps = ⋃ prior FN caps` and `new_caps = ⋃ new
      FN caps` (both via `Cap_lattice.normalize`). Compute `widening = { c ∈
      new_caps | ¬∃ p ∈ prior_caps. Cap_lattice.subsumes p c }` and `narrowing =
      prior_caps \ new_caps` (for logging only — narrowing is always allowed).
- [ ] **Step 5:** If `widening` is nonempty, abort the deploy before any
      activation with the diagnostic shape given in this plan's "Diagnostic
      shape" section under Part B (list each widened cap + the source function
      whose manifest line introduced it).
- [ ] **Step 6:** Add forge tests (`forge/test/test_forge.ml`) covering: no
      prior manifest (first deploy — treat as legacy/permissive per Failure
      Modes, no gate), pure narrowing (allowed, logged), a subsumed add
      (allowed), a sibling widen (blocked), a parent widen (blocked), an `IO`
      root add (blocked), and a `ROOT cap_root=` line parsing correctly
      without fabricating a phantom `"ROOT"` function entry.
- [ ] **Step 7:** Standard gates + forge test runner. **Commit**
      `feat(forge): monotonicity gate — block capability widening on hot deploy (Phase5C-B.1)`.

### Task 5: `--grant-cap` — authorize widening

**Files:** Modify `forge/bin/main.ml` (Cmdliner term), `forge/lib/cmd_deploy_hot.ml`.
**Depends on:** Task 4.

- [ ] **Step 1:** Add a repeatable `--grant-cap <C>` flag in `forge/bin/main.ml`'s
      `deploy hot` Cmdliner term: `Arg.(value & opt_all string [] & info
      ["grant-cap"] ~doc:"...")` — forge's existing flags are all single-value,
      this is the first `opt_all`; confirm the term threads through to
      `cmd_deploy_hot.ml`'s entry point the same way other flags do.
- [ ] **Step 2:** In the monotonicity check from Task 4, remove each granted cap
      (normalized/subsumption-matched, not exact string match only — a grant of
      `IO.FileSystem` should cover a widening of `IO.FileWrite`) from the
      blocking `widening` set before the abort decision.
- [ ] **Step 3:** Track the final authorized cap set (prior_caps ∪ granted) —
      this is the value a later Part C task will fold into a signed
      `ACTIVATE4`; for this task, expose it as a return value / log line, not a
      wire-protocol change (`ACTIVATE4` is explicitly out of scope here).
- [ ] **Step 4:** Extend the diagnostic: when caps are ungranted, print the exact
      `forge deploy hot --grant-cap <C>` suggestion per widened cap (matching
      this plan's "Diagnostic shape" section). Emit an audit-log-style line
      (whatever forge's existing deploy logging mechanism is — check
      `cmd_deploy_hot.ml` for the current audit/status output pattern) recording
      each granted widening.
- [ ] **Step 5:** Add forge tests: widening blocked without grant, widening
      allowed with exact-match grant, widening allowed via a broader
      subsuming grant, multiple simultaneous widenings requiring multiple
      grants (one missing ⇒ still blocked, listing only the ungranted one).
- [ ] **Step 6:** Standard gates + forge test runner. **Commit**
      `feat(forge): --grant-cap authorizes capability widening on hot deploy (Phase5C-B.2)`.

### Task 6: Bookkeeping

- [ ] Update `specs/todos.md`: move the Phase 5C Part A/B items to Done.
- [ ] Update `specs/progress.md`: bump test counts, add the capability-manifest
      + monotonicity-gate bullets to the feature list.
- [ ] Confirm `scripts/check-docs.sh` passes (new `lib/caps/` module, new
      `--grant-cap` flag — check whether either needs a doc-lint marker or a
      `docs/capabilities.md` mention).
- [ ] **Commit** `docs(specs): Phase 5C Parts A/B — update todos/progress (Phase5C-A/B.done)`.

---

## Implementation Tasks — Part C

**Scope:** node-side admission (`ACTIVATE4`, `MARCH_DEPLOY_POLICY`, tamper +
policy check in the C reload server) and the compile-time `migrate_state`
IO-free bound. Builds on Parts A & B (landed: `lib/caps/cap_lattice.ml`,
`fn_capability_closures`, `.hcr_manifest` `caps=`/`cap_root`, the forge
monotonicity gate + `--grant-cap`). Reflects the 2026-07-03 design corrections
above: the cap set rides the `ACTIVATE4` wire (no CAS manifest read), and the
`migrate_state` check uses a new own-caps projection (not the module-merged
closure).

### Global Constraints (Part C)

- **`cap_root` is BLAKE3**, matching Part A and `cas_hash`. The server must
  recompute with the *same* algorithm — it cannot substitute the SHA-512 that
  `tweetnacl.c` already provides, because Part A's shipped `cap_root` is BLAKE3.
  Getting BLAKE3 into the C runtime link is a real task (Task C2), not a given.
- **The wire cap set is the artifact cap *union*** (normalized, ~11 entries
  measured), not the per-function manifest. The server never reads a manifest
  file.
- **`caps:` is unsigned on the wire; `cap_root` is signed.** Trust comes from
  the server recomputing `cap_root` over the received `caps:` and matching it
  against the signed value — a forged cap set fails the tamper check.
- **All gates opt-in/additive.** No `caps:`/legacy artifact ⇒ permissive
  admission. No `MARCH_DEPLOY_POLICY` ⇒ permissive. `ACTIVATE4` is a new verb;
  `ACTIVATE`/`2`/`3` legacy paths must remain byte-for-byte untouched.
- **The generated C lattice table must not drift** from OCaml `Cap_lattice` —
  enforced by a CI regenerate-and-diff check (Task C1). It lives in `runtime/`,
  so the existing CAS `runtime_identity` (`lib/cas/cas.ml:168`, digests
  `runtime/*.c`/`*.h`) auto-invalidates cached binaries when the lattice changes.
- Standard gates before each commit: `dune build --root .`, `scripts/run-tests.sh`
  (full). The reload server is exercised by the compiled/native admission tests —
  the implementer must locate the existing `march_reload` test harness (grep
  `test/` for `ACTIVATE`/`reload`/`do_activate` and the native-test dune rules)
  and extend it rather than invent a new one.
- One commit per task, `feat(hcr):` / `fix(typecheck):` / `docs(specs):` prefix
  as appropriate.

### Task C1: `runtime/march_cap_lattice.{h,c}` generated from `Cap_lattice`

**Files:** New OCaml emitter (e.g. `lib/caps/emit_c_table.ml` as a small
`executable`), new `runtime/march_cap_lattice.{h,c}` (generated, checked in),
dune rule + CI freshness check. **Depends on:** nothing (Part A's `Cap_lattice`
exists).

- [ ] **Step 1:** Write an OCaml executable that reads `Cap_lattice.hierarchy`
      (the `(cap_path, parent option)` list) and emits `runtime/march_cap_lattice.c`
      + `.h` exposing two C functions: `int march_cap_subsumes(const char *parent,
      const char *child)` and a `march_cap_normalize` (drop-subsumed) over a
      string array — semantics identical to `Cap_lattice.cap_subsumes`/`normalize`.
      The table is a static array of `{path, parent}` pairs; subsumption walks the
      parent chain (mirror `cap_ancestors`). No hashing here — just the lattice.
- [ ] **Step 2:** dune rule that runs the emitter and writes the two files. Decide
      generate-at-build vs. checked-in-and-verified: given the CAS `runtime_identity`
      digests `runtime/*.c`, the file must physically exist in `runtime/` at link
      time — so **check the generated files in**, and add a CI check (a test, or a
      `scripts/check-docs.sh`-adjacent guard) that regenerates and `diff`s against
      the committed copy, failing on drift. This is the anti-drift mechanism; there
      is **no existing generated-C precedent** in the repo, so document the workflow
      in a header comment on the generated file ("DO NOT EDIT — regenerate with …").
- [ ] **Step 3:** Unit-test the C functions match the OCaml ones on the full
      hierarchy (every pair), plus root/sibling/unrelated cases — a C test or a
      round-trip test that shells the emitter and compares.
- [ ] **Step 4:** Standard gates. **Commit** `feat(hcr): generated C capability
      lattice table from Cap_lattice, with anti-drift CI check (Phase5C-C.1)`.

### Task C2: BLAKE3 available to the C runtime link

**Files:** `bin/main.ml` (the runtime clang-link list, ~`:405` where
`march_reload.c` is added), possibly a tiny `runtime/march_blake3.{c,h}` wrapper.
**Depends on:** nothing.

- [ ] **Step 1:** `march_reload.c` needs to compute a BLAKE3 hex digest, but the
      runtime currently links only `tweetnacl.c` (ed25519 + SHA-512) — BLAKE3 lives
      on the OCaml side (`lib/cas/blake3_stubs.c` + libblake3, via the
      `blake3_cflags.sexp`/`blake3_libs.sexp` discovered flags). Make libblake3
      linkable into the compiled-program runtime: add the same discovered
      `blake3_libs`/`blake3_cflags` flags to `bin/main.ml`'s clang invocation for
      the runtime, so `march_reload.c` can call the libblake3 C API (`blake3_hasher_*`)
      directly. `blake3_stubs.c` itself is an OCaml-FFI stub — do **not** link that;
      link the underlying library and call it from C.
- [ ] **Step 2:** Add a small `march_blake3_hex(const unsigned char *buf, size_t
      len, char out[65])` helper (new `runtime/march_blake3.{c,h}` or inline in
      `march_reload.c`) producing the 64-char lowercase hex the OCaml
      `March_cas.Blake3.hash_string` produces.
- [ ] **Step 3:** **Cross-implementation agreement test** (critical — a mismatch
      here silently breaks every `cap_root` tamper check): assert the runtime's
      `march_blake3_hex` of a fixed byte string equals `March_cas.Blake3.hash_string`
      of the same string. Reuse the Part-A determinism-test fixture value if one
      exists.
- [ ] **Step 4:** Standard gates. **Commit** `feat(hcr): link BLAKE3 into the C
      runtime for server-side cap_root recompute (Phase5C-C.2)`.

### Task C3: `ACTIVATE4` admission in `runtime/march_reload.c`

**Files:** `runtime/march_reload.c`. **Depends on:** C1 (lattice table), C2 (BLAKE3).

- [ ] **Step 1:** Add an `ACTIVATE4` branch (clone the `ACTIVATE3` branch at
      `march_reload.c:791`; keep `ACTIVATE`/`2`/`3` untouched). Parse `cap_root:<hex>`
      and `caps:<csv>` from the line — **both before `callers:`** (which still parses
      to end-of-line at `:716–720`). Parse `caps:` by a bounded scan to the next
      ` <key>:` boundary, not to EOL.
- [ ] **Step 2:** Reconstruct the canonical signed message
      `"ACTIVATE4 <name> <impl_hash> <cas_hash> <migrate> epoch:<N> cap_root:<hex>
      callers:<sorted-csv>"` (note: `caps` is **not** in the signed message) and
      verify with `crypto_sign_open` exactly as `ACTIVATE3` does (`:877`), same
      `err_sig` audit on failure.
- [ ] **Step 3:** **Tamper check.** `march_cap_normalize` + sort the received
      `caps:` set, `march_blake3_hex` it, compare to the signed `cap_root`. Mismatch
      ⇒ `wresp("ERR cap_tamper\n")`, `write_audit_log(..., "err_cap_tamper")` (follow
      the existing `err_abi`/`err_cas_miss`/`err_sig` convention at `:283`/`:669`).
- [ ] **Step 4:** **Policy load + check.** At server startup (or lazily on first
      ACTIVATE4), read `getenv("MARCH_DEPLOY_POLICY")` — a newline-delimited cap
      list; absent ⇒ permissive (skip the check). If present: every cap in the
      received set must be `march_cap_subsumes`d by some policy entry. Violation ⇒
      `wresp("ERR cap_policy <cap>\n")`, `write_audit_log(..., "err_cap_policy")`.
      Empty/absent `caps:` (legacy artifact) ⇒ permissive.
- [ ] **Step 5:** On all checks passing, call the shared `do_activate` (`:377`)
      exactly as `ACTIVATE3` does — the cap logic is a gate *before* `do_activate`,
      not a change to it.
- [ ] **Step 6:** Extend the admission tests: within-policy ⇒ activate; exceeds
      policy ⇒ `err_cap_policy`; tampered `caps:` (root mismatch) ⇒ `err_cap_tamper`;
      no policy ⇒ permissive; legacy `ACTIVATE3`/no-caps ⇒ permissive + unchanged
      behavior.
- [ ] **Step 7:** Standard gates. **Commit** `feat(hcr): ACTIVATE4 node admission —
      cap_root tamper check + MARCH_DEPLOY_POLICY (Phase5C-C.3)`.

### Task C4: forge emits `ACTIVATE4`

**Files:** `forge/lib/cmd_deploy_hot.ml` (the `ACTIVATE3` send site at `:761`/`:765`),
`forge/bin/main.ml` (the `--no-cap-gate` flag). **Depends on:** C3 (so it can be
tested against a real server).

- [ ] **Step 1:** In `run`, where `ACTIVATE3` is currently built, switch to
      `ACTIVATE4` when the parsed manifest has a `cap_root` (Part B already parses
      `cap_root` + per-fn `caps` — reuse `manifest.cap_root` and the artifact cap
      union `manifest_caps manifest.functions`). Emit `cap_root:<hex> caps:<sorted-csv>`
      **before** `callers:` on the wire; sign the ACTIVATE4 message (cap_root in the
      signed string, caps not). Legacy manifest (no `cap_root`) ⇒ keep emitting
      `ACTIVATE3` (a one-line note).
- [ ] **Step 2:** **Compat matrix.** If the server replies unknown-command to
      `ACTIVATE4` (old server predating Part C), abort with the actionable message
      ("server predates capability admission (Phase 5C); upgrade the server or
      re-run with `--no-cap-gate`") — the downgrade to `ACTIVATE3` is **only** via
      the explicit `--no-cap-gate` flag, never automatic.
- [ ] **Step 3:** Add `--no-cap-gate` to `forge/bin/main.ml`'s `deploy hot` term
      (a `bool` flag, threaded like the Part B `--grant-cap` list) that forces the
      `ACTIVATE3` path.
- [ ] **Step 4:** Tests: `ACTIVATE4` wire string is well-formed (cap_root + caps
      before callers, signed message excludes caps); `--no-cap-gate` produces
      `ACTIVATE3`. (Full client↔server round-trip is a Slow/native test if the
      harness supports it.)
- [ ] **Step 5:** Standard gates + forge test runner. **Commit** `feat(forge):
      emit ACTIVATE4 with inline cap set; --no-cap-gate downgrade (Phase5C-C.4)`.

### Task C5: `migrate_state` IO-free bound + own-caps projection

**Files:** `lib/typecheck/typecheck.ml` (+ `.mli`), `lib/tir/tir_names.ml`,
the four existing `_migrate_state` sniff sites (`dce.ml`, `llvm_emit.ml`,
`mono.ml`, `bin/main.ml`). **Depends on:** nothing (independent of C1–C4).

- [ ] **Step 1:** **Own-caps projection.** In `check_module_needs`, alongside the
      existing merged `cap_closures` table, record a parallel `own_cap_closures`
      table storing each function's *own* caps (the `own_caps` value already
      computed at each `record_fn_caps` call site — sig + body scan + extern),
      **without** the `module_wide_caps` merge. Expose `fn_own_capability_closures`
      via the `.mli`. This is the projection the migrate_state check needs (the
      merged closure would falsely flag any migrate_state in a module with a
      module-level `needs`).
- [ ] **Step 2:** Add `Tir_names.is_migrate_fn : actor:string -> string -> bool`
      (the `{actor_lower}_migrate_state` suffix convention currently in
      `bin/main.ml:1005`'s `find_migrate_fn`). Convert the four existing sniff sites
      (`dce.ml`, `llvm_emit.ml`, `mono.ml`, `bin/main.ml`) to it — Wave 3 chunk 2 is
      merged, so this is a clean sweep against the settled module layout.
- [ ] **Step 3:** In typecheck, for each `DFn` recognized by `is_migrate_fn`,
      require its `fn_own_capability_closures` entry to be empty. Any own IO cap
      (builtin or `extern`) ⇒ compile error, with the message from the plan's
      migrate_state section (names the offending builtin + its cap).
- [ ] **Step 4:** Tests: a migrate_state doing `file_write`/`println`/`extern` ⇒
      IO-free error; a pure migrate_state in a module that *does* declare
      module-level `needs IO.Console` (for its handlers) ⇒ **clean** (proves the
      own-caps projection, not the merged closure, is used — this is the exact case
      the merged closure would wrongly reject).
- [ ] **Step 5:** Standard gates. **Commit** `fix(typecheck): migrate_state must be
      IO-free (own-caps projection); is_migrate_fn in Tir_names (Phase5C-C.5)`.

### Task C6: Bookkeeping

- [ ] Update `specs/todos.md`: move Phase 5C Part C to Done; the whole Phase 5C
      item is now complete.
- [ ] Update `specs/progress.md`: add the node-admission + migrate_state-bound
      bullets; note the generated-C-table precedent this establishes.
- [ ] Update `docs/capabilities.md` if it documents deploy-time behavior (the
      `MARCH_DEPLOY_POLICY` env var and `ACTIVATE4` admission are user-facing).
- [ ] Confirm `scripts/check-docs.sh` passes.
- [ ] **Commit** `docs(specs): Phase 5C Part C complete — node admission +
      migrate_state bound (Phase5C-C.done)`.

### Sequencing

C1 (lattice table) and C2 (BLAKE3) are foundations for C3 (server). C3 then C4
(the protocol pair — server first so forge tests against a real one). C5
(migrate_state) is fully independent and can run in parallel with C1–C4. C6 last.
The one place to watch is the C2 cross-impl BLAKE3 agreement test (Step 3) — get
that green *before* C3 depends on it, or every C3 tamper check will fail for a
reason that looks like a protocol bug.
