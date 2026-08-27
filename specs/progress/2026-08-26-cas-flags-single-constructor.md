# CAS cache-key flags built in exactly one place (decomposition Phase 5, Task 5.1)

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 5, Task 5.1
**Files:** `bin/main.ml`

## The hazard

`cas_flags` — the flag list that enters the content-addressed compile cache's key —
was constructed at **two** separate sites in `bin/main.ml`: the source-level early
cache check inside `compile` (keyed on the source digest, before parsing) and the
post-TIR check (keyed on the module's per-SCC impl hashes). A codegen flag added to
one and not the other makes two semantically *different* builds collide on one cache
entry, and the cache then serves the wrong binary. The failure mode is a silently
stale result, not an error — and no standard test suite can see it.

The same duplication also existed for `target_label` (a 10-arm match over
`target_config`, written out twice) — which is likewise part of the cache key — and
for `effective_opt` (the clang `-O` level), which fed *both* the cache key and the
clang command line.

## What was found

The two sites were diffed line-by-line before any edit. Result:

- **The 18-line flag-list expressions were byte-identical.** No flag was present at
  one site and missing from the other, so there was **no live cache-collision bug** to
  fix — the risk was latent, waiting for the next codegen flag.
- The two `cross_sysroot_tag` blocks were semantically identical (only their
  explanatory comments differed in length). The plan anticipated this as the one
  *legitimate* divergence, to be threaded through as an `~extra` parameter; in fact it
  is a pure function of the parsed target, so it moved *inside* the constructor rather
  than becoming a parameter. That is strictly stronger: it cannot diverge at all now.
- The two `target_label` matches were semantically identical (whitespace only).
- **Genuine, legitimate differences (now parameters):** the hash input — `src_hash`
  (source digest) at the early site vs `mod_hash` (concatenated SCC impl hashes) at the
  post-TIR site — and the target binding's name. Both are `~src_hash` / `~target` now.
- **`MARCH_DEBUG_CASFLAGS`** existed at the post-TIR site only. It now lives inside the
  constructor, so *both* layers log their key.

## What changed

Three top-level helpers added above `compile` (after `parse_target`):

- `effective_opt ()` — the clang `-O` level, shared by the cache key and both clang
  invocations, so the cached-under level and the compiled-at level cannot drift.
- `cas_target_label : target_config -> string` — the key's `~target` component.
- `build_cas_key ~target ~target_label ~src_hash : string list * string` — **the** only
  place codegen flags enter the cache key. Computes the cross-sysroot digest, builds the
  flag list, calls `Cas.compilation_hash`, and does the `MARCH_DEBUG_CASFLAGS` print.

Both call sites collapse to a two-line `let (_, ch) = build_cas_key …`.

Net: `bin/main.ml` 5,426 → 5,429 lines (the constructor's doc comment is longer than
the duplication it removed; the point is one edit site, not fewer lines).

## Verification

**Flag-list identity (the method the plan mandates).** The cache key includes the
compiler executable's own digest, so *any* comparison spanning a compiler rebuild
always shows different `ch` values — an artifact-count comparison across builds is
structurally incapable of validating this refactor. So the *flag list* was compared
instead. As a print-only preparatory step the `MARCH_DEBUG_CASFLAGS` eprintf was
copied to the early site, "before" lists captured, then the refactor applied and
"after" lists recaptured:

```
before/after, default flags:      flags=[O2,pmt1024,rtcflags2,capstrip,capstrict]      diff exit 0
before/after, --cap-sandbox --no-trmc --opt 0:
                                  flags=[O0,pmt1024,rtcflags2,capstrip,capsandbox,capstrict]  diff exit 0
```

Byte-identical, at both sites, and flag-sensitive (the second list differs), so the
capture is not vacuous. Cross-target labels also agree across the two sites
(`--target linux/amd64` → `linux-x86_64-gnu-2.36` printed twice).

**The cache property itself, with a value-revealing program.** `--opt 2` vs `--opt 0`
on a deeply self-recursive `sum_to(2000000, 0)`: at `-O2` clang's tail-call
optimization makes it complete; at `-O0` it overflows the stack. So a wrongly reused
entry surfaces as a *wrong answer*, not merely a suspicious hit. Counting entries under
`.march/cas/artifacts-v2/` (cleared first; `artifacts/` is the inert v1 pointer store):

| step | command | entries | run result |
|---|---|---|---|
| 0 | `rm -rf .march/cas/artifacts-v2` | 0 | — |
| 1 | `--opt 2` | 2 | prints `2000001000000`, exit 0 |
| 2 | `--opt 0` | 4 (**distinct**) | exit 138 (stack overflow) |
| 3 | `--opt 2` again | 4 (**reused**, `compiled … (cached)`) | prints `2000001000000`, exit 0 |

`--trmc` (+2 → 6) and `--cap-sandbox` (+2 → 8) are likewise CAS-distinct. Two entries
per key because both cache layers store the artifact.

`cmp` of two freshly linked binaries was deliberately **not** used: on macOS they always
differ by a random `LC_UUID`, which makes it vacuous.

**Standard gates.** `dune build --root . bin/main.exe` exit 0.
`scripts/ir-oracle.sh check` → **IR IDENTICAL across 240 programs** (emitted=240
skipped=3) against a baseline recorded before the first edit — this is a driver
refactor, so emitted code must not move, and it did not. `scripts/run-tests.sh` →
3,161 tests, 11 suites, exit 0.

## Scope note

Phase 5 deliberately does **not** split `bin/main.ml`'s 2,510-line `compile` function:
linear driver code is the friendliest shape to work in — no hidden coupling, read the
window you need. Only the correctness hazard was addressed.
