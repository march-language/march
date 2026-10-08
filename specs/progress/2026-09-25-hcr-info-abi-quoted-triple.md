# HCR_INFO reports the canonical ABI ID

The compile driver passed a quoted target triple to the runtime, and the
runtime stringified it while constructing its HCR ABI identifier. As a result,
`HCR_INFO` reported a different spelling from the patch manifest and forge
had to strip quotes before comparing the two.

The compiler now passes the canonical `Hcr_abi.abi_id` as
`MARCH_HCR_ABI_ID`; the runtime uses that value for both its report and its
post-`dlopen` compatibility check. Forge compares ABI IDs exactly, so malformed
or stale quoted IDs are now rejected instead of normalized.

