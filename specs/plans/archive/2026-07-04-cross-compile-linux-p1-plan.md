# Cross-Compile to Linux — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From macOS, cross-compile pure-compute March programs to runnable dynamic-glibc Linux binaries for both `linux/amd64` and `linux/arm64`, using `zig cc`, and prove correctness by running the differential-oracle corpus on the cross-built binaries under Docker.

**Architecture:** March already emits textual LLVM IR with a parameterized `target triple` and shells out to a C compiler — exactly how the WASM target cross-compiles. P1 adds Linux cross variants to the `target_config` enum, routes their link step through `zig cc -target <t>` instead of host `clang`, replaces the build path's host-OS/host-arch assumptions with target-derived decisions, and extends the on-`main` differential oracle (`test/test_oracle.ml`) with a third "cross-compile → run under Docker → diff against interpreter" executor.

**Tech Stack:** OCaml 5.3 (compiler + forge, dune), LLVM/clang textual IR, `zig cc` (bundled clang + glibc sysroots), Docker (linux/amd64 + linux/arm64), the C runtime in `runtime/*.c`.

## Global Constraints

- **Scope P1 = pure compute only.** No TLS/OpenSSL, no zlib/compression, no HTTP server, no actors-over-network, no hot-reload `.so`, no FFI cross. Those are P2/P3. The P1 deliverable is: the deterministic differential-oracle corpus (`bench/`, `examples/`, `specs/lang/golden/`, minus the existing skip allowlist) cross-compiles and produces byte-identical stdout to the interpreter.
- **Host builds must be unchanged.** Every change is gated on the target being a Linux cross variant; `--target native` (the default) must produce a byte-identical command to today. Verify by diffing behavior, not just reading code.
- **Default glibc floor = `2.31`** (Ubuntu 20.04 / Debian 11). Hardcoded in P1; the configurable `--glibc` flag is deferred to a later phase.
- **Target arch/OS decisions must be total functions over `target_config`** so OCaml's exhaustiveness warning forces every new call site to handle the Linux variants — no silent host fallback.
- **`zig` is a new external dependency.** If absent when a cross target is requested, fail with an actionable install hint (`brew install zig`), never a raw `zig: command not found`.
- **zig target strings:** `x86_64-linux-gnu.2.31`, `aarch64-linux-gnu.2.31`. **LLVM triples:** `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`.
- **forge target aliases:** `linux/amd64` (≡ `linux/x86_64`), `linux/arm64` (≡ `linux/aarch64`).
- Build with `dune build` (opam switch `march`; `dune`/`opam` already on PATH — no `eval $(opam env)`). Run the dev compiler as `./_build/default/bin/main.exe`. Never pipe `march --compile` output (redirect to a file, judge by `$?`).
- Commit with explicit paths (no `git add -A`/`.`), no Co-Authored-By lines.

---

## File Structure

- `lib/tir/llvm_emit.ml` — add `arch` type + `LinuxGnu` variants to `target_config`; extend `target_triple`/`target_ptr_size`/`target_ptr_ty`/`target_int_ty`/`is_wasm_target`/`is_wasm32`. Add `target_arch`, `target_is_linux`, `zig_target` helpers here (they belong with the target model).
- `bin/main.ml` — extend `parse_target`; extend the cache `target_label` match; replace the host-probe flag logic (`-msse4.2`, `so_flag`, `rdynamic_flag`, `reload_ldl`, `openssl_flags`, `compress_flags`) and the literal `"clang"` driver in the final-link command with target-derived values; trim the cross runtime source set.
- `forge/lib/cmd_build.ml` — accept the `linux/*` aliases, normalize to the compiler flag, per-target output dir, `[ffi.rust]` cross guard, zig-discovery hint.
- `forge/bin/main.ml` — document the new targets in the `--target` flag help.
- `test/test_oracle.ml` — introduce an `executor` abstraction; add the `CrossCompiledLinux` executor; add an opt-in cross sweep gated on `MARCH_ORACLE_CROSS`.
- `specs/todos.md`, `specs/progress.md` — record P1 completion.

---

### Task 1: Add Linux cross variants to the target model

**Files:**
- Modify: `lib/tir/llvm_emit.ml:166-205`
- Modify: `bin/main.ml:566-576` (`parse_target`), `bin/main.ml:1152-1157` (cache label)

**Interfaces:**
- Produces: `type arch = X86_64 | Arm64`; `LinuxGnu of { arch : arch; glibc_min : string }` added to `target_config`; `val target_arch : target_config -> arch option`; `val target_is_linux : target_config -> bool`; `val zig_target : target_config -> string option` (e.g. `Some "x86_64-linux-gnu.2.31"`). `parse_target "linux/amd64"` returns `LinuxGnu { arch = X86_64; glibc_min = "2.31" }`.

- [ ] **Step 1: Write the failing test**

