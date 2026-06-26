# HCR Phase 8 — Cross-Module Function Signature Evolution

**Status:** Loose spec / design document. Not yet scheduled.

**Motivation:** The sig_hash gate in `forge deploy hot` (Phase 4) blocks any deploy where an exported function's signature changes. This is correct for preventing silent ABI mismatches, but it also blocks *intentional* coordinated upgrades where a utility module's API changes and all its callers are updated in the same deploy.

---

## The Problem

The motivating scenario:

```
Module A  — actor, calls B.foo
Module B  — utility bag of functions

v1: B.foo(a: Int, b: String, c: List) -> Result
v2: B.foo(a: Float, b: String, c: List, d: List) -> Result
```

With phases 1–7, `forge deploy hot` rejects this:

```
error: ABI mismatch — sig_hash changed for:
  B.foo: old=abc123 new=def456
```

The gate has no way to know whether old callers of `B.foo` are also being replaced. It treats every sig_hash change as potentially dangerous (correct) but also terminal (too strict).

The *correct* behavior: allow the sig_hash change when **all callers of the old signature are also being replaced in this deploy batch**.

---

## Why the Dispatch Ring Doesn't Fully Protect Us

The dispatch table already has a 2-slot ring per function (`MARCH_MAX_LIVE_VERSIONS=2`) and `march_dispatch_enter` pins the version at call entry. This protects *in-flight* handlers: an A.handler that entered B.foo before the deploy holds the pin on old B.foo until it returns.

But it does NOT protect *new calls* from old code. If an A actor hasn't been migrated yet (migrate-before-run is in progress), its next handler invocation will be old A code, which calls B.foo through the dispatch table — and the table now points to new B.foo. Old A code passes an `Int` where new B.foo expects a `Float`. ABI mismatch.

The save: **migrate-before-run** ordering. Every live A actor receives a MIGRATE message before processing any new handler, so by the time any A handler runs post-deploy, it is running new A code. If A is included in the deploy batch and A.migrate runs before A.handler, old A code never gets a chance to call new B.foo.

The gap: there's currently no enforcement that A is in the deploy batch when B.foo's sig changes. The sig_hash gate closes the gap by refusing entirely; what we want instead is an *informed* gate.

---

## Solution Space

### Option A: Coordinated Upgrade Gate (recommended near-term)

**Mechanism:** Extend the `.hcr_manifest` sidecar with a caller graph: for each exported function, list the exported functions that call it (transitive, within the hot-reload boundary). At deploy time, when a function's sig_hash changes:

1. Look up the old callers from the current server's manifest (or from a stored call graph in the server's state)
2. Verify every old caller is also in the current deploy batch (i.e., its impl_hash is being replaced)
3. If yes → allow the sig_hash change
4. If no → reject with a named-caller error message:
   ```
   error: B.foo signature changed but the following callers are not included in this deploy:
     A.handler — old caller of B.foo, must also be updated
   hint: add A to the deploy batch or use expand-contract instead
   ```

**What "included in the deploy batch" means:** the caller's impl_hash differs from what the server has loaded (i.e., the caller is already in the change set), OR the caller's impl_hash is unchanged (it was already updated in a prior deploy before B.foo was updated — but this case requires careful reasoning about whether old callers of the old B.foo sig exist on the server).

The simplest version: if any server-loaded function calls old B.foo *and is not in the current deploy*, reject. This is slightly over-strict (it rejects cases where the caller has already been updated) but safe.

**Manifest extension needed:**

The `.hcr_manifest` file currently carries:
```
<name> <impl_hash> <sig_hash> <cas_hash>
```

Extend with optional caller annotations:
```
<name> <impl_hash> <sig_hash> <cas_hash> [callers: <name1>,<name2>...]
```

The compiler has the full call graph during `--compile-so` — it already walks SCCs to compute impl_hashes. Recording direct callers at the dispatch boundary is a small addition.

**Server-side state:** the server needs to track, for each loaded function slot, which other dispatch slots call it. This is a reverse index built at ACTIVATE time from the manifest.

---

### Option B: Module-Level Versioning (correct long-term model)

Erlang's model: the runtime holds two module versions simultaneously. Old code (in-flight or not-yet-migrated) sees old module; new code sees new module. The old module is GC'd once no more call frames reference it.

In March terms:
- Each module gets a `module_generation_id` in its dispatch slots
- `march_dispatch_enter` takes a caller's generation id; it returns the function pointer for the *closest matching generation*
- When old A code calls B.foo, it passes its generation id → gets old B.foo
- When new A code calls B.foo, it passes its generation id → gets new B.foo

