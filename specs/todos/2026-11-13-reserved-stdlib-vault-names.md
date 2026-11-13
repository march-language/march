`[P3]` Stdlib cluster tables can be opened by name from user code (2026-11-13)

Found by the ocap phase 2b final review (`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`,
"Pre-existing, not filed by this branch"). The cluster plumbing keeps state in named Vaults:
`node_queue_sinks : Vault(Bytes -> Unit)` (stdlib/node_queue.march, the closures a local
queue writes frames through), `net_kernel_mac_hooks` and `net_kernel_raw`
(stdlib/net_kernel.march). `Vault.open(name)` / `Vault.whereis(name)` accept any string
and let the caller pick the element type, so any `IO.Mut` holder can open these tables,
read or replace what is in them, and steer cluster writes. The threat model files this
under "Handles minted from a name" as a type-safety gap; for these tables it is an
authority gap too.

Expected: names the stdlib reserves (a `__march_` prefix, or a registry of reserved
names) cannot be opened from user code (an `Authority.check`-style refusal, or a
compile-time gate like `@[stdlib_internal]` on a name literal), and the stdlib's own
tables move under the reserved prefix.

Predates ocap phase 2b; not fixed there.
