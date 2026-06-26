# HCR Phase 9 — Epoch-Tagged Dispatch

**Status:** Design. Prerequisite: Phase 8 complete (`20e54959`).

**Motivation:** Phase 8's coordinated gate requires every caller of a sig-changed function to be included in the same deploy batch. This works well for same-project deploys but breaks down in two real situations:

1. **Cross-binary callers.** Module C lives in a separate binary (separate CI, separate team). Its caller data is never recorded on the server, so Phase 8 conservatively allows sig changes involving C — but C's code on the server still calls old B.foo through the dispatch table, and after a sig change it will ABI-mismatch silently.

2. **Independent upgrade pace.** You want to ship B.foo v2 today and update A next sprint. With Phase 8 you must do both in one shot. With epoch dispatch, old A code naturally keeps calling old B.foo until A is redeployed.

Actors are already protected by migrate-before-run (Phase 5): the migration runs before the next handler, so old actor code never calls new B.foo between invocations. The remaining exposure is **plain (non-actor) cross-binary callers of sig-changed functions**.

---

## Core Idea: The Dispatch Ring Already Has Two Slots

The runtime already maintains a 2-slot ring per function. The Phase 9 insight: instead of always routing to the *current* slot, route to the slot that was *current when the caller was compiled*. Old A code compiled against B.foo-slot-0 calls slot 0 forever. New B.foo lands in slot 1. Old B.foo (slot 0) is reclaimed once all old A handlers drain.

This requires:

1. **A compile-time epoch constant baked into call sites** — tells the runtime which "generation" the caller belongs to.
2. **The ring to track which epoch is in each slot** — so the runtime can find the right slot for a given caller epoch.
3. **The server to assign and track epochs** — globally monotonic, assigned per `forge deploy hot` invocation.

---

## Epoch Assignment

The reload server owns a `next_epoch` counter (starts at 1, incremented on each deploy, persisted to `<cas_root>/next_epoch` across restarts). A new protocol command returns the next epoch and atomically increments it:

```
GET_EPOCH
→ EPOCH <N>
```

The `forge deploy hot` flow gains a step **before** compilation:

```
1. SSH tunnel open
2. GET_EPOCH → N                    ← new step
3. Compile with --hcr-epoch=N
4. VERSIONS drift check
5. ABI_QUERY
6. Set-diff, coordinated gate
7. CAS_CHECK + CAS_PUT
8. ACTIVATE ... epoch:<N> ...       ← extended
```

Epoch N is passed to the compiler as `--hcr-epoch N` (or `MARCH_HCR_EPOCH=N`). The compiler bakes it as a compile-time integer literal at every boundary call site.

**Backward compatibility:** if `--hcr-epoch` is absent (old forge, or non-HCR build), the compiler emits the existing `march_dispatch_enter` with no epoch — which the runtime treats as epoch 0 ("see the current version"). Epoch 0 is reserved for "no epoch / always current".

---

## Runtime Changes

### `march_dispatch.h` additions

```c
/* Phase 9: each ring slot tracks the epoch it was published at.
 * Callers compiled with --hcr-epoch=N call march_dispatch_enter_gen(id, N, &v),
 * which finds the newest ring slot with slot_epoch <= N. */

int march_dispatch_publish_epoch(uint32_t name_id, void *fn_ptr,
                                 const char *impl_hash, const char *sig_hash,
                                 uint8_t kind, uint32_t epoch);

void *march_dispatch_enter_gen(uint32_t name_id, uint32_t caller_epoch,
                               uint32_t *out_version);
```

### `MarchFnVersion` struct addition

```c
typedef struct {
    void              *fn_ptr;
    _Atomic(uint64_t)  refs;
    char               impl_hash[65];
    char               sig_hash[65];
    uint8_t            kind;
    uint8_t            live;
    uint32_t           epoch;          /* Phase 9: epoch this slot was published at */
} MarchFnVersion;
```

### `march_dispatch_enter_gen` logic

```
Find the ring slot s where:
  ring[s].live == 1
  AND ring[s].epoch <= caller_epoch
  AND ring[s].epoch is the maximum such value

If no such slot exists (caller_epoch predates all live slots), fall back to current.
```

On a 2-slot ring this is a 2-iteration scan. The fallback ensures old-format callers (epoch 0) keep working.

### `march_dispatch_publish_epoch`

Same as `march_dispatch_publish` but also sets `ring[idx].epoch = epoch`. The existing `march_dispatch_publish` stays for callers that don't pass an epoch (sets `epoch = 0`).

### Ring eviction

When publishing epoch G+2, we need to evict the oldest ring slot. If that slot's refs > 0 (old callers still in-flight), the publish fails and the server responds `ERR all_slots_pinned` — same as today, but now with epoch context in the error: "epoch G still has N active callers; retry when they drain."

This is the Erlang "soft purge": wait for old code to drain before overwriting its slot.

---

## Compiler Changes

**`lib/tir/llvm_emit.ml`** (boundary call emission):

```ocaml
(* Today: *)
let enter = "march_dispatch_enter" in
build_call enter_fn [| name_id_val; version_ptr |] "enter_v" builder

(* Phase 9, when hcr_epoch is set: *)
let enter = "march_dispatch_enter_gen" in
let epoch_val = const_int i32 hcr_epoch in
build_call enter_gen_fn [| name_id_val; epoch_val; version_ptr |] "enter_v" builder
```

