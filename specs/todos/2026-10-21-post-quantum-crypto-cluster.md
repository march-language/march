`[P3]` Post-quantum crypto phase 3: hybrid cluster handshake and certificates

Phase 1 (ML-KEM-768 / ML-DSA-65 primitives, `MlKem` / `MlDsa`) and phase 2
(post-quantum TLS key exchange by default) landed:
`specs/progress/2026-10-21-post-quantum-crypto-phase1.md`,
`specs/progress/2026-10-21-post-quantum-crypto-phase2-tls.md`.

Open: node certificates are ed25519 only and the cert-mode handshake's frame
keys come from X25519 alone. Add an ML-KEM share to the handshake IKM and a v2
certificate with an ML-DSA-65 co-signature, with a `require_pq` switch.

Plan: `specs/plans/post-quantum-crypto-plan.md`, phase 3.
