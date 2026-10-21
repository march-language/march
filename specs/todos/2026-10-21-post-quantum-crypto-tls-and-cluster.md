`[P3]` Post-quantum crypto phases 2-3: explicit PQ TLS groups, hybrid cluster handshake

Phase 1 (ML-KEM-768 / ML-DSA-65 primitives, `MlKem` / `MlDsa`) landed:
`specs/progress/2026-10-21-post-quantum-crypto-phase1.md`.

Open:
- **Phase 2, TLS:** `runtime/march_tls.c` never sets groups, so hybrid
  `X25519MLKEM768` is negotiated only by OpenSSL >= 3.5 defaults, untested. Set it
  explicitly when available and add a loopback test asserting the negotiated group.
- **Phase 3, cluster:** node certificates are ed25519 only and the cert-mode
  handshake's frame keys come from X25519 alone. Add an ML-KEM share to the
  handshake IKM and a v2 certificate with an ML-DSA-65 co-signature, with a
  `require_pq` switch.

Plan: `specs/plans/post-quantum-crypto-plan.md`.
