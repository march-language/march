# Distributed deploys step 12b, second half: certificates and revocations delivered by the control plane

**Landed** 2026-10-01. Design: section 10 "12b" of
`specs/plans/2026-09-28-dd-step12-control-plane-design.md`, D37 (no root keys in the
control plane) and D39 (issuance stays offline with the operator). The first half, live
replacement on a node, is [2026-09-28-dd-step12b-live-cert-replacement.md](2026-09-28-dd-step12b-live-cert-replacement.md);
the control plane it rides on is [2026-09-30-dd-step12a-control-wiring.md](2026-09-30-dd-step12a-control-wiring.md).

## What

- **Release items** (`stdlib/control.march`, `forge/lib/control_release.ml`):
  `cert <node> <certificate text>` and `revoke <token>`, delivered by a new step action
  `do:certs`. They sit after the signed `line` entries and before `drain` in the signed
  text, so the deploy key's signature covers them. `check` takes them structurally: each
  decodes, one certificate per node, and a `do:certs` step exists exactly when items do.
  The leader holds no operator key, so whether a certificate is the operator's, unexpired,
  and names the node it is for is the node's check. A certificate item naming another node
  therefore passes the leader and is refused by the node, which is what the two-node
  scenario provokes. forge keeps items beside the release (`Control_release.items`,
  `signed_text_with`, `sign_with`, `serialize_with`), not in `t`, so `Cluster_deploy`'s
  releases are unchanged. The same text is pinned byte for byte in both suites.
- **The executor.** A `do:certs` step's end state is per node (`want_for`):
  `cert:<serial>` when the release carries that node's certificate, and `rev:<id>` for each
  revocation. `AgentReport` gained `certs` (`certs_text`: the serial the node presents and
  `NodeCert.revocation_id` of every revocation it knows). Two exceptions:
  - The step does not wait for a node one of its revocations cuts off, by name or by the
    serial that node reports (`revoked_by`). Its peers drop it, so it may never report.
  - The step always targets the nodes its certificate items name, member or not
    (`with_item_nodes`). Without this, a release renewing a node the leader had not heard
    from completed at once without it. The scenario's first run hit exactly that.
