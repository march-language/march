`[P3]` Inline refcount fast path

Every RC op in compiled code is an out-of-line call into the runtime, and because
compiled `main` runs on a scheduler worker it always takes the atomic branch.
Inlining the fast path measured +14% on `bench/list_ops.march` and +2% on
`tree_transform`/`binary_trees` (M3 Max, 2026-09-30); atomic vs non-atomic made no
difference.

Spec: `specs/plans/2026-09-30-inline-rc-fast-path.md`. `internal alwaysinline`
fast paths behind one rename point, exported trace state, a new
`march_rc_dec_slow` runtime helper; off for wasm (whose RC entries are no-ops),
sanitizer builds, and `MARCH_NO_INLINE_RC=1`. Must be measured on x86 Linux
before merge.
