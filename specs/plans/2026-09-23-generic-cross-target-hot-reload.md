# Generic Cross-Target Hot Reload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Forge build an HCR-enabled baseline and a signed hot patch for any March target that supports dynamic loading, while verifying the patch against the baseline that is actually running.

**Architecture:** March exposes one canonical HCR identity derived from its existing target configuration, embeds that identity in both the baseline and patch, and makes the baseline report it over the reload socket. Forge obtains the running identity before compiling or uploading a patch, then uses the same target, module prefix, and signing key for the patch. The runtime repeats the identity check after `dlopen`, so a stale Forge configuration or altered manifest cannot bypass compatibility enforcement.

**Tech Stack:** OCaml/Dune, Zig C cross-compilation, C runtime with `dlopen` and Unix sockets, vendored portable BLAKE3 1.8.3, Alcotest, Linux `readelf`, and QEMU user-mode arm64 execution.

**Spec:** `specs/2026-07-04-cross-compile-linux-hot-deploy-design.md`, extended by the identity and negotiation contract defined here.

## Execution Preconditions

- Execute all compiler, runtime, and Forge work in this repository worktree. Forge paths are under `forge/`; `/Users/80197052/code/march/forge` is another checkout and must not be edited for this feature.
- The current worktree is detached at `f7ef5da57`. Before Task 1, create `codex/generic-cross-hcr` from that commit using the Codex “Create branch” control or `git switch -c codex/generic-cross-hcr`.
- Keep the existing Vault alignment commit `f7ef5da57` in the branch history.
- The plan lives under `specs/plans/` because `docs/superpowers/` is ignored by this repository.

## Global Constraints

- One target-capability function covers every current and future `target_config` constructor. Today, cross HCR is supported by `LinuxGnu` for `X86_64` and `Arm64`; unsupported targets fail before code generation.
- Linker policy remains in `bin/main.ml`; LLVM target identity remains sourced from `Llvm_toplevel.target_triple`, `target_ptr_size`, and `zig_target`.
- The compatibility tuple is `(runtime ABI version, canonical target, LLVM triple, pointer width, module prefix, signing public key)`.
- A patch is checked twice: Forge compares its manifest to `HCR_INFO`, then the runtime compares exported patch markers after `dlopen` and before activation.
- Cross HCR artifacts do not require `libblake3` on the deployment host. The OCaml CAS binding may continue using the build-host library.
- `forge deploy hot --so` remains supported. Manifest v1 is accepted only for the legacy native-server path; cross deployment requires manifest v2 and `HCR_INFO`.
- Tests run cross-built binaries as bare Linux processes. Container images are not part of the deployment or acceptance model.

## Review Focus

- A stale `[hot-reload] target` cannot override a different target reported by the running server; Task 6 tests rejection before upload.
- A manifest edited to claim the right target cannot make a wrong-ABI shared object activate; Task 5 tests runtime marker enforcement.
- `linux/arm64` never receives x86 SIMD flags and loads under QEMU; Tasks 3 and 7 test this.
- A clean target sysroot without `libblake3.so` links and runs the HCR server; Tasks 2 and 7 test this.
- Existing native HCR remains usable, while legacy manifest behavior is explicit rather than accidental; Tasks 4 and 6 test both paths.

---

### Task 1: Define a canonical HCR target identity without duplicating target truth

**Files:**
- Create: `lib/tir/hcr_abi.ml`
- Create: `lib/tir/hcr_abi.mli`
- Modify: `lib/tir/dune`
- Modify: `bin/main.ml`
- Create: `test/test_hcr_abi.ml`
- Modify: `test/dune`

**Interfaces:**
- Consumes: `Llvm_toplevel.target_config`, `target_triple`, and `target_ptr_size`.
- Produces:

```ocaml
type platform = Elf | MachO

type t = {
  canonical_target : string;
  llvm_triple : string;
  pointer_bytes : int;
  platform : platform;
  runtime_abi : int;
}

val of_target : Llvm_toplevel.target_config -> (t, string) result
val abi_id : t -> string
```

