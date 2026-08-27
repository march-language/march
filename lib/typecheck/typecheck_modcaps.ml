(** The module-level capability checkers — the four whole-module [cap]
    enforcement passes and the panic-surface tables they consult.

    The four panic-surface [StringSet]s, [proof_based_panic_surface],
    [panic_surface_all_direct], [panic_surface_suggestion], [span_within],
    [check_no_panic_module], [is_nondeterministic_cap], [check_pure_module],
    [check_no_extern_module], [check_deterministic_module] and their
    suggestion strings.  Lifted verbatim out of [Typecheck] on 2026-08-27
    (Target B, task B2); the band depends on no name defined in [Typecheck]
    itself, in either direction — only on [Typecheck_env]'s [env] type and on
    [builtin_cap_table] from [Typecheck_builtins], hence the three includes
    below.

    [proof_based_panic_surface] is a mutable cell that [bin/main.ml] and three
    test suites set through [March_typecheck.Typecheck.proof_based_panic_surface].
    [include] ALIASES it rather than copying it, so the writers and
    [check_no_panic_module]'s reader stay pointed at one cell — the same
    property [Typecheck_types]'s [_counter] relies on.  This is why the call
    site must be [include], not [open]; consumers also reach these names
    through [let open] and through aliases (Tc., TC., T.) that no grep can
    see. *)

include Typecheck_types
include Typecheck_env
include Typecheck_builtins

(* ── Panic-surface analysis for `cap no_panic` ────────────────────────── *)

let panic_surface_direct : StringSet.t = StringSet.of_list [
  (* Division/modulo operators are handled by the Z3-backed Division_safety
     pass in march_refinecheck, which can approve them when the divisor has a
     {v | v != 0} (or v > 0) refinement.  Remove them here so the syntactic
     no-panic check does not double-report when refinements prove safety. *)
  "panic"; "panic_"; "todo_"; "unreachable_";
]

(* EMPTY since 2026-08-05 (Task 3, specs/progress/2026-08-05-no-panic-proof-based-ban.md).
   Every prelude name that used to live here — `unwrap`, `expect`, `head`,
   `tail`, `last` — carries a real refinement precondition, so it is no longer
   banned by NAME: [Panic_surface_by_proof] (lib/refinecheck) checks each call
   site against its actual verdict instead, admitting the ones that are
   provably safe.  The binding stays (rather than being deleted along with
   [panic_surface_all_direct]) because it is the seam where a future prelude
   name with NO possible contract would go. *)
let panic_surface_prelude : StringSet.t = StringSet.empty

(* What remains SYNTACTICALLY banned among qualified stdlib names: only the
   ones with no refinement contract to consult.  `Array.get`/`Array.set`/
   `Array.pop` are Group B — they panic (out of bounds, and on an empty vector
   respectively) and no contract exists for them, so an unconditional ban is
   still the only sound answer.

   And it is the only answer AVAILABLE for them, not merely the one nobody got
   to yet: the 2026-08-05 feasibility gate established that a contract on these
   three cannot currently be discharged at all.  `Array.length` is a scalar
   CONSTRUCTOR FIELD read (`PVec(n,_,_,_) -> n`), and call-site reflection
   erases every non-datatype constructor field to a fresh unconstrained
   constant, so the measure is inert — see
   `specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`.  Do not move
   these into [panic_surface_contracted] until that todo is closed: the
   proof-based pass is fail-closed on `Skipped`, so an inert contract would
   reject every call while advertising the name as proof-checked.

   Everything else that used to be here now carries a refinement contract and
   lives in [panic_surface_contracted] below.  Ban-list audit 2026-08-05
   (specs/progress/2026-08-05-no-panic-ban-list-audit.md) is what established
   which names carry a real contract. *)
let panic_surface_stdlib : StringSet.t = StringSet.of_list [
  "Array.get"; "Array.set"; "Array.pop";
]

(* ── The CONTRACTED panic surface ─────────────────────────────────────────
   Names that panic exactly when a declared refinement precondition fails, so
   a call to one CAN be proved safe.  This is the single source of truth for
   the set: [Panic_surface_by_proof.covered] (lib/refinecheck) aliases this
   binding rather than repeating it, which is what makes "disjoint from the
   syntactic ban lists" a structural property instead of a hand-checked one.

   Whether these are banned by NAME here depends on
   [proof_based_panic_surface] below. *)
