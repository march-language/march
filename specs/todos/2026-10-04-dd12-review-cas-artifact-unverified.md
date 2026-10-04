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
