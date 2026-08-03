# `forge cap audit` — capability audit of a compiled March executable

**Date:** 2026-08-03
**Status:** design, approved for planning

Answer the question "what can this binary actually do?" for a compiled March
executable — including one you did not build and have no source for — by
embedding an inferred capability manifest at compile time and verifying it
against the binary's own instructions.

---

## 1. Motivation and what already exists

March tracks IO effects in the type system, but that knowledge dies at the
compiler. Nothing survives into a compiled executable, so the strongest
question the toolchain can answer today is a source-level one.

Already present, and reused rather than rebuilt:

| Piece | Location | Role here |
|---|---|---|
| `forge cap query` / `coverage` | `forge/lib/cmd_cap.ml` | Source-level cap summary. `audit` joins them as a third subcommand. |
| `Typecheck.fn_own_capability_closures` | `lib/typecheck/typecheck.ml` | Per-function OWN cap closure (sig + body + extern). The manifest's input. |
| `Cap_lattice` | `lib/caps/cap_lattice.ml` | `normalize` / `cap_subsumes`. Single source of truth, already code-genned into `runtime/march_cap_lattice.c`. |
| `builtin_cap_table` | `lib/typecheck/typecheck.ml:1661` | builtin name → cap. Basis of the runtime-symbol → cap table. |
| `.hcr_manifest` emission | `bin/main.ml:3305` | Precedent: per-function `caps=` already serialized, but only for `--compile-so`. |

This feature serves three consumers with one artifact: trusting a third-party
binary, diffing your own releases, and deploy/CI admission.

### Relationship to planned work

`specs/capability-system-design.md` §8 plans `forge cap diff main..feature/x` —
a *source*-level diff between two git refs. This spec's binary-to-binary
comparison is deliberately named `--baseline`, not `diff`, so the two do not
collide.

---

## 2. What "the binary's capabilities" means

> The union of **OWN** caps over the functions **reachable from `main`** in the
> post-mono/DCE TIR call graph, `Cap_lattice.normalize`d.

Both halves of that are load-bearing, and both are corrections to approaches
that have already failed in this codebase:

- **OWN caps, not `cap_closures`.** `cap_closures` folds in module-wide `needs`
  *and* transitively-imported module needs. That merge is exactly what made the
  whole-artifact union app-invariant and left the hot-deploy capability gate
  unable to discriminate between artifacts (the 2026-07-04 granularity
  revision). `own_cap_closures` omits the merge.
- **Reachable from `main`, not per-function.** Per-function caps never answer
  "what can this program do?"

**This is stronger than `--check`.** Body-scanned caps are WARNING-only today
(open item: `specs/todos/2026-07-07-p2-compiler-capabilities-effects-*.md`, F1),
so a module can call `file_read` with no `needs` and still exit 0. The
*inferred* closure records it regardless, so the manifest reports it. The audit
closes that gap at the artifact level without changing `--check`'s exit code.

---

## 3. Embedded manifest

`--compile` gains cap metadata, embedded rather than sidecar so the binary is
self-describing.

**Mechanism.** An LLVM constant global `@__march_cap_manifest`, pinned with
`@llvm.used` so DCE cannot drop it, holding a magic-prefixed blob:

```
MARCHCAP\x01 <u32 little-endian length> <json>
```

Located by **scanning the file for the magic bytes**. This is a deliberate
choice over a named section: it avoids writing and maintaining both a Mach-O and
an ELF parser, and works identically on both.

**Payload.**

```json
{ "v": 1,
  "compiler": "march 0.x.y",
  "source_cas": "<blake3 hex>",
  "text_hash":  "<blake3 hex of the text section>",
  "effective":  ["IO.Console", "IO.FileRead"],
  "declared":   ["IO.FileRead"],
  "witnesses":  [ { "cap": "IO.FileRead",
                    "fn":  "IoApp.main",
                    "via": "body-builtin:file_read" } ],
  "foreign":    [ { "symbol": "curl_easy_perform",
                    "fn": "Net.fetch", "blocking": false } ] }
```

- `declared` vs `effective` surfaces undeclared body-call effects — the F1 gap,
  made visible.
- `witnesses` make the report actionable rather than a bare list. `via` is one
  of `signature`, `body-builtin:<name>`, `extern:<symbol>`.
- `text_hash` binds the manifest to the code. See §5 for exactly what this does
  and does not catch.

**CAS interaction.** Any opt-out flag (`--no-cap-manifest`) is codegen-affecting
and **must** be registered in `cas_flags` at both sites, or cached binaries will
silently carry the wrong manifest. This failure mode has occurred before.

---

## 4. `forge cap audit <binary>`

New subcommand in `forge/lib/cmd_cap.ml`, alongside `query` and `coverage`.