**`bin/main.ml`**: add `--hcr-epoch N` to the flag set (integer, default 0). Thread through to `Llvm_emit.emit_module`.

The epoch value of 0 means "no epoch — always call current" so omitting `--hcr-epoch` is a no-op for existing deploys.

---

## Reload Server Changes

**`runtime/march_reload.c`**:

### `GET_EPOCH` handler (new)

```c
} else if (strcmp(line, "GET_EPOCH") == 0) {
    uint32_t e = g_next_epoch++;
    persist_next_epoch();          /* write to <cas_root>/next_epoch */
    char resp[64];
    int n = snprintf(resp, sizeof(resp), "EPOCH %u\n", e);
    write(fd, resp, (size_t)n);
```

### ACTIVATE handler extension

Parse optional `epoch:<N>` field after `migrate_required` (similar to how `callers:` is parsed). Call `march_dispatch_publish_epoch(slot_id, fn_ptr, impl_hash, sig_hash, kind, epoch)` instead of `march_dispatch_publish`.

---

## Forge Changes

**`forge/lib/cmd_deploy_hot.ml`**:

```ocaml
(* Before compile step: *)
send_line conn "GET_EPOCH";
let epoch_line = recv_line conn in
let hcr_epoch = match String.split_on_char ' ' epoch_line with
  | ["EPOCH"; n] -> int_of_string_opt n |> Option.value ~default:0
  | _ -> 0
in

(* Pass to compiler: *)
Unix.putenv "MARCH_HCR_EPOCH" (string_of_int hcr_epoch);
(* or: extend build command with --hcr-epoch hcr_epoch *)

(* In ACTIVATE command: *)
let epoch_field = if hcr_epoch > 0
  then Printf.sprintf " epoch:%d" hcr_epoch
  else "" in
let cmd = Printf.sprintf "ACTIVATE %s %s %s %s %d%s%s"
  fm.fn_name fm.fn_impl_hash cas_hash sig_b64 migrate_required
  epoch_field callers_suffix in
```

---

## Interaction With Phase 8

Once Phase 9 is live, the coordinated gate's rejection logic can be loosened:

- **Before Phase 9:** sig_hash change → require all callers in batch (or reject)
- **After Phase 9:** sig_hash change → still warn ("callers on the server will continue routing to the old version until their epoch advances"), but allow the deploy

The coordinated gate can remain as an opt-in strictness mode (`--strict-callers`) for teams that want the hard guarantee. The default can become: deploy succeeds, old callers see old code, no ABI mismatch.

Phase 8's caller tracking (`slot_callers`, `callers:` in ACTIVATE) remains useful even in Phase 9: it tells `forge deploy hot` which functions will have split-epoch callers in flight, so it can print informative progress output like "B.foo: old A.Worker_dispatch callers will route to old B.foo until next A deploy."

---

## Phase 9 Does Not Require Phase 8 to Work

Phase 9 is independently sufficient for the original problem (sig change without touching callers). Phase 8 is a belt-and-suspenders check for the case where Phase 9 isn't deployed yet (old server, no epoch tracking). The two coexist cleanly:

| Server has epoch support | Forge has epoch support | Behavior |
|---|---|---|
| No (old server) | No (old forge) | Phase 8 gate: must include all callers |
| Yes | No | Phase 8 gate (forge doesn't request epoch) |
| No | Yes | Forge requests epoch, server says ERR unknown_command, forge falls back to Phase 8 |
| Yes | Yes | Full Phase 9: epoch-tagged routing, gate becomes advisory |

---

## What This Unlocks After Phase 9

- **Zero-downtime library upgrades.** Update a shared utility module's API without scheduling a coordinated multi-module deploy.
- **Independent team deploy pace.** Team B ships B.foo v2; Team A deploys A the following week. No cross-team coordination required.
- **Expand-contract as a last resort, not the default.** The expand-contract pattern is still valid (and still documented) but is no longer the *only* safe path.

---

## Open Questions

1. **Epoch persistence across server restarts.** The `next_epoch` counter must survive crashes. Writing to `<cas_root>/next_epoch` atomically (tmp + rename) on every `GET_EPOCH` is sufficient. On restart, read it back; if missing, start at 1.

2. **`GET_EPOCH` race.** Two concurrent `forge deploy hot` invocations hitting the same server will each get a unique epoch (the counter is atomic). This is fine — they get different epochs and their slots don't collide.

3. **Epoch wrapping.** `uint32_t` gives ~4 billion deploys before wrapping. Not a concern in practice. If it ever matters, restart the epoch counter and flush the ring (require all callers to redeploy). A warning at epoch 2^31 is sufficient.

4. **Non-.so (main binary) callers.** The server binary itself is compiled without `--hcr-epoch` (epoch 0 / always-current). If the main binary calls a hot-reloaded function and that function's sig changes, the main binary will ABI-mismatch. This is unchanged from today — changing a function that the main binary calls directly requires restarting the server. The HCR system is designed for boundary functions between reloadable modules, not for functions called from the static server binary.

5. **Clustering.** Two server instances may be at different epochs (one just did `GET_EPOCH`; the other hasn't). A request routed to either server will see the same behavior: each server's ring is independent. The concern is if one server has B.foo v2 at epoch G+1 and another only has v1 at epoch G. The ring on server 2 will correctly serve v1 to all callers until it receives its own ACTIVATE for epoch G+1. No cross-server coordination needed — each server's ring is self-consistent.