Create `/tmp/xc_triv.march`:
```march
fn main() do
  println("hello from march")
end
```
Create the test script `/tmp/xc_task1.sh`:
```bash
#!/bin/sh
set -e
M=./_build/default/bin/main.exe
for t in linux/amd64 linux/arm64; do
  out=$("$M" --compile --target "$t" /tmp/xc_triv.march -o /tmp/xc_out 2>&1 || true)
  if echo "$out" | grep -q "unknown target"; then
    echo "FAIL: $t rejected as unknown target"; exit 1
  fi
done
echo "PASS: both linux targets parse"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build bin/main.exe 2>/dev/null; sh /tmp/xc_task1.sh`
Expected: `FAIL: linux/amd64 rejected as unknown target` (parse_target currently `exit 1`s with "unknown target").

- [ ] **Step 3: Add the `arch` type and `LinuxGnu` variants**

In `lib/tir/llvm_emit.ml`, replace the `target_config` definition (lines 167-172):
```ocaml
(** Target architecture for native/cross builds. *)
type arch = X86_64 | Arm64

(** Compilation target. *)
type target_config =
  | Native          (** Host-native binary (arm64-apple-macosx, x86_64-linux, etc.) *)
  | LinuxGnu of { arch : arch; glibc_min : string }
      (** Cross target: dynamic glibc Linux, e.g. x86_64-unknown-linux-gnu *)
  | Wasm64Wasi      (** wasm64-wasi — 8-byte pointers, WASI preview *)
  | Wasm32Wasi      (** wasm32-wasi — 4-byte pointers, WASI preview *)
  | Wasm32Unknown   (** wasm32-unknown-unknown — browser, no WASI *)
  | Js              (** ES module output — no LLVM, no clang *)
```

- [ ] **Step 4: Extend the total functions over `target_config`**

In `lib/tir/llvm_emit.ml`, update each match to add the `LinuxGnu` case (the compiler will warn on each until you do):

`is_wasm_target` (line 174):
```ocaml
let is_wasm_target = function
  | Native | LinuxGnu _ | Js -> false
  | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown -> true
```
`is_wasm32` (line 178): add `| LinuxGnu _` to the `false`/`_` arm (leave as `| _ -> false`).

`target_triple` (line 185):
```ocaml
let target_triple = function
  | Native          -> Lazy.force native_triple
  | LinuxGnu { arch = X86_64; _ } -> "x86_64-unknown-linux-gnu"
  | LinuxGnu { arch = Arm64;  _ } -> "aarch64-unknown-linux-gnu"
  | Wasm64Wasi      -> "wasm64-wasi"
  | Wasm32Wasi      -> "wasm32-wasi"
  | Wasm32Unknown   -> "wasm32-unknown-unknown"
  | Js              -> "js"
```
`target_ptr_size` (line 193): add `| LinuxGnu _` to the `8` arm.
`target_ptr_ty` (line 198): add `| LinuxGnu _` to the `"ptr"` arm.
`target_int_ty` (line 203): add `| LinuxGnu _` to the `"i64"` arm.

- [ ] **Step 5: Add the target helpers**

In `lib/tir/llvm_emit.ml`, immediately after `target_triple` (after line 190):
```ocaml
(** Architecture, when meaningful (native's arch is the host, decided by clang). *)
let target_arch = function
  | LinuxGnu { arch; _ } -> Some arch
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> None

let target_is_linux = function
  | LinuxGnu _ -> true
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> false

(** zig cc -target string for a cross target, or None for host/wasm/js. *)
let zig_target = function
  | LinuxGnu { arch = X86_64; glibc_min } -> Some ("x86_64-linux-gnu." ^ glibc_min)
  | LinuxGnu { arch = Arm64;  glibc_min } -> Some ("aarch64-linux-gnu." ^ glibc_min)
  | Native | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> None
```

- [ ] **Step 6: Extend `parse_target`**

In `bin/main.ml`, in `parse_target` (after line 573, before the `| other` fallthrough):
```ocaml
  | "linux/amd64" | "linux/x86_64" | "linux-x86_64" ->
    March_tir.Llvm_emit.(LinuxGnu { arch = X86_64; glibc_min = "2.31" })
  | "linux/arm64" | "linux/aarch64" | "linux-arm64" ->
    March_tir.Llvm_emit.(LinuxGnu { arch = Arm64; glibc_min = "2.31" })
```
Update the error message (line 575) to list the new targets:
```ocaml
    Printf.eprintf "march: unknown target '%s'\n  Valid targets: native, linux/amd64, linux/arm64, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown, js\n" other;
```

- [ ] **Step 7: Extend the cache label (exhaustive)**

In `bin/main.ml`, in the `target_label` match (lines 1152-1157), add:
```ocaml
          | March_tir.Llvm_emit.LinuxGnu { arch = March_tir.Llvm_emit.X86_64; glibc_min } ->
            "linux-x86_64-gnu-" ^ glibc_min
          | March_tir.Llvm_emit.LinuxGnu { arch = March_tir.Llvm_emit.Arm64; glibc_min } ->
            "linux-arm64-gnu-" ^ glibc_min
```
(Distinct per arch + floor so `linux/amd64`, `linux/arm64`, and `native` never alias.)

