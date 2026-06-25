# HCR Phase 7 — Fleet Tooling Design

**Date:** 2026-06-25
**Status:** Draft
**Depends on:** HCR Phases 1–5 complete. Phase 6 (ORC JIT) is independent — Phase 7 works with either Model A or B.
**Spec parent:** `specs/hot-code-reload.md` § Phase 7

---

## Goal

Turn `forge deploy hot` from a single-server tool into a fleet-grade deploy pipeline: multi-server fan-out, canary gating, a remote artifact registry as a third CAS tier, audit logging, and key rotation. No new protocol concepts — all of this builds on the signed ACTIVATE mechanism from Phase 4.

---

## Feature Inventory

| Feature | One-line goal |
|---------|---------------|
| `--env` / `forge.toml` env lists | Deploy to N servers in one command |
| `--canary <n>` | Activate on n servers first, health-check, then roll out or rollback |
| Third CAS tier (`s3://`/`https://`) | Pull-based artifact distribution; no SSH artifact push for large fleets |
| `forge hot-reload init` | Git-history analysis → suggested `exclude` list |
| `forge hot-reload keygen --rotate` | Safe keypair rotation without downtime |
| Effective-version endpoint | `VERSIONS_DETAIL` protocol command |
| Append-only audit log | Every ACTIVATE appended to a structured log on each server |
| `forge hot-reload status` | Cross-fleet version dashboard |

---

## `forge.toml` Schema — Multi-Server Environments

```toml
# Single-server (existing, unchanged):
[hot-reload]
ssh_host   = "do-march"
socket     = "/tmp/march.sock"
public_key = "base64pubkey"

# Multi-server with named environments:
[[hot-reload.env]]
name       = "canary"
ssh_host   = "node-01"
socket     = "/tmp/march.sock"
public_key = "base64pubkey"

[[hot-reload.env]]
name       = "prod"
ssh_host   = "node-01"
socket     = "/tmp/march.sock"
public_key = "base64pubkey"

[[hot-reload.env]]
name       = "prod"
ssh_host   = "node-02"
socket     = "/tmp/march.sock"
public_key = "base64pubkey"

[[hot-reload.env]]
name       = "prod"
ssh_host   = "node-03"
socket     = "/tmp/march.sock"
public_key = "base64pubkey"
```

`name` is a grouping key; multiple `[[hot-reload.env]]` entries with the same name form a deploy group. A flat `[hot-reload]` config (no env) continues to work as-is.

---

## `forge deploy hot --env <name>` — Parallel Fan-Out

```
forge deploy hot [--so <path>] [--env <name>] [--canary <n>] [--timeout <ms>] [--force]
```

**Without `--canary`:** Opens SSH tunnels to all servers in `<name>` concurrently. Runs the full VERSIONS → ABI_QUERY → CAS_CHECK/CAS_PUT → signed ACTIVATE sequence in parallel per server. Prints a per-server status table:

```
node-01  OK  Server.handle (49→343 via a1e8c52)
node-02  OK  Server.handle (49→343 via a1e8c52)
node-03  ERR ABI mismatch — sig_hash changed for: Server.handle
```

Exit code 0 only if ALL servers returned OK for every activated function. On partial failure, lists which servers succeeded (and notes they are now at the new version) and which failed.

**With `--canary <n>`:**

1. Pick n servers from the env group (in order of appearance in forge.toml, or randomly with `--canary-random`).
2. Deploy to canary group; wait `--timeout` ms (default 30 000).
3. During the wait: poll each canary server with `PING` every 2 s. A server that stops responding counts as failed.
4. **If all canaries healthy:** deploy to remaining servers.
5. **If any canary fails:** rollback ALL canaries (re-activate the previous `impl_hash` stored in the `.march/` prev-schemas state), print failure summary, exit 1.

Rollback is a plain ACTIVATE with the prior `impl_hash` — no separate command needed because the CAS already holds the prior artifact.

