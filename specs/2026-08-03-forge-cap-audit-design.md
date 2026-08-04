# `forge cap inspect` — capability audit of a compiled March executable

**Date:** 2026-08-03
**Status:** design (v2 — supersedes the v1 in this file's git history)

Answer "what can this binary actually do?" for a compiled March executable,
including one you did not build and have no source for.

**v1 of this document was wrong and is retained only in git history.** It
proposed verifying an embedded manifest by scanning the binary for call sites.
Measurement falsified that; §3 records the evidence and §4 the replacement.

---

## 1. What already exists

| Piece | Location | Role here |
|---|---|---|
| `forge cap query` / `coverage` | `forge/lib/cmd_cap.ml` | Source-level cap summary. `audit` joins them. |
| `Typecheck.fn_own_capability_closures` | `lib/typecheck/typecheck.ml` | Per-function OWN cap closure (sig + body + extern). |
| `Cap_lattice` | `lib/caps/cap_lattice.ml` | `normalize` / `cap_subsumes`. Already code-genned into `runtime/march_cap_lattice.c`. |
| `builtin_cap_table` | `lib/typecheck/typecheck.ml:1661` | March builtin name → cap. |
| builtin table | `lib/tir/llvm_builtins.ml:474` | `march_name` → `c_name`. Crossed with the above, gives **cap → runtime symbol**. |
| `Runtime_archive.ensure` | `lib/cas/runtime_archive.ml:136` | Runtime object cache. **`cflags` is already in its key**, so changing compile flags invalidates it automatically. |
| `.hcr_manifest` | `bin/main.ml:3305` | Precedent for per-function `caps=`, but `--compile-so` only. |

Related planned work, deliberately not collided with:
`specs/capability-system-design.md` §8 plans `forge cap diff main..feature/x`, a
*source*-level git-ref diff. Binary-to-binary comparison here is `--baseline`.

---

## 2. What "the binary's capabilities" means

> The union of **OWN** caps (`own_cap_closures`) over functions reachable from
> `main` in post-mono/DCE TIR, `Cap_lattice.normalize`d.

Not `cap_closures` — that folds in module-wide `needs` *and* transitively
imported module needs, which is what made the whole-artifact union app-invariant
and left the hot-deploy gate unable to discriminate (2026-07-04 granularity
revision). Not raw per-function caps — that never answers the question.

**Stronger than `--check`.** Body-scanned caps are WARNING-only
(`specs/todos/2026-07-07-p2-compiler-capabilities-effects-*.md`, F1), so a module
can call `file_read` with no `needs` and exit 0. The inferred closure records it
regardless.

---

## 3. Measured: why static inference from the artifact fails

Three programs, one compiler, one runtime. `lam` uses
`apply1(fn p -> file_read(p), "/etc/hosts")` — an ordinary closure — and runs
correctly.

| | reads a file? | `bl _march_file_read` | `_open` | `_read` | addr-of `file_read` in data |
|---|---|---|---|---|---|
| pure | no | 0 | 1 | 9 | 1 |
| direct | yes | 1 | 1 | 10 | 1 |
| **closure** | **yes** | **0** | **1** | **9** | **1** |

Also measured: undefined/dynamic imports are byte-identical (226 = 226) between
pure and file-reading binaries, and `_march_file_read`, `tls_connect`,
`random_bytes`, `vault_set` are all *present* in a hello-world.

Three detection strategies therefore fail:

1. **Symbol presence** — app-invariant; reports maximum caps for every binary.
2. **Direct call sites** — false negative on closure routing, which is idiomatic
   March. A file-reading program is indistinguishable from hello-world.
3. **Address-takes in data** — app-invariant (1 occurrence in all three).

**Conclusion: you cannot verify a manifest against a fully-linked artifact.**
The runtime is linked whole and its tables reference everything, so binary
content does not discriminate. v1's `--verify` would have printed
`code-consistency: ok` for a binary that reads files — the exact false-assurance
failure §8 names as the primary risk.

---

## 4. The replacement: make the claim true at link time

Stop inferring; change the build so the binary contains only what it uses.

### 4.1 Dead-strip (default for executables)

| | macOS / Mach-O | Linux / ELF |
|---|---|---|
| link flag | `-Wl,-dead_strip` | `-Wl,--gc-sections` |
| function granularity | free (`.subsections_via_symbols`) | needs `-ffunction-sections -fdata-sections` **at object compile time** |
| works on prebuilt objects | yes | **no** |

Measured on macOS — pure control vs. direct vs. closure-routed file read, all
correct:

| | size | `_march_file_read` |
|---|---|---|
| pure | 56,120 | **0** |
| direct | 56,920 | 1 |
| closure | 57,032 | **1** |

Symbol presence succeeds under dead-strip exactly where it failed without it,
**including the closure route**. Four benchmarks (`fib`, `list_ops`,
`binary_trees`, `tree_transform`) produce byte-identical output at 72–79%
smaller.

Verified on Linux (gcc 11 and clang 18): `--gc-sections` *alone* leaves the
function in; adding `-ffunction-sections -fdata-sections` removes it.

This is the security property, not a reporting detail: the code **is not there**.
No manifest edit and no call routing can conjure it back. Under-claiming becomes
self-defeating — removing a capability from the audit requires removing the
functionality.

**Linux hazard.** Until the runtime objects are rebuilt with the section flags,
capability-by-absence silently does nothing on Linux while working on macOS —
a platform-dependent wrong answer. Mitigated by two requirements: the flags go
in `cflags` (already keyed by `Runtime_archive.ensure`), and the audit must
*positively confirm* stripping rather than assume it (§4.4).

**Carve-outs.** Executables only. `--compile-so` and hot-reload builds must not
be stripped: `runtime/march_reload.c:318-351` resolves `__march_init` and
`__migrate_<Actor>` via `dlsym`, which dead-strip cannot see.

### 4.2 Extraction channels, measured

A full `strip` removes `_march_file_read` (50 symbols left) and the binary still
runs. Dynamic-library load commands survive, because the loader requires them.

| channel | survives full `strip` | falsifiable without breaking the program |
|---|---|---|
| embedded manifest blob | yes | **yes, trivially** |
| symbol names | **no** | no |
| dead-strip absence | n/a (a property) | no |
| dynamic library deps | yes | no |
| self-imposed sandbox profile | yes | only upward, and visibly |

### 4.3 The three shipped mechanisms

**C — cap marker symbols (default).** During codegen, the set of runtime
builtins actually referenced in the emitted LLVM module is mapped through
`builtin_cap_table` and emitted as marker globals
(`@__march_cap_IO_FileRead`). Derived from *emitted IR*, not from the
typechecker's claim, so it reflects codegen reality. Portable across
macOS/Linux/WASM, works on Linux without waiting for the object-cache rebuild,
and gives precise March-level cap identity that raw runtime symbols cannot.
Strippable and forgeable by a modified compiler — this is attribution, not the
trust root.

**D — registry notarization (default for registry packages).** `forge publish`
records the source-derived cap set against the artifact hash. `forge cap inspect`
compares a binary's caps to the registry's record. Sound wherever source exists,
which covers how most third-party March code actually arrives — as dependencies.

**B — self-imposed sandbox (opt-in, NOT default).** The binary installs a
seccomp-bpf filter (Linux) or `sandbox_init` profile (macOS) derived from its
cap set before user code runs. The profile is editable, but editing it downward
breaks the program and upward is visible, making it incentive-compatible without
cryptography. Also enables `forge run --enforce`, which imposes the profile
externally and so requires trusting nothing. Opt-in behind `--cap-sandbox`
because it changes runtime behavior and can break legitimate programs.

### 4.4 Confirming the build

The audit must never assume stripping happened. A binary in which *every* cap
symbol is present was almost certainly not stripped and is reported as
`coverage: unstripped build` rather than as "needs everything."

---

## 5. `forge cap inspect <binary>`

Third subcommand in `forge/lib/cmd_cap.ml`.

| Flag | Behavior |
|---|---|
| *(none)* | Human report (§5.1) |
| `--json` | Machine output; `coverage` is a **required** field |
| `--baseline <binary\|json>` | Caps gained/lost vs. a previous release |
| `--deny <cap>` / `--allow-only <caps>` | Exit nonzero on violation, via `Cap_lattice.cap_subsumes` |
| `--allow-foreign` | Required for a gate to pass on a binary with foreign code |
| `--notarized` | Compare against the registry record (D) |

### 5.1 Report

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

build: dead-stripped    notarized: registry-match    coverage: partial (foreign code)
```

### 5.2 FFI is a scope limitation, not a cap row

`IO.Foreign` is **not** a row in the cap table. It gets a section naming the
extern symbols and declaring functions, plus an explicit statement that analysis
stops at the boundary — because a reader who sees it as row 7 of 7 reads "one
more capability" rather than "the list above is no longer complete."

The **gate is fail-closed where the report is informative**: `--deny` /
`--allow-only` fail on foreign code unless `--allow-foreign`, and fail on any
`coverage:` value other than full. Stripping is an *evasion*, not merely a
degradation. `dlopen`/`dlsym` get their own line; `IO.Foreign.Blocking` is tagged
inline.

---

## 6. Manifest

Retained for attribution, **demoted from trust root**. Emitted as an LLVM
constant global `@__march_cap_manifest` pinned with `@llvm.used`, located by
scanning for magic `MARCHCAP\x01<u32 le len><json>`; scanning must find **all**
occurrences and error on multiplicity, or a second planted blob shadows the real
one.

```json
{ "v": 1, "compiler": "…", "source_cas": "<blake3>",
  "build": { "dead_stripped": true },
  "effective": ["IO.Console","IO.FileRead"],
  "declared":  ["IO.FileRead"],
  "witnesses": [{"cap":"IO.FileRead","fn":"IoApp.main","via":"body-builtin:file_read"}],
  "foreign":   [{"symbol":"curl_easy_perform","fn":"Net.fetch","blocking":false}] }
```

`declared` vs `effective` surfaces the F1 gap. No `text_hash`: it is
unimplementable as v1 specified, because the manifest is embedded before clang
links, so the final text section does not exist yet — it would require a
post-link patch step ordered before `Cas.store_artifact`. Dropped rather than
half-built; dead-strip supersedes what it was for.

---

## 7. Threats and honest bounds

| Threat | Covered by |
|---|---|
| Drift — stale/mismatched manifest | dead-strip + marker symbols (derived from emitted IR) |
| Manifest edited in place | dead-strip (symbols contradict it) |
| Lying build (modified compiler) | dead-strip; D where source exists |
| Whole-binary substitution | D (registry), or signing — deferred |
| Effects via FFI / `dlopen` | **nothing** — reported as reduced coverage |
| Hand-written asm / raw syscalls | **nothing** — B, if enabled, still constrains |

Signing remains deferred; see `specs/todos/2026-08-03-forge-wide-artifact-signing.md`.

---

## 8. Primary risk: false assurance

The worst outcome is not a forged manifest. It is a tidy green
`capabilities: IO.Console` that people rely on, sitting on a binary whose real
effects arrive through `extern` C or a `dlopen`. v1 of this document fell into
exactly that trap with `--verify`.

Every choice that looks like over-engineering traces here: the three-verdict
output line, `coverage` as a required JSON field, the fail-closed gate, FFI as a
scope limitation, and §4.4's refusal to assume stripping.

---

## 9. Components

| Component | Location | Responsibility |
|---|---|---|
| Link flags | `bin/main.ml` (~3137, ~3180) | Platform-selected strip flags; `.so`/hot-reload carve-out; `cflags` for Linux sections |
| CAS keying | `bin/main.ml:1798` | Strip mode in `cas_flags` |
| Cap→symbol table | `lib/caps/cap_symbols.ml` (new) | Join `builtin_cap_table` × `llvm_builtins` table |
| Marker emission | `lib/tir/llvm_emit.ml` | `@__march_cap_*` from referenced builtins |
| Manifest builder | `lib/caps/cap_manifest.ml` (new) | Reachability walk; join `own_cap_closures`; serialize |
| Binary reader | `forge/lib/cap_binary.ml` (new) | Symbol + marker + manifest extraction; no object-file parser |
| CLI/rendering | `forge/lib/cmd_cap.ml` | `audit`, `--json`, gates |
| Notarization | `forge/lib/cmd_publish.ml`, `registry_client.ml` | D |
| Sandbox | `runtime/march_sandbox.c` (new) | B, opt-in |

---

## 10. Testing

| Test | Guards |
|---|---|
| Pure binary's `effective` ≠ full lattice | The app-invariance regression, hit twice already |
| Closure-routed file read is detected | The §3 false negative that killed v1 |
| Full benchmark + test suite under dead-strip | Stripping breaks nothing |
| Actor/HTTP/TLS programs under dead-strip | Untested at design time; callbacks may need pinning |
| `.so`/hot-reload build is NOT stripped | `dlsym` breakage |
| Linux build without section flags | Must report `unstripped`, never a cap list |
| Stripped binary | `coverage: limited`, never a clean pass |
| Two planted manifest blobs | Reader errors, does not take the first |
| FFI fixture | `--deny` fails without `--allow-foreign` |

Absence-of-clean-bill-of-health is the property §8 depends on.

---

## 11. Out of scope

Signing; per-capability dynamic libraries (option A — strongest extraction, but
gives up single-binary distribution); WASM/JS targets; reproducible-rebuild
verification; `forge cap diff` over git refs.
