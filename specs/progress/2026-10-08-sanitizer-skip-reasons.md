# Two-node sanitizer skips report their reason

The golden sanitizer gate reports the final nonempty line from a two-node
scenario's exit-3 log instead of labelling every skip an unsupported sanitizer
runtime. Empty logs get a neutral fallback. This exposes genuine reasons such
as the hosted-protocol race without claiming to fix that race.

Validation: shell syntax and focused nonempty/empty log extraction checks.
The remaining sanitizer issue stays in
[protocol evolution under ASan](../todos/2026-09-25-protocol-evolve-under-asan.md).