`runtime_abi` starts at `2`. `abi_id` is exactly `march-hcr-v2;triple=<llvm-triple>;ptr=<bytes>`; module prefix and key are separate members of the compatibility tuple.
For `Native`, `canonical_target` is exactly `native`, while `llvm_triple` records the actual host triple; this preserves native CLI compatibility without treating two different native hosts as ABI-compatible.

- [ ] **Step 1: Add the failing target-identity test**

```ocaml
let test_linux_identities () =
  let open March_tir.Llvm_toplevel in
  let amd64 = Result.get_ok (March_tir.Hcr_abi.of_target
    (LinuxGnu { arch = X86_64; glibc_min = "2.36" })) in
  let arm64 = Result.get_ok (March_tir.Hcr_abi.of_target
    (LinuxGnu { arch = Arm64; glibc_min = "2.36" })) in
  Alcotest.(check string) "amd64 triple"
    "x86_64-unknown-linux-gnu" amd64.llvm_triple;
  Alcotest.(check string) "arm64 triple"
    "aarch64-unknown-linux-gnu" arm64.llvm_triple;
  Alcotest.(check string) "amd64 canonical target"
    "linux/amd64" amd64.canonical_target;
  Alcotest.(check string) "arm64 canonical target"
    "linux/arm64" arm64.canonical_target

let test_unsupported_target () =
  match March_tir.Hcr_abi.of_target March_tir.Llvm_toplevel.Wasm32Wasi with
  | Error msg -> Alcotest.(check string) "diagnostic"
      "hot reload requires a native dynamic loader and Unix-domain sockets; target wasm32-wasi is unsupported" msg
  | Ok _ -> Alcotest.fail "WASM must not advertise HCR"
```

Add `hcr_abi` to the explicit module list in `lib/tir/dune` and add a `(test (name test_hcr_abi) (libraries march_tir alcotest))` stanza in `test/dune`.

- [ ] **Step 2: Verify the test fails**

Run: `dune exec ./test/test_hcr_abi.exe`

Expected: compilation fails because `March_tir.Hcr_abi` does not exist.

- [ ] **Step 3: Implement `Hcr_abi.of_target` and compiler validation**

Map both `LinuxGnu` variants to `Elf`, using the existing triple and pointer-size helpers. For `Native`, accept only triples containing `linux`, `darwin`, or `apple`; select `Elf` for Linux and `MachO` for Apple. Return the exact unsupported-target diagnostic above for WASI, browser WASM, JS, and unsupported native triples. In `bin/main.ml`, call this validation before LLVM emission whenever `--hot-reload` or `--compile-so` is present.

- [ ] **Step 4: Verify target behavior**

Run: `dune exec ./test/test_hcr_abi.exe && dune build bin/main.exe`