---

## Third CAS Tier — Remote Artifact Registry

Today: local CAS → (SSH tunnel) → server-side local CAS.

Phase 7 adds: local CAS → **remote registry** → server-side local CAS (read-through on miss).

```toml
[hot-reload]
artifact_registry = "s3://my-bucket/march-cas"
# or:
artifact_registry = "https://artifacts.example.com/march-cas"
```

### Push (client side, `forge deploy hot`)

After building the `.so` and computing the `cas_hash`:

1. Check if the artifact already exists in the registry (`HEAD <cas_hash>`).
2. If not: `PUT <cas_hash> <bytes>` with ed25519 signature in a header.
3. Send `ACTIVATE` to each server with `cas_hash` (no artifact bytes inline).

### Pull (server side, `march_reload.c`)

When `ACTIVATE` arrives with a `cas_hash` the server doesn't have locally:

1. Check local CAS (`~/.march/cas/artifacts/<cas_hash>`). Hit → use it.
2. Check `artifact_registry` URL if configured. `GET <cas_hash>` → verify ed25519 sig in response header → write to local CAS.
3. `dlopen` the artifact.

**S3 auth:** `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars on the server. For `https://`, a `Bearer` token in `MARCH_REGISTRY_TOKEN`.

**ACTIVATE protocol change:** the `cas_hash` field is already present (Phase 4). Phase 7 drops the inline `CAS_PUT` step when a registry is configured; the server pulls instead of receiving the push. Servers without `artifact_registry` fall back to the existing inline push (`CAS_PUT`).

---

## `forge hot-reload init` — Exclude Suggestions

Analyzes git history to produce a `forge.toml` snippet that excludes rarely-changed modules from the hot-reload boundary. Excluded modules get full inlining + defun optimization (no boundary deopt tax).

```
forge hot-reload init [--lookback <days>] [--threshold <n>]
```

**Algorithm:**

1. `git log --name-only --since=<lookback> --diff-filter=M -- 'src/**/*.march'` — collect commit-modified files.
2. Count commits per file over the lookback window (default 90 days).
3. Files with fewer than `--threshold` (default 3) commits are candidates for exclusion.
4. Print a suggested `[hot-reload] exclude = [...]` snippet.

**Output:**

```
Analyzing git history (last 90 days)...

Modules changed 0-2 times (suggest excluding):
  MyApp.Config     (0 commits)
  MyApp.Auth       (1 commit)

Modules changed 3+ times (keep reloadable):
  MyApp.Handler    (14 commits)
  MyApp.Router     (8 commits)

Add to forge.toml:
  [hot-reload]
  exclude = ["MyApp.Config", "MyApp.Auth"]
```

Excluded modules are compiled without dispatch wrappers — functionally identical to a non-hot-reload build.

---

## `forge hot-reload keygen --rotate`

Rotate the ed25519 signing key without server downtime.

```
forge hot-reload keygen --rotate
```

**Steps:**

1. Generate a new keypair, save to `~/.march/ed25519_secret_v<N>.key`.
2. Print the new public key (base64) and instructions:

```
New keypair generated: ~/.march/ed25519_secret_v2.key
New public key: <base64>

To complete rotation:
  1. Update forge.toml: public_key = "<new base64>"
  2. Re-compile your server binary with the new --signing-pubkey:
       forge build --release
  3. Deploy the new server binary (standard restart)
  4. Run: forge hot-reload use-key ~/.march/ed25519_secret_v2.key
```

3. `forge hot-reload use-key <path>` switches subsequent `forge deploy hot` to sign with the new key.

**No dual-key window needed** — the server verifies with the pubkey baked into the binary at compile time. Key rotation requires a server restart to pick up the new pubkey. This is acceptable: key rotation is a rare operational event, not a hot operation.

---

## Effective-Version Endpoint — `VERSIONS_DETAIL`

