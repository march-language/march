(** The march driver's command-line flag cells.

    Hoisted verbatim out of [bin/main.ml] (Target A, task A2 of
    [specs/plans/2026-08-27-remaining-decomposition-targets.md]).  They sat
    below the helper bands and above [compile], so any extraction out of
    [compile] into a sibling [bin/] module would otherwise have had to thread
    them through as parameters.  Every initialiser is a literal or a library
    constant -- none references a [main.ml] local -- so they hoist with no
    reordering, and [main.ml] reaches them through [open Flags] unchanged.

    [caps_env] is NOT here: it is not a flag, and it is defined after
    [compile] on purpose. *)

let dump_tir       = ref false
(* --dump-role-authority: the per-role effective-authority report; a
   typecheck-only mode like --check (bin/main.ml sets do_check from it). *)
let dump_role_authority = ref false
let dump_phases    = ref false
let do_timings     = ref false
let emit_llvm      = ref false
let do_compile     = ref false
(* --jit: run a whole program through the in-process ORC JIT (the REPL's
   backend) instead of the tree-walking interpreter.  Experimental; see the
   [jit_run] guard in [compile] for what falls back to the interpreter. *)
let jit_mode       = ref false
(* FFI Phase 5: extra C sources / linker flags from forge.toml [[ffi]] blocks,
   compiled + linked into the native binary alongside the runtime. *)
let ffi_c_files    : string list ref = ref []      (* C source paths, in declaration order (reversed) *)
let ffi_link_flags : string list ref = ref []      (* extra linker flags, e.g. "-lz" *)

let do_check       = ref false   (* --check: typecheck only, no codegen or eval *)
let topology_file  : string option ref = ref None
(* --topology <json>: a forge topology digest (.forge/topology.json, schema
   version 1). The compiler validates the digest's version and names (step 7),
   checks each binding against its expected shape and each pool's written caps
   (step 3), generates `main` when the entry module has none
   (lib/desugar/desugar_topology.ml), and derives each pool's caps and
   initiated roles, which --emit-core-ast reports as a `topology` object. *)
let topology_pools : string list option ref = ref None
(* --topology-pools a,b: the pools this build contains (an isolated pool's own
   build, or the shared build without the isolated ones). Default: every pool. *)
let protocol_baselines : string list ref = ref []
(* --protocol-baseline <file> (repeatable): a protocol's previous version, as
   `--emit-protocols` wrote it (.forge/protocols/<P>.json). `<P>_Msg.compat()`
   is computed against it (plan II.5, build step 9). *)
let emit_protocols_dir : string option ref = ref None
(* --emit-protocols <dir>: after a clean typecheck, write <dir>/<P>.json for
   every `@[endpoints]` protocol: this build's version, and the previous one
   when the protocol changed. forge passes .forge/protocols on every build. *)
let protocol_baseline_tag : string option ref = ref None
(* A digest of the --protocol-baseline files, for the CAS key: the baseline
   changes the generated `compat()`, so it changes the binary. *)
let topology_isolate_foreign = ref false
(* --topology-isolate-foreign: reject an IO.Foreign role or hook in a pool
   that is not `isolate = true` (the opt-in check of plan section 4). *)