| Flag | Behavior |
|---|---|
| *(none)* | Human report (§4.1). |
| `--json` | Machine output. `coverage` is a **required** field. |
| `--baseline <binary\|json>` | Compare against a previous release; report caps gained and lost. |
| `--deny <cap>` / `--allow-only <caps>` | Exit nonzero on violation. Uses `Cap_lattice.cap_subsumes`, so `--deny IO` catches `IO.FileRead`. CI gate and deploy admission. |
| `--allow-foreign` | Required for a gate to pass on a binary containing foreign code. See §4.2. |
| `--verify` | Run the code-consistency cross-check (§5). |

`forge deploy hot`'s existing `--grant-cap` admission becomes a caller of the
same comparison logic.

### 4.1 Report shape

```
Capabilities — ./vendor-tool
  IO.Console      println      App.main
  IO.FileRead     file_read    App.load_config

Foreign code (IO.Foreign) — 3 extern declarations
  curl_easy_perform          Net.fetch
  sqlite3_open               Db.connect          [blocking]
  Capability analysis stops at the FFI boundary. The caps above describe
  March code only; what these C functions do is outside the compiler's
  knowledge and is not covered by any guarantee in this report.

signature: n/a    code-consistency: ok    coverage: partial (foreign code)
```

Three independent verdicts on one line, never collapsed into a single boolean.

### 4.2 FFI: scope limitation, not a capability row

`IO.Foreign` is **not** rendered as a row in the cap table. It appears as a
separate section that names the actual extern symbols and the March functions
declaring them, followed by an explicit statement that the analysis does not
extend past the FFI boundary.

The rationale is the primary risk this feature carries (§7): a reader who sees
`IO.Foreign` as row 7 of 7 reads "one more capability," when what it means is
"the list above stops being a complete account."

**The gate is fail-closed where the report is merely informative.** `--deny` /
`--allow-only` fail on a binary containing foreign code unless `--allow-foreign`
is passed. A project that legitimately uses FFI opts in once; nobody gets a
silent green gate on a binary whose effects route through C.

`dlopen` / `dlsym` call sites are reported on their own line, not folded into
the FFI section — dynamic loading is strictly worse than a declared `extern`
because there is no declaration at all. `IO.Foreign.Blocking` is tagged inline,
since it additionally implies an OS thread spawn.

---

## 5. `--verify`: code-consistency cross-check

### 5.1 Why symbol presence does not work

Measured on this branch, comparing a pure hello-world against a
`file_read` program built by the same compiler:

| | pure | file-reading |
|---|---|---|
| undefined / dynamic imports | 226 | **226** (identical set) |
| `_march_file_read` present | **yes** | yes |
| `tls_connect`, `random_bytes`, `vault_set` present | **all** | all |
| total defined symbols | 1080 | 1083 |

The whole C runtime is statically linked into every binary regardless of use.
A symbol-presence scan reports maximum capabilities for every March binary —
the identical app-invariance trap the per-function `caps=` fix already escaped
once. **This approach is rejected on evidence.**

### 5.2 Call sites do discriminate

Direct branch targets, same two binaries:

| | pure | file-reading |
|---|---|---|
| `bl _march_file_read` | **0** | **1** |
| `bl … tls_connect` | 0 | 0 |
| `bl … random_bytes` | 0 | 0 |

The mechanism: disassemble (`otool -tV` / `objdump -d`), collect direct branch
targets, map runtime entry symbols to caps via a table generated from
`builtin_cap_table`.

### 5.3 The noise floor requires a baseline

Also measured: the runtime itself directly calls some cap-bearing entries even
in a pure program — `bl _march_vault_set` ×2 (→ `IO.Mut`) and
`_march_process_argv_init` ×9 (runtime startup). A naive "any direct `bl`" rule
falsely attributes `IO.Mut` to every binary.

**Fix:** subtract a baseline — the cap-entry call-site set of a fixed pure
fixture built by the same compiler and runtime. `cas.ml` already digests runtime
identity, so forge caches one baseline per `(compiler, runtime)` digest and
computes it on demand. Anything above the floor is March-originated.

### 5.4 Why the scan is close to sound

To use a builtin you must reach its runtime entry, and every route bottoms out
in a direct `bl` in March-emitted text — including through closures, since a
first-class builtin compiles to an apply-fn whose body still contains the direct
call. Indirection changes *who* calls, not *whether the instruction exists*.
Hiding a cap therefore requires removing the code that implements it.

### 5.5 Polarity, and the honest completeness bound

Indirect dispatch is invisible to a disassembler, so the scan
**under**-approximates while the manifest **over**-approximates. This asymmetry
is favorable:

- cap in scan but **not** in manifest → **FINDING** (stale, edited, or lying build)
- cap in manifest but not in scan → informational, expected, common

The property `--verify` delivers, stated precisely:

> The manifest is consistent with the code present in the binary. Any manifest
> that under-claims relative to the binary's own instructions is detected.

It cannot see four escapes, which are named in the docs rather than papered
over: inline asm / raw syscalls; `dlopen` + `dlsym`; FFI `extern` (which
self-declares as `IO.Foreign`, so it is *declared unverifiable* rather than
hidden); and a maliciously modified compiler emitting a different runtime ABI
wholesale. None are closable by inspection at any depth.

**Degradation is always explicit, never a silent pass:**

- stripped binary → `coverage: limited (stripped)`
- no manifest → `not a March binary, or built without cap metadata`
- foreign code present → `coverage: partial (foreign code)`

### 5.6 What `text_hash` does and does not catch

It catches drift — a stale manifest, or one lifted from a different binary.

It does **not** catch an in-place edit of the cap list: an attacker who deletes
`IO.Network` from the JSON has not touched the text, so `hash(text)` still
matches. That case is caught by the code-consistency scan, whose entire job it
is. The two mechanisms are complementary and neither is redundant.

---

## 6. Deferred: signing

Signing is **out of scope**, by decision.

A signature asserts "the holder of key K says this manifest belongs to this
binary." It says nothing about whether the manifest is *true* — a publisher
whose own pipeline is lying or merely stale produces a valid signature over a
wrong manifest. Sorting by threat:

| Threat | Caught by |
|---|---|
| Drift — stale or mismatched manifest | `text_hash` |
| Manifest edited in place | code-consistency scan |
| Lying build (modified compiler) | scan, to the limit of §5.5 |
| Whole-binary substitution | **signing only** |

Signing's unique contribution is exactly one threat, and it is the generic "did
I receive the artifact you published" problem rather than a capability problem.
It is better solved once for all forge artifacts — reusing the existing ed25519
path (`--signing-pubkey` bakes `MARCH_SIGNING_PUBKEY_HEX` into a server binary;
`runtime/march_reload.c:792` verifies hot-reload artifacts) — than by growing a
PKI inside `forge cap audit`.

**Action:** file forge-wide artifact signing as its own `specs/todos/` item. The
`signature:` verdict field ships in v1 reporting `n/a`, so adding it later is
additive.

---

## 7. Primary risk: false assurance

The worst outcome of this feature is not a forged manifest. It is a tidy green
`capabilities: IO.Console` that people come to rely on, sitting on a binary
whose real effects arrive through `extern` C or a `dlopen`.

Every design choice above that looks like over-engineering traces to this: the
three-verdict output line rather than a boolean, `coverage` as a required JSON
field, the fail-closed gate, and FFI as a scope limitation rather than a table
row. Getting this presentation right buys more real security than any
cryptography would.

---

## 8. Components

| Component | Location | Responsibility |
|---|---|---|
| Manifest builder | `lib/caps/cap_manifest.ml` (new) | Reachability walk over post-DCE TIR; join with `own_cap_closures`; serialize JSON. Pure, no IO — independently testable. |
| Manifest emission | `bin/main.ml` | Emit `@__march_cap_manifest` global for `--compile`. Register opt-out in `cas_flags`. |
| Manifest reader | `forge/lib/cap_manifest_read.ml` (new) | Magic scan + JSON parse. No object-file parsing. |
| Cross-check | `forge/lib/cap_verify.ml` (new) | Disassembly, baseline subtraction, symbol→cap mapping, verdicts. |
| CLI + rendering | `forge/lib/cmd_cap.ml` | `audit` subcommand, report, `--json`, gates. |

Boundaries chosen so the builder is testable without compiling, and the reader
and cross-check are testable against fixture binaries without invoking forge.

---

## 9. Testing

| Test | Guards against |
|---|---|
| Golden manifests: pure / file-read / network fixtures | Basic correctness |
| **A pure binary's `effective` is not the full lattice** | The app-invariance regression — the one failure mode this codebase has hit twice. Non-negotiable. |
| Forged-manifest fixture (cap deleted from JSON) | `--verify` must report a FINDING |
| Stripped-binary fixture | Must report `coverage: limited`, **never** a clean pass |
| No-manifest fixture (non-March binary) | Must report absence, never a clean pass |
| FFI fixture | `--deny` fails without `--allow-foreign`; report shows the scope statement |
| Baseline staleness | A binary built with a different runtime digest recomputes the floor |

The stripped and no-manifest cases assert on the *absence of a clean bill of
health*, which is the property §7 actually depends on.

---

## 10. Out of scope for v1

Signing and key management (§6); runtime enforcement (the lattice is already in
the C runtime, making this the natural v2); JS and WASM targets; source-hash
reproducibility rebuild; `forge cap diff` over git refs (already planned
separately in `specs/capability-system-design.md` §8).
