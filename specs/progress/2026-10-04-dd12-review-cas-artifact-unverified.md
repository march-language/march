# [P1] DD step 12: a signed ACTIVATE loads unverified artifact bytes — the CAS never binds bytes to the signed `cas_hash`

**Review:** distributed-deploys step 12 end-to-end security pass (see
`specs/progress/2026-10-04-dd12-security-review.md`). Independently found by two
reviewers.

## What breaks

Design D37 (`specs/plans/2026-09-28-dd-step12-control-plane-design.md`): "the
control plane holds no root keys and cannot forge; a compromised control-plane
node can delay or withhold changes, but can't forge them." This is violated. A
party who can write the CAS — which includes any peer that can reach a
candidate's **unauthenticated** control-API `CAS_PUT`, and any process that can
reach the local reload socket — makes an operator-signed `ACTIVATE*` load and run
arbitrary native code it never signed.

Root cause: the operator's ed25519 signature covers only the text
`"<name> <impl_hash> <cas_hash>"`. Nothing in the pipeline ever hashes the
actual `.so` bytes and checks them against a signed value:

- `CAS_PUT` (`runtime/march_reload.c:1979-2009`) writes the received bytes to
  the path keyed by the client-declared `<hash>` and `rename()`s unconditionally.
  It never computes a hash of the bytes. (Contrast `handle_topology`,
  `runtime/march_reload.c:1191-1196`, which **does** reject a body whose digest
  ≠ the claimed one — the asymmetry is the bug.)
- `activate_items` (`runtime/march_reload.c:795-826`) only does
  `access(path, F_OK)` then `dlopen(path, RTLD_NOW|RTLD_GLOBAL)`. It never
  re-hashes the file. `impl_hash` is stored/echoed/audited but never recomputed
  from the loaded code.
- `cas_hash` is the compiler's *compilation hash* (blake3 over
  impl_hash+target+identities+flags, see the note at
  `forge/lib/cmd_deploy_hot.ml:1393-1406`), **not** a hash of the `.so` bytes, so
  even a content-addressed CAS keyed by `cas_hash` could not detect substitution.
  There is currently no signed digest of the compiled bytes anywhere. forge's own
  comment admits the gap ("Proper manifest/binary skew detection needs a real
  content hash recorded in the manifest … tracked as a follow-up") but frames it
  as a skew nicety; it is a signature-integrity hole.

The control-API `CAS_PUT` verb (`lib/desugar/control_wiring.march:1264-1278`)
relays straight to the same C handler, and the listener
(`ctl_start`/`ctl_api_accept`, `lib/desugar/control_wiring.march:1309-1352`) binds
`INADDR_ANY` with no authentication. The threat model (parent plan section 3) is
"a misbehaving member on a trusted network" — exactly someone who can reach that
port.

## Attack, concretely

1. Attacker reaches a candidate's control port (or the local reload socket) and
   sends `HCR_INFO` to learn the required `target:/abi:/prefix:` identity triple.
2. Attacker compiles a malicious patch `.so` that carries those identity markers
   (public, linked from `runtime/march_hcr_identity.c` like any real patch),
   exports the symbol named by the signed `<name>`, and optionally a
   `__attribute__((constructor))`.
3. Attacker `CAS_PUT`s those bytes under the `cas_hash` the operator's next (or
   current) release references. forge skips its own upload when `cas_check`
   returns `PRESENT` (`forge/lib/cmd_deploy_hot.ml:1407-1411`), so pre-seeding is
   durable; otherwise the attacker overwrites the good bytes (rename replaces).
4. The operator's genuine signed `ACTIVATE*` for `<name> <impl_hash> <cas_hash>`
   arrives (relayed by anyone). The signature verifies — it is the operator's.
   The node `dlopen`s the attacker's bytes: the constructor runs immediately
   (before even the identity check at `:811`), and the published slot then
   dispatches to the attacker's function.

## Evidence

Self-contained, does not run in CI (no dune under `specs/`):

    dune build --root . bin/main.exe test/hcr_deploy.exe
    bash specs/reviews/dd12/repro.sh

Output (full transcript in `specs/progress/2026-10-04-dd12-security-review.md`):

    == cas_probe over the local reload socket ==
    CAS_PUT verdict -> OK aaaaaaaa…aaaa
    CAS_CHECK -> PRESENT
    sha256(payload) = 96a03aa8…  claimed hash = aaaa…   (do not match)
    == api_probe over the unauthenticated network control API (port 29051) ==
    CAS_PUT verdict -> OK bbbb…       (bytes != claimed hash, accepted)
    CAS_CHECK -> PRESENT

A second reviewer drove the full chain in C (built like
`test/test_reload_activate4.c`): an operator-signed `ACTIVATE5` over a `cas_hash`,
with *substituted* bytes staged at that hash, was accepted and the live function
returned the attacker value `1337` instead of the legit `42`
(`RESULT: SUBSTITUTION ACCEPTED — signed cas_hash did not bind the bytes`).

`specs/reviews/dd12/{repro.sh,cas_probe.py,api_probe.py}` are the committed repro.

## Suggested fix (not applied)