let cap_sandbox    = ref false   (* --cap-sandbox: embed a self-imposed capability sandbox profile *)
(* `needs` is a hard ceiling, checked against attributed use.  ON by default
   since 2026-08-08; `--no-cap-strict` opts out.

   It was opt-in from the day it shipped because its false-positive rate made
   it unusable as a default: capabilities reached through a trampoline-lowered
   builtin could not be attributed at all (fixed 2026-08-07,
   specs/progress/2026-08-07-cap-attrib-table-agreement.md), and a module with
   no entry point was charged for the whole prepended stdlib (fixed with it —
   see [Dce.prune_unreachable]'s [extra_root]).  With both closed, the check
   is the only one that sees a stdlib-MEDIATED capability use; leaving it
   opt-in meant the default build enforced nothing on that route. *)
let cap_strict     = ref true
(* `--stdlib-source`: the entry file(s) ARE standard-library sources, checked
   under a spelling that is not under the resolved stdlib root (the CI
   ratchet's `march --check --stdlib-source stdlib/list.march` from the repo
   root, while the compiler loads its staged `_build/default/stdlib` copy).
   Exempts them from the stdlib-only builtin gate and puts their diagnostics
   at stdlib severity. Never inferred from a file's name: a user's own
   `json.march` used to get this for free. *)
let stdlib_source  = ref false
let check_json     = ref false   (* --check-json: emit diagnostics as NDJSON to stdout *)
let emit_core_ast_file : string option ref = ref None  (* --emit-core-ast <file>: dump desugared core AST + verdict + diagnostics as JSON to stdout *)
let measure_axioms = ref true    (* --no-measure-axioms: reflect @[measure]s symbolically *)
let refine_report  = ref false   (* --refine-report: print obligation-ledger proved/violated/skipped counts *)
(* --refine-report-sites: one line per SKIPPED obligation — file:line:col, the
   reason slug, the callee and predicate, and the reason's detail sentence.
   [refine_report]'s per-reason counts answer "how many", which is the wrong
   question when deciding what to build next: a bucket of 42 says nothing
   about whether those 42 share a cause.  Attributing them needs the sites,
   and reading them out of the hint text is not a substitute — the hints are
   throttled per module, so most skips never print one. *)
let refine_report_sites = ref false
(* --refine-audit: print every declared refinement occurrence the checker
   never enforces (Unenforced) or only warns about (Inert_warned), plus a
   three-bucket summary. Read-only: changes no verdict, emits no diagnostic.
   See lib/refinecheck/refine_audit.ml for the classification itself; this
   flag only decides whether it runs and whether its result gets printed. *)
let refine_audit   = ref false

(* --report-contracts / --contract-scope <globs>: emit one --check-json-shaped
   line, with an `insert` fix, per function the @[no_alloc] checker verified
   allocation-free and that is in the generation scope.  Consumed by
   `forge fix --contracts`.  See lib/tir/alloc_contract.ml. *)
let report_contracts = ref false
let contract_scope   = ref ""    (* comma-separated globs, e.g. "Dsp.*,Audio.mix" *)

(* --refine-suggest <FN> / --refine-suggest-all: propose the parameter
   refinement that discharges what a function's body leaves unproven.
   See lib/refinecheck/precond_infer.ml for the inference itself; this is
   only the reporting surface (`forge refine` consumes the JSON form). *)
let refine_suggest_target : string option ref = ref None   (* Some fn-name (possibly qualified) *)
let refine_suggest_all    = ref false
let refine_suggest_json   = ref false
let refine_suggest_budget = ref March_refinecheck.Precond_infer.default_budget
(* --refine-suggest-post: propose the RETURN refinement that lets a function's
   CALLERS discharge obligations.  Separate from the precondition flags because
   it answers a different question — see lib/refinecheck/postcond_infer.ml. *)
let refine_suggest_post : string option ref = ref None
let refine_suggest_post_all = ref false

let do_test        = ref false   (* --test: compile test blocks into a test-runner binary *)
let emit_io_ops    = ref false   (* --emit-io-ops: print the generated stdlib/io_ops.march *)

(** Capability MOCKING: the dictionary types resolve for IO capabilities, the
    dispatch wrappers are injected, and operations are rewritten to route
    through them.  ONE predicate for all three, because they must agree: the
    wrappers were once injected only under --test while the rewrite was gated
    separately, so a build with the rewrite on and the injection off emitted
    calls to `__march_dispatch_print_line` and failed at link with an
    undefined symbol. *)
let cap_mocking () =
  !do_test || Sys.getenv_opt "MARCH_CAP_DISPATCH" = Some "1"

let output_file    = ref ""
let debug_mode     = ref false
let debug_tui_mode = ref false
let opt_enabled    = ref true
let fast_math      = ref false
let pmap_threshold = ref 1024    (* --pmap-threshold: List.pmap sequential-fallback cutoff *)
let no_copy_runtime = ref false    (* --no-copy-runtime: skip auto-copy of march_runtime.mjs *)
(* --hot-reload=<Prefix>: compile boundary modules (under <Prefix>) with the
   versioned dispatch table so their functions can be hot-swapped at runtime. *)
let hot_reload_prefix : string option ref = ref None
let compile_so = ref false   (* --compile-so: emit a shared library patch (no @main) *)
let signing_pubkey = ref ""  (* --signing-pubkey: base64 ed25519 public key (with --hot-reload) *)

let opt_level      = ref (-1)   (* -1 = not set; 0..3 = explicit clang -ON *)
let do_fmt         = ref false   (* --fmt: format source before compiling *)
let target_str     = ref "native"  (* --target: native | wasm64-wasi | wasm32-wasi | wasm32-unknown-unknown *)
(* Gap #3: --check-migration mode — verify migrate_state soundness via SMT *)
let check_migration   = ref false
let prior_schema_path = ref ""
let new_schema_path   = ref ""