let panic_surface_contracted : StringSet.t = StringSet.of_list [
  (* prelude spellings (prelude is unwrapped into global scope) *)
  "head"; "tail"; "last"; "unwrap"; "expect";
  (* qualified stdlib spellings *)
  "List.nth"; "List.head"; "List.last"; "List.tail";
  "List.maximum_int"; "List.minimum_int";
  "Option.unwrap"; "Option.expect";
  "Result.unwrap"; "Result.expect"; "Result.unwrap_err";
  "Random.normal"; "Random.exponential"; "Random.bernoulli"; "Random.choice";
  "Random.choice_weighted";
  "DateTime.fixed_zone"; "DateTime.fixed_zone_hm";
  "Stats.mean"; "Stats.min_val"; "Stats.max_val";
  "Stats.percentile"; "Stats.quantile"; "Stats.quantiles";
  "Stats.five_number_summary"; "Stats.variance"; "Stats.mode";
  "Stats.covariance"; "Stats.correlation"; "Stats.linear_regression";
]

(** Set by a pipeline that ALSO runs [Panic_surface_by_proof] (lib/refinecheck)
    after [Refine_check.check_module].  When true, this syntactic check leaves
    [panic_surface_contracted] alone and the proof-based pass decides those
    call sites from their actual verdicts.

    Default FALSE, and the default is the whole point.  March has three
    separate check pipelines and only two of them run refinecheck at all:

      - `bin/main.ml`'s compile/`--check` path and its `run_test_cmd` copy DO
        (they set this to true);
      - `bin/main.ml`'s [run_check_cmd] (`march check`, `march caps`) does NOT
        — it is a package-level, typecheck-only path seeded from a cached
        stdlib env, deliberately skipping the solver;
      - the LSP (`lsp/lib`) does NOT — it does not even link march_refinecheck.

    Without a verdict index there is nothing to consult, and `cap no_panic` is
    a guarantee, so "cannot prove" must mean "reject".  Leaving the flag false
    in those two pipelines therefore keeps the OLD unconditional ban (including
    its transitive fixpoint) exactly as it was before 2026-08-05 — conservative,
    no regression, just no proof-based widening there.  Getting this default
    backwards would silently let genuinely panicky code pass `march check` and
    make editor squiggles disappear, which is the failure direction the plan's
    Global Constraints call as serious as a false positive. *)
let proof_based_panic_surface : bool ref = ref false

let panic_surface_all_direct : StringSet.t =
  StringSet.union panic_surface_direct panic_surface_prelude

let panic_surface_suggestion : string -> string = function
  | "List.nth" ->
    "\n\nUse `List.nth_opt` to return `Option(a)` instead of panicking on out-of-bounds."
  | "List.head" | "head" ->
    "\n\nUse `List.head_opt` (or match on `Cons`/`Nil` directly) to avoid panicking on empty."
  | "List.tail" | "tail" ->
    "\n\nUse `List.tail_opt` or match on `Nil` to avoid panicking on empty."
  | "List.maximum_int" | "List.minimum_int" ->
    "\n\nCheck `List.length(xs) > 0` before calling, or use a `List.length` guard \
     followed by a total fold instead."
  | "unwrap" | "Option.unwrap" ->
    "\n\nUse `unwrap_or(opt, default)` or `match opt do Some(x) -> ... | None -> ... end`."
  | "expect" | "Option.expect" ->
    "\n\nUse `unwrap_or` or an explicit match to handle the `None` case."
  | "Result.unwrap" | "Result.expect" ->
    "\n\nUse `Result.unwrap_or` or match on `Ok`/`Err` to handle the error case."
  | "Array.get" | "Array.set" ->
    "\n\nBounds-check the index before access, or use a bounds-checked variant."
  | "Array.pop" ->
    "\n\nCheck `Array.length(v) > 0` before calling."
  | "Random.normal" | "Random.exponential" | "Random.bernoulli" ->
    "\n\nGuard the parameter before the call (e.g. clamp `sigma`/`lambda`/`p` to its \
     valid range) so the refinement precondition provably holds."
  | "Random.choice" ->
    "\n\nCheck `List.length(xs) > 0` before calling."
  | "DateTime.fixed_zone" ->
    "\n\nGuard `offset_seconds` to the range `-50400..=50400` before calling."
  | "DateTime.fixed_zone_hm" ->
    "\n\nGuard `minutes` to the range `0..<60` before calling."
  | "Stats.mean" | "Stats.min_val" | "Stats.max_val" ->
    "\n\nCheck `List.length(xs) > 0` before calling."
  | "panic" | "panic_" ->
    "\n\nReturn an error value (`Result`, `Option`) instead of calling `panic`."
  | "todo_" ->
    "\n\nImplement the body instead of using `todo!`, or remove the `cap no_panic` directive."
  | "unreachable_" ->
    "\n\nAdd a proof comment if this branch is truly unreachable, or handle it explicitly."
  | _ -> ""

