`[P1]` Hot reload: a patch that flips a parameter's borrow mode passes the sig_hash gate (UAF or leak)

Found by the HCR Phase 0 spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`,
experiments E2 and E2'; prototype in `specs/spikes/2026-10-13-hcr-phase0/`).

## Symptom

Borrow inference (`Borrow.infer_module`) is whole-program, so a running caller
was compiled against the borrow mode of the callee version it was built with.
A patch whose new body turns a borrowable parameter (String, List, any ADT;
`Kind.borrowable_of`) from borrowed to owned releases a reference the caller
still holds. ASan on macOS and Linux reports a heap-use-after-free, with the
free in the patch's `Handler.count` and the use in the base's
`march_incrc`. The reverse flip leaks one reference per call (LSan: 40 000
allocations over 10 000 calls). Records and tuples are always owned
parameters, so they are not affected.

`forge deploy hot` compares `sig_hash` (`Serialize.serialize_fn_sig`, the type
signature only). Both versions of the reproducer's `Handler.count` have
`sig_hash bd9fc78c…`, with different borrow modes, so the gate accepts the patch.

```
specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v1 v3_owned     # UAF
specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v3_owned v1     # leak
```

## Direction

Fold each parameter's final borrow mode (the map Perceus used) into the hash
the gate compares, as `sig_hash` or as a separate `abi_hash` in the manifest
and `ABI_QUERY`. Then a flip is an ABI change, and the existing rule (every
caller of a sig-changed slot ships in the same deploy) makes it safe. This has
no runtime cost. The alternative, forcing every slot parameter owned under
`--hot-reload`, costs an inc/dec per borrowable argument per call.

## Fixed 2026-10-13

### Cause

A dispatch slot published, and the `.hcr_manifest` listed, the CAS `sig_hash`
(`Serialize.serialize_fn_sig`: parameter and return types only).  Borrow modes
come from the body, so a mode flip kept the hash and passed every check.  A
second hole made it worse: the reload server staged every activated version
with `sig_hash = NULL` (`activate_items`), so after any hot deploy `ABI_QUERY`
reported `(none)` for that slot and the next deploy could not be compared with
the running version at all.

### Fix

- **Compiler.** `Contract_pipeline.result` now exposes the converged
  `borrow_map` Perceus placed RC against.  Under `--hot-reload` only,
  `bin/main.ml` (`hr_abi_sigs`) computes each function's slot ABI hash,
  `March_cas.Hash.hcr_sig_hash ~sig_hash ~modes` =
  BLAKE3(`"march-hcr-slot-sig-v1\000" ^ type sig_hash ^ "\000" ^ modes`), with
  `modes` one char per parameter (`b`/`o`, `-` when not inferred).  It is what
  the baseline passes to `march_dispatch_publish` (`Llvm_toplevel`'s `hr_setup`,
  new `?hr_sig_hashes`), the manifest's sig_hash column, and a new
  `@__march_hcr_sigs` table (`"<name> <hash>\n"` per slot) a `--compile-so`
  patch exports.  The manifest line also carries `tsig=<type hash>` and
  `modes=<modes>`.  The type-only hash is unchanged everywhere else (RPC
  admission, `remote_ref_hashes`, the CAS, `--dump-impl-hashes`).
- **What is in the hash, and why only that.** Parameter modes are the only
  ownership fact of the boundary convention that varies per function: a
  return is always owned (+1 to the caller, `Borrow`'s "returned = owning
  use"), a closure call always consumes its arguments and a Float crosses
  boxed and stays the caller's (`Clo_flags`), and the `$clo_wrap` trampoline
  that reads `Clo_flags`' extra "unused erased" bit calls its own binary's
  symbol directly, never through a slot, so it never crosses versions.
  Representation (unboxed aggregates, records) is already in the type hash.
- **Runtime.** `activate_items` (runtime/march_reload.c) reads the patch's
  `__march_hcr_sigs` line for each activated name (`patch_sig_hash`) and stages
  it as the version's sig_hash, so `ABI_QUERY` reports the running version's
  ABI after a deploy and after a restart's patch-stack replay.
- **forge.** `Cmd_deploy_hot.mode_changes` recognises a mode-only change: when
  the server's slot hash differs from the patch's, it hashes the patch's
  `tsig=` with every other mode string of that length (at most 2^16) and finds
  the running modes.  `run` then refuses the deploy before activating
  anything, whatever the callers and the epoch, with
  `mode_change_refusal`: "a hot deploy cannot change a boundary function's
  parameter borrow mode: parameter 1 of count changed from borrowed to owned.
  ... Deploy this build with a restart, or keep the mode ...".  A type change
  (no mode string matches) goes through the coordinated-upgrade gate as before.
- **Why refuse even with every caller in the deploy.** The todo's direction
  assumed the coordinated-upgrade rule makes a flip safe.  It does not: a
  flip changes every caller's own RC around the call, so the callers are
  always in the patch and the rule is always satisfied, yet a caller frame
  that is already running keeps running old code.  Measured with the first
  version of this fix (which only refused uncovered callers): `count` and
  `serve` activated together ("Coordinated upgrade: sig_hash changed, all
  callers covered"), and the server died with SIGSEGV 2 s later, because
  `serve`'s loop runs on the compiled `main`, which always follows the newest
  code.  The same reasoning applies to a type change; that is filed
  separately (`specs/todos/2026-10-13-hcr-coordinated-sig-change-running-caller-frame.md`).

### Upgrade behaviour (existing deployments)

The HCR ABI id went from `march-hcr-v3` to `march-hcr-v4` (`Hcr_abi.runtime_abi
= 4`), following the v2 -> v3 precedent (actor-message tags).  A server built
by a pre-fix toolchain publishes type-only hashes and records none for its
patches, so nothing a v4 patch carries can be checked against it.  The first
`forge deploy hot` after upgrading is refused by the HCR_INFO identity
preflight, before any upload, with a dedicated message
(`check_identity`: "the running server was built by an older March toolchain
(HCR ABI march-hcr-v3;...) than this patch (march-hcr-v4;...). The hot-reload
ABI changed in between (... signature hash covers its parameters' borrow
modes ...), so this server cannot take hot patches from this toolchain, and
nothing was deployed. Restart the server once on a base build from this
toolchain (a cold deploy); hot deploys work again after that").  The
runtime's own post-dlopen identity check (`march_hcr_patch_identity_ok`)
refuses the same patch (`ERR identity abi mismatch`) if an older forge sends
it anyway.  The reverse (a v3 patch into a v4 server) says to rebuild the
patch with the server's toolchain.  `forge deploy --plan` already plans a
restart on an HCR ABI change (`Deploy_plan`, "HCR ABI ... -> ...").  So an
operator is never silently stuck and no ABI mismatch is silently accepted:
one cold restart per server, then hot deploys resume.  A forge-local manifest
baseline written by the old toolchain only feeds the capability gates and the
plan, and is replaced by the next successful deploy.

### Tests

- `test_stdlib_suite`, adversarial-regressions "HCR: a patch that flips a
  parameter borrowed->owned is refused; body-only and unchanged builds
  deploy" (`test_hcr_borrow_flip_refused_end_to_end`): a real compiled
  `--hot-reload Main` base and three `--compile-so` patches deployed through
  `Cmd_deploy_hot.run ~tunnel:false`.  The unchanged build deploys nothing;
  the borrowed->owned patch is refused against the baseline, with the
  parameter named; a body-only patch deploys and `ABI_QUERY` then reports
  its sig_hash (not `(none)`); the flip is refused again against that
  patched slot; the server is alive at the end.
  **RED** with the pre-fix sources restored by copy (compiler, runtime,
  forge lib; the test unchanged): `FAIL the borrowed->owned patch was
  ACCEPTED against the baseline` (`activated: serve`, `activated: count`).
  **GREEN** with the fix.
- `forge/test/test_reconcile.ml`, identity group: "a newer toolchain's patch
  into an older server: refused, restart once" (`check_identity` v4 patch vs
  v3 server and the reverse, plus `run` against a fake server answering an
  older ABI: refused, only `HCR_INFO` reached it) and "a parameter
  borrow-mode change is recognised and named" (`mode_changes` both directions,
  no change, a type change, a manifest without `tsig=`/`modes=`, the manifest
  fields).
- By hand: a base built by the pre-fix compiler (v3) and a body-only patch
  from the new one: `HCR_INFO ... abi:march-hcr-v3`, deploy refused with the
  upgrade message, server alive; the same base rebuilt by the new compiler:
  the same patch deploys ("1 function(s) activated").
- IR: `--emit-llvm --opt 2` without `--hot-reload` is byte-identical old vs new
  for `bench/list_ops`, `bench/tree_transform`, `bench/binary_trees` and the
  fixture above (private HOME each, same stdlib); with `--hot-reload` the only
  difference is the two `@.hr_sighash<N>` constants.
- The spike harness (`specs/spikes/2026-10-13-hcr-phase0/run.sh`) swaps
  in-process through `swap_shim.c`, with no forge and no gate, so
  `run.sh ... v1 v3_owned` still crashes by construction.  With this
  compiler the two patch manifests show the change: both `Handler.count`s
  keep `tsig=bd9fc78c…`, v1 has `modes=b` and sig_hash `b140106e…`,
  v3_owned `modes=o` and `b1b42cdf…`.
- Also green: `scripts/run-tests.sh -q`; the HCR group of
  adversarial-regressions (39-48); `test_hot_reload`, `test_hcr_abi`, the C
  runners `test_hcr_identity`, `test_reload_activate4`,
  `test_hcr_migrate_order`; forge `test_forge`, `test_reconcile`,
  `test_deploy_plan`, `test_hcr_manifest_diff`, `test_deploy_e2e`,
  `test_upgrade_from`; two-node `hcr_new_code_session`, `hcr_role_policy`,
  `hcr_remote_msg_epoch`, `protocol_evolve`, `protocol_expand_contract`,
  `control_artifact_digest`, `control_forge_deploy`, `control_plane`.
  `hcr_role_policy` greps a manifest line for `caps=...$`, so `tsig=`/`modes=`
  go before `caps=`, which stays the last field.