Bind the bytes to a signed value. Minimal: `bin/main.ml` writes a
`# so_blake3 <hex>` line into the manifest after linking (the follow-up at
`forge/lib/cmd_deploy_hot.ml:1402-1404`); include it in the signed `ACTIVATE`
message; in `activate_items`, `blake3(file)` and reject before `dlopen` on
mismatch. Additionally make `CAS_PUT` verify received bytes against the key when
that key is a content hash, mirroring `handle_topology`'s `digest_mismatch`;
hashing at `CAS_PUT` also prevents the `dlopen`-constructor-before-identity
execution. Authenticate the control-API write verbs regardless (see the
companion resource-exhaustion and AUDIT_COPY todos).

## Resolution (2026-10-04, fixed)

**Choice: sign the bytes in a new verb, keep the CAS key.** The other option,
making the CAS key the blake3 of the bytes, would let `CAS_PUT` verify every
upload. But the CAS key is the compilation hash everywhere else: the control
plane names artifacts by it (release steps, `NODE_STATE ARTIFACT`, `CAS_GET`
prefetch in `stdlib/control.march` and `control_wiring.march`), and forge's
cache-hit skip uses it. Changing what the key means would also change what an
already signed field means without changing the verb. So the fix follows the
ACTIVATE3-6 precedent:

- **`ACTIVATE7`** (`runtime/march_reload.c`) is ACTIVATE5, or ACTIVATE6 when
  `role_caps:` is present, plus `so_blake3:<blake3 of the .so bytes>` inside the
  signed message (between `epoch:` and `cap_root:`). An older server answers
  `ERR unknown_command` and never loads unverified bytes for it.
- **Verified load, no TOCTOU** (`load_verified`). The node reads the CAS file
  once into memory and hashes those bytes. Only on a match does it write them to
  `<state_dir>/loaded/<so_blake3>.so` (dir 0700, written by no verb; temp +
  rename) and `dlopen` that copy. A copy already there is reused if it still
  hashes right, so one artifact is one image. A mismatch is `ERR artifact_digest`
  (audit `err_artifact_digest`) before any byte is mapped, so a substituted
  `.so`'s constructor never runs. The same path serves single activations,
  `COMMIT_BATCH` and replay.
- **Replay**: a v7 entry whose CAS bytes no longer hash to its signed digest is
  skipped (`err_restore_digest`) and the function stays on the base build.
- **CAS verbs**: `CAS_CHECK <hash> so_blake3:<hex>` answers PRESENT only for those
  bytes, so forge re-uploads a pre-seeded or stale artifact; that defeats durable
  pre-seeding, since forge used to skip the upload on PRESENT. `CAS_PUT <hash>
  <size> so_blake3:<hex>` refuses other bytes (`ERR digest_mismatch`, nothing
  stored). Both still accept the old form, so the control plane's prefetch relay
  and older clients work unchanged. Upload verification protects against
  corruption; the security boundary is the signed digest at load. A CAS writer
  can still replace bytes after forge's upload and so delay a deploy (`ERR
  artifact_digest`), which D37 allows ("delay or withhold, not forge").
  Authenticating the control API's write verbs is a separate todo, in another
  session.
- **forge** (`cmd_deploy_hot.ml`) computes `artifact_digest so_path` once, sends
  it on CAS_CHECK/CAS_PUT, and signs it in `build_activate7_lines` for every
  capability-aware deploy, inside the SEQ release wrapper as before.
  `Cluster_deploy.upload` sends the digest. `Control_release`'s recorder accepts
  the digested CAS_CHECK and records ACTIVATE7.

**Old-format lines** (ACTIVATE through ACTIVATE6 sign no digest): refused with
`ERR artifact_digest_required` once the node holds a release or under
`MARCH_HCR_REQUIRE_RELEASE=1`, wrapped or not. This is the same sticky rule as
`release_required`. Before a node's first release they are accepted as before.
`--no-cap-gate` still sends ACTIVATE3, so it only works against such a node.

**Persisted old-format entries: a fresh deploy is required.** They cannot be
re-verified against the bytes, because no signed digest of those bytes ever
existed. They are replayed only where a live unbound line would be accepted, and
skipped (`err_restore_no_digest`) on a node holding a release or requiring one.
The function comes back on its base build until the next (v7) deploy.

**Tests.** `test/test_reload_activate4.c` (default, policy, policy-all) runs the
review's repro. `hcr_evil.so` (same exports and identity markers, returns 1337,
and its constructor drops a marker file) is stored under the cas_hash of a
signed ACTIVATE7 for `hcr_stub.so`. The activation is refused singly and in a
batch, the marker never appears, and the baseline stays live. The test also
covers: the signature binds so_blake3; the digested CAS_PUT/CAS_CHECK; a good
activation loads the private copy; a later substitution is still refused; and,
after a release, a wrapped ACTIVATE5 gets `ERR artifact_digest_required`.
Restore mode phases 12-15 cover an old-format entry not replayed under a
release, a v7 entry replayed, and a v7 entry whose CAS bytes were replaced not
replayed. `test/two_node/control_artifact_digest` covers the same through the
unauthenticated control API on a real compiled 3-node cluster: release v1 to v2,
then `CAS_PUT` a v666 patch of the same build over v2's artifact on a
candidate, then restart it. Result: `RESTORED entries:0 skipped:1`,
`err_restore_digest`, and the node is back on version 1, never 666.

**Proved red.** With the activation and replay checks disabled, all four C
modes fail: the attacker's constructor ran and 1337 was live, or the restart
replayed the substituted bytes. The scenario fails with `RESTORED entries:1`.
Disabling the sticky rule fails the release and phase-12 checks.
