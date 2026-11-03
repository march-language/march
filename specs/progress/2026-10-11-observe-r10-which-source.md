# Observe R10: `WHICH` / `SOURCE`, `Recon.which` / `Recon.source`

**Date:** 2026-10-11
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R10.
**Builds on:** [`2026-10-05-observe-r4b-signed-debug-verbs.md`](2026-10-05-observe-r4b-signed-debug-verbs.md) (the signed debug tier).
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).

## What exists now

- **Key.** The slot's `impl_hash`: the non-transitive `Hash.hash_fn_def` hash
  plus the folded-in bare helpers (`hr_slot_hashes`, `bin/main.ml`), the one
  `WHICH` reports and `forge deploy hot` diffs. The shell's source-identity table
  (`Shell_ident`) is a different, source-level hash and is not the key.
- **Build time.** `hr_store_sources` (`bin/main.ml`), right after
  `hr_slot_hashes`, for every `--hot-reload` build, node and `--compile-so`
  patch. For each slot function it finds the declaration by the function's
  provenance span, using `Shell_ident`'s regions (declaration start to the next
  declaration's start; `Shell_ident.region_text` trims trailing blanks), and
  `Cas.store_source`s the text under the `impl_hash`. An actor's `<Actor>_dispatch`
  has no span of its own and takes its actor declaration (only when exactly one
  actor has that name). Lambdas and helpers (`$`-names) and functions with no
  span get none. It runs before the CAS artifact lookup, so a cache hit still
  stores.
- **Store.** `lib/cas/cas.ml`: `<root>/sources/<2 hex>/<62 hex>`, in the
  project's `.march/cas` and in `~/.march/cas` (the node's own CAS root). Never
  rewritten; at most 256 KiB per function; a malformed hash is ignored. Not
  part of an artifact entry and not collected by `gc`.
- **Upload.** `forge deploy hot` (`Cmd_deploy_hot.upload_sources`), after the
  `.so` upload and before activation: for each function to activate, the new
  hash's text and the replaced hash's text, when this machine has them, by
  `CAS_PUT <impl_hash> <size> kind:source`. Only when the file named by the
  forge process's `$MARCH_DEBUG_POLICY` lists `SOURCE`. A failure is a note, not
  a failed deploy.
- **Node, reload socket** (`runtime/march_reload.c`): `CAS_PUT ... kind:source`
  writes `<cas root>/sources/...`, never `artifacts/` (so nothing a source
  upload carries can be mapped by ACTIVATE). The hash must be 64 lowercase hex,
  the size 1 byte to 256 KiB. `march_sig.c` now owns the CAS root and the source
  path (`march_cas_root`, `march_source_path`).
- **Node, observe socket.**
  - `WHICH <name>` (observe tier, `march_observe_snapshot.c`): `{name, id,
    impl_hash, baseline_hash, patched, epoch, activated_at_ms}` from the
    dispatch table; `not_found` for a name that is not a slot (including a build
    without `--hot-reload`); `bad_args` unless the name is 1-255 bytes of
    `[A-Za-z0-9_.$']`.
  - `SOURCE <sig> nonce:… not_after_ms:… name:<fn>` (debug tier,
    `march_observe_debug.c`): the same `admit` as `STATE` and `CRASHES_FULL`
    (key, arguments, signature, freshness, `$MARCH_DEBUG_POLICY`), audited with
    `"name"`. The name must be a registered slot; the file is opened by that
    slot's current `impl_hash` alone, never by the argument. `no_source` when
    nothing was uploaded for that version.
- **In process.** `Recon.which(intro, name)` -> `Result(FnVersion, String)` and
  `Recon.source(debug, name)` -> `Result(String, String)`
  (`stdlib/recon.march`), through `observe_query`. `Recon.source` sends
  `SOURCE local name:<fn>`: only an in-process caller (`tl_in_process`, set by
  `observe_query`, which user code cannot call) may say `local`, standing for
  `Cap(Actor.Debug)` in place of the signature, the same trust as
  `Actor.inspect_state`. `$MARCH_DEBUG_POLICY` must still list `SOURCE`, and the
  attempt is audited with the signer `in-process`. On a socket, `local` is just a
  malformed request (`bad_args`, there is no nonce). The interpreter's emulation
  answers both verbs `not_found`.

## Tests

- `test/observe_which_source_check.ml` (rule `native_observe_which_source`,
  golden `test/native/observe_which_source.expected`), 44 checks. It builds
  `test/native/observe_which_source_v1.march` as a `--hot-reload
  --signing-pubkey` node and `_v2` as a `--compile-so` patch, starts the node
  under a different `HOME` from the builder's, and runs `Cmd_deploy_hot.run`, the
  function `forge deploy hot` calls (`tunnel:false`; the ssh tunnel is the only
  part not exercised):
  - before the deploy, `WHICH` gives the baseline hash (`patched` false,
    `activated_at_ms` 0) and `SOURCE` the old body, only the one declaration;
  - after it, `WHICH` gives a new hash, `patched` true, the baseline remembered,
    and `SOURCE` the new body, which reached the node's store only through the
    upload; the untouched function keeps its hash and text;
  - gates: no policy, another key, garbage signature, a name changed after
    signing, `local` on the socket, replay, policy dropped mid-run;
  - names: `../../etc/passwd`, `/etc/passwd`, no name, two names, an extra
    argument, an unknown slot;
  - `CAS_PUT kind:source` refuses an upper-case hash, a short one, 0 bytes and
    256 KiB + 1, and stores no artifact;
  - the program's own `Recon.which` / `Recon.source` (in process) before and
    after the policy allows it, and the audit log in order with the function
    name and the `in-process` signer.
- Red controls, by file copy: no build-time store (11 failures: every `SOURCE`
  answers `no_source`), forge's upload disabled (4: the new body is not found
  after the deploy), `SOURCE` skipping signature and policy (7:
  `bad_signature` x3, `policy` x2, `replay`, the audit order). Two unit
  tests also go red under their own perturbations: `Cas.store_source` without its
  hash guard, and `debug_policy_allows` matching loosely.
- `test/test_cas.ml`: `source text round trip`, `bad keys and big text`.
- `forge/test/test_observe_client.ml`: `debug_policy_allows`, `local_source`.
- `test/native/recon_basic.march`: `Recon.which` is `not_found` identically
  compiled and interpreted.
- `test/observe_snapshot_check.ml`: the pinned `HELP` list gains `WHICH` and
  `SOURCE`.

## Notes and limits

- The audit trail for `WHICH` is none (observe tier, like the other counts).
- Source is stored by whoever can reach the reload socket (`CAS_PUT` is
  unauthenticated there, as for artifacts). A planted text could mislead, never
  run, and a deploy overwrites it with the real text. `SOURCE` is the only way to
  read it and is gated.
- The text of a declaration includes comments written just before the next
  declaration. A multi-clause function is whole.
- Not done (filed as
  [`todos/2026-10-11-observe-source-followups.md`](../todos/2026-10-11-observe-source-followups.md)):
  `forge observe --source`, source through the cluster control API, a `gc` for
  `sources/`, and `forge shell` doing a deploy upload for a cross-host baseline.
