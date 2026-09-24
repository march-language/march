# Distributed deploys step 11a: node certificates, cert handshake, per-frame MAC, revocation

**Plan:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
section 3 (Identity, Threat model), 7.4, II.9, D3, D4. The authorization half
(11b: the two-way role check, raw-send denial) is still open:
[../todos/2026-09-22-dd-step11-certificates-segregation.md](../todos/2026-09-22-dd-step11-certificates-segregation.md).

## 1. Certificates

- **Crypto builtins.** `ed25519_seed_keypair(seed)`, `ed25519_sign(sk, msg)`,
  `ed25519_verify(pk, msg, sig)`, `x25519(scalar, point)`, all over `Bytes`.
  Native: `runtime/march_nacl.c` over the vendored `runtime/tweetnacl.c`, which
  gained `crypto_sign_seed_keypair` and TweetNaCl's `crypto_scalarmult`
  (X25519, the same radix-2^16 field code the ed25519 half uses). Interpreter:
  `lib/eval/eval_builtins.ml` through `lib/ed25519` (the OCaml bindings forge
  already used, which link the same C). A wrong-length argument returns empty
  Bytes (verify: `false`), never an abort; `x25519` also returns empty Bytes for
  an all-zero result (a low-order peer point). Checked against RFC 8032 section
  7.1 tests 1-2 and RFC 7748 sections 5.2 and 6.1, natively and interpreted.
- **Runtime manifest.** `tweetnacl.c` moved from role `hcr` to `core`+`jit`
  (it was skipped under `--compile-so`; the builtins need it everywhere), and
  `march_nacl.c` is new (`core`, `jit`). The wrappers are a separate file
  because `tweetnacl.c` is also compiled standalone into `lib/ed25519` and C
  test harnesses with no March runtime to link.
- **`NodeCert`** (`stdlib/node_cert.march`): `Cert { node, roles, flags,
  not_after, issuer, pubkey, serial }`; canonical MessagePack body; signed form
  `[Bin(body), Bin(signature)]`, base64 as text; `verify(signed, operator_pub,
  now)`; signed revocations (by serial, or by node with an empty serial).
  SPIFFE-style URIs: `spiffe://<td>/pool/<pool>/node/<name>` and
  `spiffe://<td>/operator/<16 hex of the operator key>`.
- **Deviation from the requested record:** two fields were added to the five
  asked for. `pubkey` (hex of the node's ed25519 public key) is what the
  handshake's proof of possession checks against, and `serial` is what a
  revocation names. `not_after` is unix seconds, inclusive.
- **`forge cluster keygen | cert | revoke`** (`forge/lib/cmd_cluster.ml`,
  registered in `forge/bin/main.ml` and `known_builtin_names`). The operator
  key is its own file (`operator.key`, 0600), not the hot-reload deploy key
  (plan section 3: separate keys). `cert` writes `<node>.key` and
  `<node>.cert`; `--seconds` exists for short-lived certificates in tests;
  `--node-key` renews with an existing key.
- **Byte compatibility** between forge's OCaml MessagePack encoder and
  `Msgpack.encode` is pinned by one vector asserted in both
  `test/stdlib/test_node_cert.march` and `forge/test/test_cluster.ml`
  (perturbing one digit of the March copy fails the test).

## 2. The certificate handshake

- **`ClusterAuth.Auth = Secret(String) | Certified(NodeCert.Credentials)`**, and
  `NetKernel.handshake_auth(fd, me, auth, nonce, role, addr, timeout_ms)`
  returning `NetKernel.Authed { identity, role, addr, cert, mac }`. The old
  entry points (`handshake`, `handshake_role`, `handshake_addr`) are
  `handshake_auth` with `Secret`.
- **Certificate mode.** The hello gains a seventh element
  `["cert1", Bin(signed cert), Bin(ephemeral X25519 key)]`; a shared-secret
  hello is byte-identical to before. Each side checks the peer's certificate
  (`Handshake.verify_peer_cert`: operator signature, `not_after`, the node's
  revocation predicate, the URI's node name equals the hello's name, and the
  hello's node id is `NodeIdentity.name_id(name)`), then sends an ed25519
  signature over the PEER's nonce and the transcript
  (`ClusterAuth.transcript`: both hellos' bytes, ordered by nonce) in place
  of the HMAC proof, and verifies the peer's under the certificate's key.
- **Modes do not mix.** `Handshake.check_mode`: a certificate node refuses a
  shared-secret hello, and a shared-secret node refuses a certificate hello,
  each naming the variables to set. A pre-11a node cannot decode a
  certificate hello ("malformed hello").
- **Reflection closed.** A peer whose nonce equals ours is refused in both
  modes. Before this, a shared-secret node accepted an attacker that sent its
  own hello back and then its own proof back (the proof is an HMAC of the
  nonce the node itself issued).
- **Where certificates are kept.** `ClusterConn.connect_split_auth` /
  `accept_split_auth` return the peer's certificate and remember it
  (`ClusterConn.peer_cert(node_id)`). `ClusterNode` carries it from the dial
  and accept tasks to the node (`Accepted`/`Dialed`), keeps it in the core
  (`CnState.certs`, `core_peer_cert`) and mirrors it for
  `ClusterNode.peer_cert(c, node_id)` through the `ClusterOps` dictionary
  (D35; `ops_stub` panics for it like every other field).
- **Config.** `CnConfig.auth` (default `Secret(secret)`); `config_from_env`
  switches to certificate mode when `MARCH_NODE_CERT` is set, requiring
  `MARCH_NODE_KEY` and `MARCH_CLUSTER_OPERATOR_PUBKEY`; each value may name a
  file. `ClusterNode.credentials` checks the node's own certificate at
  startup (operator signature, expiry, its name, its key).
- **Security events.** `ClusterNode.on_security_event(c, f)` reports refused
  handshakes (`HandshakeRejected(who, why)`); before, a dial or accept that
  failed its handshake was silent.
- **A dial now checks both connections reach the same node** (ClusterNode's
  `dial` and `connect_split_auth`); before, the data connection's peer was
  never compared with the control connection's.
- **Deviation:** node ids are still `derive_id("pk-" ++ name)`, not the hash
  of the node's real key. Changing that would move every node id (topology
  ranking, tests). The certificate binds the id through the name instead.
- **Found on the way (pre-existing, not fixed here):** the bare `sha256`
  builtin is typed `Bytes -> Bytes` but returns a hex String on both backends,
  and a compiled program that uses its result as Bytes dies with SIGBUS. The
  transcript uses `hmac_sha256_bytes` under a fixed label instead.
