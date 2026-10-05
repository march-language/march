# Observe R4b: signed debug verbs on the observe socket

**Date:** 2026-10-05
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R4, parts 3-7.
**Builds on:** [`2026-10-05-observe-r4a-inspect-state.md`](2026-10-05-observe-r4a-inspect-state.md) (`Actor.inspect_state`).
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).

## What exists now

- **`runtime/march_sig.c`** (role `core`), shared by the reload server and the
  observe socket:
  - the compiled-in deploy key (`MARCH_SIGNING_PUBKEY_HEX`);
  - `march_sig_verify`;
  - `march_sig_admit`, the freshness check;
  - `march_sig_debug_allowed`, the policy check;
  - `march_audit_open`/`march_audit_close`, the audit log's path and a
    process-wide lock.

  `march_reload.c` now takes its key, `verify_signed_line`, its audit path and
  `pubkey_to_hex` from here. Its inline ACTIVATE checks still call
  `crypto_sign_open` themselves, against the same key.
- **Freshness.** Each request carries `nonce:<16-64 hex>` and `not_after_ms:<t>`.
  The node refuses:
  - an expiry in the past (`expired`);
  - an expiry more than 60 s ahead (`not_after_too_far`);
  - a nonce it has seen (`replay`).

  A 256-slot ring remembers nonces. A slot is reused only once its nonce has
  expired, so a replay is never possible. When all 256 are live, new requests
  are refused (`nonce_ring_full`).
- **`runtime/march_observe_debug.c`** (role `core`): the debug-tier verbs.
  - `STATE <sig> nonce:… not_after_ms:… pid:<p> [timeout_ms:<t>]` returns
    `{pid, state, error}`.
  - `CRASHES_FULL <sig> nonce:… not_after_ms:… [n:<n>]` returns `CRASHES`
    plus each crash's message.

  Checks run in order: key present, arguments, signature, freshness, then
  `$MARCH_DEBUG_POLICY`. The policy file lists the allowed verbs one per line,
  is re-read on every request, and with no file nothing is allowed. Each
  attempt appends a `"type":"debug"` audit line (verb, pid, nonce, signer,
  result).

  `march_observe_snapshot_install` calls `march_observe_debug_install`. A weak
  no-op stands in when a C harness links the snapshot verbs without this file.
- **`STATE` from a non-green thread.** Added
  `march_actor_inspect_external(pid, timeout_ms, &text)` in `march_runtime.c`.
  The R4a inspect request is now a two-field record:
  - field 0 is the green-thread asker's reply-ref, or 0;
  - field 1 is an `inspect_waiter` (mutex, condvar, two references).

  When field 0 is 0, `inspect_reply` copies the rendered text into the waiter
  and signals it. The socket thread waits with a deadline, and whichever side
  drops the last reference frees the waiter. `STATE` refuses to run on a green
  thread (`not_from_a_green_thread`, reachable through `observe_query`).
  Blocking there could wait on the very scheduler the actor needs.
- **forge.** New options on `forge observe`: `--state PID [--timeout-ms MS]` and
  `--crashes-full [-n N | --count N]`. It signs with
  `~/.march/ed25519_secret.key` (`Observe_client.signed_request`, pure), and
  each request is valid for 30 s. Refusals are explained: the clock-skew
  direction for `expired` / `not_after_too_far`, which key for
  `bad_signature`, and the policy file for `policy`.

  The interpreter's observe emulation (`lib/eval/eval_observe.ml`) answers
  both verbs `signing_not_configured`, as a keyless compiled build does,
  rather than `unknown_verb`.

  `forge top`'s and `forge observe`'s `-n` also answer to `--count`; cmdliner
  makes a one-letter name short-only, so `--n` never worked. This was a
  finding from the guide (PR #787).

## Tests

- `test/native/observe_debug.march` with `test/observe_debug_check.ml`, against
  a fresh keypair and a `--hot-reload --signing-pubkey` build:
  - `HELP` tiers;
  - three bad signatures: another key, garbage, and a pid changed after
    signing;
  - no policy entry;
  - a valid `STATE` (`{ n: 5, tags: [x] }`), then its replay;
  - expired, too far ahead, a short nonce, an unknown argument;
  - a dead pid;
  - `CRASHES_FULL` with the message, while `CRASHES` still shows none;
  - a policy edit taking effect at once;
  - the audit lines, in order, with the signer.

  A second leg builds without a key and expects `signing_not_configured`.
- Red control: a verifier that accepts any signature, a ring that records
  nothing and a skipped policy check together turn six checks red
  (`bad_signature` ×2, `policy` ×2, `replay`, the audit sequence).
- The reload server's ACTIVATE harness (`test_reload_activate4_runner`) passes
  in all four modes (plain, `policy`, `policy-all`, `restore`) on the shared
  key and audit code.
- `forge/test/test_observe_client.ml`: the signed line verifies over exactly
  the line without its signature, and the refusal texts.
- `test/observe_snapshot_check.ml`'s pinned `HELP` verb list gains `STATE`
  and `CRASHES_FULL`.
- ASAN/LeakSanitizer (Linux): the signed fixture under `MARCH_SANITIZE=1`
  passes all 17 checks with no errors. One leak per answered `STATE`,
  allocated in `Counter_inspect`, turned out to be an existing `--hot-reload`
  leak in `Show$List.show`. An ordinary handler calling `to_string` on a
  `List(String)` leaks the same 24 bytes, and a build without `--hot-reload`
  does not. Filed as
  [`todos/2026-10-05-hot-reload-show-list-closure-leak.md`](../todos/2026-10-05-hot-reload-show-list-closure-leak.md).
- Live smoke test: `forge observe --state` and `--crashes-full` against a node
  built with a `forge hot-reload keygen` key, and a different key's
  `bad_signature` explanation.

## Deviations from the plan

1. **`MESSAGES` is not here.** Rendering a stuck actor's queue safely needs a
   renderer green thread; see
   [`todos/2026-10-05-observe-messages-verb.md`](../todos/2026-10-05-observe-messages-verb.md).
2. **`STATE`'s actor-side failures are data, not envelope errors**
   (`{"state":null,"error":"timeout"}`): the request was authorised and
   audited as `ok`; only the actor could not answer.
3. **`not_after_ms` is capped at 60 s ahead**, which the plan did not
   specify. Without it, a far-future expiry outlives the 256-entry ring.
4. **No node binding in the signed text.** A request signed for one node is
   accepted by another node with the same key within its 30 s. The verbs are
   read-only; binding the node name is a one-field change if R5's `EVAL`
   wants it.
5. **No A/B run**: the actor loop is unchanged from R4a; the inspect request
   only grew a field.