Expected: the identity tests and compiler build pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/hcr_abi.ml lib/tir/hcr_abi.mli lib/tir/dune bin/main.ml test/test_hcr_abi.ml test/dune
git commit -m "feat(hcr): define canonical target identity"
```

### Task 2: Vendor a portable BLAKE3 runtime implementation

**Files:**
- Create: `runtime/third_party/blake3/blake3.c`
- Create: `runtime/third_party/blake3/blake3.h`
- Create: `runtime/third_party/blake3/blake3_dispatch.c`
- Create: `runtime/third_party/blake3/blake3_impl.h`
- Create: `runtime/third_party/blake3/blake3_portable.c`
- Create: `runtime/third_party/blake3/LICENSE_A2`
- Create: `runtime/third_party/blake3/LICENSE_A2LLVM`
- Create: `runtime/third_party/blake3/LICENSE_CC0`
- Create: `runtime/third_party/blake3/UPSTREAM.md`
- Modify: `runtime/march_blake3.c`
- Modify: `bin/main.ml`
- Modify: `test/dune`

**Interfaces:**
- Consumes: upstream BLAKE3 tag `1.8.3`, commit `8b829b697fa4cfe35de35e9aa8c20b56266cb091`.
- Produces: `march_blake3.c` backed by three portable sources and these exact defines:

```text
-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2
-DBLAKE3_NO_AVX512 -DBLAKE3_USE_NEON=0
```

- [ ] **Step 1: Change the C agreement test to depend on the vendored source set**

Update the `test_blake3_agreement_runner` rule to compile `march_blake3.c`, `blake3.c`, `blake3_dispatch.c`, and `blake3_portable.c` with `-Iruntime/third_party/blake3` and the five defines above. Remove `blake3_cflags.sexp` and `blake3_libs.sexp` only from this C runner; the OCaml CAS tests keep their existing build-host dependency.

- [ ] **Step 2: Verify the changed test fails before sources are present**

Run: `dune build test/test_blake3_agreement_runner`

Expected: Dune reports a missing `runtime/third_party/blake3/blake3.c` dependency.

- [ ] **Step 3: Vendor and document the exact upstream files**

Copy the listed files from tag `1.8.3`. `UPSTREAM.md` records the repository URL, tag, full commit, copied file list, five portable-only defines, and both included upstream licenses. Change `march_blake3.c` from `<blake3.h>` to `"third_party/blake3/blake3.h"`. Add the three C sources and defines to the compiler runtime input list for every non-patch executable that includes `march_blake3.c`.

- [ ] **Step 4: Update reload-runtime test rules and verify**

Apply the same source list, include directory, and defines to `test_reload_activate4_runner` and `test_reload_activate4_policy_runner` in `test/dune`.

Run:

```sh
dune build test/test_blake3_agreement_runner test/test_reload_activate4_runner test/reload_keys.txt
_build/default/test/test_blake3_agreement_runner
(cd _build/default/test && ./test_reload_activate4_runner reload_keys.txt)
```

Expected: both runners pass without linking `-lblake3` on their C-runtime side.

- [ ] **Step 5: Commit**

```bash
git add runtime/third_party/blake3 runtime/march_blake3.c bin/main.ml test/dune
git commit -m "feat(runtime): vendor portable BLAKE3 for HCR"
```

### Task 3: Cross-link HCR baselines and patches from the selected target

**Files:**
- Modify: `bin/main.ml`
- Create: `test/native/hcr_smoke.march`
- Create: `test/cross_hcr_compile.sh`
- Modify: `test/dune`

**Interfaces:**
- Consumes: `Hcr_abi.t` from Task 1 and vendored BLAKE3 sources from Task 2.
- Produces: baseline executables and patch shared objects for `linux/amd64` and `linux/arm64`.

- [ ] **Step 1: Add a failing cross-compile smoke script**

```sh
#!/bin/sh
set -eu
key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
out_dir=${MARCH_HCR_TEST_TMP:-${TMPDIR:-/tmp}}
for target in linux/amd64 linux/arm64; do
  arch=${target##*/}
  base="$out_dir/march-hcr-$arch"
  dune exec ./bin/main.exe -- --compile --target "$target" \
    --hot-reload HcrSmoke --signing-pubkey "$key" \
    -o "$base" test/native/hcr_smoke.march
  dune exec ./bin/main.exe -- --compile --compile-so --target "$target" \
    --hot-reload HcrSmoke -o "$base.so" test/native/hcr_smoke.march
  file "$base" "$base.so"
done
```

The script additionally asserts `x86-64` for amd64, `aarch64` for arm64, `executable` for baselines, and `shared object` for patches using `file` output, which is available on macOS and Linux.

- [ ] **Step 2: Verify current failure**

Run: `sh test/cross_hcr_compile.sh`

Expected: the baseline link fails because the current cross path removes `march_reload.c` and `march_blake3.c` while generated HCR code references the reload server.

- [ ] **Step 3: Replace host probes and the blanket cross-source filter**

Derive `link_is_linux`, executable export flags, patch undefined-symbol flags, and `-ldl` from `Hcr_abi.platform`. For cross HCR baselines, keep `march_dispatch.c`, `march_reload.c`, `march_blake3.c`, `march_cap_lattice.c`, TweetNaCl, and the vendored BLAKE3 sources. For patches, keep the current undefined-symbol model. Do not apply `-msse4.2` to `LinuxGnu Arm64`.

When `--compile-so` is active, do not require or link target OpenSSL/zlib shared objects; their symbols resolve from the running baseline. Continue requiring the target sysroot for a full baseline.

- [ ] **Step 4: Verify both targets and dynamic dependencies**

Run locally: `MARCH_HCR_TEST_TMP=/tmp sh test/cross_hcr_compile.sh`

Run on a Linux CI runner:

```sh
readelf -d /tmp/march-hcr-amd64 | grep -q 'libblake3' && exit 1 || true
readelf -d /tmp/march-hcr-arm64 | grep -q 'libblake3' && exit 1 || true
readelf -h /tmp/march-hcr-amd64.so | grep -q 'Advanced Micro Devices X86-64'
readelf -h /tmp/march-hcr-arm64.so | grep -q 'AArch64'
```

Expected: both target pairs compile; neither baseline needs `libblake3`; both patches have the correct ELF architecture.

- [ ] **Step 5: Commit**

```bash
git add bin/main.ml test/native/hcr_smoke.march test/cross_hcr_compile.sh test/dune
git commit -m "feat(compiler): cross-link HCR baselines and patches"
```

### Task 4: Embed and emit manifest-v2 patch identity

**Files:**
- Create: `runtime/march_hcr_identity.c`
- Create: `runtime/march_hcr_identity.h`
- Modify: `bin/main.ml`
- Create: `test/test_hcr_identity.c`
- Modify: `test/dune`

**Interfaces:**
- Produces exported patch symbols `__march_hcr_abi`, `__march_hcr_target`, and `__march_hcr_prefix`.
- Produces manifest headers:

```text
# march-hcr-manifest v2
# cas_hash <64-hex>
# target linux/amd64
# hcr_abi march-hcr-v2;triple=x86_64-unknown-linux-gnu;ptr=8
# module_prefix HcrSmoke
```

- [ ] **Step 1: Add a failing C identity test**

Compile two shared-library fixtures from `march_hcr_identity.c`, one with matching macros and one with `MARCH_HCR_TARGET="linux/arm64"`. The test uses `dlopen`/`dlsym` and asserts the three symbols contain the macro values. Add a Dune runner named `test_hcr_identity_runner`.

- [ ] **Step 2: Verify the identity test fails**

Run: `dune build test/test_hcr_identity_runner`

Expected: Dune reports that `runtime/march_hcr_identity.c` does not exist.

- [ ] **Step 3: Implement compiler macros, runtime symbols, and manifest v2**

For every HCR baseline or patch, compile `march_hcr_identity.c` with shell-quoted `MARCH_HCR_ABI_ID`, `MARCH_HCR_TARGET`, and `MARCH_HCR_PREFIX` definitions derived from Task 1 and `--hot-reload`. Whenever the compiler emits an HCR manifest, write the exact v2 headers above before function records. The compiler does not create a manifest for `--compile-so` without `--hot-reload`; legacy v1 support remains a Forge parser/deployment compatibility path.

- [ ] **Step 4: Verify exported markers and manifest fields**

Run:

```sh
dune exec ./test/test_hcr_identity_runner
MARCH_HCR_TEST_TMP=/tmp sh test/cross_hcr_compile.sh
grep -q '^# march-hcr-manifest v2$' /tmp/march-hcr-amd64.so.hcr_manifest
grep -q '^# target linux/amd64$' /tmp/march-hcr-amd64.so.hcr_manifest
grep -q '^# module_prefix HcrSmoke$' /tmp/march-hcr-amd64.so.hcr_manifest
```

Expected: identity runner and all header assertions pass.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_hcr_identity.c runtime/march_hcr_identity.h bin/main.ml test/test_hcr_identity.c test/dune
git commit -m "feat(hcr): embed patch identity and manifest v2"
```

### Task 5: Make the running server advertise and enforce its identity

**Files:**
- Modify: `runtime/march_reload.c`
- Modify: `runtime/march_reload.h`
- Modify: `test/test_reload_activate4.c`
- Modify: `test/dune`

**Interfaces:**
- Produces protocol command:

```text
HCR_INFO
HCR_INFO target:linux/amd64 abi:march-hcr-v2;triple=x86_64-unknown-linux-gnu;ptr=8 prefix:HcrSmoke key:<64-hex>
```

- Produces: `int march_hcr_patch_identity_ok(void *handle, char *reason, size_t reason_len)`.

- [ ] **Step 1: Add failing protocol and loader-enforcement cases**

Extend `test_reload_activate4.c` to send `HCR_INFO` and assert all four fields. Build a matching and mismatching fixture `.so`; assert `march_hcr_patch_identity_ok` accepts the first and returns `0` with `target mismatch` for the second. Compile the runner with baseline identity macros and `march_hcr_identity.c`.

- [ ] **Step 2: Verify the new assertions fail**

Run:

```sh
dune build test/test_reload_activate4_runner test/reload_keys.txt
(cd _build/default/test && ./test_reload_activate4_runner reload_keys.txt)
```

Expected: the response is `ERR unknown_command` and the identity-check function is undefined.

- [ ] **Step 3: Implement `HCR_INFO` and enforce markers after `dlopen`**

Return the baseline macros plus the configured public key as lowercase hex. In every activation path, call `march_hcr_patch_identity_ok` immediately after `dlopen` and before `dlsym` of patch functions or migration hooks. On failure, `dlclose` the handle, return `ERR identity <reason>`, and write the rejection to the audit log. A v2 baseline rejects a patch missing any marker.

- [ ] **Step 4: Run runtime verification**

Run:

```sh
dune build test/test_reload_activate4_runner test/reload_keys.txt
(cd _build/default/test && ./test_reload_activate4_runner reload_keys.txt)
dune runtest
```

Expected: `HCR_INFO`, matching activation, mismatched-target rejection, signature tests, and existing HCR tests pass.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_reload.c runtime/march_reload.h test/test_reload_activate4.c test/dune
git commit -m "feat(runtime): negotiate and enforce HCR identity"
```

### Task 6: Bootstrap HCR baselines and preflight patches through Forge

**Files:**
- Modify: `forge/lib/project.ml`
- Modify: `forge/lib/cmd_build.ml`
- Modify: `forge/lib/cmd_deploy_hot.ml`
- Modify: `forge/bin/main.ml`
- Modify: `forge/test/test_forge.ml`
- Modify: `forge/test/test_entry_rule.ml`

**Interfaces:**
- Extends `Project.hot_reload_config` with `hr_target : string option` and `hr_module_prefix : string option`.
- Adds `[hot-reload]` keys `target` and `module_prefix` to the known-key validator.
- Adds:

```ocaml
type hcr_build = { prefix : string; public_key : string }

val compile_command :
  lib_path_env:string -> ffi_flags:string -> output:string -> release:bool ->
  dump_phases:bool -> ?target:string -> ?hcr:hcr_build -> pin_main:bool ->
  string -> string

type hcr_info = {
  target : string; abi : string; prefix : string; key_hex : string;
}

type manifest = {
  version : int;
  cas_hash : string;
  target : string option;
  hcr_abi : string option;
  module_prefix : string option;
  functions : fn_manifest list;
}

val query_hcr_info : ssh_host:string -> remote_socket:string ->
  (hcr_info, string) result

val query_hcr_info_connected : conn -> (hcr_info, string) result

val build_so : proj:Project.project -> target:string ->
  module_prefix:string -> output:string -> (string * string, string) result
```

- [ ] **Step 1: Add failing project, command, manifest, and negotiation tests**

Use `with_temp_parent` and a real temporary `forge.toml`; do not introduce a nonexistent `Project.load_from_string`. Assert:

```ocaml
Alcotest.(check (option string)) "target" (Some "linux/arm64") hr.hr_target;
Alcotest.(check (option string)) "prefix" (Some "App") hr.hr_module_prefix;
Alcotest.(check bool) "baseline prefix" true
  (contains command "--hot-reload App");
Alcotest.(check bool) "baseline key" true
  (contains command "--signing-pubkey");
Alcotest.(check bool) "patch target" true
  (contains patch_command "--target linux/arm64")
```

Add manifest-v2 parsing cases, a v1-native compatibility case, `HCR_INFO` parsing, configured-target-versus-server rejection, prefix rejection, and key rejection.

- [ ] **Step 2: Verify Forge tests fail**

Run: `dune runtest forge/test`

Expected: tests fail because the new configuration fields and HCR command flags do not exist.

- [ ] **Step 3: Implement baseline build semantics**

When `[hot-reload]` is present for an app/tool build, require `module_prefix` and `public_key`, add `--hot-reload` and `--signing-pubkey`, and resolve the target as explicit `forge build --target` first, then `[hot-reload].target`, then native. An explicit build target may override the configured deployment target for local testing, but print the selected target in the build summary. Libraries remain check-only and do not receive HCR flags.

- [ ] **Step 4: Implement deploy preflight and patch construction**

Add `--target` and `--module-prefix` to `forge deploy hot`. Before building or accepting `--so`, query `HCR_INFO`. Resolve each value in this order: CLI, `[hot-reload]`, running server. If a CLI/config value differs from the server, fail before compilation and before `CAS_CHECK`. Decode the configured base64 public key to lowercase hex and compare it with `key_hex`. Build the patch using the server-confirmed target and prefix. Parse manifest v2 and compare all identity fields with the server response.

If `HCR_INFO` returns `ERR unknown_command`, permit only a native manifest-v1 `--so` deployment and print `legacy server: target identity cannot be verified`; reject cross compilation with `cross hot deploy requires an HCR v2 baseline; rebuild and restart the server`.

- [ ] **Step 5: Verify Forge behavior and CLI help**

Run:

```sh
dune runtest forge/test
dune exec ./forge/bin/main.exe -- deploy hot --help
```

Expected: tests pass; help documents target resolution, module-prefix resolution, and the baseline-restart requirement.

- [ ] **Step 6: Commit**

```bash
git add forge/lib/project.ml forge/lib/cmd_build.ml forge/lib/cmd_deploy_hot.ml forge/bin/main.ml forge/test/test_forge.ml forge/test/test_entry_rule.ml
git commit -m "feat(forge): build and preflight cross-target hot patches"
```

### Task 7: Prove bare-process hot replacement on amd64 and arm64

**Files:**
- Modify: `forge/lib/cmd_deploy_hot.ml`
- Create: `forge/test/test_cross_hcr_e2e.ml`
- Create: `test/native/hcr_e2e_server.march`
- Create: `test/native/hcr_e2e_patch.march`
- Create: `test/run_cross_hcr_e2e.sh`
- Modify: `forge/test/dune`
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/hot-code-reload.md`
- Modify: `specs/2026-07-04-cross-compile-linux-hot-deploy-design.md`

**Interfaces:**
- Extracts the connection-owned deployment core from the current SSH-owning `run` function:

```ocaml
val deploy_connected :
  conn -> signing_pubkey:string -> sk:bytes -> manifest:manifest ->
  so_path:string -> ?old_schemas_path:string -> ?new_schemas_path:string ->
  ?entry_path:string -> ?old_manifest_path:string -> ?provided_epoch:int ->
  ?grant_caps:string list -> ?no_cap_gate:bool -> unit ->
  (unit, string) result
```

Production retains SSH tunneling; tests connect directly to a temporary Unix socket and call `query_hcr_info_connected` plus `deploy_connected`.
- Produces CI coverage for native amd64 execution and `qemu-aarch64` execution using the prepared arm64 sysroot.

- [ ] **Step 1: Add the failing direct-socket integration test**

The Alcotest binary accepts `--target linux/amd64|linux/arm64`, builds a baseline application variant that returns `v1` and a patch variant that returns `v2`, starts the baseline with a temporary `MARCH_HOT_RELOAD_SOCKET`, calls `deploy_connected`, and asserts the application response changes from `v1` to `v2`. It then attempts the opposite-architecture manifest and asserts rejection occurs before `CAS_CHECK`.

- [ ] **Step 2: Verify the integration test fails before connection extraction**

Run on Linux amd64: `dune exec ./forge/test/test_cross_hcr_e2e.exe -- --target linux/amd64`

Expected: compilation fails because `deploy_connected` is not exported.

- [ ] **Step 3: Extract the connection-owned core without changing production transport**

Move the code beginning with `VERSIONS` through activation into `deploy_connected`. Keep `run` responsible for creating and closing the SSH tunnel and connection. The test creates `conn` with the existing `connect_socket` helper; no test-only production environment variable or deployment container is introduced.

- [ ] **Step 4: Add bare Linux and QEMU runners**

`test/run_cross_hcr_e2e.sh` uses these exact execution modes:

```sh
# On an x86_64 Linux runner
dune exec ./forge/test/test_cross_hcr_e2e.exe -- --target linux/amd64

# On the same runner with qemu-user installed
MARCH_HCR_RUNNER="qemu-aarch64 -L $MARCH_CROSS_SYSROOT_ARM64" \
  dune exec ./forge/test/test_cross_hcr_e2e.exe -- --target linux/arm64
```

Add a required CI job that installs `qemu-user`, prepares both existing cross sysroots, runs `test/cross_hcr_compile.sh`, then runs both commands. Do not use a deployment image.

- [ ] **Step 5: Run the full verification set**

Run locally:

```sh
dune build @all
dune runtest
MARCH_HCR_TEST_TMP=/tmp sh test/cross_hcr_compile.sh
```

Run on Linux CI:

```sh
sh test/run_cross_hcr_e2e.sh linux/amd64
sh test/run_cross_hcr_e2e.sh linux/arm64
```

Expected: unit tests pass; both bare-process live replacements change `v1` to `v2`; cross-target and altered-manifest attempts fail before upload or activation.

- [ ] **Step 6: Update operator documentation and commit**

Document the bootstrap sequence:

```toml
[hot-reload]
target = "linux/amd64"
module_prefix = "Forgepm"
socket = "/var/run/forgepm-hcr/forgepm.sock"
public_key = "<output of forge hot-reload show-pubkey>"
```

```sh
forge build --release
# Install this baseline once and set:
# MARCH_HOT_RELOAD_SOCKET=/var/run/forgepm-hcr/forgepm.sock
forge deploy hot
```

State that patches are in-memory until the next full baseline deployment. Replace the old macOS-to-Linux limitation note with the supported target and legacy-server rules.

```bash
git add forge/lib/cmd_deploy_hot.ml forge/test/test_cross_hcr_e2e.ml forge/test/dune test/native/hcr_e2e_server.march test/native/hcr_e2e_patch.march test/run_cross_hcr_e2e.sh .github/workflows/ci.yml docs/hot-code-reload.md specs/2026-07-04-cross-compile-linux-hot-deploy-design.md
git commit -m "test(hcr): cover bare cross-target hot deployment"
```