**Problems with this approach for March:**
1. The caller's generation id is a compile-time constant baked into code. Old A code has gen G baked in; new A code has gen G+1.
2. The migration system already handles this by running migrate-before-run atomically per actor — once an actor migrates, it only runs new code. There's no interleaving of old/new code within a single actor.
3. The ring buffer (size 2) is the existing mechanism; it just needs the right index selection logic.

This is a cleaner model but requires threading generation ids through all dispatch calls, which is a bigger codegen change than the coordinated-upgrade gate.

---

## Recommended Path

**Near-term (Phase 8):** Implement the coordinated upgrade gate.

- Extend the manifest with a caller index
- Add server-side reverse call graph tracking (built from manifests at ACTIVATE time)
- Replace the hard sig_hash rejection with the coordinated check
- Emit clear error messages naming which callers are missing from the batch

**Long-term (Phase 9?):** Move toward module-level versioning.

- Track module boundaries explicitly rather than function boundaries
- Allows safe concurrent deploy of incompatible modules as long as the caller graph is fully covered

---

## What Success Looks Like

```march
-- v1
mod B do
  fn foo(a: Int, b: String, c: List(Int)) -> Result(Int, String) do
    Ok(a + List.length(c))
  end
end

-- v2 (signature changed)
mod B do
  fn foo(a: Float, b: String, c: List(Int), d: List(String)) -> Result(Float, String) do
    Ok(a +. float_of_int(List.length(c)))
  end
end
```

```march
-- v2 caller (updated in same deploy batch)
mod A do
  actor Worker do
    state { count: Int }
    init  { count: 0 }
    on Process(x: Float, tags: List(String)) do
      let result = B.foo(x, "work", [1, 2, 3], tags)
      { count: state.count + 1 }
    end
  end
end
```

```
$ forge deploy hot
Connecting to my-server via SSH...
Checking call graph compatibility...
  B.foo: sig_hash changed — verifying all callers are in deploy batch
  A.Worker_dispatch: present in deploy (impl_hash changed) ✓
Deploying 2 changed function(s)...
  activated: B.foo
  activated: A.Worker_dispatch  [migrate_required]
Deploy complete: 2 function(s) activated, 1 actor migration(s) broadcast.
```

Compare to the error case (caller not included):

```
$ forge deploy hot  # only B in the changeset
error: B.foo signature changed but the following callers are not included in this deploy:

  A.Worker_dispatch calls B.foo (old sig: Int, String, List(Int) -> Result(Int, String))

To fix, include Module A in this deploy or use expand-contract:
  1. Add B.foo_v2 alongside B.foo, update A to call B.foo_v2, deploy together
  2. In a later deploy, remove B.foo

Spec: specs/plans/2026-06-26-hcr-cross-module-versioning.md
```

---

## Open Questions

1. **Caller graph storage on the server.** Where does the server keep the reverse call graph? Options: in-memory (rebuilt from manifests at ACTIVATE time), or persisted to a file alongside the audit log. In-memory is simpler.

2. **Cross-binary caller detection.** If Module A and Module B are compiled in separate `forge deploy hot` invocations, the server may not have the caller graph for A at the time B is deployed. The gate would fall back to rejecting unless A is in the same batch. Is this acceptable? Probably yes for V1.

3. **Expand-contract ergonomics.** Until Phase 8 lands, users must use expand-contract manually. Should `forge` provide a `forge hot-reload expand B.foo` subcommand that scaffolds the two-deploy pattern automatically?

4. **Generation ids vs. ring slots.** If we go to module-level versioning (Option B), the ring buffer needs to map a caller's generation to a slot. Today the ring maps `{0, 1}` (two versions); generation ids would be monotonically increasing. The ring is still bounded at 2 — we just need to be able to say "version G maps to slot 0; version G+1 maps to slot 1; once G drains, reclaim slot 0."

5. **Sig-compatible changes.** Adding an optional parameter with a default is backward-compatible. The gate today treats any sig_hash change as breaking. A more nuanced gate could allow truly backward-compatible changes (same arity, same param types, widened return type) without requiring all callers to be in the batch.

---

## Files That Will Change

- `forge/lib/cmd_deploy_hot.ml` — coordinated upgrade gate, replaces hard sig_hash rejection
- `runtime/march_reload.c` — build reverse call graph from manifest at ACTIVATE time
- `runtime/march_dispatch.{h,c}` — per-slot caller set storage (names of callers, for the reverse index)
- `bin/main.ml` — emit caller list in `.hcr_manifest` sidecar
- `lib/tir/llvm_emit.ml` or `lib/cas/pipeline.ml` — extract caller graph for boundary functions
- `forge/lib/schema_diff.ml` — extend with `sig_evolution` type (breaking vs. compatible)
- `docs/hot-code-reload.md` — document the coordinated upgrade pattern and expand-contract fallback