Extends the existing `VERSIONS` command (returns `name impl_hash` pairs) with activation metadata.

**New command:** `VERSIONS_DETAIL`

**Response:**
```
SLOT <id> <name> <impl_hash> <activated_at_unix_ms> <signer_pubkey_hex>
...
END
```

`signer_pubkey_hex` is the 32-byte ed25519 public key (64 hex chars) extracted from the most recent verified ACTIVATE signature for that slot. Empty if the slot has never been activated (baseline).

`forge deploy hot` already connects and reads `VERSIONS`; `forge hot-reload status` uses `VERSIONS_DETAIL`.

---

## Append-Only Audit Log

Every ACTIVATE that passes signature verification appends one JSON line to `$MARCH_AUDIT_LOG` (default: `${XDG_DATA_HOME:-$HOME/.local/share}/march/audit.jsonl`).

```json
{"ts":1750000000123,"type":"activate","fn":"Server.handle","impl_hash":"a1e8c52...","signer":"abcdef12...","cas_hash":"deadbeef...","result":"ok"}
{"ts":1750000001456,"type":"activate","fn":"Server.handle","impl_hash":"a1e8c52...","signer":"abcdef12...","cas_hash":"deadbeef...","result":"err_sig"}
```

Fields:
- `ts` — Unix milliseconds (server clock)
- `type` — `"activate"` | `"rollback"` | `"migrate"` (actor migration, Phase 5)
- `fn` — function name
- `impl_hash` — the hash being activated
- `signer` — 64-char hex ed25519 public key
- `cas_hash` — artifact hash
- `result` — `"ok"` | `"err_sig"` | `"err_abi"` | `"err_cas_miss"` | `"err_dlopen"`

The log is append-only from the server's perspective. Rotation and shipping to a SIEM are out of scope — that's `logrotate` / standard syslog tooling.

**Implementation:** in `march_reload.c`, after the signature check, before/after `dlopen`.

---

## `forge hot-reload status` — Cross-Fleet Dashboard

```
forge hot-reload status [--env <name>]
```

Opens VERSIONS_DETAIL on each server in the env group (parallel SSH tunnels) and prints a table:

```
Function          node-01           node-02           node-03
Server.handle     a1e8c52 (5m ago)  a1e8c52 (5m ago)  9b3f1aa (2h ago) ← DRIFT
Server.router     c2d4e5f (1h ago)  c2d4e5f (1h ago)  c2d4e5f (1h ago)
```

Flags `← DRIFT` when a server is on a different `impl_hash` than the majority. Exit code 1 if any drift detected.

---

## Implementation Order

1. **Audit log** — pure addition to `march_reload.c`, no protocol change. Easy, high value.
2. **`VERSIONS_DETAIL`** — small protocol extension; only reads state already tracked in `march_dispatch`.
3. **`forge hot-reload status`** — client-side table render using `VERSIONS_DETAIL`.
4. **Multi-env fan-out + `--canary`** — `cmd_deploy_hot.ml` loop over env entries with Lwt concurrency (or sequential with `Unix.fork`).
5. **`forge hot-reload init`** — `git log` parse; pure OCaml, no runtime change.
6. **`forge hot-reload keygen --rotate`** — keypair file naming + `use-key` subcommand.
7. **Third CAS tier** — `march_reload.c` HTTP GET fallback + `forge deploy hot` registry push.

---

## Open Questions

- **Canary health signal** — today the spec uses `PING` liveness. A better signal would be a user-provided HTTP health endpoint polled during the canary window. Defer unless someone asks.
- **Registry auth for `https://`** — bearer token covers the common case; S3 sig4 is the other. Implementing both is ~200 lines each. Start with bearer token only.
- **Parallel SSH in OCaml** — `Lwt` or `Thread`? `forge deploy hot` today is synchronous. Phase 7 needs genuine concurrency for fleet deploy. Use `Thread` (simpler, no Lwt dep in forge yet) with a summary mutex.