(** [span_within inner outer] is true when [inner] is nested inside [outer] by
    source position — same file, and [inner]'s start/end fall within [outer]'s
    line/column bounds.  Used to attribute a recorded non-exhaustive-match span
    to the enclosing `cap no_panic` function whose body it lives in, so a match
    in some UNRELATED (plain) module is never blamed on the no_panic module. *)
let span_within (inner : Ast.span) (outer : Ast.span) : bool =
  inner.Ast.file = outer.Ast.file
  && (inner.Ast.start_line > outer.Ast.start_line
      || (inner.Ast.start_line = outer.Ast.start_line
          && inner.Ast.start_col >= outer.Ast.start_col))
  && (inner.Ast.end_line < outer.Ast.end_line
      || (inner.Ast.end_line = outer.Ast.end_line
          && inner.Ast.end_col <= outer.Ast.end_col))

let check_no_panic_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let fn_entries : (string * (string * Ast.span) list * Ast.span) list =
    List.filter_map (fun d ->
      match d with
      | Ast.DFn (def, fn_span) ->
        let all_calls =
          List.fold_left (fun acc clause ->
            March_ast.Calls.calls_in_expr acc clause.Ast.fc_body
          ) [] def.Ast.fn_clauses
          |> List.map (fun (n, name_span, _app_span) -> (n, name_span))
        in
        Some (def.Ast.fn_name.txt, all_calls, fn_span)
      | _ -> None
    ) decls
  in
  (* Which local functions can carry TRANSITIVE blame to their callers.
     A [panic_surface_contracted] name is excluded, and that exclusion is
     load-bearing rather than cosmetic: `bin/main.ml` unwraps prelude into the
     ENTRY module's own decl list, so prelude's `fn tail`/`head`/`last`/
     `unwrap`/`expect` are literally `DFn`s of the `cap no_panic` module being
     checked.  Their bodies call `panic`, so the fixpoint seeded them and then
     blamed every caller "transitively calls `tail`" — which reintroduced the
     chain-blaming this task removed, and (worse) rejected a call the proof
     pass had just PROVED safe, since a transitive verdict never consults one.
     A guarded bare `tail(xs)` was still an error for exactly this reason.

     Excluding them is sound in both pipeline modes: when
     [proof_based_panic_surface] is false these names are back in
     [is_direct_panic_site] below, so a caller is rejected DIRECTLY and never
     needs the transitive path; when it is true, the proof pass owns the
     decision. A user-defined function that happens to be named `tail` is
     likewise decided by the proof pass, which fail-closes when it carries no
     contract. *)
  let local_fns =
    List.fold_left (fun s (name, _, _) ->
      if StringSet.mem name panic_surface_contracted then s
      else StringSet.add name s)
      StringSet.empty fn_entries
  in
  let _no_panic_mod_names = StringSet.of_list env.no_panic_modules in
  let is_direct_panic_site name =
    StringSet.mem name panic_surface_all_direct
    || StringSet.mem name panic_surface_stdlib
    (* Only when no proof-based pass will run — see [proof_based_panic_surface]. *)
    || ((not !proof_based_panic_surface)
        && StringSet.mem name panic_surface_contracted)
  in
  let seed =
    List.fold_left (fun (panicky, site_map) (fn_name, calls, _span) ->
      match List.find_opt (fun (n, _sp) ->
        is_direct_panic_site n
      ) calls with
      | Some (site_name, site_span) ->
        (StringSet.add fn_name panicky,
         StrMap.add fn_name (site_name, site_span, `Direct) site_map)
      | None ->
        (panicky, site_map)
    ) (StringSet.empty, StrMap.empty) fn_entries
  in
  let seed_panicky, seed_site_map = seed in
  let rec fixpoint panicky site_map =
    let (panicky', site_map') =
      List.fold_left (fun (p, sm) (fn_name, calls, _span) ->
        if StringSet.mem fn_name p then (p, sm)
        else
          match List.find_opt (fun (n, _sp) ->
            StringSet.mem n p && StringSet.mem n local_fns
          ) calls with
          | Some (callee_name, callee_span) ->
            (StringSet.add fn_name p,
             StrMap.add fn_name (callee_name, callee_span, `Transitive) sm)
          | None -> (p, sm)
      ) (panicky, site_map) fn_entries
    in
    if StringSet.cardinal panicky' = StringSet.cardinal panicky then
      (panicky', site_map')
    else
      fixpoint panicky' site_map'
  in
  let (all_panicky, site_map) = fixpoint seed_panicky seed_site_map in
  List.iter (fun (fn_name, _calls, fn_span) ->
    if StringSet.mem fn_name all_panicky then begin
      match StrMap.find_opt fn_name site_map with
      | None -> ()
      | Some (site_name, site_span, kind) ->
        let mod_name = env.current_module in
        let msg = match kind with
          | `Direct ->
            let suggestion = panic_surface_suggestion site_name in
            Printf.sprintf
              "`%s` in `mod %s` (declared `cap no_panic`) calls `%s`, which can panic.%s"
              fn_name mod_name site_name suggestion
          | `Transitive ->
            Printf.sprintf
              "`%s` in `mod %s` (declared `cap no_panic`) transitively calls `%s`, \
               which can panic."
              fn_name mod_name site_name
        in
        let _ = fn_span in
        Err.error errors ~span:site_span msg
    end
  ) fn_entries;
  (* A NON-exhaustive `match` lowers to a runtime "no matching clause" panic, so
     it is a panic surface just like `panic`/`unwrap`.  [check_exhaustiveness]
     already found and recorded every non-exhaustive match's span (see
     [env.nonexhaustive_match_spans]); here we reject any that falls inside one
     of THIS `cap no_panic` module's own function bodies.  Span containment
     attributes each match to its enclosing fn, so a non-exhaustive match in an
     unrelated (plain) module is never blamed on this module. *)
  let mod_name = env.current_module in
  let ne_spans = !(env.nonexhaustive_match_spans) in
  List.iter (fun (fn_name, _calls, fn_span) ->
    List.iter (fun (msp : Ast.span) ->
      if span_within msp fn_span then
        Err.error errors ~span:msp
          (Printf.sprintf
             "`%s` in `mod %s` (declared `cap no_panic`) contains a non-exhaustive \
              `match`, which panics at runtime when no clause matches.\n\n\
              A `cap no_panic` module must handle every case, or add a `_ -> ...` \
              catch-all arm."
             fn_name mod_name)
    ) ne_spans
  ) fn_entries

