# Forge Cap Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the capabilities of a compiled March executable extractable and trustworthy, by linking executables so unused capability code is physically absent, then reading what remains.

**Architecture:** Four independent phases. Phase 1 changes the link so the binary contains only the capability code it uses — this is the security property everything else reports on. Phase 2 emits per-capability marker symbols from codegen and adds `forge cap audit`. Phase 3 records source-derived cap sets at publish time so registry artifacts can be checked against their source. Phase 4 adds an opt-in self-imposed sandbox. Each phase ships working software on its own.

**Tech Stack:** OCaml 5.3.0, dune, menhir; clang/LLVM for codegen and linking; `nm`/`otool`/`objdump` for binary inspection; cmdliner for the forge CLI.

**Spec:** `specs/2026-08-03-forge-cap-audit-design.md` (v2). Read §3 and §4 before starting — they record measurements that rule out three approaches that look obviously correct.

## Global Constraints

- Never use `eval $(opam env ...)`. Run `dune`/`opam` directly.
- Build with `dune build --root .`. A bare targetless `dune build` can wedge; prefer named targets or `scripts/run-tests.sh`.
- Run tests with `scripts/run-tests.sh` (full, ~17s) or `-q` (quick). Judge by exit code `$?`, never by tail output.
- Never pipe `march --compile` output — redirect to a file and read it separately.
- Stage files explicitly by name. Never `git add -A`, `git add .`, or `git commit -am`.
- No `Co-Authored-By` lines in commits.
- Update `specs/todos/` and `specs/progress/` in the same commit that lands a feature. Add a `CHANGELOG.md` bullet under `## [Unreleased]` for user-visible changes.
- Any codegen- or link-affecting flag MUST be added to `cas_flags` in `bin/main.ml:1798`, or cached binaries silently ignore it.
- Capability path strings are dot-joined and normalized only via `March_caps.Cap_lattice.normalize`. Never hand-roll subsumption.

---

## Phase 1 — Dead-strip executables (the security property)

### Task 1: Platform-selected dead-strip for executables

**Files:**
- Modify: `bin/main.ml:3007-3025` (add `strip_flag` beside `so_flag`)
- Modify: `bin/main.ml:3137-3160` (add section flags to `cflags`)
- Modify: `bin/main.ml:3180` (thread `strip_flag` into the link command)
- Modify: `bin/main.ml:1798-1804` AND `bin/main.ml:2783-2789` (add strip mode to `cas_flags` — BOTH sites)
- Test: `test/test_cap_strip.ml` (new), registered in `Test_compiler.compiler_suites` (`test/test_compiler.ml:10665`)

**Interfaces:**
- Consumes: `link_is_linux : bool` and `!compile_so : bool`, both already in scope at `bin/main.ml:3007`.
- Produces: `strip_flag : string` — `" -Wl,-dead_strip"` on macOS, `" -Wl,--gc-sections"` on Linux, `""` for `.so`/hot-reload builds.

- [ ] **Step 1: Write the failing test**

Create `test/test_cap_strip.ml`:

```ocaml
(* A pure program must NOT contain the file-read runtime entry point after
   dead-stripping; a program that reads a file MUST contain it — including
   when the call is routed through a closure, which is the case that defeats
   call-site scanning (see specs/2026-08-03-forge-cap-audit-design.md §3). *)

let compile src_text out_bin =
  let src = Filename.temp_file "cap_strip" ".march" in
  let oc = open_out src in output_string oc src_text; close_out oc;
  let log = Filename.temp_file "cap_strip" ".log" in
  let rc = Sys.command (Printf.sprintf
    "./_build/default/bin/main.exe --compile -o %s %s > %s 2>&1"
    (Filename.quote out_bin) (Filename.quote src) (Filename.quote log)) in
  if rc <> 0 then failwith ("compile failed; see " ^ log);
  Sys.remove src

let has_symbol bin sym =
  let out = Filename.temp_file "nm" ".txt" in
  ignore (Sys.command (Printf.sprintf "nm %s > %s 2>/dev/null"
                         (Filename.quote bin) (Filename.quote out)));
  let ic = open_in out in
  let found = ref false in
  (try while true do
     let line = input_line ic in
     (* match the symbol as a whole word at end of line: "_march_file_read" *)
     let n = String.length sym in
     let l = String.length line in
     if l >= n && String.sub line (l - n) n = sym then found := true
   done with End_of_file -> ());
  close_in ic; Sys.remove out; !found

let pure_src = {|
mod PureStripApp do
  fn main() : () do
    println(int_to_string(1 + 1))
  end
end
|}

let closure_src = {|
mod ClosureStripApp do
  needs IO.FileRead

  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end

  fn main() : () do
    match apply1(fn p -> file_read(p), "/etc/hosts") do
      Ok(_)  -> println("ok")
      Err(_) -> println("err")
    end
  end
end
|}

(* On macOS the runtime symbol is prefixed with an underscore; on Linux it is not. *)
let file_read_sym = if Sys.file_exists "/usr/lib/dyld" then "_march_file_read"
                    else "march_file_read"

let test_pure_lacks_file_read () =
  let bin = Filename.temp_file "pure_strip" ".bin" in
  compile pure_src bin;
  Alcotest.(check bool) "pure binary must not contain march_file_read"
    false (has_symbol bin file_read_sym);
  Sys.remove bin

let test_closure_keeps_file_read () =
  let bin = Filename.temp_file "closure_strip" ".bin" in
  compile closure_src bin;
  Alcotest.(check bool) "closure-routed file read must retain march_file_read"
    true (has_symbol bin file_read_sym);
  Sys.remove bin

let tests = [
  "pure binary is stripped of file_read", `Slow, test_pure_lacks_file_read;
  "closure-routed file read retains file_read", `Slow, test_closure_keeps_file_read;
]
```

Register it by appending `("cap_strip", Test_cap_strip.tests);` to
`Test_compiler.compiler_suites` (`test/test_compiler.ml:10665`) —
`test/run_compiler.ml` is a one-line driver over that list and does not change.