- **The Agent** (`Control.agent_apply_certs`, over a `CertOps` dictionary). A `do:certs`
  order carries the whole signed release. The node checks, in order:
  - the deploy key's signature (the key its reload server trusts, `HCR_INFO`);
  - that the release is the one the order names;
  - that it is not older than one this node already took certificates from (`cert_floor`,
    or the reload server's release head, whichever is newer).

  It then applies the certificate item for its own node only. It refuses one whose
  certificate names another node, skips one already in use, and otherwise calls
  `ClusterNode.replace_cert` (keeping the node's key). It then applies every revocation
  through `ClusterNode.revoke`, which gossips it and ignores one it knows. A refusal
  answers not-ok, which halts the release, and the reason shows in the report and `STATUS`.
  The wiring (`lib/desugar/control_wiring.march`) does three more things:
  - it saves a certificate it took over the `MARCH_NODE_CERT` file (tmp + rename, from
    the prefetch loop, which holds the root capability), so a restart comes back on it;
  - `STATUS` node lines gained `cert:<serial>`;
  - `replace_cert` now treats the certificate and key already in use as a no-op, reported
    as nothing. Without that, the node's own file watch reading the saved certificate back
    would re-announce it to every peer.
- **forge.** `forge cluster cert NODE ... --deliver HOST:PORT[,...]` and
  `forge cluster revoke ... --deliver ...`, with `--deploy-key` (hex or base64, default
  forge's own) and `--env`. Chosen over a separate `forge cluster rotate`: issuance and
  delivery are one act, and the certificate written to `--out` is byte for byte the one
  delivered. They share `Cluster_deploy`'s client (STATUS, RELEASE, follow), the path
  `forge deploy` uses.
  - `cert --deliver` needs `--node-key`: a release never carries a secret key.
  - Delivery is refused while the head release is still rolling out, since the new release
    would supersede it.
  - It warns when a certificate's node does not report to the control plane.

## Decisions

- **One action, `do:certs`,** for certificates and revocations, not two. A release from
  forge carries one or the other. A combined one (renew and revoke the old serial) works,
  but the revocation can reach a peer before the renewal reaches the node, which drops the
  link once. The docs say to revoke the old serial in a later release.
- **The order carries the whole release**, not per-item signatures. "The node checks both
  signatures" then needs no new signed format: the release's own signature covers the
  items, and each item keeps its operator signature.
- **Replay** is bounded by `cert_floor` in memory and the reload server's head. After a
  restart a replayed older release could put back an older certificate that is still valid
  and unrevoked. The answer to "that certificate must stop working" is to revoke its
  serial, which the node then also refuses through `replace_cert`. Persisting the floor
  needs the Agent role to write a file; it is listed in the step-12 todo.

## Tests

- **Unit** (`test/stdlib/test_control.march`, "certificate items", 11 cases, eval):
  - parse and serialise, and the signature covering the items;
  - the shape checks;
  - the forge byte pin;
  - `want_for` and completion, the revoked node not waited for (by name and by serial), a
    non-member item node waited for;
  - `certs_text`;
  - the Agent: takes its own certificate and every revocation, once (idempotent); does not
    apply another node's item; refuses a certificate naming another node and one signed by
    another operator; refuses an unsigned release, one signed by another key, one that is
    not the release the order names, and a stale one.

  Each was seen failing under a perturbed expectation.
- **forge** (`forge/test/test_cluster.ml`, "delivery (step 12b)"): the pinned item text,
  `--deliver` without `--node-key` refused, the certificate written is the one delivered,
  the revocation token is delivered, the deploy key as hex and base64, endpoint parsing.
- **Two-node** `test/two_node/control_certs` (three nodes in certificate mode, a and b
  candidates):
  - node b is delivered a 40 s certificate and then its renewal;
  - both releases complete, the leader's `STATUS` shows b presenting each serial, a and c
    take each over their links, and b saves the renewal to its `MARCH_NODE_CERT` file;
  - a raw release (`hcr_deploy certs`) carrying a certificate for a that names c halts on
    a with "names ... not this node";
  - `forge cluster cert a --deliver` signed by a second operator key halts on a with "not
    signed by the cluster operator", and a still presents its own certificate;
  - past the short certificate's expiry neither a nor c has seen b die;
  - `forge cluster revoke --node c --deliver` completes, and a and b both report c dead
    with "certificate revoked".

  **Red:**
  - with the stdlib and wiring from before this change, the leader refuses the release
    ("do: expected activate(build), topology or drain, got certs");
  - with an Agent that answers ok without calling `replace_cert`, the first rotation
    release never completes ("did not finish within 120 s").

## Findings

- **A use-after-free in `Control.serialize`, now fixed.** Compiled, its sig line,
  `(if r.signature == "" do "-" else r.signature end)`, released the signature while the
  release still held it. The leader's `ctl_release` serialises a release before taking
  it, so the release it then held had a freed signature. Nothing read it in 12a. A
  `do:certs` order serialises the held release, and:
  - without ASAN the order arrived with an empty `sig` (the node refused it as unsigned);
  - CI's sanitize-gate reported `heap-use-after-free` in `march_string_eq` from
    `Control.serialize` under `Control.order`.

  This is shape 2 of
  [2026-10-01-compiled-record-with-projection-sigsegv.md](2026-10-01-compiled-record-with-projection-sigsegv.md)
  (an `if` returning a borrowed field into a consuming `++`). The compiler side is still
  open there. `serialize` now concatenates the signature where it reads it.
  `test/native/control_serialize_twice` serialises one release three times compiled. It
  fails with the old `serialize` ("second or third: DIFFERENT", "no longer verifies") and
  passes with the new one.
- The leader keeps a node's last failure in its report after a later release succeeds on
  that node (`leader_report` keeps a known failure when a report omits it), so `STATUS`
  still shows `FAILED` from a halted release. It does not halt the newer release, because
  the failure names the old seq. Noted in the step-12 todo.
- In a `describe`-style test module, a top-level `fn` placed between two `describe` blocks
  made the typechecker report every `==` in the file as a missing `Eq` instance, pinned to
  that `fn`. Moving the helpers above the first `describe` fixed it. Filed as a separate task.
