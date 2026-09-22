# macOS `--cap-sandbox`: `IO.NetListen` is not separate from the other network capabilities

Filed 2026-09-21, alongside the Linux fix
(`specs/progress/2026-09-21-cap-sandbox-linux-netlisten.md`).

The embedded SBPL profile (`bin/main.ml`, `cap_sandbox_define`) emits
`(allow network*)` whenever `holds "IO.Network"` is true, and `holds` is
bidirectional, so a program holding only `IO.NetConnect` gets `network*`,
which includes `network-bind`. Measured by an existing test:
`test/test_cap_sandbox_runtime.ml`'s macOS deny-process fixture holds
NetConnect only and its `sbx_probe_bind` returns 0.

Linux now denies `bind`/`listen` in that case. The macOS equivalent would be
to split the grant (`network-outbound` for NetConnect; `network-bind` /
`network-inbound` only with NetListen). Needs measuring first: which SBPL
operations a NetConnect-only March program (DNS resolution, TLS) actually
requires, and whether `mDNSResponder` lookups go through `network-outbound`
or `mach-lookup`. Keep `test/test_cap_sandbox_profile.ml` in step with forge's
`profile_for`, which folds NetListen into `network*` for the same reason.
