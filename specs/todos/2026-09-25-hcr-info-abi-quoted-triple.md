# `[P3]` `HCR_INFO` reports the ABI id with a quoted triple

A cross-built server answers
`HCR_INFO target:linux/arm64 abi:march-hcr-v2;triple="aarch64-unknown-linux-gnu";ptr=8 ...`:
`runtime/march_reload.c` builds `MARCH_HCR_ABI_ID` with
`MARCH_HCR_STRINGIFY(MARCH_HCR_TRIPLE)`, and `bin/main.ml` already passes
`-DMARCH_HCR_TRIPLE="\"...\""` quoted, so the quotes end up inside the id. The
manifest writes `Hcr_abi.abi_id` bare. The runtime's post-`dlopen` check compares two
ids built the same way, so it is consistent; forge's preflight compares without quotes
(`Cmd_deploy_hot.check_identity`, distributed-deploys step 10b). `ptr=8` is also
hardcoded in that fallback.

**Fix.** Pass `-DMARCH_HCR_ABI_ID="<Hcr_abi.abi_id>"` from bin/main.ml (the runtime
already prefers it), or stringify an unquoted triple. Then drop forge's unquoting.