(* ── cap pure: ban side-effectful builtins ───────────────────────────────── *)

(* A cap tag denotes a NONDETERMINISM source (wall-clock or RNG) — the only
   effects a `cap deterministic` module must reject. Ordinary IO
   (file/console/network) is deterministic-ish and stays allowed. *)
let is_nondeterministic_cap (cap : string) : bool =
  cap = "IO.Clock" || cap = "IO.Random"

(* `cap pure` = NO side effect at all → ban every builtin the authoritative
   effect map (`builtin_cap_table`) attributes an IO/effect cap to. Derived
   from the table (not a hand-guessed parallel list) so it stays in lockstep
   with the real builtin surface. `spawn`/`send`/`exit` are impure surface
   names not carried in the table (they route through other mechanisms) —
   union them in as incidental-correct extras. `read_byte` (raw stdin read,
   like `read_line`) is another such stdin-effect surface name not in the
   table, so union it in too. *)
let pure_banned : StringSet.t =
  let from_table = builtin_cap_table |> List.map fst |> StringSet.of_list in
  StringSet.union from_table
    (StringSet.of_list [ "spawn"; "send"; "exit"; "read_byte" ])

let pure_suggestion : string =
  "Use pure functions (no IO, spawn, vault, or random ops) in a `cap pure` module."

