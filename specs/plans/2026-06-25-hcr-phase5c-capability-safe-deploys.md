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
5. **`cap_root` uses SHA-512, not blake3.** The C runtime has no blake3; SHA-512 already
   exists inside `runtime/tweetnacl.c` (used by ed25519) and only needs exposing in the
   header. Client side uses digestif SHA512 (already a forge dep).

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
| a7588911 | **Phase 10: cluster-aware rolling deploy** | `forge deploy hot` orchestrates multi-node; the monotonicity gate (Part B) runs once on the deployer side before any per-node activation. The prior-caps baseline is fetched from the **epoch-master node** (the same first-server Phase 10 already uses for the shared epoch). Node admission (Part C) runs independently on each node. |

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
| `cap_root` hash | **SHA-512, hex** (not blake3): the reload server already links SHA-512 inside `runtime/tweetnacl.c` (ed25519's hash) — expose it in `tweetnacl.h` and reuse it; client side uses digestif SHA512 (already a forge dependency). The C runtime has no blake3 and vendoring one for this is not worth it. |
| Protocol | New verb **`ACTIVATE4`** = ACTIVATE3 + `cap_root:<hex>` in wire and signed message. A new verb, not an appended field: (a) adding anything to the signed message makes old servers reconstruct a different message and fail with a misleading `bad_signature`; (b) the server parses `callers:` to end-of-line, so a trailing field would be swallowed into the CSV. Old servers answer `ACTIVATE4` with a clean unknown-command error. |
| Monotonicity rule | Deploy may *narrow* freely; *widening* (a new cap not subsumed by any prior-held cap) aborts before activation unless an explicit `--grant-cap <C>` authorizes each widened cap |
| Grant authority | A widening grant rides the deployer's ed25519 signature: `cap_root` is added to the signed activation payload, so the authority claim is tamper-evident and audit-logged |
| Multi-node baseline | On a Phase 10 multi-node deploy, the prior-caps baseline is fetched once from the **epoch-master node** (the first server, same node the shared epoch comes from); the gate runs once on the deployer before any per-node activation |
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
cap_root      = sha512_hex( "\n".join(artifact_caps) )          -- deterministic content digest
```

Union is the correct aggregation for *authority* (the artifact can do anything any of its functions can do). This is exactly why guarantee caps don't belong in the same set — they hold by intersection.

### Manifest format extension

`.hcr_manifest` gains a per-fn `caps=` field and a top-level `ROOT` line. The current manifest format (writer at `bin/main.ml:2158`, after Phase 8 added `callers:`) is:

```
FN   <name> <impl_hash> <sig_hash> callers:<sorted-csv>
```

The extended format adds `caps=` after `callers:` and a new top-level `ROOT` line:

```
CAS  <cas_hash>
ROOT cap_root=<hex>
FN   MyApp.Server.handle   <impl_hash> <sig_hash> callers:MyApp.Router.route caps=IO.Console,IO.NetConnect
FN   MyApp.Server.server_migrate_state  <impl_hash> <sig_hash> callers: caps=
```

(Note the migration function's real name follows the implemented `{actor_lower}_migrate_state` suffix convention, not a bare `migrate_state`.)

`forge/lib/cmd_deploy_hot.ml` already parses `callers:` from field index 3 (`fn_callers`, `cmd_deploy_hot.ml:51`) and its match pattern ends in a wildcard, so **old parsers tolerate the new field**; new parsing logic for `caps=` at field index 4 is additive.

Caps go in `.hcr_manifest` (per-function) rather than `.schemas.json` (per-actor-state). The manifest is already keyed in the CAS next to the artifact, so `forge deploy hot` and the server both reach it by the path derivation Phase 5 established.

---

## Part B: Monotonicity Gate (deploy time)

In `forge/lib/cmd_deploy_hot.ml`, after the existing `ABI_QUERY` prior-state fetch and `sig_hash` ABI gate (the prior-manifest read already uses the `.hcr_manifest` path derivation established in Phase 5):

1. **Fetch prior caps.** Read the prior deployed artifact's `.hcr_manifest` from the CAS (same path derivation already used to fetch the prior `.schemas.json`). On a multi-node deploy, the prior baseline comes from the **epoch-master node** — the same first-server Phase 10 already queries for the shared epoch — so the gate runs exactly once per deploy even mid-rolling-upgrade. Compute `prior_caps = ⋃ prior fn caps`.
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

Phase 5C defines **`ACTIVATE4`**, which inserts `cap_root:<hex>` **before** `callers:`:

```
Wire:   ACTIVATE4 <name> <impl_hash> <cas_hash> <sig_b64> <migrate> epoch:<N> cap_root:<hex> callers:<sorted-csv>
Signed: "ACTIVATE4 <name> <impl_hash> <cas_hash> <migrate> epoch:<N> cap_root:<hex> callers:<sorted-csv>"
```

Two wire-format constraints force this shape (both verified against `march_reload.c`):

- **New verb, not a new field on ACTIVATE3.** The server reconstructs the canonical signed
  message from parsed values (`march_reload.c:759` pattern); any field added to the signed
  payload makes an old server reconstruct a *different* message and fail with a misleading
  `ERR bad_signature`. An unknown `ACTIVATE4` verb instead yields a clean unknown-command
  error, which forge turns into an actionable diagnostic. This matches how 2 and 3 were
  introduced.
- **`cap_root:` before `callers:`.** The server's callers parse consumes from `callers:` to
  end-of-line (`march_reload.c:716–720`) — the CSV is definitionally "the rest of the line".
  Any field placed after it would be silently absorbed into the callers set and corrupt the
  canonical form. `callers:` stays last.

**Compatibility matrix (explicit, no silent fallback):**

| Client | Server | Behavior |
|---|---|---|
| new forge, caps in manifest | new server | `ACTIVATE4`, full admission |
| new forge, legacy artifact (no caps) | new server | `ACTIVATE3`; permissive admission + one-line warning |
| new forge, caps in manifest | old server | server: unknown command; forge aborts with "server predates capability admission (Phase 5C); upgrade the server or re-run with `--no-cap-gate`" — the downgrade is an explicit operator choice, never automatic |
| old forge | new server | `ACTIVATE3` (or older); legacy path, permissive admission |

Server flow on `ACTIVATE4`, after sig-verify + CAS-load (existing) and before `dlopen`:

1. Read the just-received artifact's `.hcr_manifest` from the CAS; recompute `cap_root'` over its `caps` (SHA-512 via the exposed tweetnacl hash). **This is new C code** — today the server never reads the manifest (it is parsed only client-side in `cmd_deploy_hot.ml`); the server needs the manifest path derivation, a line parser for `FN`/`ROOT`, and the digest call.
2. **Tamper check:** `cap_root' == cap_root` (the signed value). Mismatch ⇒ `ERR cap_tamper`, audit `err_cap_tamper` (naming follows the existing `err_abi`/`err_cas_miss`/`err_sig` convention in `write_audit_log`).
3. **Policy check:** every cap in the artifact set is subsumed by some policy entry. Violation ⇒ `ERR cap_policy <cap>`, audit `err_cap_policy`.
4. Proceed to `dlopen` + `march_dispatch_publish` as today (extend the shared `do_activate()` helper, `march_reload.c:377`).

This is the single runtime checkpoint that re-materializes the erased static cap discipline at the trust boundary. The subsumption check in C works off a **generated table** emitted from `Cap_lattice` so it cannot drift from the OCaml hierarchy. Note there is currently **no precedent** in this repo for OCaml-generated C sources — this needs a dune rule that runs the emitter and a CI freshness check (regenerate + diff) as the anti-drift mechanism. The generated file lives in `runtime/`, so the existing CAS cache key (which digests `runtime/*.c` and `*.h`) automatically invalidates cached binaries when the lattice changes.

### `migrate_state` capability bound

State-migration functions run as the actor's next turn, ahead of any pending user messages (Phase 5 Part A, migrate-before-run ordering). A migration is a pure old→new state transformation; doing IO inside the migration window (or panicking — which already forces supervisor restart) is a smell. Enforce at compile time.

**Where recognition actually lives today** (correcting the earlier draft): the typechecker does *not* recognize migration functions. Recognition is a name-suffix heuristic in `bin/main.ml:1005` (`find_migrate_fn`): a `DFn` whose name ends in `_migrate_state` and whose prefix equals `lowercase(actor_name)`, used by the `--check-migration` SMT mode. The parent design's "function named exactly `migrate_state` with return-type disambiguation" (`hcr-phase5-design.md:170`) is what TIR/llvm_emit implemented as the `{actor_lower}_migrate_state` convention.

**Change:** teach **typecheck** the same suffix convention (it owns the cap-closure machinery Part A exposes, so the check is one map lookup), and require the recognized function's IO cap closure to be empty. Any IO builtin or `extern` ⇒ compile error. `bin/main.ml`'s `find_migrate_fn` stays as-is for the SMT mode; the shared predicate belongs in **`lib/tir/tir_names.ml`** — Wave 3's designated single home for cross-pass name contracts (W3.1). Note the `_migrate_state` suffix is currently name-sniffed in four places (`dce.ml`, `llvm_emit.ml`, `mono.ml`, `bin/main.ml`) and not yet in `Tir_names`; 5C should add the predicate there and convert its own uses to it rather than adding a fifth sniff site. Converting the existing four is Wave-3-flavored cleanup, best coordinated with chunk 2 (which is actively restructuring `llvm_emit`).

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
| `bin/main.ml` | Aggregate `artifact_caps` + `cap_root` (SHA-512); emit `caps=`/`ROOT` into `.hcr_manifest` in `--hot-reload --compile-so` (writer at `:2158`) |
| `forge/lib/dune` | Add the shared caps lib (forge already depends on `march_ast`/`march_parser`/etc., so this is routine) |
| `forge/lib/cmd_deploy_hot.ml` | Parse `caps=` (field 4) + `ROOT`; fetch prior cap manifest from the epoch-master node; monotonicity diff; `--grant-cap` handling; emit `ACTIVATE4` with `cap_root` in the signed message; explicit old-server diagnostic + `--no-cap-gate`; widening diagnostic; cap-change lines in `status` |
| `forge/bin/main.ml` | `--grant-cap` via Cmdliner `Arg.opt_all` (first repeatable flag in forge); `--no-cap-gate` |
| `runtime/tweetnacl.h` | Expose the SHA-512 already implemented inside `tweetnacl.c` (one declaration) for the `cap_root` recompute |
| `runtime/march_reload.c` | New `ACTIVATE4` branch (extend `do_activate()` at `:377`); **new** server-side `.hcr_manifest` CAS read + parse (none exists today); `cap_root` recompute + tamper check; load `MARCH_DEPLOY_POLICY`; policy check; `err_cap_tamper`/`err_cap_policy` audit results |
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
2. `ABI_QUERY` + fetch prior manifest (epoch-master node): `prior_caps = {IO.Console, IO.NetConnect}`.
3. Monotonicity diff: `IO.FileWrite` is **not** subsumed by any prior cap → widening → **abort** with the Part B diagnostic.
4. Operator decides this is intended: `forge deploy hot --grant-cap IO.FileWrite`. The grant is signed into `cap_root`, the deploy proceeds via `ACTIVATE4`.
5. Server: verifies sig (covers `cap_root`); recomputes `cap_root'` from the CAS manifest, matches; checks `{IO.Console, IO.FileWrite, IO.NetConnect}` ⊆ node policy. If the node policy omits `IO.FileWrite` → `ERR cap_policy IO.FileWrite`, deploy rejected at the boundary even though it was correctly signed and granted. Otherwise `dlopen` + publish.
6. Audit log records the granted widening with signer + `cap_root`.

A narrowing deploy (v3 drops `IO.FileWrite`) sails through with no grant and no policy friction.

---

## Testing

- `forge/test/test_forge.ml`: `Cap_lattice.subsumes`/`normalize` (hierarchy edges, root, siblings); monotonicity diff (narrow / subsumed-add / sibling-widen / parent-widen / root-add) × (grant present / absent); repeatable `--grant-cap` parsing.
- `test/test_cas.ml`: `.hcr_manifest` `caps=` + `ROOT` emit/parse round-trip; old parser tolerates `caps=` field (wildcard match); `cap_root` determinism vs cap order; OCaml (digestif) and C (tweetnacl) SHA-512 agree on `cap_root` for the same cap list.
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
- **`cap_root` hash is SHA-512, hex-encoded**, not blake3 — OCaml side via
  `digestif` (already a `forge` dependency; add to `lib/caps` or wherever the
  digest is computed), matching the plan's Decisions table.
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
      per-fn), compute `cap_root = sha512_hex(String.concat "\n" artifact_caps)`
      using `digestif` (add as a `bin/dune` library dependency if not already
      present — check first, `forge` already depends on it).
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

- [ ] **Step 1:** Add `Cap_lattice` (via `lib/caps`) to `forge/lib/dune`'s
      `libraries` stanza.
- [ ] **Step 2:** Extend the existing `.hcr_manifest` parser (`cmd_deploy_hot.ml`,
      the `name :: impl_h :: sig_h :: callers_field :: _` match at `:51`) to
      also extract a `caps=` field when present at index 4 (absent/legacy ⇒
      empty list, not an error), and parse the new `ROOT cap_root=<hex>` line.
- [ ] **Step 3:** In the deploy flow, after the existing `ABI_QUERY`/sig_hash
      gate: fetch the prior deployed artifact's `.hcr_manifest` from the CAS
      using the same path derivation already used for the prior `.schemas.json`.
      On a multi-node deploy (Phase 10's `deploy_env`), fetch from the
      epoch-master node specifically (the same first-server the shared epoch
      already comes from) — the gate runs once per deploy, not once per node.
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
      root add (blocked).
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