- [ ] **Step 8: Run test to verify it passes**

Run: `dune build bin/main.exe 2>&1 | grep -i warning ; sh /tmp/xc_task1.sh`
Expected: no non-exhaustive-match warnings from `dune build`; script prints `PASS: both linux targets parse`. (The link will still fail later — that's Task 3 — but parsing now succeeds.)

- [ ] **Step 9: Commit**

```bash
git add lib/tir/llvm_emit.ml bin/main.ml
git commit -m "feat(xc): add LinuxGnu cross targets to target_config + parse_target + cache label"
```

---

### Task 2: Target-derived build-flag helpers (de-host-ify, part 1)

**Files:**
- Modify: `bin/main.ml` (add helpers near the top of the compile section, before the final-link command block ~line 2020)

**Interfaces:**
- Produces (all in `bin/main.ml`, taking the parsed `target_config`):
  - `cc_driver : target_config -> string` — `"clang"` for `Native`, `"zig cc -target <zt>"` for `LinuxGnu`.
  - `arch_cflags : target_config -> string` — `" -msse4.2"` for x86-family (Native and `LinuxGnu X86_64`), `""` for `LinuxGnu Arm64`.
  - `link_is_linux : target_config -> bool` — `true` for `LinuxGnu`, else host-probe (`Sys.file_exists "/proc/version"`) for `Native`.
- Consumes: `March_tir.Llvm_emit` target helpers from Task 1.

- [ ] **Step 1: Write the failing test**

Add `/tmp/xc_task2.sh` (asserts the driver string is chosen correctly by observing the invoked command; we make the compiler echo its link command under an env flag):
```bash
#!/bin/sh
set -e
M=./_build/default/bin/main.exe
amd=$(MARCH_ECHO_CC=1 "$M" --compile --target linux/amd64 /tmp/xc_triv.march -o /tmp/xc_out 2>&1 || true)
arm=$(MARCH_ECHO_CC=1 "$M" --compile --target linux/arm64 /tmp/xc_triv.march -o /tmp/xc_out 2>&1 || true)
echo "$amd" | grep -q "zig cc -target x86_64-linux-gnu.2.31" || { echo "FAIL: amd64 driver"; exit 1; }
echo "$amd" | grep -q -- "-msse4.2" || { echo "FAIL: amd64 should keep -msse4.2"; exit 1; }
echo "$arm" | grep -q "zig cc -target aarch64-linux-gnu.2.31" || { echo "FAIL: arm64 driver"; exit 1; }
if echo "$arm" | grep -q -- "-msse4.2"; then echo "FAIL: arm64 must NOT pass -msse4.2"; exit 1; fi
echo "PASS: driver + arch flags correct"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build bin/main.exe 2>/dev/null; sh /tmp/xc_task2.sh`
Expected: `FAIL: amd64 driver` (helpers + `MARCH_ECHO_CC` don't exist yet).

- [ ] **Step 3: Add the helper functions**

In `bin/main.ml`, just before the final-link command block (before line ~2020, inside the compile branch where `target_parsed` is in scope — thread `target_parsed` in if it is not already; it is computed at line 1151), add:
```ocaml
    let open March_tir.Llvm_emit in
    let cc_driver cfg =
      match zig_target cfg with
      | Some zt -> Printf.sprintf "zig cc -target %s" zt
      | None    -> "clang"
    in
    let arch_cflags cfg =
      match cfg with
      | LinuxGnu { arch = Arm64; _ } -> ""          (* NEON by default; SSE flags are x86-only *)
      | LinuxGnu { arch = X86_64; _ } | Native -> " -msse4.2"
      | Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js -> ""
    in
    let link_is_linux cfg =
      target_is_linux cfg || (match cfg with Native -> Sys.file_exists "/proc/version" | _ -> false)
    in
```

- [ ] **Step 4: Add the `MARCH_ECHO_CC` debug hook**

The final-link command is built at `bin/main.ml:2053-2055` into `cmd`. Immediately after `let cmd = ... in` (line 2055) add:
```ocaml
            (if Sys.getenv_opt "MARCH_ECHO_CC" <> None then
               Printf.eprintf "MARCH_CC_CMD: %s\n%!" cmd);
```
(You will wire `cmd` to actually use the helpers in Task 3; for now this test only checks the *command string*, so also make the minimal wiring here: replace the literal `"clang"` at the start of the `Printf.sprintf` format at line 2054 with `%s` and pass `(cc_driver target_parsed)` as its first arg, and replace the literal ` -msse4.2` in that format string with `%s` fed `(arch_cflags target_parsed)`. Keep every other flag exactly as-is for now.)

Concretely, change line 2053-2055 from:
```ocaml
            let cmd = Printf.sprintf
              "clang%s%s%s%s%s -msse4.2 -Wno-unused-command-line-argument%s%s%s %s%s%s%s%s %s -o %s%s%s"
              opt_flag dbg_flag san_flag rdynamic_flag so_flag evloop_flag ffi_inc signing_define runtime extra_c_files openssl_flags2 compress_flags2 ffi_link ll_file out_bin math_flag reload_ldl in
```
to:
```ocaml
            let cmd = Printf.sprintf
              "%s%s%s%s%s%s%s -Wno-unused-command-line-argument%s%s%s %s%s%s%s%s %s -o %s%s%s"
              (cc_driver target_parsed) opt_flag dbg_flag san_flag rdynamic_flag so_flag (arch_cflags target_parsed) evloop_flag ffi_inc signing_define runtime extra_c_files openssl_flags2 compress_flags2 ffi_link ll_file out_bin math_flag reload_ldl in
```

- [ ] **Step 5: Run test to verify it passes**

Run: `dune build bin/main.exe 2>/dev/null; sh /tmp/xc_task2.sh`
Expected: `PASS: driver + arch flags correct`.

- [ ] **Step 6: Verify host builds are unchanged**

Run: `MARCH_ECHO_CC=1 ./_build/default/bin/main.exe --compile /tmp/xc_triv.march -o /tmp/xc_native 2>&1 | grep MARCH_CC_CMD`
Expected: the command still begins with `clang` and still contains ` -msse4.2` (native path byte-identical to before). Then run `/tmp/xc_native` → prints `hello from march`.

- [ ] **Step 7: Commit**

```bash
git add bin/main.ml
git commit -m "feat(xc): target-derived cc driver + arch-gated cflags; MARCH_ECHO_CC hook"
```

---

### Task 3: First green cross ELF — target-OS link flags + trim external libs

**Files:**
- Modify: `bin/main.ml` (`rdynamic_flag` 2024-2031, `so_flag` 2032-2040, `reload_ldl` 2041-2044; `openssl_flags`/`compress_flags` computation ~408-466; runtime source list)

**Interfaces:**
- Consumes: `cc_driver`, `arch_cflags`, `link_is_linux`, `target_is_linux` from Task 2/1.
- Produces: a cross link command that (a) uses target-OS undefined/`-ldl`/`-export-dynamic` flags and (b) links **no** external C libraries and excludes `march_tls.c`/`march_compress.c` from the cross runtime source set.

- [ ] **Step 1: Write the failing test**

Add `/tmp/xc_task3.sh`:
```bash
#!/bin/sh
set -e
M=./_build/default/bin/main.exe
"$M" --compile --target linux/amd64 /tmp/xc_triv.march -o /tmp/xc_amd64 2>/tmp/xc_amd64.err
"$M" --compile --target linux/arm64 /tmp/xc_triv.march -o /tmp/xc_arm64 2>/tmp/xc_arm64.err
file /tmp/xc_amd64 | grep -q "ELF 64-bit LSB .*x86-64" || { echo "FAIL amd64 ELF: $(file /tmp/xc_amd64)"; cat /tmp/xc_amd64.err; exit 1; }
file /tmp/xc_arm64 | grep -q "ELF 64-bit LSB .*\(aarch64\|ARM aarch64\)" || { echo "FAIL arm64 ELF: $(file /tmp/xc_arm64)"; cat /tmp/xc_arm64.err; exit 1; }
# Must NOT have dragged in host libs:
if grep -q -- "-lssl\|-lcrypto\|/opt/homebrew" /tmp/xc_amd64.err; then echo "FAIL: host lib leaked"; exit 1; fi
echo "PASS: valid ELF for both arches, no host libs"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build bin/main.exe 2>/dev/null; sh /tmp/xc_task3.sh`
Expected: FAIL — link errors (macOS `-undefined dynamic_lookup` passed to zig, and/or `-lssl`/`/opt/homebrew` leaked from the host probes).

- [ ] **Step 3: Make `rdynamic_flag`/`so_flag`/`reload_ldl` target-aware**

In `bin/main.ml`, replace the three host-probe blocks (lines 2024-2044). Change every `Sys.file_exists "/proc/version"` to `link_is_linux target_parsed`:
```ocaml
            let rdynamic_flag =
              if !hot_reload_prefix <> None && not !compile_so then
                if link_is_linux target_parsed then " -Wl,--export-dynamic"
                else " -Wl,-export_dynamic"
              else "" in
            let so_flag =
              if !compile_so then
                let undef = if link_is_linux target_parsed
                            then " -Wl,--allow-shlib-undefined"
                            else " -undefined dynamic_lookup" in
                " -shared -fPIC" ^ undef
              else "" in
            let reload_ldl =
              if !hot_reload_prefix <> None && not !compile_so
                 && link_is_linux target_parsed then " -ldl" else "" in
```

- [ ] **Step 4: Force external-lib flags off for cross targets**

The final-link command uses `openssl_flags2` and `compress_flags2` (computed near lines 408-466, mirrored in the `2` variants). Wrap both so a cross target contributes nothing. Locate where `openssl_flags2` and `compress_flags2` are bound in the final-link branch and change each binding to:
```ocaml
            let openssl_flags2 = if target_is_linux target_parsed then "" else openssl_flags2 in
            let compress_flags2 = if target_is_linux target_parsed then "" else compress_flags2 in
```
(Add these two `let` shadows immediately before `let cmd = ...` at line 2053. This keeps host builds identical and prevents `/opt/homebrew` paths from ever entering a cross link.)

- [ ] **Step 5: Exclude `march_tls.c` and `march_compress.c` from the cross runtime source set**

The `runtime` string (built from `opt_file`-joined `.c` paths around lines 393-407) includes every runtime module. Immediately before `let cmd = ...` (line 2053), filter them for cross:
```ocaml
            let runtime =
              if target_is_linux target_parsed then
                (* P1 pure-compute: drop the only external-lib-bearing modules. *)
                runtime
                |> String.split_on_char ' '
                |> List.filter (fun p ->
                     let b = Filename.basename p in
                     b <> "march_tls.c" && b <> "march_compress.c")
                |> String.concat " "
              else runtime in
```
If, after building, the link reports undefined references from a *third* module into `march_tls`/`march_compress` symbols, add that module's `.c` to the exclusion list and note it — the differential-oracle corpus is pure compute, so any module that only exists to serve TLS/compression/HTTP can be excluded for P1. Record every excluded file in a comment.

- [ ] **Step 6: Run test to verify it passes**

Run: `dune build bin/main.exe 2>/dev/null; sh /tmp/xc_task3.sh`
Expected: `PASS: valid ELF for both arches, no host libs`. (Requires `zig` installed: `brew install zig`.)

- [ ] **Step 7: Re-confirm host build unchanged**

Run: `./_build/default/bin/main.exe --compile /tmp/xc_triv.march -o /tmp/xc_native && /tmp/xc_native`
Expected: `hello from march` (native path still fully works, TLS/compress modules still linked for native).

- [ ] **Step 8: Commit**

```bash
git add bin/main.ml
git commit -m "feat(xc): target-OS link flags + strip external libs/tls/compress for cross; first green Linux ELF"
```

---

### Task 4: Run gate — execute the cross binary under Docker

**Files:**
- Create: `test/xc/run_under_docker.sh` (helper used by the oracle in Task 5 and by CI)

**Interfaces:**
- Produces: `test/xc/run_under_docker.sh <arch> <binary>` → runs the binary in a minimal glibc Linux container for `<arch>` (`amd64`|`arm64`), prints its stdout, exits with the binary's exit code.

- [ ] **Step 1: Write the failing test**

Add `/tmp/xc_task4.sh`:
```bash
#!/bin/sh
set -e
./_build/default/bin/main.exe --compile --target linux/amd64 /tmp/xc_triv.march -o /tmp/xc_amd64
out=$(sh test/xc/run_under_docker.sh amd64 /tmp/xc_amd64)
[ "$out" = "hello from march" ] || { echo "FAIL: got [$out]"; exit 1; }
echo "PASS: cross binary runs under docker"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh /tmp/xc_task4.sh`
Expected: FAIL — `test/xc/run_under_docker.sh` does not exist.

- [ ] **Step 3: Write the Docker run helper**

Create `test/xc/run_under_docker.sh`:
```bash
#!/bin/sh
# Run a cross-built glibc Linux binary in a matching container.
# Usage: run_under_docker.sh <amd64|arm64> <binary-path>
set -e
arch="$1"; bin="$2"
case "$arch" in
  amd64) platform="linux/amd64" ;;
  arm64) platform="linux/arm64" ;;
  *) echo "unknown arch: $arch" >&2; exit 2 ;;
esac
# debian:bookworm-slim ships glibc 2.36 (>= our 2.31 floor). Mount the binary read-only.
exec docker run --rm --platform "$platform" \
  -v "$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")":/work/prog:ro \
  debian:bookworm-slim /work/prog
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x test/xc/run_under_docker.sh; sh /tmp/xc_task4.sh`
Expected: `PASS: cross binary runs under docker`. (Prereq: Docker running. On Apple Silicon, `linux/arm64` runs natively and `linux/amd64` runs via emulation — both supported by Docker Desktop.)

- [ ] **Step 5: Verify arm64 too**

Run:
```bash
./_build/default/bin/main.exe --compile --target linux/arm64 /tmp/xc_triv.march -o /tmp/xc_arm64
sh test/xc/run_under_docker.sh arm64 /tmp/xc_arm64
```
Expected: `hello from march`.

- [ ] **Step 6: Commit**

```bash
git add test/xc/run_under_docker.sh
git commit -m "test(xc): docker run helper for cross-built linux binaries"
```

---

### Task 5: Differential-oracle cross executor

**Files:**
- Modify: `test/test_oracle.ml:144-197` (add executor abstraction + cross path), and the sweep driver (~240-323) to run the cross gate when `MARCH_ORACLE_CROSS` is set.

**Interfaces:**
- Consumes: `run_shell_capture` (`test/test_oracle.ml:110`), `should_skip`, the existing `run_oracle` (`:159`), `test/xc/run_under_docker.sh` (Task 4).
- Produces: `run_oracle_cross : arch:string -> string -> run_result` comparing interpreter stdout vs the cross-compiled-and-Dockerized stdout, reusing the same `run_result` verdicts and skip allowlist.

- [ ] **Step 1: Write the failing test**

Add a deterministic corpus check as `/tmp/xc_task5.sh`:
```bash
#!/bin/sh
set -e
dune build test/test_oracle.exe 2>/dev/null
# Cross sweep over the golden corpus for amd64. Exit 0 iff all match/skip.
MARCH_ORACLE_CROSS=amd64 ./_build/default/test/test_oracle.exe 2>&1 | tee /tmp/xc_oracle.out
grep -q "CROSS(amd64)" /tmp/xc_oracle.out || { echo "FAIL: cross sweep did not run"; exit 1; }
grep -q "MISMATCH" /tmp/xc_oracle.out && { echo "FAIL: cross mismatch"; exit 1; }
echo "PASS: cross oracle sweep clean"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh /tmp/xc_task5.sh`
Expected: FAIL — `MARCH_ORACLE_CROSS` is ignored; no `CROSS(amd64)` output.

- [ ] **Step 3: Add the cross executor**

In `test/test_oracle.ml`, after `run_oracle` (line 197), add:
```ocaml
(* Cross-compile the program for [arch], run it under Docker, and diff its
   stdout against the interpreter (the oracle).  Reuses the same skip allowlist
   and run_result verdicts as run_oracle. *)
let run_oracle_cross ~arch src_path =
  if should_skip src_path then
    Skipped (Filename.basename (Filename.remove_extension src_path))
  else begin
    let q = Filename.quote in
    let interp_cmd =
      Printf.sprintf "cd %s && %s %s" (q project_root) (q march_abs) (q src_path) in
    match run_shell_capture ~timeout_s:10.0 interp_cmd with
    | `Timeout       -> InterpTimeout
    | `Error code    -> InterpFail code
    | `Ok interp_out ->
      let bin_dir = Filename.concat (Filename.get_temp_dir_name ()) "march_oracle_xc" in
      (try Unix.mkdir bin_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let src_base = Filename.basename (Filename.remove_extension src_path) in
      let out_bin  = Filename.concat bin_dir (arch ^ "_" ^ src_base) in
      let target = if arch = "arm64" then "linux/arm64" else "linux/amd64" in
      let compile_cmd =
        Printf.sprintf "cd %s && %s --compile --target %s %s -o %s"
          (q project_root) (q march_abs) target (q src_path) (q out_bin) in
      (match run_shell_capture ~timeout_s:60.0 compile_cmd with
       | `Timeout    -> CompileTimeout
       | `Error code -> CompileFail code
       | `Ok _       ->
         let run_cmd =
           Printf.sprintf "sh %s %s %s"
             (q (Filename.concat project_root "test/xc/run_under_docker.sh"))
             (q arch) (q out_bin) in
         (match run_shell_capture ~timeout_s:60.0 run_cmd with
          | `Timeout    -> RunTimeout
          | `Error code -> RunFail code
          | `Ok out     ->
            if out = interp_out then Match out
            else Mismatch (interp_out, out)))
  end
```

- [ ] **Step 4: Wire the cross sweep into the driver**

In the sweep driver (the `main`/entry that iterates `find_march_files` over `bench/`+`examples/`+golden and prints the results matrix, ~lines 240-323), add near the top of the run:
```ocaml
  let cross_arch = Sys.getenv_opt "MARCH_ORACLE_CROSS" in
```
and, in the per-file loop, when `cross_arch = Some a`, call `run_oracle_cross ~arch:a path` instead of `run_oracle path`, and prefix its printed verdict line with `Printf.sprintf "CROSS(%s) " a`. Keep the existing exit-code logic (`is_failure` → exit 1 on any `Mismatch`).

- [ ] **Step 5: Run test to verify it passes**

Run: `sh /tmp/xc_task5.sh`
Expected: `PASS: cross oracle sweep clean`. Any real codegen divergence on x86_64 surfaces here as `MISMATCH` with both outputs — that is the gate working.

- [ ] **Step 6: Run the arm64 sweep**

Run: `MARCH_ORACLE_CROSS=arm64 ./_build/default/test/test_oracle.exe 2>&1 | grep -c MISMATCH`
Expected: `0`. (If nonzero, a real aarch64 codegen bug — investigate the specific program with `systematic-debugging`; do not mark it skipped without cause.)

- [ ] **Step 7: Commit**

```bash
git add test/test_oracle.ml
git commit -m "test(xc): differential-oracle cross executor (interp vs cross-compiled-in-docker)"
```

---

### Task 6: forge `--target linux/*` plumbing

**Files:**
- Modify: `forge/lib/cmd_build.ml:562-566` (per-target build dir), `:619-624` (output ext already fine), the `[ffi.rust]` guard near `:333-366`
- Modify: `forge/bin/main.ml:151-155` (help text for `--target`)

**Interfaces:**
- Consumes: `compile_entry ?target` (`cmd_build.ml:371`) — already forwards `--target <t>` to the compiler verbatim, so passing `"linux/amd64"` works end-to-end.
- Produces: `forge build --target linux/amd64` writes `.march/build/linux-amd64/<mode>/<name>` (a valid ELF); an `[ffi.rust]` project cross-building errors clearly.

- [ ] **Step 1: Write the failing test**

Add `/tmp/xc_task6.sh`:
```bash
#!/bin/sh
set -e
d=$(mktemp -d)
cd "$d"
"$OLDPWD/_build/default/forge/bin/main.exe" new xcapp >/dev/null 2>&1 || ./_build/default/forge/bin/main.exe new xcapp
cd xcapp
FORGE=$OLDPWD/_build/default/forge/bin/main.exe
# (forge new scaffolds lib/xcapp.march with a main)
"$FORGE" build --target linux/amd64 >/tmp/xc_forge.out 2>&1 || { cat /tmp/xc_forge.out; echo "FAIL: build"; exit 1; }
test -f .march/build/linux-amd64/debug/xcapp || { echo "FAIL: per-target output missing"; ls -R .march/build; exit 1; }
file .march/build/linux-amd64/debug/xcapp | grep -q "ELF .*x86-64" || { echo "FAIL: not an amd64 ELF"; exit 1; }
echo "PASS: forge cross build produces per-target ELF"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune build forge/bin/main.exe 2>/dev/null; sh /tmp/xc_task6.sh`
Expected: FAIL — output lands in `.march/build/debug/xcapp` (host), no `linux-amd64/` subdir.

- [ ] **Step 3: Normalize aliases + per-target build dir**

In `forge/lib/cmd_build.ml`, where the `target` option arrives into `build`, add a normalizer near the top of `build`:
```ocaml
  let target = Option.map (fun t ->
    match t with
    | "linux/x86_64" | "linux-x86_64" -> "linux/amd64"
    | "linux/aarch64" | "linux-arm64" -> "linux/arm64"
    | other -> other) target in
  let target_subdir = match target with
    | Some "linux/amd64" -> "linux-amd64"
    | Some "linux/arm64" -> "linux-arm64"
    | _ -> "" in
```
Then change the `build_dir` (lines 563-566) to include `target_subdir` when non-empty:
```ocaml
    let build_dir =
      let base = Filename.concat proj.Project.root
        (Filename.concat ".march" "build") in
      let base = if target_subdir = "" then base else Filename.concat base target_subdir in
      Filename.concat base mode
    in
```

- [ ] **Step 4: Add the `[ffi.rust]` cross guard**

In `ffi_flags_full`/the Rust build path (`cmd_build.ml:333-366`), before invoking `cargo build`, guard on cross:
```ocaml
      (match proj.Project.ffi_rust, target_is_cross with
       | Some _, true ->
         Error "this project uses [ffi.rust]; cross-compilation of Rust bindings \
                is not yet supported (P1). Build on Linux, or use `forge deploy hot --so`."
       | _ -> (* existing cargo build path *) ...)
```
where `target_is_cross = (target_subdir <> "")`. Thread `target_is_cross` into `ffi_flags_full` as a labeled arg (`~target_is_cross`). Update the one call site accordingly.

- [ ] **Step 5: Add zig-discovery hint**

In `build`, when `target_subdir <> ""`, check for `zig` up front:
```ocaml
    (if target_subdir <> "" && Sys.command "command -v zig >/dev/null 2>&1" <> 0 then begin
       Printf.eprintf "forge: cross target %s requires `zig` (used as the C cross-compiler).\n  Install: brew install zig\n"
         (Option.value ~default:"" target);
       exit 1
     end);
```

- [ ] **Step 6: Update `--target` help text**

In `forge/bin/main.ml:151-155`, extend the `--target` doc string to mention `linux/amd64`, `linux/arm64`.

- [ ] **Step 7: Run test to verify it passes**

Run: `dune build forge/bin/main.exe 2>/dev/null; sh /tmp/xc_task6.sh`
Expected: `PASS: forge cross build produces per-target ELF`.

- [ ] **Step 8: Commit**

```bash
git add forge/lib/cmd_build.ml forge/bin/main.ml
git commit -m "feat(xc): forge --target linux/{amd64,arm64} — aliases, per-target output, zig hint, ffi.rust guard"
```

---

### Task 7: Cache distinctness, CI wiring, and doc updates

**Files:**
- Create: `.github/workflows/` cross job (or extend the existing CI workflow) — a macOS runner that builds the compiler and runs `MARCH_ORACLE_CROSS=amd64` under Docker.
- Modify: `specs/todos.md`, `specs/progress.md`.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing cache-distinctness test**

Create `/tmp/xc_sizeof.march` (value-revealing across arch is unnecessary since both are 64-bit; instead assert cache does not alias across *target*):
```bash
#!/bin/sh
set -e
M=./_build/default/bin/main.exe
printf 'fn main() do\n  println("A")\nend\n' > /tmp/xc_c.march
"$M" --compile --target linux/amd64 /tmp/xc_c.march -o /tmp/xc_c_amd
"$M" --compile --target linux/arm64 /tmp/xc_c.march -o /tmp/xc_c_arm
a=$(file /tmp/xc_c_amd); b=$(file /tmp/xc_c_arm)
echo "$a" | grep -q x86-64 || { echo "FAIL: amd64 aliased ($a)"; exit 1; }
echo "$b" | grep -q -i "aarch64\|arm aarch64" || { echo "FAIL: arm64 aliased ($b)"; exit 1; }
echo "PASS: no cross-target cache aliasing"
```

- [ ] **Step 2: Run test to verify it passes (label already distinct from Task 1)**

Run: `sh /tmp/xc_sizeof.march` — wait, invoke as `sh` on the script path you saved. Save the above as `/tmp/xc_task7.sh` and run `sh /tmp/xc_task7.sh`.
Expected: `PASS: no cross-target cache aliasing`. (This confirms Task 1 Step 7's per-arch label works; if it FAILS with one arch's `file` output matching the other, the cache label is not distinct — fix `target_label`.)

- [ ] **Step 3: Add the CI job**

Add a job to the CI workflow that runs on `macos-latest`:
```yaml
  cross-linux-oracle:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install zig + docker
        run: |
          brew install zig
          brew install --cask docker || true
      - name: Build compiler
        run: dune build bin/main.exe test/test_oracle.exe
      - name: Cross oracle (amd64)
        run: MARCH_ORACLE_CROSS=amd64 ./_build/default/test/test_oracle.exe
```
(If GitHub macOS runners cannot run Docker Linux containers, fall back to running this job on `ubuntu-latest` with `zig` — it still exercises the cross path since the build host is x86_64 Linux cross-building via zig; note this in a comment. Keep the macOS variant if the runner supports it, since it exercises the true Mac→Linux path.)

- [ ] **Step 4: Update specs**

In `specs/todos.md`, move the P1 cross-compile item to Done. In `specs/progress.md`, add to the feature list: "Cross-compilation to Linux (x86_64/arm64) for pure-compute programs via `zig cc`, validated by the differential oracle; `forge build --target linux/{amd64,arm64}`." Update the "Current State" counts if a test count changed.

- [ ] **Step 5: Run the full suite to confirm no regression**

Run: `scripts/run-tests.sh`
Expected: green (the new cross oracle is opt-in via `MARCH_ORACLE_CROSS`, so the default suite is unaffected). Judge by `$?`, not tail output.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows specs/todos.md specs/progress.md
git commit -m "ci(xc): macOS cross-linux oracle job; docs: record P1 cross-compile"
```

---

## Self-Review

**Spec coverage (against `specs/2026-07-04-cross-compile-linux-hot-deploy-design.md`):**
- §2 target model / aliases → Task 1 (compiler), Task 6 (forge). glibc floor 2.31 hardcoded → Task 1 (`--glibc` flag deferred, matches spec's "P1 hardcode").
- §3.1 cross native targets → Task 1. §3.2 cc driver → Task 2. §3.3 de-host-ify (`-msse4.2`, `so_flag`, `-ldl`, `rdynamic`, host paths) → Tasks 2+3. §3.4 runtime-from-source / reload-so distinction → covered by Task 3's source trim (main binary); reload `.so` is P2.
- §5 external libs → Task 3 (forced off for P1 pure-compute, per spec's "P1 may ship zlib+OpenSSL only / defer"). Note: P1 goes further and ships *neither*, since the oracle corpus is pure compute — libs move to the phase that needs HTTP/TLS.
- §6 FFI cross → Task 6 guard error (matches spec's "clear error, not silent failure").
- §7 forge changes → Task 6. §8 cache → Task 1 Step 7 + Task 7 test.
- Testing (differential oracle third executor) → Tasks 4+5. CI → Task 7.
- **Out of P1 by design:** P2 (`--compile-so` cross + `forge deploy hot --target`), P3 (OpenSSL/TLS, zstd/brotli, glibc-floor runtime check, soname manifest). These get their own plans.

**Placeholder scan:** The one intentionally open-ended spot is Task 3 Step 5 ("if a third module drags in tls/compress symbols, add it to the exclusion list") — this is genuinely discovered at link time and bounded by the link errors, with the differential oracle as the pass criterion; it is not a hand-wave. All other steps contain concrete code/commands.

**Type consistency:** `arch`/`LinuxGnu` defined in Task 1 are used identically in Tasks 2/3 (`target_arch`, `zig_target`, `target_is_linux`). `run_oracle_cross ~arch` (Task 5) matches the `amd64`/`arm64` strings produced by `run_under_docker.sh` (Task 4) and the forge `linux-amd64`/`linux-arm64` subdirs (Task 6). `cc_driver`/`arch_cflags`/`link_is_linux` names are stable across Tasks 2-3.