let check_pure_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  (* See [locally_declared_names_of]: a `cap pure` module's own function
     sharing a builtin's name (e.g. its own `random_bytes`) is not a call to
     that builtin. *)
  let locally_declared_names = locally_declared_names_of decls in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = March_ast.Calls.names_and_name_spans clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name pure_banned
             && not (Hashtbl.mem locally_declared_names name) then
            Err.error errors ~span:site_span
              (Printf.sprintf
                 "`%s` in `mod %s` (declared `cap pure`) calls `%s`, which has side effects.\n\n%s"
                 def.Ast.fn_name.txt mod_name name pure_suggestion)
        ) calls
      ) def.Ast.fn_clauses
    | _ -> ()
  ) decls

(* ── cap no_extern: ban FFI extern blocks ────────────────────────────────── *)

let no_extern_suggestion : string =
  "Remove `extern` blocks and `needs IO.Foreign` from `cap no_extern` modules."

let check_no_extern_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  List.iter (fun d ->
    match d with
    | Ast.DExtern (edef, sp) ->
      Err.error errors ~span:sp
        (Printf.sprintf
           "`mod %s` (declared `cap no_extern`) contains an `extern` block (`%s`).\n\n%s"
           mod_name edef.Ast.ext_lib_name no_extern_suggestion)
    | Ast.DNeeds (caps, sp) ->
      (* Check if any capability path starts with "IO" and contains "Foreign" *)
      let has_foreign = List.exists (fun (path, _scope) ->
        match path with
        | first :: rest ->
          first.Ast.txt = "IO" &&
          List.exists (fun p -> p.Ast.txt = "Foreign") rest
        | [] -> false
      ) caps in
      if has_foreign then
        Err.error errors ~span:sp
          (Printf.sprintf
             "`mod %s` (declared `cap no_extern`) uses `needs IO.Foreign`.\n\n%s"
             mod_name no_extern_suggestion)
    | _ -> ()
  ) decls

(* ── cap deterministic: ban non-deterministic builtins ───────────────────── *)

(* `cap deterministic` = no dependence on wall-clock time or an RNG (a weaker
   claim than `pure` — a deterministic module MAY still do ordinary IO like
   `println` or a `file_read`). Ban only the builtins the effect map attributes
   to `IO.Clock`/`IO.Random`, derived from the same authoritative table. *)
let deterministic_banned : StringSet.t =
  builtin_cap_table
  |> List.filter (fun (_, cap) -> is_nondeterministic_cap cap)
  |> List.map fst
  |> StringSet.of_list

let deterministic_suggestion : string =
  "Use deterministic operations only in a `cap deterministic` module. \
   Avoid random/time builtins."

let check_deterministic_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  let mod_name = env.current_module in
  (* See [locally_declared_names_of]: same shadowing guard as
     [check_pure_module]. *)
  let locally_declared_names = locally_declared_names_of decls in
  List.iter (fun d ->
    match d with
    | Ast.DFn (def, _fn_span) ->
      List.iter (fun clause ->
        let calls = March_ast.Calls.names_and_name_spans clause.Ast.fc_body in
        List.iter (fun (name, site_span) ->
          if StringSet.mem name deterministic_banned
             && not (Hashtbl.mem locally_declared_names name) then
            Err.error errors ~span:site_span
              (Printf.sprintf
                 "`%s` in `mod %s` (declared `cap deterministic`) calls `%s`, \
                  which is non-deterministic.\n\n%s"
                 def.Ast.fn_name.txt mod_name name deterministic_suggestion)
        ) calls
      ) def.Ast.fn_clauses
    | _ -> ()
  ) decls