- [ ] **Step 2: Run the test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test cap_strip
```

Expected: FAIL on "pure binary must not contain march_file_read" — without dead-strip the whole runtime is linked, so the symbol is present. This is the app-invariance baseline from spec §3.

- [ ] **Step 3: Add the strip flag**

In `bin/main.ml`, immediately after the `so_flag` binding that ends at line 3025, add:

```ocaml
            let strip_flag =
              (* Capability-by-absence (specs/2026-08-03-forge-cap-audit-design.md §4.1):
                 drop runtime functions the program never references, so a binary
                 physically cannot perform a capability it does not use.

                 Executables only.  A hot-reload .so resolves __march_init and
                 __migrate_<Actor> via dlsym (runtime/march_reload.c:318-351),
                 which the linker cannot see, so stripping would break hot deploy.
                 The same applies to the --hot-reload server build, whose exported
                 symbols are resolved from a dlopen'd patch .so. *)
              if !compile_so || !hot_reload_prefix <> None then ""
              else if link_is_linux then " -Wl,--gc-sections"
              else " -Wl,-dead_strip" in
```

In the `cflags` binding inside `runtime_objs` (around line 3158), append the
section flags so ELF gets function granularity. Change the `Printf.sprintf`
format string's trailing `%s%s%s` group by adding one more `%s` and passing
`section_cflags` as its argument, where:

```ocaml
                (* ELF --gc-sections only drops whole sections.  Without
                   -ffunction-sections each object's .text is one section, so
                   individual functions survive (verified with gcc 11 and
                   clang 18).  Mach-O gets function granularity for free via
                   .subsections_via_symbols.  Runtime_archive.ensure already
                   folds cflags into its cache key, so adding this invalidates
                   stale objects automatically. *)
                let section_cflags =
                  if link_is_linux then " -ffunction-sections -fdata-sections"
                  else "" in
```

Add the same `section_cflags` to the non-cached fallback compile path so both
routes produce identical objects.

Finally, thread `strip_flag` into the link command at line 3180 by adding one
`%s` to the format string immediately before ` -o %s` and passing `strip_flag`
in the matching argument position.

- [ ] **Step 4: Register the flag in the CAS key — at BOTH sites**

`cas_flags` is constructed twice, at `bin/main.ml:1798` and `bin/main.ml:2783`,
each feeding its own `Cas.compilation_hash`. Extend **both** identically:

```ocaml
              @ (if !compile_so then ["compile-so"] else [])
              @ (if !compile_so || !hot_reload_prefix <> None
                 then [] else ["capstrip"])
```

Patching only one is a silent failure: binaries built through the other path
keep pre-change cache keys, so a stale unstripped artifact is served and the
audit reports every capability. Verify both took effect with
`MARCH_DEBUG_CASFLAGS=1` (it prints `flags=[...]`; `capstrip` must appear).

- [ ] **Step 5: Run the test to verify it passes**

```bash
dune build --root . && ./_build/default/test/run_compiler.exe -e test cap_strip
```

Expected: PASS, both cases.

- [ ] **Step 6: Verify nothing else broke, and record the size win**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Then confirm the size reduction on a benchmark:

```bash
./_build/default/bin/main.exe --compile --opt 2 -o /tmp/bt_1f5c33 bench/binary_trees.march > /tmp/bt.log 2>&1 && ls -l /tmp/bt_1f5c33 && /tmp/bt_1f5c33 | head -3
```

Expected: ~75KB rather than ~270KB, identical output to before the change.

- [ ] **Step 7: Commit**

```bash
git add bin/main.ml test/test_cap_strip.ml test/test_compiler.ml
git commit -m "build: dead-strip executables so unused capability code is absent"
```

---

### Task 2: Prove dead-strip is safe for actors, HTTP, and TLS

Spec §10 lists these as untested at design time. They lean on callback tables and
`dlsym`-adjacent patterns, which are exactly what a linker's reachability
analysis gets wrong.

**Files:**
- Modify: `test/test_cap_strip.ml` (add a corpus smoke test)

**Interfaces:**
- Consumes: `compile`, `has_symbol` from Task 1.
- Produces: nothing consumed later; this is a safety gate.

- [ ] **Step 1: Write the failing test**

Append to `test/test_cap_strip.ml`:

```ocaml
(* Dead-stripping must not change observable behavior for programs that reach
   the runtime through callback tables (actors) or long-lived event loops
   (HTTP/TLS).  Each fixture is run and its stdout compared against the
   interpreter, which is unaffected by link flags. *)

let run_capture bin =
  let out = Filename.temp_file "run" ".txt" in
  let rc = Sys.command (Printf.sprintf "%s > %s 2>&1"
                          (Filename.quote bin) (Filename.quote out)) in
  let ic = open_in out in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; Sys.remove out; (rc, s)

let actor_src = {|
mod ActorStripApp do
  actor Counter do
    state count : Int = 0

    handle bump() : Int do
      state.count = state.count + 1
      state.count
    end
  end

  fn main() : () do
    let c = Counter.start()
    let _ = Counter.bump(c)
    println(int_to_string(Counter.bump(c)))
  end
end
|}

let test_actor_program_survives_strip () =
  let bin = Filename.temp_file "actor_strip" ".bin" in
  compile actor_src bin;
  let (rc, out) = run_capture bin in
  Alcotest.(check int) "actor program exits 0" 0 rc;
  Alcotest.(check string) "actor program prints 2" "2\n" out;
  Sys.remove bin

let tests = tests @ [
  "actor program survives dead-strip", `Slow, test_actor_program_survives_strip;
]
```

If the actor surface syntax above does not match the current parser, adapt it
from a working actor fixture found via `forge search` — do not weaken the test
to a program that avoids actors.

- [ ] **Step 2: Run it**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test cap_strip
```

Expected: PASS if Task 1 is safe for actors. If it FAILS, that is a real finding
— the fix is to pin the affected runtime entry points with
`__attribute__((used))` in the relevant `runtime/*.c` file, then re-run.

- [ ] **Step 3: Extend to HTTP and TLS by hand**

```bash
./_build/default/bin/main.exe --compile -o /tmp/http_1f5c33 <an http fixture>.march > /tmp/http.log 2>&1; echo $?
```

Locate fixtures with `forge search` over the stdlib http/tls modules. Confirm each
runs correctly. Any breakage is fixed the same way — `__attribute__((used))` on
the entry point the linker wrongly dropped.

- [ ] **Step 4: Commit**

```bash
git add test/test_cap_strip.ml
git commit -m "test: verify dead-strip preserves actor, HTTP, and TLS behavior"
```

---

## Phase 2 — Cap marker symbols and `forge cap audit`

### Task 3: Cap → runtime symbol table

**Files:**
- Create: `lib/caps/cap_symbols.ml`, `lib/caps/cap_symbols.mli`
- Modify: `lib/caps/dune` (no new deps; `march_typecheck` must not be depended on — see below)
- Test: `test/test_cap_symbols.ml` (new), registered in `Test_compiler.compiler_suites` (`test/test_compiler.ml:10665`)

**Interfaces:**
- Produces:
  - `val table : (string * string) list` — `(runtime_c_symbol, cap_path)`, e.g. `("march_file_read", "IO.FileRead")`.
  - `val cap_of_symbol : string -> string option` — accepts either `march_file_read` or the Mach-O `_march_file_read` spelling.
  - `val all_caps : string list` — every cap appearing in `table`, deduplicated.

`lib/caps` must not depend on `march_typecheck` (that would be a dependency
cycle — typecheck already depends on caps). Generate the table as a literal in
`cap_symbols.ml`, and add a freshness test (Step 3) that fails when
`builtin_cap_table` and this table drift apart. This mirrors the existing
`emit_c_table.ml` freshness-check pattern.

- [ ] **Step 1: Write the failing test**

Create `test/test_cap_symbols.ml`:

```ocaml
let test_known_mappings () =
  Alcotest.(check (option string)) "file_read maps to IO.FileRead"
    (Some "IO.FileRead")
    (March_caps.Cap_symbols.cap_of_symbol "march_file_read");
  Alcotest.(check (option string)) "underscore-prefixed Mach-O spelling works"
    (Some "IO.FileRead")
    (March_caps.Cap_symbols.cap_of_symbol "_march_file_read");
  Alcotest.(check (option string)) "unknown symbol maps to nothing"
    None
    (March_caps.Cap_symbols.cap_of_symbol "march_list_map")

(* Freshness: for every builtin the typechecker attributes a cap to, the C
   symbol it lowers to must map to that same cap here.  Cap-level coverage is
   NOT enough — a missing symbol under an otherwise-covered cap silently
   under-reports that builtin.  Joined through the codegen builtin table;
   lib/tir has no .mli files, so [March_tir.Llvm_builtins.builtins] is
   accessible from tests. *)
let test_no_drift_from_builtin_cap_table () =
  let missing =
    List.filter_map (fun (march_name, cap) ->
      match List.find_opt
              (fun (b : March_tir.Llvm_builtins.builtin) ->
                b.March_tir.Llvm_builtins.march_name = march_name)
              March_tir.Llvm_builtins.builtins with
      | None | Some { March_tir.Llvm_builtins.c_name = None; _ } ->
        None  (* no runtime symbol to audit *)
      | Some { March_tir.Llvm_builtins.c_name = Some c; _ } ->
        if March_caps.Cap_symbols.cap_of_symbol c = Some cap then None
        else Some (Printf.sprintf "%s (%s) -> %s" march_name c cap))
      March_typecheck.Typecheck.builtin_cap_table
  in
  Alcotest.(check (list string))
    "every cap-bearing builtin's C symbol maps to its cap" [] missing

let tests = [
  "known cap symbol mappings", `Quick, test_known_mappings;
  "no drift from builtin_cap_table", `Quick, test_no_drift_from_builtin_cap_table;
]
```

The test lives in `test/`, which may depend on both libraries, so the freshness
check works without creating a cycle.

- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . test/run_compiler.exe 2>&1 | tail -5
```

Expected: build FAILS — `March_caps.Cap_symbols` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/caps/cap_symbols.mli`:

```ocaml
(** Capability-bearing runtime entry points.

    Maps the C symbol a capability's builtin lowers to (see the builtin table in
    [lib/tir/llvm_builtins.ml]) to the capability path the typechecker attributes
    to it (see [builtin_cap_table] in [lib/typecheck/typecheck.ml]).

    Consumed by [forge cap audit] to read a binary's capabilities from its
    symbol table.  Kept in sync with [builtin_cap_table] by a freshness test in
    [test/test_cap_symbols.ml] — this module cannot depend on the typechecker
    without creating a cycle. *)

val table : (string * string) list
(** [(runtime_c_symbol, cap_path)] pairs, e.g. [("march_file_read", "IO.FileRead")]. *)

val cap_of_symbol : string -> string option
(** Accepts either the plain [march_file_read] or Mach-O [_march_file_read]
    spelling. *)

val all_caps : string list
(** Every distinct capability path appearing in [table]. *)
```

Create `lib/caps/cap_symbols.ml` with the literal table. Build it by walking
`builtin_cap_table` (`lib/typecheck/typecheck.ml:1661`) and, for each entry,
finding the matching `march_name` in the builtin table at
`lib/tir/llvm_builtins.ml:474` to read its `c_name`. Start with:

```ocaml
let table : (string * string) list = [
  (* IO.FileRead *)
  ("march_file_read",        "IO.FileRead");
  ("march_file_read_line",   "IO.FileRead");
  ("march_file_read_chunk",  "IO.FileRead");
  ("march_file_exists",      "IO.FileRead");
  (* IO.FileWrite *)
  ("march_file_write",       "IO.FileWrite");
  ("march_file_append",      "IO.FileWrite");
  ("march_file_delete",      "IO.FileWrite");
  ("march_file_copy",        "IO.FileWrite");
  (* IO.Mut *)
  ("march_vault_set",        "IO.Mut");
  ("march_vault_set_ttl",    "IO.Mut");
  (* IO.Process *)
  ("march_process_exit",     "IO.Process");
  ("march_process_env",      "IO.Process");
  ("march_process_set_env",  "IO.Process");
  ("march_process_spawn_sync",  "IO.Process");
  ("march_process_spawn_async", "IO.Process");
  (* … complete for every entry in builtin_cap_table … *)
]

let strip_underscore s =
  if String.length s > 0 && s.[0] = '_'
  then String.sub s 1 (String.length s - 1) else s

let cap_of_symbol sym = List.assoc_opt (strip_underscore sym) table

let all_caps =
  List.sort_uniq String.compare (List.map snd table)
```

The freshness test tells you when the table is complete: it lists every
cap-bearing builtin whose C symbol is missing or mismapped. Work until that
list is empty.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune build --root . && ./_build/default/test/run_compiler.exe -e test cap_symbols
```

Expected: PASS, both cases, with the drift list empty.

- [ ] **Step 5: Commit**

```bash
git add lib/caps/cap_symbols.ml lib/caps/cap_symbols.mli lib/caps/dune test/test_cap_symbols.ml test/test_compiler.ml
git commit -m "caps: add capability to runtime-symbol table with drift test"
```

---

### Task 4: Emit cap marker symbols from codegen

Markers are derived from the builtins actually referenced in the **emitted LLVM
module**, not from the typechecker's claim, so they reflect codegen reality.

**Files:**
- Modify: `lib/tir/llvm_ctx.ml` (record called builtin c_names in the emit context)
- Modify: `lib/tir/llvm_calls.ml` (record at the direct-call emission site)
- Modify: `lib/tir/llvm_builtins.ml` (record in the builtin apply-fn/wrapper path)
- Modify: `lib/tir/llvm_emit.ml` (emit markers in the module epilogue)
- Test: `test/test_cap_markers.ml` (new), registered in `Test_compiler.compiler_suites` (`test/test_compiler.ml:10665`)

**Interfaces:**
- Consumes: `March_caps.Cap_symbols.cap_of_symbol` from Task 3.
- Produces: globals named `__march_cap_<CAP_WITH_DOTS_AS_UNDERSCORES>`, e.g. `__march_cap_IO_FileRead`, pinned in `@llvm.used`.

- [ ] **Step 1: Write the failing test**

Create `test/test_cap_markers.ml`:

```ocaml
(* A marker global must exist for each capability the emitted module actually
   references, and must NOT exist for capabilities it does not use. *)

let emit_ir src_text =
  let src = Filename.temp_file "cap_marker" ".march" in
  let oc = open_out src in output_string oc src_text; close_out oc;
  (* --emit-llvm ignores -o: it writes <input-basename>.ll next to the input
     (bin/main.ml:2616, `let ll_file = basename ^ ".ll"`). *)
  let ll = Filename.remove_extension src ^ ".ll" in
  let rc = Sys.command (Printf.sprintf
    "./_build/default/bin/main.exe --emit-llvm %s > /dev/null 2>&1"
    (Filename.quote src)) in
  if rc <> 0 then failwith "emit-llvm failed";
  let ic = open_in ll in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; Sys.remove src; Sys.remove ll; s

let contains haystack needle =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl &&
    (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let file_src = {|
mod MarkerFileApp do
  needs IO.FileRead
  fn main() : () do
    match file_read("/etc/hosts") do
      Ok(_) -> println("ok")
      Err(_) -> println("err")
    end
  end
end
|}

let pure_src = {|
mod MarkerPureApp do
  fn main() : () do
    println("hi")
  end
end
|}

let test_marker_present_for_used_cap () =
  let ir = emit_ir file_src in
  Alcotest.(check bool) "IO.FileRead marker emitted"
    true (contains ir "__march_cap_IO_FileRead")

let test_marker_absent_for_unused_cap () =
  let ir = emit_ir pure_src in
  Alcotest.(check bool) "IO.FileRead marker not emitted for a pure program"
    false (contains ir "__march_cap_IO_FileRead")

let tests = [
  "marker emitted for used capability", `Quick, test_marker_present_for_used_cap;
  "no marker for unused capability", `Quick, test_marker_absent_for_unused_cap;
]
```


- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test cap_markers
```

Expected: FAIL on "IO.FileRead marker emitted" — nothing emits markers yet.

- [ ] **Step 3: Implement marker emission**

In `lib/tir/llvm_emit.ml`, at the point where the module epilogue is written
(the same place `@llvm.used` and other module-level globals are emitted — find
it by searching for `llvm.used` or the function that finalizes the module),
add:

```ocaml
(* Capability markers (specs/2026-08-03-forge-cap-audit-design.md §4.3, C).
   Derived from the runtime entry points this module actually references, so
   the markers describe emitted code rather than the typechecker's claim.
   Pinned in @llvm.used so DCE and dead-strip cannot drop them: a marker's
   absence must mean "capability unused", never "optimizer removed it". *)
let emit_cap_markers buf ~(called_c_symbols : string list) =
  let caps =
    called_c_symbols
    |> List.filter_map March_caps.Cap_symbols.cap_of_symbol
    |> List.sort_uniq String.compare
    |> March_caps.Cap_lattice.normalize
  in
  let mangle cap = String.map (fun c -> if c = '.' then '_' else c) cap in
  List.iter (fun cap ->
    Buffer.add_string buf
      (Printf.sprintf "@__march_cap_%s = constant i8 1\n" (mangle cap)))
    caps;
  if caps <> [] then begin
    let refs =
      List.map (fun cap ->
        Printf.sprintf "ptr @__march_cap_%s" (mangle cap)) caps in
    Buffer.add_string buf
      (Printf.sprintf
         "@llvm.used = appending global [%d x ptr] [%s], section \"llvm.metadata\"\n"
         (List.length refs) (String.concat ", " refs))
  end
```

**Where `called_c_symbols` comes from — the correctness-critical choice.**
The declare preamble is NOT usable: `emit_preamble`
(`lib/tir/llvm_toplevel.ml:101-110`) emits `declare`s for **every builtin
unconditionally** — it is a fixed blob. Deriving markers from declares would
emit every marker in every binary, the app-invariance trap a third time.
(Unused declares produce no relocations, which is why dead-strip itself still
works — but used and unused are indistinguishable at the declare level.)

Record at call-emission time instead: add a
`called_builtins : (string, unit) Hashtbl.t` to the emit context in
`lib/tir/llvm_ctx.ml`, and record the `c_name` at each site that emits a direct
call to a builtin's C symbol — the direct-call path in `lib/tir/llvm_calls.ml`
and the builtin apply-fn/wrapper path in `lib/tir/llvm_builtins.ml` (the
wrapper's generated body contains the same direct call, which is what keeps the
closure-routed case covered). `emit_cap_markers` reads that table.

No `@llvm.used` global exists in the current emitter (verified:
`grep -rn "llvm.used" lib/tir/` is empty), so the marker block is the only one —
no merging needed.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune build --root . && ./_build/default/test/run_compiler.exe -e test cap_markers
```

Expected: PASS, both cases.

- [ ] **Step 5: Verify markers survive the actual link**

```bash
./_build/default/bin/main.exe --compile -o /tmp/mk_1f5c33 <the file_src fixture>.march > /tmp/mk.log 2>&1
nm /tmp/mk_1f5c33 | grep __march_cap
```

Expected: `__march_cap_IO_FileRead` present. If it is missing, `@llvm.used` did
not pin it through dead-strip — that is a real bug in Step 3, not a reason to
disable stripping.

Then verify the same on Linux (docker, as in the Task 1 flow): on ELF,
`@llvm.used` survives `--gc-sections` only via the `SHF_GNU_RETAIN` section
flag, which needs a reasonably recent clang/binutils. If the marker is GC'd
there, place markers in an explicitly retained section rather than weakening
the strip — a marker's absence must always mean "capability unused", never
"linker removed it".

- [ ] **Step 6: Commit**

```bash
git add lib/tir/llvm_emit.ml lib/tir/llvm_ctx.ml lib/tir/llvm_calls.ml lib/tir/llvm_builtins.ml test/test_cap_markers.ml test/test_compiler.ml
git commit -m "codegen: emit capability marker symbols from called runtime entries"
```

---

### Task 5: Binary reader

**Files:**
- Create: `forge/lib/cap_binary.ml`, `forge/lib/cap_binary.mli`
- Test: `forge/test/test_cap_binary.ml` (new; register in `forge/test/dune`)

**Interfaces:**
- Produces:
  ```ocaml
  type build_kind = Dead_stripped | Unstripped | Symbols_removed
  type t = {
    caps        : string list;      (* normalized *)
    markers     : string list;      (* from __march_cap_* globals *)
    rt_symbols  : string list;      (* cap-bearing runtime symbols present *)
    build       : build_kind;
    manifest    : string option;    (* raw JSON, None when absent *)
  }
  val read : string -> (t, string) result
  ```

- [ ] **Step 1: Write the failing test**

Create `forge/test/test_cap_binary.ml`:

```ocaml
(* The reader must classify the build, never assume stripping happened, and
   must refuse a binary carrying two manifest blobs (a planted blob would
   otherwise shadow the real one — design §6). *)

let test_unstripped_is_reported_as_such () =
  (* A binary where every cap symbol is present was not stripped; reporting its
     full symbol set as "capabilities" would be the app-invariance failure. *)
  match Cap_binary.read "test/fixtures/unstripped.bin" with
  | Error e -> Alcotest.fail e
  | Ok t ->
    Alcotest.(check bool) "classified unstripped"
      true (t.Cap_binary.build = Cap_binary.Unstripped)

let test_duplicate_manifest_is_an_error () =
  match Cap_binary.read "test/fixtures/two_manifests.bin" with
  | Ok _ -> Alcotest.fail "must not accept a binary with two manifest blobs"
  | Error msg ->
    Alcotest.(check bool) "error mentions multiple manifests"
      true (String.length msg > 0)

let tests = [
  "unstripped build is reported, not treated as full caps", `Quick,
    test_unstripped_is_reported_as_such;
  "duplicate manifest blobs are rejected", `Quick,
    test_duplicate_manifest_is_an_error;
]
```

Build the two fixtures in the test's setup: compile a trivial program for
`unstripped.bin` using `MARCH_NO_RUNTIME_CACHE=1` and a build without the strip
flag, and produce `two_manifests.bin` by appending a second
`MARCHCAP\x01`-prefixed blob to a copy of a normal binary.

- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . forge/test/ 2>&1 | tail -5
```

Expected: build FAILS — `Cap_binary` does not exist.

- [ ] **Step 3: Implement the reader**

Create `forge/lib/cap_binary.ml`. Read caps from three sources and combine:

```ocaml
type build_kind = Dead_stripped | Unstripped | Symbols_removed

type t = {
  caps       : string list;
  markers    : string list;
  rt_symbols : string list;
  build      : build_kind;
  manifest   : string option;
}

let read_symbols path =
  let out = Filename.temp_file "capnm" ".txt" in
  let rc = Sys.command (Printf.sprintf "nm %s > %s 2>/dev/null"
                          (Filename.quote path) (Filename.quote out)) in
  if rc <> 0 then begin
    (try Sys.remove out with Sys_error _ -> ());
    []                     (* nm failed: caller classifies via other channels *)
  end else begin
    let acc = ref [] in
    let ic = open_in out in
    (try while true do
       let line = input_line ic in
       match String.rindex_opt line ' ' with
       | Some i -> acc := String.sub line (i+1) (String.length line - i - 1) :: !acc
       | None -> ()
     done with End_of_file -> ());
    close_in ic;
    (try Sys.remove out with Sys_error _ -> ());
    !acc
  end

(* Locate every MARCHCAP\x01 blob.  Multiplicity is an error: a planted blob
   placed earlier in the file would otherwise shadow the real manifest. *)
let find_manifests data =
  let magic = "MARCHCAP\x01" in
  let ml = String.length magic and dl = String.length data in
  let rec go i acc =
    if i + ml > dl then List.rev acc
    else if String.sub data i ml = magic then go (i + ml) (i :: acc)
    else go (i + 1) acc
  in
  go 0 []
```

Classify the build:

- **`Symbols_removed`** — no `__march_cap_*` markers *and* no cap-bearing
  runtime symbols at all. Names were stripped; report reduced coverage.
- **`Unstripped`** — *every* symbol in `Cap_symbols.table` is present. A real
  program almost never uses all of them; this means the strip flag did not
  apply (a stale CAS entry, or a Linux build whose runtime objects predate the
  section flags). Report the build, not a capability list.
- **`Dead_stripped`** — otherwise.

Derive `caps` from markers when present (precise, March-level), falling back to
`rt_symbols` mapped through `Cap_symbols.cap_of_symbol`. Normalize with
`Cap_lattice.normalize`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune build --root . && ./_build/default/forge/test/<runner>.exe -e
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add forge/lib/cap_binary.ml forge/lib/cap_binary.mli forge/test/test_cap_binary.ml forge/test/dune
git commit -m "forge: add capability reader for compiled binaries"
```

---

### Task 6: `forge cap audit` command

**Files:**
- Modify: `forge/lib/cmd_cap.ml` (add `audit`)
- Modify: `forge/bin/main.ml:963-966` (add the subcommand to `cap_cmd`)
- Test: `forge/test/test_cap_audit.ml` (new)

**Interfaces:**
- Consumes: `Cap_binary.read` from Task 5, `Cap_lattice.cap_subsumes`.
- Produces: `val audit : bin:string -> json:bool -> deny:string list -> allow_only:string list option -> allow_foreign:bool -> baseline:string option -> (unit, string) result`

- [ ] **Step 1: Write the failing test**

Create `forge/test/test_cap_audit.ml`:

```ocaml
(* The gate must be fail-closed: anything less than full coverage fails unless
   explicitly allowed.  Stripping is an evasion, not merely a degradation. *)

let test_deny_matches_subsumed_cap () =
  (* --deny IO must reject a binary needing IO.FileRead, via the lattice. *)
  let r = Cmd_cap.audit ~bin:"test/fixtures/filereader.bin" ~json:false
            ~deny:["IO"] ~allow_only:None ~allow_foreign:false ~baseline:None in
  Alcotest.(check bool) "denied capability fails the gate"
    true (match r with Error _ -> true | Ok () -> false)

let test_gate_fails_on_reduced_coverage () =
  let r = Cmd_cap.audit ~bin:"test/fixtures/stripped.bin" ~json:false
            ~deny:[] ~allow_only:None ~allow_foreign:false ~baseline:None in
  Alcotest.(check bool) "reduced coverage fails the gate by default"
    true (match r with Error _ -> true | Ok () -> false)

let tests = [
  "deny uses lattice subsumption", `Quick, test_deny_matches_subsumed_cap;
  "gate fails closed on reduced coverage", `Quick, test_gate_fails_on_reduced_coverage;
]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . 2>&1 | tail -5
```

Expected: FAILS — `Cmd_cap.audit` does not exist.

- [ ] **Step 3: Implement `audit`**

Add to `forge/lib/cmd_cap.ml`, following the existing `query`/`coverage` style.
Render per design §5.1. Rules that are not optional:

- `IO.Foreign` is **not** a row in the capability table. It gets its own section
  with the extern symbols and the sentence from §5.1 stating that analysis stops
  at the FFI boundary.
- The final line always prints three verdicts: `build:`, `notarized:`,
  `coverage:`. Never collapse them into one boolean.
- `--json` always includes `coverage`.
- The gate (`--deny` / `--allow-only`) fails on any `coverage` other than full,
  unless `--allow-foreign` is passed for the foreign-code case specifically.

- [ ] **Step 4: Wire up the CLI**

In `forge/bin/main.ml`, add an `cap_audit_cmd` beside `cap_query_cmd` and
`cap_coverage_cmd` (lines 933-961 show the exact cmdliner pattern), then add it
to the group at line 966:

```ocaml
    [cap_query_cmd; cap_coverage_cmd; cap_audit_cmd]
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dune build --root . && ./_build/default/forge/test/<runner>.exe -e
```

Expected: PASS.

- [ ] **Step 6: Manual smoke test**

```bash
./_build/default/forge/bin/main.exe cap audit /tmp/mk_1f5c33
```

Expected: `IO.FileRead` listed, `build: dead-stripped`, `coverage: full`.

- [ ] **Step 7: Update docs and commit**

Add a `CHANGELOG.md` bullet under `## [Unreleased]` → `### Added`, and file
`specs/progress/2026-08-03-forge-cap-audit-phase-1-2.md` describing what shipped.

```bash
git add forge/lib/cmd_cap.ml forge/bin/main.ml forge/test/test_cap_audit.ml CHANGELOG.md specs/progress/2026-08-03-forge-cap-audit-phase-1-2.md
git commit -m "forge: add cap audit for compiled binaries"
```

---

## Phase 3 — Registry notarization (D)

### Task 7: Record the cap set at publish time

**Files:**
- Modify: `forge/lib/cmd_publish.ml` (compute and attach the cap set)
- Modify: `forge/lib/registry_client.ml` (send/receive the field)
- Test: `forge/test/test_cap_notarize.ml` (new)

**Interfaces:**
- Consumes: `March_typecheck.Typecheck.fn_own_capability_closures` via a package
  typecheck. NOT the parse-only walk in `Cmd_cap.query` — that sees only
  *declared* `needs`, which is insufficient (see Step 3).
- Produces: `val cap_set_of_project : root:string -> (string list, string) result` in `cmd_publish.ml`, and a `caps` field on the published package record.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_cap_set_is_normalized () =
  match Cmd_publish.cap_set_of_project ~root:"test/fixtures/proj_filereader" with
  | Error e -> Alcotest.fail e
  | Ok caps ->
    Alcotest.(check (list string)) "normalized cap set"
      ["IO.FileRead"] caps

(* The F1 gap: a body call to file_read with no `needs` is WARNING-only at
   --check, but must still notarize.  If publish recorded only declared needs,
   this package would publish as [] while its own honest binary reports
   IO.FileRead — a false registry-MISMATCH in Task 8. *)
let test_body_call_without_needs_is_included () =
  match Cmd_publish.cap_set_of_project ~root:"test/fixtures/proj_body_call_only" with
  | Error e -> Alcotest.fail e
  | Ok caps ->
    Alcotest.(check (list string)) "inferred caps, not just declared needs"
      ["IO.FileRead"] caps

let tests = [
  "publish computes a normalized cap set", `Quick, test_cap_set_is_normalized;
  "body-call-only caps are notarized", `Quick, test_body_call_without_needs_is_included;
]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
dune build --root . 2>&1 | tail -5
```

Expected: FAILS — `cap_set_of_project` does not exist.

- [ ] **Step 3: Implement it**

**Do not compute this from the parse-only walk in `Cmd_cap.query`.** That walk
extracts *declared* `needs` only, but body-scanned caps are WARNING-only (the
F1 gap the design cites in §2) — a module calling `file_read` with no `needs`
would publish as `[]`, and its own honest binary would then report
`IO.FileRead`, producing a false `registry-MISMATCH` in Task 8.

Compute the *inferred* set instead: typecheck the package (the same
entry-per-file check `forge build` performs — see
`project_forge_build_per_file_entry` conventions in `forge/lib/cmd_check.ml`)
and take the union of `Typecheck.fn_own_capability_closures` over the
package's own functions (filter to qualified names whose module prefix belongs
to the package, so linked stdlib functions are excluded — including them would
recreate the app-invariant union). Return `Cap_lattice.normalize`d, sorted
caps. Attach to the publish payload beside the existing API-surface data
(`forge/lib/cmd_publish.ml:51-53` shows where surface extraction happens).

- [ ] **Step 4: Run tests and commit**

```bash
dune build --root . && ./_build/default/forge/test/<runner>.exe -e
git add forge/lib/cmd_publish.ml forge/lib/registry_client.ml forge/test/test_cap_notarize.ml
git commit -m "forge: record source-derived capability set when publishing"
```

---

### Task 8: `forge cap audit --notarized`

**Files:**
- Modify: `forge/lib/cmd_cap.ml` (add the comparison)
- Modify: `forge/bin/main.ml` (add the flag)
- Test: `forge/test/test_cap_notarize.ml` (extend)

**Interfaces:**
- Consumes: `Cap_binary.read`, `Registry_client` lookup by artifact hash.
- Produces: a `notarized:` verdict — one of `registry-match`, `registry-MISMATCH <caps>`, `not-published`, `registry-unreachable`.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_mismatch_is_reported () =
  (* A binary claiming fewer caps than the registry's source-derived set is a
     mismatch and must not be reported as a match. *)
  let v = Cmd_cap.notarized_verdict
            ~binary_caps:["IO.Console"] ~registry_caps:["IO.Console"; "IO.Network"] in
  Alcotest.(check bool) "mismatch detected"
    true (match v with `Mismatch _ -> true | _ -> false)
```

- [ ] **Step 2: Run to verify failure, then implement**

Compare with `Cap_lattice.cap_subsumes`, not string equality: a binary needing
`IO.FileRead` is consistent with a registry record of `IO` but not vice versa.
`registry-unreachable` must never render as a match.

- [ ] **Step 3: Run tests and commit**

```bash
dune build --root . && ./_build/default/forge/test/<runner>.exe -e
git add forge/lib/cmd_cap.ml forge/bin/main.ml forge/test/test_cap_notarize.ml CHANGELOG.md
git commit -m "forge: compare binary capabilities against the registry record"
```

---

## Phase 4 — Optional self-imposed sandbox (B)

**Not default.** Enabled only by `--cap-sandbox`. It changes runtime behavior and
can break legitimate programs; the default build must be unaffected.

### Task 9: Sandbox profile derivation and installation

**Files:**
- Create: `runtime/march_sandbox.c`, `runtime/march_sandbox.h`
- Modify: `bin/main.ml` (add `--cap-sandbox`, add to `cas_flags`)
- Modify: `runtime/dune` or the runtime source list so the new file is compiled
- Test: `test/test_cap_sandbox.ml` (new)

**Interfaces:**
- Produces: `void march_sandbox_install(const char *const *caps, int n);` — installs a seccomp-bpf filter (Linux) or `sandbox_init` profile (macOS) permitting only the syscalls implied by `caps`, plus the runtime baseline.

- [ ] **Step 1: Write the failing test**

```ocaml
(* A sandboxed pure program must be killed if it attempts a file read.  The
   fixture calls file_read through a closure so the test also covers the
   routing that defeats static analysis. *)
let test_sandbox_blocks_undeclared_file_read () =
  let bin = Filename.temp_file "sandbox" ".bin" in
  compile_with_flags "--cap-sandbox" undeclared_file_read_src bin;
  let (rc, _) = run_capture bin in
  Alcotest.(check bool) "undeclared file read is blocked" true (rc <> 0);
  Sys.remove bin

let test_sandbox_allows_declared_file_read () =
  let bin = Filename.temp_file "sandbox_ok" ".bin" in
  compile_with_flags "--cap-sandbox" declared_file_read_src bin;
  let (rc, _) = run_capture bin in
  Alcotest.(check int) "declared file read still works" 0 rc;
  Sys.remove bin
```

The second test matters more than the first: a sandbox that blocks everything
passes the first test and is useless.

- [ ] **Step 2: Run to verify failure**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e test cap_sandbox
```

Expected: FAIL — no sandbox exists.

- [ ] **Step 3: Implement the runtime side**

Write `runtime/march_sandbox.c` mapping caps to syscall permissions:

| cap | Linux syscalls | macOS SBPL |
|---|---|---|
| `IO.FileRead` | `open`/`openat` (O_RDONLY), `read`, `fstat`, `close` | `(allow file-read*)` |
| `IO.FileWrite` | `open`/`openat` (write modes), `write`, `unlink`, `rename` | `(allow file-write*)` |
| `IO.NetConnect` | `socket`, `connect` | `(allow network-outbound)` |
| `IO.NetListen` | `bind`, `listen`, `accept` | `(allow network-inbound)` |
| `IO.Process` | `fork`, `execve`, `kill` | `(allow process-exec)` |
| `IO.Random` | `getrandom` | `(allow file-read* (literal "/dev/urandom"))` |

The **runtime baseline** must always be permitted regardless of caps — the GC,
scheduler, and thread machinery need `mmap`, `munmap`, `futex`/`ulock`,
`clock_gettime`, and thread creation. Characterize it by running the pure
fixture under `strace -c` (Linux) and adding exactly what it needs. Caps whose
syscalls are indistinguishable from the baseline (notably `IO.Clock` and
`IO.Spawn`) are **not enforceable** and must be documented as advisory in the
audit output rather than silently treated as enforced.

Call `march_sandbox_install` from the runtime entry point before user `main`
runs, gated on a compile-time define set by `--cap-sandbox`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune build --root . && ./_build/default/test/run_compiler.exe -e test cap_sandbox
```

Expected: PASS, both cases — especially the second.

- [ ] **Step 5: Verify the default build is unaffected**

```bash
scripts/run-tests.sh
```

Expected: exit 0, with no sandbox installed in any default-built binary.

- [ ] **Step 6: Commit**

```bash
git add runtime/march_sandbox.c runtime/march_sandbox.h bin/main.ml test/test_cap_sandbox.ml CHANGELOG.md
git commit -m "runtime: add opt-in capability sandbox behind --cap-sandbox"
```

---

### Task 10: `forge run --enforce`

Impose the profile externally so nothing in the binary needs to be trusted.

**Files:**
- Modify: `forge/lib/cmd_run.ml`
- Modify: `forge/bin/main.ml` (add `--enforce`)
- Test: `forge/test/test_cap_enforce.ml` (new)

**Interfaces:**
- Consumes: `Cap_binary.read` (Task 5), the cap→syscall mapping from Task 9.
- Produces: `val run_enforced : bin:string -> args:string list -> (int, string) result`

- [ ] **Step 1: Write the failing test**

```ocaml
(* Enforcement must not depend on the binary cooperating: a binary whose
   manifest under-claims is killed when it exceeds the claimed cap set. *)
let test_underclaiming_binary_is_killed () =
  let r = Cmd_run.run_enforced ~bin:"test/fixtures/underclaiming.bin" ~args:[] in
  Alcotest.(check bool) "under-claiming binary does not complete"
    true (match r with Ok 0 -> false | _ -> true)
```

Build `underclaiming.bin` by compiling a file-reading program and renaming its
marker symbol so the claim under-reports —
`llvm-objcopy --redefine-sym __march_cap_IO_FileRead=__march_cap_removed
in.bin underclaiming.bin` (llvm-objcopy handles both Mach-O and ELF and ships
with the clang toolchain). This is exactly the tampering the design says must
be self-defeating: enforcement derives the profile from the (falsified) claim,
and the program's real file read then violates it.

- [ ] **Step 2: Run to verify failure, then implement**

Read the cap set, derive the profile, and apply it to the child before `exec`
(`sandbox_init` in a forked child on macOS; seccomp before `execve` on Linux).

- [ ] **Step 3: Run tests and commit**

```bash
dune build --root . && ./_build/default/forge/test/<runner>.exe -e
git add forge/lib/cmd_run.ml forge/bin/main.ml forge/test/test_cap_enforce.ml CHANGELOG.md specs/progress/2026-08-03-forge-cap-audit-phase-3-4.md
git commit -m "forge: add run --enforce to impose a capability sandbox externally"
```

---

## Self-Review Notes

**Spec coverage.** §4.1 dead-strip → Tasks 1–2. §4.2 extraction channels →
Task 5's `build_kind`. §4.3 C → Tasks 3–4; D → Tasks 7–8; B → Tasks 9–10.
§4.4 confirm-the-build → Task 5 `Unstripped` classification, gated in Task 6.
§5 CLI → Task 6. §5.2 FFI framing → Task 6 Step 3. §10 test table → distributed
across each task's tests.

**Deliberately deferred.** §6 manifest emission is *not* a task: markers
(Task 4) supply the capability list, and the manifest only adds per-function
attribution (`witnesses`, `declared` vs `effective`). Task 10 assumes an
embedded manifest for its fixture — if Phase 4 runs before a manifest exists,
build that fixture from marker symbols instead. File manifest emission as its
own todo when Phase 2 lands.

**Known risk carried into execution.** Task 4 assumes `own_cap_closures` is not
needed for the marker path (markers are recorded at call-emission time in
codegen, avoiding the typecheck-name vs post-mono-name join entirely). If manifest emission is added
later, that join is unverified and must be tested before it is trusted — mono
and defun rename functions, and this codebase has been bitten by a suffix-map
mismatch in `llvm_emit` before.
