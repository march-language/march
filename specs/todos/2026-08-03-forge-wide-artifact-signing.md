# Forge-wide artifact signing

- [ ] **Sign forge-produced artifacts end to end, reusing the existing ed25519 path.**
  Split out of the `forge cap audit` design
  (`specs/2026-08-03-forge-cap-audit-design.md` §6), where signing was
  deliberately deferred rather than scoped into the capability audit.

  **Why it is its own item.** A signature proves *provenance* ("the holder of key K
  published this artifact"), not *truth* — a publisher whose build pipeline is lying or
  stale produces a valid signature over a wrong manifest. Sorting the cap-audit threats
  by what catches them, signing uniquely covers exactly one: whole-binary substitution.
  That is the generic "did I receive the artifact you published" problem, not a
  capability problem, so it belongs at the distribution layer covering *all* forge
  artifacts rather than as a PKI grown inside `forge cap audit`.

  **What already exists to build on.** `--signing-pubkey` bakes
  `-DMARCH_SIGNING_PUBKEY_HEX` into a server binary at compile time
  (`bin/main.ml:3028`), and `runtime/march_reload.c:792` verifies an ed25519 signature
  on an incoming hot-reload artifact before loading it. The trust root pattern is
  already established: whoever builds the server pins the key. No registry, TOFU, or
  keyring exists today — extending to general artifacts needs a trust-root decision
  (registry-served keys vs. TOFU pinning vs. bring-your-own-keyring), which is the main
  open design question here.

  **Interface already reserved.** `forge cap audit` ships a `signature:` verdict field
  in v1 reporting `n/a`, so wiring this in later is additive and needs no change to the
  audit's output shape.
