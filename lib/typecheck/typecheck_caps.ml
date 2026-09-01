(** The capability checker: what a module declares it [needs], and whether the
    code inside it stays within that grant.

    [cap_annots_in_expr], [check_module_needs] (1,296 lines — the
    second-largest function in the checker), [cap_in_solved_ty],
    [check_cap_narrow_sites], [check_json_cap_sites], [check_mint_cap_sites]
    and the four [fn_*_capability_closures] accessors.  Lifted verbatim out of
    [Typecheck] on 2026-08-26; the largest single win in Phase 6.

    Its only contact with the inference knot is a single call to [repr] —
    which is why a band this big can leave a file whose inference is
    thoroughly mutually recursive.

    The [free_vars_*] walkers it uses live in [Typecheck_types] rather than
    here: [warn_unused_params] sits between them and this band and calls them,
    so they could not travel down with it.  See the commit that moved them.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.6). *)

open Typecheck_types
open Typecheck_env
open Typecheck_builtins

(** [cap_annots_in_expr acc e] collects every capability named by a type
    ANNOTATION inside an expression: a [let] binding's [bind_ty], a lambda or
    local-function parameter type, a local function's return type, and
    [EAnnot].

    Check 1 historically read function SIGNATURES only, so a capability named
    inside a body escaped [needs] entirely.  That is reachable: [root_cap] is
    ambient, so a module declaring only [IO.Console] could narrow the root to
    [Cap(IO.FileWrite)] and bind it without ever putting a capability in a
    signature.  See [specs/lang/types/reject/t151_cap_let_annotation_undeclared.march].

    On [EAnnot]: the parser never produces one — desugar synthesizes the only
    instance, a hardcoded [SupervisorSpec] on an [app] block's spec field — so
    no source program can route a capability through it and there is no
    reject-witness for it in the corpus.  It is walked anyway because it costs
    one line and because the next construct desugared into an [EAnnot] should
    inherit the coverage rather than quietly reopen the gap.

    Exhaustive over [Ast.expr] with no wildcard arm, mirroring
    [March_ast.Calls.calls_in_expr]; a new expression form must break this
    build. *)
let rec cap_annots_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
  : (string * Ast.span) list =
  let of_ty acc (sp : Ast.span) (t : Ast.ty) =
    List.fold_left (fun a cap -> (cap, sp) :: a) acc (cap_paths_in_surface_ty t)
  in
  let of_ty_opt acc sp = function None -> acc | Some t -> of_ty acc sp t in
  let of_params acc sp ps =
    List.fold_left (fun a (p : Ast.param) -> of_ty_opt a sp p.param_ty) acc ps
  in
  match e with
  | Ast.ELet (b, sp) ->
    let acc = of_ty_opt acc sp b.Ast.bind_ty in
    cap_annots_in_expr acc b.Ast.bind_expr
  | Ast.EAnnot (ex, t, sp) -> cap_annots_in_expr (of_ty acc sp t) ex
  | Ast.ELam (ps, body, sp) -> cap_annots_in_expr (of_params acc sp ps) body
  | Ast.ELetFn (_, ps, ret, body, sp) ->
    let acc = of_ty_opt (of_params acc sp ps) sp ret in
    cap_annots_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) | Ast.ELetStar (_, rhs, body, _) ->
    cap_annots_in_expr (cap_annots_in_expr acc rhs) body
  | Ast.EApp (f, args, _) ->
    List.fold_left cap_annots_in_expr (cap_annots_in_expr acc f) args
  | Ast.ECon (_, args, _) -> List.fold_left cap_annots_in_expr acc args
  | Ast.EBlock (es, _) -> List.fold_left cap_annots_in_expr acc es
  | Ast.EMatch (scrut, arms, _) ->
    let acc = cap_annots_in_expr acc scrut in
    List.fold_left (fun a arm ->
        let a = Option.fold ~none:a ~some:(cap_annots_in_expr a) arm.Ast.branch_guard in
        cap_annots_in_expr a arm.Ast.branch_body) acc arms
  | Ast.ETuple (es, _) -> List.fold_left cap_annots_in_expr acc es
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun a (_, ex) -> cap_annots_in_expr a ex) acc fields
  | Ast.ERecordUpdate (base, fields, _) ->
    let acc = cap_annots_in_expr acc base in
    List.fold_left (fun a (_, ex) -> cap_annots_in_expr a ex) acc fields
  | Ast.EField (inner, _, _) -> cap_annots_in_expr acc inner
  | Ast.EIf (cond, then_, else_, _) ->
    cap_annots_in_expr (cap_annots_in_expr (cap_annots_in_expr acc cond) then_) else_
  | Ast.ECond (arms, _) ->
    List.fold_left (fun a (ce, be) ->
        cap_annots_in_expr (cap_annots_in_expr a ce) be) acc arms
  | Ast.EPipe (a, b, _) -> cap_annots_in_expr (cap_annots_in_expr acc a) b
  | Ast.EAtom (_, args, _) -> List.fold_left cap_annots_in_expr acc args
  | Ast.ESend (a, b, _) -> cap_annots_in_expr (cap_annots_in_expr acc a) b
  | Ast.ESpawn (ex, _) -> cap_annots_in_expr acc ex
  | Ast.EDbg (Some inner, _) -> cap_annots_in_expr acc inner
  | Ast.EAssert (ex, _) -> cap_annots_in_expr acc ex
  | Ast.ESigil (_, content, _) -> cap_annots_in_expr acc content
  | Ast.EDbg (None, _) -> acc
  | Ast.EHole _ -> acc
  | Ast.EResultRef _ -> acc
  | Ast.ELit _ | Ast.EVar _ -> acc   (* carry no type annotation *)

(** True if [fn_name] ends in the bare "_migrate_state" suffix, regardless of
    which actor it belongs to — the hot-reload state-migration naming
    convention (Phase5C-C.5). This is a local copy of
    [March_tir.Tir_names.is_migrate_fn_name]: [march_typecheck] cannot depend
    on [march_tir] ([march_tir]'s dune already depends on
    [march_typecheck]), so the bare-suffix predicate this module's
    migrate_state IO-free check needs (see below) is duplicated here rather
    than shared. Keep byte-identical to [Tir_names.is_migrate_fn_name] if
    either changes. *)
let is_migrate_fn_name (fn_name : string) : bool =
  let sfx = "_migrate_state" in
  let nl = String.length fn_name and sl = String.length sfx in
  nl >= sl && String.sub fn_name (nl - sl) sl = sfx

(** [fn_transitive_capability_closures_tbl env] is each function's capability set
    including everything it reaches through the reference graph:

      caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }

    computed to fixpoint. Sets only grow and the capability lattice is finite,
    so this terminates; mutual recursion is handled by ITERATING rather than by
    descending, so no cycle detection is needed.

    Built on [own_cap_closures] and NOT [cap_closures], deliberately: the
    latter folds in [module_wide_caps], which itself contains
    module-granularly-propagated import caps, so deriving this from it would be
    circular — and would reintroduce exactly the over-approximation this exists
    to remove (importing [List] to call [map] would inherit [pmap]'s
    [IO.Spawn]).

    Edges come from [free_vars_expr] (see [env.fn_refs]), never from a
    calls-only walk. A reference that does not resolve to a known function — a
    local binding, a parameter, a constructor, an unloaded module's member —
    contributes nothing: it has no entry, so the lookup yields [].

    This table IS load-bearing for enforcement as of 2026-08-06 —
    [check_module_needs]'s Check 4 consults it (see [import_required_caps]).

    [record_fn_caps] covers every declaration form that can hold an expression:
    [DFn] signatures/bodies/guards, default-argument expressions, actor
    handlers, [DExtern]s, module-level [DLet] bodies, [DInterface] default
    method bodies and [DImpl] method bodies. The last four were added
    2026-08-06 (see
    [specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md]);
    until then they had no entry, so an edge pointing at one contributed
    nothing and the closure of anything that REACHED one was silently
    truncated — dropping a capability the pre-demand-driven Check 4 required.
    Keep this list in step with the walks in [check_module_needs]: a form with
    no entry is a fail-open hole, not merely a missing analysis.

    Returns the raw table so an in-pass consumer ([check_module_needs]'s
    demand-driven import propagation) gets O(1) lookups;
    [fn_transitive_capability_closures] is the sorted-assoc-list public view.

    Defined ABOVE [check_module_needs] because that function consumes it —
    Check 4 asks what the functions an importer actually references require,
    rather than what the imported module as a whole requires. *)
let fn_capability_rows_tbl ?(with_rows = true) (env : env)
  : (string, March_caps.Cap_rows.row) Hashtbl.t =
  (* Seeds are derived HERE, not at recording time, and only when the caller
     will actually read [deps]/[unknown] — see [record_fn_refs]. *)
  let seeds : (string, March_caps.Cap_rows.seed) Hashtbl.t =
    if not with_rows then Hashtbl.create 1
    else begin
      let t = Hashtbl.create 64 in
      Hashtbl.iter
        (fun k bodies ->
           Hashtbl.replace t k (March_caps.Cap_rows.seed_of_bodies bodies))
        env.fn_row_bodies;
      t
    end
  in
  March_caps.Cap_rows.solve ~with_rows ~own_caps:env.own_cap_closures
    ~refs:env.fn_refs ~seeds ()

let fn_transitive_capability_closures_tbl (env : env)
  : (string, string list) Hashtbl.t =
  (* The caps PROJECTION of the row table, not a second fixpoint.  R1 stage C
     moved this computation into [Cap_rows.solve] verbatim — same resolver,
     same [sort_uniq]-before-[normalize] ordering, same iterate-to-fixpoint
     over [fn_refs] — precisely so the flat closure and the rows cannot drift
     apart.  Two independently-maintained capability tables is this
     codebase's established failure mode; a projection cannot exhibit it. *)
  let tbl : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  Hashtbl.iter
    (fun k (r : March_caps.Cap_rows.row) -> Hashtbl.replace tbl k r.caps)
    (fn_capability_rows_tbl ~with_rows:false env);
  tbl

(** [check_module_needs env mod_name decls] validates capability declarations for a module:
    1. Every Cap(X) in any function signature must be covered by a [needs] declaration.
    2. Every [needs X] must be used by at least one function.
    3. Hint when Cap(IO) (root) is used — narrower caps may be more appropriate.

    [cap_qname_prefix] is the fully-accumulated dotted path (from
    [env.cap_qual_prefix] extended by [mod_name.txt], or [mod_name.txt] alone
    at the entry module) used ONLY to key [env.cap_closures] so it matches
    TIR's fully-qualified function-name convention (see [lib/tir/lower.ml]'s
    [mod_prefix]). [mod_name] itself continues to be used for all
    diagnostics/messages and the [proof_caps] self-declaration check below,
    unchanged. *)
(* ── Path-scoped capability checking ──────────────────────────────────

   Which builtins take a FILESYSTEM PATH, and at which argument.  Verified
   against the signature table: the read/write builtins take the path at
   argument 0, [file_rename] and [file_copy] take two paths, and
   [file_read_line] / [file_read_chunk] / [csv_next_row] take an INT HANDLE
   rather than a path — those need no check, because a handle cannot be
   obtained except through an opening builtin, which is checked.  That is what
   makes this sound without dataflow analysis. *)
let path_arg_builtins : (string * int list) list = [
  ("file_read", [0]); ("file_open", [0]); ("file_exists", [0]);
  ("file_stat", [0]); ("dir_list", [0]); ("dir_exists", [0]);
  ("file_write", [0]); ("file_append", [0]); ("file_delete", [0]);
  ("dir_mkdir", [0]); ("dir_mkdir_p", [0]); ("dir_rmdir", [0]);
  ("dir_rm_rf", [0]);
  (* Both arguments are paths. *)
  ("file_rename", [0; 1]); ("file_copy", [0; 1]);
]

(* Literal path arguments at capability-builtin call sites.
   Deliberately only LITERALS: a computed path is left to runtime enforcement
   rather than guessed at.  Reporting only definite violations matches the
   refinement checker's existing stance, and keeps this out of Z3's string
   theory, which refine_check.ml explicitly stays clear of. *)
let rec literal_path_uses (acc : (string * string * Ast.span) list)
    (e : Ast.expr) : (string * string * Ast.span) list =
  let acc =
    match e with
    | Ast.EApp (Ast.EVar fn, args, _) ->
      (match List.assoc_opt fn.Ast.txt path_arg_builtins with
       | None -> acc
       | Some idxs ->
         List.fold_left (fun a i ->
             match List.nth_opt args i with
             | Some (Ast.ELit (Ast.LitString path, sp)) ->
               (fn.Ast.txt, path, sp) :: a
             | _ -> a)
           acc idxs)
    | _ -> acc
  in
  match e with
  | Ast.EApp (f, args, _) ->
    List.fold_left literal_path_uses (literal_path_uses acc f) args
  | Ast.ELet (b, _) -> literal_path_uses acc b.Ast.bind_expr
  | Ast.EBlock (es, _) -> List.fold_left literal_path_uses acc es
  | Ast.EMatch (sc, brs, _) ->
    let acc = literal_path_uses acc sc in
    List.fold_left (fun a br -> literal_path_uses a br.Ast.branch_body) acc brs
  | Ast.EIf (c, t, f, _) ->
    literal_path_uses (literal_path_uses (literal_path_uses acc c) t) f
  | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) ->
    literal_path_uses (literal_path_uses acc x) y
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.fold_left literal_path_uses acc es
  | Ast.ERecord (fs, _) ->
    List.fold_left (fun a (_, e) -> literal_path_uses a e) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    List.fold_left (fun a (_, e) -> literal_path_uses a e) (literal_path_uses acc e) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.ESpawn (e, _) | Ast.EAssert (e, _) -> literal_path_uses acc e
  | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> literal_path_uses acc b
  | _ -> acc

let check_module_needs (env : env) (mod_name : Ast.name)
    ~(cap_qname_prefix : string) (decls : Ast.decl list) =
  (* [cap_qname_prefix] carries no trailing dot (e.g. "", "Lib", "Lib.Sub").
     Build the fully-qualified cap-closure key for a function/extern name,
     omitting the leading dot when the prefix is empty (top-level function of
     the entry module) — matching TIR's [mod_prefix ^ name] convention where
     [mod_prefix] is "" at the entry level. *)
  let cap_qname (leaf_name : string) : string =
    if cap_qname_prefix = "" then leaf_name
    else cap_qname_prefix ^ "." ^ leaf_name
  in
  let declared_needs = List.concat_map (function
    | Ast.DNeeds (caps, _) -> List.map (fun (p, _) -> cap_path_of_names p) caps
    | _ -> []
  ) decls in
  (* Check 0: every `needs X` must name a real capability.  The lattice is
     closed, so an `IO`-rooted path not in it (wrong case, a typo) or a bare
     leaf standing in for a real capability (`needs Network`) is definitely
     wrong and is rejected eagerly with a did-you-mean, rather than silently
     accepted and surfacing later as an unrelated "no function requires it"
     unused-capability warning or a missing-`needs` error somewhere else.
     FFI capability roots (e.g. `LibC`) are deliberately outside the lattice
     and stay legal — see [March_caps.Cap_lattice.suggest_cap]. *)
  (* Capability paths Check 0 rejects as unknown.  Check 2 (unused `needs`,
     below) must skip these: a module with a typo'd `needs Network` used to
     get BOTH "not a known capability, did you mean `IO.Network`?" AND
     "declares `needs Network` but no function requires it — help: remove
     the unused capability declaration" for the very same line — directly
     opposing advice (fix the name vs. delete the line) on a check that
     already fixed this exact class of contradiction once between the
     ceiling and Check 2 (see the comment at Check 2's [own_transitive_caps]
     above). A capability Check 0 has already rejected is never "unused" in
     any meaningful sense — it was never a real capability to use. *)
  let unknown_needs = ref [] in
  List.iter (function
    | Ast.DNeeds (caps, sp) ->
      List.iter (fun (path, _scope) ->
        let cap_path = cap_path_of_names path in
        match March_caps.Cap_lattice.suggest_cap cap_path with
        | None -> ()
        | Some known ->
          unknown_needs := cap_path :: !unknown_needs;
          Err.error_with_fix env.errors ~span:sp
            ~fix:(Err.FReplace { span = sp; text = "needs " ^ known })
            (Printf.sprintf
               "`%s` is not a known capability.\n\
                help: did you mean `%s`?"
               cap_path known)
      ) caps
    | _ -> ()
  ) decls;
  let unknown_needs = !unknown_needs in
  (* See [locally_declared_names_of] for why a raw call-name match against
     [builtin_cap_table] must first check for module-local shadowing. *)
  let locally_declared_names = locally_declared_names_of decls in
  let cap_of_builtin_call (name : string) : string option =
    if Hashtbl.mem locally_declared_names name then None
    else List.assoc_opt name builtin_cap_table
  in
  (* Per-function inferred IO-capability closure (Phase5C-A.2): attributes the
     same cap data the checks below already compute to the owning function and
     records it into [env.cap_closures] for a later hot-deploy
     capability-manifest task. Purely additive bookkeeping — does not affect
     any Check 1/1b/1c/2/3/4/5/6 validation logic or diagnostics below.
     [record_fn_caps] is called as a side effect from within [used_caps],
     [body_cap_uses], and [extern_cap_uses] below (each of which already
     iterates [decls] and already computes sig/body/extern caps per-DFn or
     per-DExtern) rather than via a separate re-traversal, so no function body
     or signature is walked twice. Merge order across the three call sites
     doesn't matter: [record_fn_caps] always merges with whatever is already
     in [env.cap_closures] for that qualified name. *)
  (* ── Demand-driven import propagation ──────────────────────────────────
     What an `import M` / `use M` costs this module.

     It used to be M's WHOLE capability set: importing [List] to call [map]
     inherited [pmap]'s [IO.Spawn].  Now it is the union of the transitive
     capability closures of the functions this module actually REFERENCES from
     M — [record_use] recorded exactly those into [ie_used_names] as it
     resolved each [EVar].  This can only ever require LESS than before, so no
     module that compiles today can start failing.

     [trans_closures] is [lazy] because it runs a fixpoint over the whole
     program's reference graph: this must not be paid by the (many) modules
     that import nothing, and both consumers below share the one computation.

     FALLBACK: a referenced name with no closure entry falls back to
     [env.module_caps], i.e. exactly the pre-demand-driven module-granular
     answer, because reading "no entry" as "no capabilities" would silently
     drop enforcement.  Since 2026-08-06 [record_fn_caps] covers every
     declaration form that can hold an expression (see
     [fn_transitive_capability_closures_tbl]), so this branch is a DEFENSIVE
     backstop for a key-shape miss rather than a routinely exercised path —
     measured: with it instrumented it fires zero times across the whole
     run_compiler suite and across a --check sweep of stdlib/*.march,
     test/native/*.march and bench/*.march.  Do not read its survival as
     coverage for an uncovered declaration form; add the form instead.  The
     separate [[] -> mod_caps] early exit above still carries the live cases:
     an import that produced no tracker entry, and a cyclic module group whose
     importee has not been analyzed yet.

     The fallback is deliberately scoped to names in [ie_used_names] — names
     the index proved came from THIS import.  Applying it to every unresolved
     reference would catch every local and parameter and degenerate straight
     back to module granularity. *)
  let trans_closures = lazy (fn_transitive_capability_closures_tbl env) in
  let module_level_caps (imported : string) : string list =
    match List.assoc_opt imported env.module_caps with
    | None -> [] | Some req_caps -> req_caps
  in
  let import_required_caps (ud : Ast.use_decl) (sp : Ast.span) (imported : string)
    : string list =
    match module_level_caps imported with
    | [] ->
      (* The import required nothing before, so it requires nothing now.  The
         early exit is also what keeps this affordable: the fixpoint is never
         forced for the overwhelming majority of imports, whose target declares
         no [needs] at all. *)
      []
    | mod_caps ->
      (* [UseSingle]/[UseAll]/[UseExcept] file one entry at the decl's own span;
         [UseNames] files one per listed name, at that name's span. *)
      let spans = sp :: (match ud.Ast.use_sel with
        | Ast.UseNames names -> List.map (fun (n : Ast.name) -> n.Ast.span) names
        | Ast.UseAll | Ast.UseSingle | Ast.UseExcept _ -> []) in
      (match List.filter (fun ie -> List.mem ie.ie_span spans) !(env.import_tracker) with
       | [] -> mod_caps   (* no tracker entry to read demand from: as before *)
       | entries ->
         let used =
           List.concat_map
             (fun ie -> Hashtbl.fold (fun k () acc -> k :: acc) ie.ie_used_names [])
             entries
         in
         let tbl = Lazy.force trans_closures in
         let caps_of_name (n : string) : string list =
           (* A recorded name is either bare ("pure_double", rebound by
              `import M`) or fully dotted ("M.pure_double" / "Sub.pure_double",
              matched by the prefix index).  Closure keys are "Mod.fn" for a
              nested module and BARE for the entry module's own top-level
              functions, so try, in order: the imported module's own
              qualification of a bare name; the name verbatim; and — for
              `use A.B` re-exporting under the short "B.f" spelling — the
              imported path plus the name's tail. *)
           let candidates =
             (imported ^ "." ^ n) :: n ::
             (match String.index_opt n '.' with
              | Some i ->
                [ imported ^ "." ^ String.sub n (i + 1) (String.length n - i - 1) ]
              | None -> [])
           in
           match List.find_map (fun k -> Hashtbl.find_opt tbl k) candidates with
           | Some caps -> caps
           | None -> mod_caps
         in
         let demanded = List.concat_map caps_of_name used in
         (* FILTER [mod_caps] rather than return [demanded] directly.  The
            result is a SUBSET of what this import required before, by
            construction — which is the whole safety property: this change may
            only ever require less, so nothing that compiles today can start
            failing.  Returning [demanded] itself would not have that property:
            a referenced function's closure can contain a capability the
            imported module never declared (Check 1b only WARNS about a
            capability builtin called directly in a body), and propagating that
            outward would be a brand-new error on code that compiles today.

            A declared cap is kept when some referenced function demands
            something related to it in either direction: [cap_subsumes c d] for
            an umbrella declaration ([needs IO] kept by a demanded IO.Console),
            [cap_subsumes d c] for the exact/narrower case. *)
         List.filter
           (fun c -> List.exists
               (fun d -> cap_subsumes c d || cap_subsumes d c) demanded)
           mod_caps)
  in
  let module_wide_caps : string list =
    (* Caps that apply to every function in this module regardless of which
       function's own signature/body/extern-block produced them: declared
       [needs] (in-scope for the whole module body) and caps propagated in
       from imported modules (Check 4). *)
    let propagated = List.concat_map (function
      | Ast.DUse (ud, sp) ->
        let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
        import_required_caps ud sp imported
      | _ -> []
    ) decls in
    declared_needs @ propagated
  in
  let record_fn_caps (fn_qname : string) (own_caps : string list) =
    let prior = Option.value ~default:[] (Hashtbl.find_opt env.cap_closures fn_qname) in
    let merged = March_caps.Cap_lattice.normalize (module_wide_caps @ own_caps @ prior) in
    Hashtbl.replace env.cap_closures fn_qname merged;
    (* Parallel own-caps-only projection (Phase5C-C.5 design correction): same
       accumulate-across-call-sites behavior as [cap_closures] above, but
       WITHOUT folding in [module_wide_caps]. This is what the migrate_state
       IO-free check needs — the merged closure would falsely blame a pure
       migrate_state for its module's handler-level [needs]. *)
    let prior_own = Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures fn_qname) in
    let merged_own = March_caps.Cap_lattice.normalize (own_caps @ prior_own) in
    Hashtbl.replace env.own_cap_closures fn_qname merged_own
  in
  (* Body-only capability recording for the `--check`-side ceiling. [caps] must
     be the function's DIRECT body-builtin caps (never signature caps).
     Accumulates across a function's multiple recording sites like
     [record_fn_caps]. [sp] is the declaration's span: a stdlib-spanned
     function is marked TRANSPARENT, which serves two roles — its caps roll up
     to the user callers that reach them, AND it is excluded from the set of
     functions the ceiling holds against a module's [needs]. The latter is why
     the marking must be span-accurate down to individual PRELUDE functions
     (stdlib code unwrapped into the entry module, so bare-named): mistaking a
     prelude function for an entry-module one would attribute every capability
     the prelude touches to the entry module. Called for EVERY function
     (even cap-free ones) so transparency is marked regardless of body caps. *)
  let record_body_caps (fn_qname : string) (sp : Ast.span) (caps : string list) =
    (if caps <> [] then
       let prior = Option.value ~default:[] (Hashtbl.find_opt env.body_cap_closures fn_qname) in
       Hashtbl.replace env.body_cap_closures fn_qname
         (March_caps.Cap_lattice.normalize (caps @ prior)));
    if span_is_stdlib sp then Hashtbl.replace env.stdlib_fns fn_qname ()
  in
  (* Reference edges for the per-function TRANSITIVE capability closure
     ([fn_transitive_capability_closures]). Purely additive bookkeeping — no
     Check 1/1b/1c/2/3/4/5/6 diagnostic reads [env.fn_refs].

     [free_vars_expr] rather than [March_ast.Calls]: the call-walker collects
     only [EApp] callees, so a function passed as a VALUE — [apply(xs, noisy)]
     — would contribute no edge and its capabilities would silently vanish
     from the caller's closure. That is the fail-open direction. The
     free-variable walk collects every [EVar], bare and dotted, and respects
     shadowing, so an inner binding that happens to share a top-level
     function's name does not manufacture a spurious edge.

     Each body is paired with the names ITS OWN PARAMETERS bind, and those seed
     [free_vars_expr]'s [bound] list. This is load-bearing, not hygiene:
     [free_vars_expr] binds lambda / [let] / match-arm / [let?] binders
     internally, but it has no visibility into a clause's parameter list, so
     passing [] would let

       pfn helper(p) do file_read(p) end
       fn wrap(helper) do helper(1) end

     record an edge from [wrap] to the SIBLING [helper] — [wrap] would inherit
     [IO.FileRead] while being pure. That is a false positive, which this
     subsystem treats as its cardinal sin. (Note [dependency_order_dfn_run]'s
     [deps_of] does pass []; there an over-approximation only perturbs
     dependency ORDERING, which is harmless. Here it fabricates a capability.)

     Merged with any prior entry, matching [record_fn_caps]'s
     accumulate-across-call-sites behavior. *)
  let record_fn_refs (fn_qname : string) (bodies : (string list * Ast.expr) list) =
    let refs = List.concat_map (fun (bound, e) -> free_vars_expr bound e) bodies in
    (* A `spawn(Actor)` reaches the actor's message handlers at runtime, but
       neither the call walk nor [free_vars_expr] sees that edge — the actor
       name is a nullary [ECon] tag both walks discard.  Emit each spawned
       actor's bare name as an extra reference; the [DActor] arm registers the
       matching [Actor -> handler_qname] edges, so a handler's capabilities
       flow into the closure of every function that spawns its actor, and thus
       into [main]'s grant.  Charged on SPAWN (reachability), so a defined-but-
       never-spawned actor stays free like any other dead code. *)
    let spawn_refs =
      List.concat_map
        (fun (_, e) -> March_ast.Calls.spawned_actor_names [] e) bodies
    in
    let prior = Option.value ~default:[] (Hashtbl.find_opt env.fn_refs fn_qname) in
    Hashtbl.replace env.fn_refs fn_qname
      (List.sort_uniq compare (refs @ spawn_refs @ prior));
    (* R1 stage C (now removed, 2026-08-13 — see [check_fn_grants]'s deletion
       note near [fn_grant_points]): retain the same (params, body) pairs the
       reference walk used, so a row SEED can be derived from them later.
       Deliberately not walked here: the seed walk is a second full pass over
       every function body, and its output ([deps]/[unknown]) is read only by
       [dump_cap_rows]'s debug dump — nothing enforces on it anymore. Doing it
       eagerly cost ~18% of `--check` wall-clock across the conformance corpus
       for a result almost every program discards. Storing the pairs is
       O(1) — they are already-built AST nodes. *)
    let prior_bodies =
      Option.value ~default:[] (Hashtbl.find_opt env.fn_row_bodies fn_qname)
    in
    Hashtbl.replace env.fn_row_bodies fn_qname (prior_bodies @ bodies)
  in
  (* Names bound by a clause's parameter list. [FPPat] goes through
     [free_vars_pattern] so a destructuring head ([fn f((a, b))]) binds its
     components too, not just a bare [PatVar]. *)
  let fn_clause_param_names (c : Ast.fn_clause) : string list =
    List.concat_map (function
      | Ast.FPNamed p | Ast.FPDefault (p, _) -> [ p.Ast.param_name.txt ]
      | Ast.FPPat pat -> free_vars_pattern pat)
      c.Ast.fc_params
  in
  (* ── Coverage-gap closure, 2026-08-06 ────────────────────────────────
     [record_fn_caps]/[record_fn_refs] used to fire for [DFn]s, actor handlers
     and [DExtern]s only.  Module-level [DLet] bodies, interface default-method
     bodies, impl-method bodies and default-argument expressions got NO
     own(...) entry, so an edge pointing at one contributed nothing and the
     transitive closure of anything that REACHED one came back silently
     truncated — dropping a capability Check 4 required before demand-driven
     propagation landed (see
     specs/progress/2026-08-06-record-fn-caps-misses-dlet-and-methods.md).

     Unlike the [DFn] scan, none of this feeds the Check 1b/Check 2
     DIAGNOSTIC lists ([body_cap_uses] / [used_caps]): it only populates the
     closure tables.  Keeping the diagnostic surface byte-identical is
     deliberate — this change exists to restore ENFORCEMENT that the closure
     lost, not to start warning about forms that never warned. *)
  let builtin_caps_of_expr (e : Ast.expr) : string list =
    List.filter_map
      (fun (call_name, _) -> cap_of_builtin_call call_name)
      (March_ast.Calls.names_and_name_spans e)
  in
  let default_param_exprs (c : Ast.fn_clause) : Ast.expr list =
    List.filter_map (function Ast.FPDefault (_, e) -> Some e | _ -> None)
      c.Ast.fc_params
  in
  (* Record one non-[DFn] expression owner: its own builtin-implied caps and
     its reference edges, with [bound] seeding [free_vars_expr] exactly the way
     [record_fn_refs] does for a clause's parameters. *)
  let record_expr_owner ?(sp = Ast.dummy_span) (qname : string) (bound : string list)
      (es : Ast.expr list) =
    let body_caps = List.concat_map builtin_caps_of_expr es in
    record_fn_caps qname body_caps;
    record_body_caps qname sp body_caps;
    record_fn_refs qname (List.map (fun e -> (bound, e)) es)
  in
  (* An [impl]'s target type, keyed the way lib/tir/lower.ml keys it when it
     builds the [Iface$Ty.method] mangled symbol — same four cases, same
     arity-keyed tuple spelling.

     NOT a full mirror, deliberately: lower.ml additionally applies a
     COLLISION-CONDITIONAL module qualification (lower.ml:1299-1301) when a
     short type name is declared more than once in the program, so two impls of
     a general interface for same-short-named types get distinct symbols. This
     key does not reproduce that, so two such impls in ONE module would share a
     cap-closure key and their capabilities would merge. Harmless today —
     nothing cross-references the TIR symbol from here, and the merge is a
     union within a single module's own impls — but it is the one place where
     these two manglings can disagree. *)
  let impl_ty_key (t : Ast.ty) : string =
    match t with
    | Ast.TyCon (n, _) -> n.Ast.txt
    | Ast.TyTuple tys -> Printf.sprintf "$Tuple%d" (List.length tys)
    | Ast.TyRecord _ -> "$Record"
    | _ -> "$Unknown"
  in
  (* [DFn]s declared directly in this module — the guard that keeps the impl
     DISPATCH node below from ever claiming a plain function's key. *)
  let module_fn_names =
    List.filter_map (function
        | Ast.DFn (def, _) -> Some def.Ast.fn_name.Ast.txt
        | _ -> None)
      decls
  in
  (* Append a single reference edge without a body walk. Used only for the
     impl dispatch node, which owns no expression of its own. *)
  let record_dispatch_edge (dispatch_qname : string) (target : string) =
    let prior =
      Option.value ~default:[] (Hashtbl.find_opt env.fn_refs dispatch_qname)
    in
    Hashtbl.replace env.fn_refs dispatch_qname
      (List.sort_uniq compare (target :: prior))
  in
  (* Desugar's [expand_defaults_decl] rewrites [fn f(x \\ d)] into arity-
     mangled [f$0]/[f$1] declarations with [d] moved into [f$0]'s BODY, and it
     runs before the typechecker (bin/main.ml, and [parse_and_desugar] in the
     tests).  It does NOT rewrite call sites — those still say [f] — and it
     emits no dispatcher [DFn], so the base name had no closure entry at all
     and every caller's closure was truncated.  Recording each variant's caps
     and edges under the base name too is what makes a reference to [f]
     resolve.  A user cannot write ['$'] in an identifier, so this can only
     ever fire on a desugar-generated name. *)
  let arity_mangled_base (n : string) : string option =
    match String.rindex_opt n '$' with
    | None -> None
    | Some i ->
      let suffix = String.sub n (i + 1) (String.length n - i - 1) in
      if i > 0 && suffix <> ""
         && String.for_all (fun c -> c >= '0' && c <= '9') suffix
      then Some (String.sub n 0 i)
      else None
  in
  List.iter (fun (d : Ast.decl) ->
      match d with
      (* A module-level binding is an ordinary value name: key it exactly the
         way a [DFn] of that name would be keyed, so a reference to it
         resolves.  A destructuring binding attributes the body to EVERY name
         it binds — any of them can be the route a caller takes. *)
      | Ast.DLet (_, b, dsp) ->
        List.iter
          (fun n ->
             let q = cap_qname n in
             (* Only the ENTRY module's top-level [let]s are always-run: lower.ml
                splices those into `main`'s body, so DCE keeps them
                unconditionally. A NESTED module's [let] lowers to an ordinary
                zero-arg function DCE prunes when unreachable — rooting it here
                would over-report a dead nested [let] `--compile` accepts. Gate
                on the empty prefix, which is exactly the entry module. *)
             if cap_qname_prefix = "" then
               Hashtbl.replace env.ceiling_extra_roots q ();
             record_expr_owner ~sp:dsp q [] [ b.Ast.bind_expr ])
          (free_vars_pattern b.Ast.bind_pat)
      (* An interface DEFAULT body is keyed by a mangled name for exactly the
         reason an impl method is, and the bare name is only a dispatch edge.

         The first version of this change wrote the default body's caps
         DIRECTLY onto [cap_qname md_name] with no mangling and no guard, on
         the assumption that a module could not declare both an interface
         method and a plain [fn] of that name.  That assumption is false —

           mod Inner do
             interface Greeter(a) do
               fn greet : a -> Unit
               fn greet_loud : a -> Unit do fn (x) -> print("loud") end
             end
             fn greet_loud(n : Int) : Int do n + 1 end
           end

         typechecks with exit 0, and [record_fn_caps] MERGES, so the pure
         [greet_loud] silently absorbed [IO.Console].  That is a false
         positive, and it was observable on the hot-deploy manifest, which
         reads [fn_own_capability_closures] unfiltered — no Check-4
         [mod_caps] filter stands between it and a deploy capability gate.
         Pinned by [test_interface_default_does_not_capture_a_same_named_fn]. *)
      | Ast.DInterface (idef, idsp) ->
        List.iter (fun (m : Ast.method_decl) ->
            match m.Ast.md_default with
            | None -> ()
            | Some e ->
              let mangled =
                cap_qname
                  (idef.Ast.iface_name.Ast.txt ^ "$default." ^ m.Ast.md_name.Ast.txt)
              in
              record_expr_owner ~sp:idsp mangled [] [ e ];
              if not (List.mem m.Ast.md_name.Ast.txt module_fn_names) then
                record_dispatch_edge (cap_qname m.Ast.md_name.Ast.txt) mangled)
          idef.Ast.iface_methods
      (* An impl method is keyed by TIR's [Iface$Ty.method] mangling.  This is
         collision-free in both directions that matter: an ordinary qualified
         name never contains ['$'] (see [Tir_names.is_iface_mangled]), so a
         [DFn] of the same short name can never share the key and have its
         capabilities silently merged; and two impls of the same method for
         DIFFERENT types get distinct keys, so a caller cannot inherit a
         sibling impl's capabilities.

         A reference site says the BARE method name, though, so the mangled key
         alone would leave every caller truncated.  The bare name therefore
         becomes a DISPATCH node whose only content is an edge to each impl —
         the union over impls, which is the sound reading of a name whose
         target is chosen by type.  It is emitted only when this module
         declares no [DFn] of that name, so the dispatch node can never absorb
         a plain function's identity. *)
      | Ast.DImpl (idef, idsp) ->
        let ty_key = impl_ty_key idef.Ast.impl_ty in
        List.iter (fun ((mn : Ast.name), (def : Ast.fn_def)) ->
            let mangled =
              cap_qname
                (idef.Ast.impl_iface.Ast.txt ^ "$" ^ ty_key ^ "." ^ mn.Ast.txt)
            in
            List.iter (fun (c : Ast.fn_clause) ->
                record_expr_owner ~sp:idsp mangled (fn_clause_param_names c)
                  (c.Ast.fc_body :: Option.to_list c.Ast.fc_guard
                   @ default_param_exprs c))
              def.Ast.fn_clauses;
            if not (List.mem mn.Ast.txt module_fn_names) then
              record_dispatch_edge (cap_qname mn.Ast.txt) mangled)
          idef.Ast.impl_methods
      | _ -> ())
    decls;
  (* The middle component is the enclosing function's bare name when the use
     comes from a single named function ([DFn]/[DImpl] method/[DActor]
     handler), and [""] otherwise (a type decl, extern block, or interface
     signature names no single function). [""] can never equal ["main"], so
     Check 3 below can compare against it safely to exempt `main`'s own
     Cap(IO) parameter without affecting any non-function-scoped use. *)
  let used_caps : (string * string * Ast.span) list = List.concat_map (function
    | Ast.DFn (def, sp) ->
      let param_tys = List.filter_map (fun p ->
        match p with
        | Ast.FPNamed { param_ty = Some t; _ } -> Some t
        | _ -> None
      ) (List.concat_map (fun c -> c.Ast.fc_params) def.fn_clauses) in
      let ret_tys = Option.to_list def.fn_ret_ty in
      let sig_caps = List.concat_map cap_paths_in_surface_ty (param_tys @ ret_tys) in
      let qname = cap_qname def.fn_name.txt in
      record_fn_caps qname sig_caps;
      (* Record which functions carry a concrete [Cap(P)] PARAMETER.  R1 stage
         C once made this a discharge point, checked once at the end of
         [check_module_core] by [check_fn_grants]; that check was REMOVED
         2026-08-13 (see [fn_grant_points]'s doc comment) because it made a
         capability parameter a per-function ceiling, forcing threading.  This
         recording step stays — Task 8 reads [fn_grant_points] — but nothing
         currently checks it.

         Parameters only, not [ret_tys]: returning a [Cap(X)] is minting or
         forwarding one, not being handed one to spend.

         [main] is skipped — [check_main_grant] is its discharge point.
         [Cap(a)] contributes nothing: [caps_in_ty] yields no path for a type
         VARIABLE, so capability-polymorphic plumbing like [cap_narrow]'s
         signature creates no gate. *)
      let param_caps = List.concat_map cap_paths_in_surface_ty param_tys in
      if param_caps <> [] && def.fn_name.txt <> "main" then
        Hashtbl.replace env.fn_grant_points qname
          (List.sort_uniq String.compare param_caps, sp);
      (* Annotations INSIDE the body are uses too, and were invisible here
         until 2026-08-05 — see [cap_annots_in_expr].

         Deliberately NOT passed to [record_fn_caps]: signature caps propagate
         to callers because they are the function's interface, while a local
         annotation is not, and folding it into the propagated closure would
         widen every caller's ceiling on the strength of a binding they cannot
         see.  So a body annotation is reported against this module's [needs]
         and stops there. *)
      let body_annot_caps =
        List.concat_map (fun (c : Ast.fn_clause) -> cap_annots_in_expr [] c.Ast.fc_body)
          def.fn_clauses
      in
      List.map (fun cap -> (cap, def.fn_name.txt, sp)) sig_caps
      @ List.map (fun (c, s) -> (c, def.fn_name.txt, s)) body_annot_caps
    (* H9 gap fix: also check actor handler signatures for Cap usage.
       Actor handlers can receive Cap(X) values as message arguments; those
       must also be covered by module-level [needs] declarations. *)
    | Ast.DActor (_, name, actor, sp) ->
      (* Record each handler's own per-function cap closure under a
         MODULE-QUALIFIED key ("Sub.Weeble_Zorp"), exactly like a sibling
         [DFn].

         The C1 fix (2026-08-06) originally keyed these BARE, to match the
         name TIR gives the synthesized handler function (lib/tir/
         lower_actor.ml's [lower_handler]: [fn_name = name ^ "_" ^
         h.ah_msg.txt], with [name] the actor's own bare name — a handler on
         actor [Weeble] nested inside [App.Sub] still lowers to bare
         [Weeble_Zorp]).  But TIR does NOT disambiguate that name across
         modules either: it records ownership out-of-band instead
         ([March_tir.Handler_owner], registered from lower.ml's nested-[DActor]
         arm).  Keying the cap closure bare therefore made two same-named
         actors in different modules share ONE key, and [record_fn_caps]
         UNIONs — so spawning either actor charged the merged capabilities of
         BOTH (specs/todos/2026-08-16-actor-grant-same-name-false-positive.md:
         sound, but a false positive that rejects valid code with a chain
         pointing at the wrong actor).

         Qualifying the key is safe because every consumer of the closure
         tables resolves a bare reference against the referring key's module
         prefix FIRST ([Cap_rows.solve]'s [resolve], [cap_reach_chain]'s
         two-way push): a `spawn(Weeble)` inside `Sub` resolves to
         `Sub.Weeble`.  The one consumer that must see the BARE TIR spelling
         is the HCR manifest (bin/main.ml), which now bridges the two through
         [Handler_owner] — the same ownership channel TIR already keeps.  A
         bare ALIAS node is registered below so a bare spawn from OUTSIDE the
         declaring module still resolves.

         The signature-cap diagnostics above and the body-scanned caps below
         still merge in [module_wide_caps] via [record_fn_caps] the same way
         [DFn] does. *)
      let actor_qname = cap_qname name.txt in
      List.iter (fun (h : Ast.actor_handler) ->
          let fn_qname = actor_qname ^ "_" ^ h.ah_msg.txt in
          let body_caps = List.filter_map (fun (call_name, _) ->
              cap_of_builtin_call call_name
            ) (March_ast.Calls.names_and_name_spans h.Ast.ah_body) in
          record_fn_caps fn_qname body_caps;
          record_body_caps fn_qname sp body_caps;
          record_fn_refs fn_qname
            [ (List.map (fun (p : Ast.param) -> p.param_name.txt) h.Ast.ah_params,
               h.Ast.ah_body) ]
        ) actor.actor_handlers;
      (* Bridge the actor-NAME node to its handler functions, so a `spawn(A)`
         site — which [record_fn_refs] records as a reference to the name as
         WRITTEN (see its [spawn_refs]) — reaches [A]'s handlers in the closure
         walk.  Keyed module-qualified, matching the handler qnames above:
         a bare `spawn(A)` written inside A's own module resolves to
         [actor_qname] through the referring key's prefix. *)
      let handler_qnames =
        List.map (fun (h : Ast.actor_handler) -> actor_qname ^ "_" ^ h.Ast.ah_msg.txt)
          actor.actor_handlers
      in
      (* The `init { ... }` initializer runs at spawn time, so its transitive
         IO is reachable exactly when a handler's is.  Fold its own builtin
         caps and its reference/spawn edges into the actor-NAME node too, so
         `main -> A` charges init alongside the handlers.  Without this an
         `init` that calls a file-writing helper escaped the grant entirely
         (the handler bridge alone did not cover it). *)
      let init_caps =
        List.filter_map (fun (call_name, _) -> cap_of_builtin_call call_name)
          (March_ast.Calls.names_and_name_spans actor.Ast.actor_init)
      in
      record_fn_caps actor_qname init_caps;
      let prior_actor_refs =
        Option.value ~default:[] (Hashtbl.find_opt env.fn_refs actor_qname)
      in
      let init_refs = free_vars_expr [] actor.Ast.actor_init in
      let init_spawn_refs =
        March_ast.Calls.spawned_actor_names [] actor.Ast.actor_init
      in
      Hashtbl.replace env.fn_refs actor_qname
        (List.sort_uniq compare
           (handler_qnames @ init_refs @ init_spawn_refs @ prior_actor_refs));
      (* Bare ALIAS node, for a nested actor spawned by its BARE name from
         outside its declaring module (`use Sub` then `spawn(Weeble)` at the
         entry level): there the referring key has no module prefix, so
         [Cap_rows.solve]'s [resolve] falls through to the raw name and would
         find nothing — dropping the handler edge entirely, which is the
         FAIL-OPEN direction.  The alias carries no caps of its own; it only
         forwards to the qualified actor node.  When two modules declare the
         same actor name the alias forwards to BOTH, which restores the old
         union — but only for this genuinely ambiguous bare-spawn shape, not
         for the resolvable one the bug was about. *)
      if actor_qname <> name.txt then begin
        record_fn_caps name.txt [];
        let prior_alias =
          Option.value ~default:[] (Hashtbl.find_opt env.fn_refs name.txt)
        in
        Hashtbl.replace env.fn_refs name.txt
          (List.sort_uniq compare (actor_qname :: prior_alias))
      end;
      List.concat_map (fun (h : Ast.actor_handler) ->
          let param_tys = List.filter_map (fun (p : Ast.param) -> p.param_ty) h.ah_params in
          List.concat_map (fun t ->
            List.map (fun cap -> (cap, "", sp)) (cap_paths_in_surface_ty t)
          ) param_tys
        ) actor.actor_handlers
    (* An extern block declares `extern "lib" : Cap(X)` — that Cap(X) is a use
       of the capability, so a module with `needs X` + an extern block must not
       trigger the "declared but not used" warning. *)
    | Ast.DExtern (edef, sp) ->
      List.map (fun cap -> (cap, "", sp)) (cap_paths_in_surface_ty edef.ext_cap_ty)

    (* A capability named in a TYPE DECLARATION — a record field, a variant
       constructor argument, or an alias right-hand side — is a use of that
       capability.  Declaring the field does not let the module OBTAIN the
       capability, but it lets it hold one and pass one, which is exactly what
       the ceiling exists to make visible, and it is already how the identical
       capability is treated in a function signature.

       These arms were covered by the `| _ -> []` wildcard that used to end
       this match, so `type Handle = { tok : Cap(IO.FileWrite) }` under
       `needs IO.Console` typechecked clean with `--cap-strict`.  See
       reject/t148-t150. *)
    | Ast.DType (_, _, _, td, sp)
    | Ast.DAlwaysLinearType (_, _, _, td, sp) ->
      List.map (fun cap -> (cap, "", sp)) (March_caps.Cap_surface_ty.caps_in_type_def td)

    (* ── Everything below names no capability position ──────────────────
       Enumerated rather than wildcarded, deliberately.  Five separate bugs in
       this codebase have come from a capability walk ending in `| _ -> ()`
       that was inert until a declaration form grew a type position; the point
       of naming every constructor is that adding a 25th one breaks this build
       instead of silently opening a hole.  Do NOT collapse these back into a
       wildcard. *)
    | Ast.DMod _ ->
      (* Nested modules are checked by their own [check_module_needs] pass,
         which attributes diagnostics to the INNER module — verified: a `Cap`
         in a nested module's signature reports against the inner name.
         Recursing here would double-report against the outer module and
         against the wrong `needs`. *)
      []
    | Ast.DLet _ ->
      (* A top-level binding's annotation is a type position, but the value
         restriction means a top-level cap binding cannot be produced without
         a call whose signature is already walked above. Left uncovered
         deliberately; revisit if a witness appears. *)
      []
    (* An INTERFACE method signature is a signature, and Check 1 treats every
       other signature — plain [fn], actor handler, [extern] — as a use.  A
       default method body is a body, and its annotations are uses too.

       These were enumerated under "names no capability position" when this
       match was made exhaustive on 2026-08-05.  That was an explicit decision
       and it was wrong; found by the R8 audit (reject/t156).  The enumeration
       is why it was a reviewable mistake rather than a silent hole. *)
    | Ast.DInterface (idef, sp) ->
      let sig_caps =
        List.concat_map (fun (md : Ast.method_decl) -> cap_paths_in_surface_ty md.md_ty)
          idef.iface_methods
      in
      let body_caps =
        List.concat_map (fun (md : Ast.method_decl) ->
            match md.md_default with
            | None -> []
            | Some body -> cap_annots_in_expr [] body)
          idef.iface_methods
      in
      List.map (fun cap -> (cap, "", sp)) sig_caps
      @ List.map (fun (c, s) -> (c, "", s)) body_caps

    (* An IMPL method is a function: its signature and its body annotations are
       uses, exactly as a top-level [DFn]'s are.  Measured before this arm
       existed: the IDENTICAL annotation errored in a plain [fn] body and
       produced NOTHING in an [impl] method body — impl bodies were darker than
       ordinary functions, which is backwards, since an [impl] is where a
       dependency's capability use is least visible to a reader
       (reject/t157). *)
    | Ast.DImpl (idef, sp) ->
      let of_fn (fd : Ast.fn_def) =
        let param_tys =
          List.filter_map (function
              | Ast.FPNamed { param_ty = Some t; _ } -> Some t
              | _ -> None)
            (List.concat_map (fun c -> c.Ast.fc_params) fd.fn_clauses)
        in
        let sig_caps =
          List.concat_map cap_paths_in_surface_ty (param_tys @ Option.to_list fd.fn_ret_ty)
        in
        let body_caps =
          List.concat_map (fun (c : Ast.fn_clause) -> cap_annots_in_expr [] c.Ast.fc_body)
            fd.fn_clauses
        in
        List.map (fun cap -> (cap, fd.fn_name.txt, sp)) sig_caps
        @ List.map (fun (c, s) -> (c, fd.fn_name.txt, s)) body_caps
      in
      (* [impl_ty] itself can name a capability: `impl Grantor(Cap(IO))`. *)
      List.map (fun cap -> (cap, "", sp)) (cap_paths_in_surface_ty idef.impl_ty)
      @ List.concat_map (fun (_, fd) -> of_fn fd) idef.impl_methods

    | Ast.DProtocol _ | Ast.DSig _
    | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _ | Ast.DProofCap _
    | Ast.DOpts _ | Ast.DTransitions _ | Ast.DApp _ | Ast.DDeriving _
    | Ast.DSatisfy _ | Ast.DTest _ | Ast.DDescribe _ | Ast.DSetup _
    | Ast.DSetupAll _ -> []
  ) decls in
  (* Body-scan: collect builtin calls that imply a cap need.
     Deduplicated to one warning per cap (first call-site span). *)
  (* ── Path-scope violations ──────────────────────────────────────────
     A literal path outside every scope declared for its capability is a
     DEFINITE violation and an error.  Three conditions keep this quiet
     otherwise, each deliberate:
       - no declaration for the capability at all -> silent; the existing
         needs checks already cover an undeclared capability, and reporting
         it twice would be noise;
       - at least one UNSCOPED declaration -> silent; unscoped means any path,
         so nothing is out of scope;
       - a computed path -> not collected at all, so nothing to say. *)
  List.iter (fun (d : Ast.decl) ->
      let bodies = match d with
        | Ast.DFn (def, _) -> List.map (fun c -> c.Ast.fc_body) def.fn_clauses
        | Ast.DLet (_, b, _) -> [ b.Ast.bind_expr ]
        | _ -> []
      in
      List.iter (fun body ->
          List.iter (fun (builtin, path, sp) ->
              match cap_of_builtin_call builtin with
              | None -> ()
              | Some cap ->
                (* Scopes declared for this capability, or for anything that
                   subsumes it: needs IO.FileSystem("/srv") also scopes
                   IO.FileRead. *)
                let relevant =
                  List.filter (fun (declared, _) -> cap_subsumes declared cap)
                    env.mod_need_scopes
                in
                if relevant <> [] then begin
                  let unscoped = List.exists (fun (_, sc) -> sc = None) relevant in
                  let permitted =
                    List.exists (fun (_, sc) -> match sc with
                        | None -> true
                        | Some scope -> March_caps.Cap_scope.within ~scope path)
                      relevant
                  in
                  if (not unscoped) && not permitted then begin
                    let scopes =
                      List.filter_map (fun (_, sc) -> sc) relevant
                      |> List.sort_uniq String.compare
                    in
                    Err.error env.errors ~span:sp
                      (Printf.sprintf
                         "`%s` is scoped to %s, but this reads `%s`, which is \
                          outside it.\n\
                          hint: widen the scope in `needs`, or use a path \
                          within it."
                         cap
                         (String.concat " and "
                            (List.map (fun s -> "`" ^ s ^ "`") scopes))
                         path)
                  end
                end)
            (literal_path_uses [] body))
        bodies)
    decls;

  let body_cap_uses : (string * Ast.span) list =
    let all = List.concat_map (function
      | Ast.DFn (def, dfn_sp) ->
        let per_clause = List.map (fun clause ->
          List.filter_map (fun (call_name, call_span) ->
            match cap_of_builtin_call call_name with
            | Some cap_name -> Some (cap_name, call_span)
            | None -> None
          ) (March_ast.Calls.names_and_name_spans clause.Ast.fc_body)
        ) def.fn_clauses in
        let qname = cap_qname def.fn_name.txt in
        (* Default-argument expressions count as this function's own: the
           default is evaluated at every call site that omits the parameter.
           This arm only sees them when the typechecker runs on an UNdesugared
           module (the LSP's analysis route); the production pipeline desugars
           first, and there the default has already moved into an arity-mangled
           [f$N] body, which the base-name alias below re-attaches to [f].
           Both routes are covered so neither can silently truncate. *)
        let own_caps =
          List.concat_map (List.map fst) per_clause
          @ List.concat_map
              (fun (c : Ast.fn_clause) ->
                 List.concat_map builtin_caps_of_expr (default_param_exprs c))
              def.fn_clauses
        in
        (* Guards are part of the function too: a guard calling an impure
           helper is as much a reference as the body is. *)
        let own_refs =
          List.concat_map (fun (c : Ast.fn_clause) ->
              let bound = fn_clause_param_names c in
              List.map (fun e -> (bound, e))
                (c.Ast.fc_body :: Option.to_list c.Ast.fc_guard
                 @ default_param_exprs c))
            def.fn_clauses
        in
        record_fn_caps qname own_caps;
        record_body_caps qname dfn_sp own_caps;
        record_fn_refs qname own_refs;
        (match arity_mangled_base def.fn_name.txt with
         | None -> ()
         | Some base ->
           let base_qname = cap_qname base in
           record_fn_caps base_qname own_caps;
           record_body_caps base_qname dfn_sp own_caps;
           record_fn_refs base_qname own_refs);
        List.concat per_clause
      | Ast.DLet (_vis, b, _) ->
        List.filter_map (fun (call_name, call_span) ->
          match cap_of_builtin_call call_name with
          | Some cap_name -> Some (cap_name, call_span)
          | None -> None
        ) (March_ast.Calls.names_and_name_spans b.Ast.bind_expr)
      (* C1 fix (part 2): fold actor handler bodies into the SAME body-scan
         this branch already performs for DFn/DLet, rather than a second/
         parallel AST walk — a handler doing undeclared IO must trip the
         same "capability not declared in needs" diagnostic (Check 1b,
         below) that a plain function body would. Cap-closure recording for
         handlers already happened above in [used_caps]'s DActor branch (so
         it isn't duplicated here); this only needs to surface the
         (cap, span) pairs for the Check 1b/Check 2 diagnostics. *)
      | Ast.DActor (_, _, actor, _) ->
        List.concat_map (fun (h : Ast.actor_handler) ->
            List.filter_map (fun (call_name, call_span) ->
              match cap_of_builtin_call call_name with
              | Some cap_name -> Some (cap_name, call_span)
              | None -> None
            ) (March_ast.Calls.names_and_name_spans h.Ast.ah_body)
          ) actor.actor_handlers
      | _ -> []
    ) decls in
    (* Drop capability uses that belong to the standard library rather than to
       this module.  Without this, prelude's own calls (it is unwrapped into
       global scope, so its decls ride in the entry module's list AHEAD of the
       user's) win the dedup below and carry a stdlib span, which the driver
       then filters out — generating the warning and discarding it.  See
       [stdlib_source_files]. *)
    let all = List.filter (fun (_, sp) -> not (span_is_stdlib sp)) all in
    List.fold_left (fun acc (cap_name, sp) ->
      if List.mem_assoc cap_name acc then acc else (cap_name, sp) :: acc
    ) [] all
  in
  (* Extern-implied caps: any DExtern → needs IO.Foreign; any blocking extern fn → needs IO.Foreign.Blocking *)
  let extern_cap_uses : (string * Ast.span) list =
    List.concat_map (function
      | Ast.DExtern (edef, sp) ->
        let base = [("IO.Foreign", sp)] in
        let has_blocking = List.exists (fun ef -> ef.Ast.ef_blocking) edef.ext_fns in
        List.iter (fun (ef : Ast.extern_fn) ->
            let qname = cap_qname ef.ef_name.txt in
            let own = if ef.Ast.ef_blocking then ["IO.Foreign"; "IO.Foreign.Blocking"] else ["IO.Foreign"] in
            record_fn_caps qname own
          ) edef.ext_fns;
        if has_blocking then base @ [("IO.Foreign.Blocking", sp)] else base
      | _ -> []
    ) decls
    |> List.fold_left (fun acc (cap_name, sp) ->
      if List.mem_assoc cap_name acc then acc else (cap_name, sp) :: acc
    ) []
  in
  let cap s = MPCode ("Cap(" ^ s ^ ")") in
  (* Check 1: every Cap(X) must be covered by a declared need.
     Exception: the declaring module of a proof cap implicitly satisfies its own needs —
     `proof cap X` in mod M auto-covers `needs M.X` so the module needn't repeat itself. *)
  (* Every [Cap(X)] Check 1 is itself separately demanding (below).  Check
     1b's aggregation (further down) must drop any capability already
     SUBSUMED by one of these — else `fn main(cap : Cap(IO))` demands
     `needs IO` here while Check 1b separately demands `needs IO.Clock`,
     `needs IO.Console`, `needs IO.Random`, ... for the same body: `needs
     IO` alone already covers all of them, so `forge fix` applying both
     diagnostics writes four lines where one suffices. *)
  let check1_demanded_caps = ref [] in
  List.iter (fun (cap_path, _fn_name, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    let self_declared = match List.assoc_opt cap_path env.proof_caps with
      | Some dm -> dm = mod_name.txt
      | None -> false
    in
    if not covered && not self_declared then begin
      check1_demanded_caps := cap_path :: !check1_demanded_caps;
      match List.assoc_opt cap_path env.proof_caps with
      | Some declaring_mod ->
        Err.error env.errors ~span:sp
          (render_parts [
            cap cap_path; MPText " is a proof capability declared in module ";
            MPCode declaring_mod; MPText ".";
            MPBreak; MPText "Add "; MPCode ("needs " ^ cap_path);
            MPText " to module "; MPCode mod_name.txt; MPText " to acknowledge this dependency.";
            MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
            MPText " can mint "; cap cap_path; MPText " — callers must receive it as a parameter." ])
      | None ->
        Err.error_with_fix env.errors ~span:sp ~code:("cap_needs:" ^ cap_path)
          ~fix:(Err.FInsert {
            after_line = mod_name.March_ast.Ast.span.March_ast.Ast.start_line;
            text = "  needs " ^ cap_path })
          (render_parts [
            cap cap_path; MPText " used in module "; MPCode mod_name.txt;
            MPText " but "; MPCode cap_path; MPText " is not declared in ";
            MPCode "needs"; MPText ".";
            MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
            MPText " to the module body." ])
    end
  ) used_caps;
  (* Check 1b: a body-scanned builtin call implying an undeclared capability.
     ERROR since 2026-08-06 (was warning-only).  `needs` was a hard floor for
     capability-PASSING code and merely advisory for a direct builtin call —
     which is the code most likely to abuse it.  Per-function transitive
     closure (#209) made the ceiling precise enough to enforce without
     collapsing every module to `needs IO`.

     Scope, stated because it is easy to over-read: this catches a DIRECT
     builtin call in a module body.  A stdlib-MEDIATED call (`File.read`
     rather than `file_read`) is invisible here and is caught by
     --cap-strict's ceiling over emitted TIR instead.  Check 1c below
     (extern -> IO.Foreign) is deliberately NOT flipped.

     Reported ONCE per module, not once per offending call site: a `main`
     that touches four undeclared capabilities used to produce four separate
     "does not declare" errors on top of the grant error, which already
     aggregates all four into one replacement signature. Accumulate every
     (cap, span) that fails the check across the whole walk, then emit a
     single diagnostic listing all of them with one multi-line insert fix —
     `forge fix` still applies it in one pass since it is one [FInsert]. *)
  let missing_needs =
    List.filter_map (fun (cap_path, sp) ->
      let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
      let self_declared = match List.assoc_opt cap_path env.proof_caps with
        | Some dm -> dm = mod_name.txt
        | None -> false
      in
      (* Already subsumed by a capability Check 1 is separately demanding
         (e.g. `Cap(IO)` subsumes `IO.Clock`/`IO.Console`/`IO.Random`) — skip
         it here so the two checks' fixes do not overlap; Check 1's own
         diagnostic above already covers this capability. *)
      let subsumed_by_check1 =
        List.exists (fun demanded -> cap_subsumes demanded cap_path)
          !check1_demanded_caps
      in
      if not covered && not self_declared && not subsumed_by_check1
      then Some (cap_path, sp) else None
    ) body_cap_uses
  in
  (match missing_needs with
   | [] -> ()
   | first :: rest ->
     (* [body_cap_uses] is not in source order (it is built by a fold that
        prepends), so pick the earliest span explicitly rather than assuming
        [first] is first in the file — the diagnostic must point at real
        code, and "first accumulated" is not "first in the module". *)
     let first_span =
       List.fold_left (fun best (_, sp) ->
         let open Ast in
         if (sp.start_line, sp.start_col) < (best.start_line, best.start_col)
         then sp else best
       ) (snd first) rest
     in
     let caps = List.sort_uniq String.compare (List.map fst missing_needs) in
     let show =
       String.concat ", " (List.map (fun c -> Printf.sprintf "`Cap(%s)`" c) caps)
     in
     (* Two renderings of the same capability set, for two different
        purposes: [fix_lines] is what `forge fix` literally splices into the
        module body (two-space indent, matching the module's own `needs`
        convention), and [display_lines] is what the diagnostic pane shows
        (eight-space indent, matching the sibling grant error's `fn main(...)`
        help block at line ~13249 above — same visual precedent, not a new
        style). Naming the capability set only ONCE in the prose (in [show])
        and then showing the literal fix text, rather than also restating the
        set in a second "needs X and needs Y and ..." sentence, was fix-round
        feedback on this task: the set was previously spelled three times
        across two different join styles (", " for the Cap(...) list, " and "
        for the needs list), which got worse rather than better as the
        module's missing-capability count grew. *)
     let fix_lines = String.concat "\n" (List.map (fun c -> "  needs " ^ c) caps) in
     let display_lines =
       String.concat "\n" (List.map (fun c -> "        needs " ^ c) caps)
     in
     (* [~code] tags this diagnostic with the exact missing capability set so
        that a presentation-layer consumer (bin/main.ml) can recognise when
        [Cap_infer]'s call-site hint is reporting a fact already covered by
        this error's capability set (same module, capability in this code's
        set — no longer requiring the SAME span, since aggregation means
        this error's span is only the first offending call site, not every
        one Cap_infer might hint at), without either pass having to know
        about the other — see
        specs/progress/2026-08-10-capability-diagnostic-duplication.md and
        specs/progress/2026-08-13-aggregate-missing-needs-diagnostics.md. *)
     Err.error_with_fix env.errors ~span:first_span
       ~code:("cap_needs:" ^ String.concat "," caps)
       ~fix:(Err.FInsert {
         after_line = mod_name.March_ast.Ast.span.March_ast.Ast.start_line;
         text = fix_lines })
       (Printf.sprintf
          "function bodies in `%s` call builtins that require %s, but `%s` \
           declares no matching `needs`.\n\
           hint: add these to the module body —\n\
           %s"
          mod_name.txt show mod_name.txt display_lines))
  ;
  (* Check 1c: extern blocks imply IO.Foreign (and IO.Foreign.Blocking for blocking fns) — warning only *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need -> cap_subsumes need cap_path) declared_needs in
    if not covered then
      Err.warning_with_fix env.errors ~span:sp
        ~fix:(Err.FInsert {
          after_line = mod_name.March_ast.Ast.span.March_ast.Ast.start_line;
          text = "  needs " ^ cap_path })
        (render_parts [
          MPText "extern block in "; MPCode mod_name.txt;
          MPText " requires "; cap cap_path;
          MPText " but "; MPCode mod_name.txt; MPText " does not declare ";
          MPCode ("needs " ^ cap_path); MPText ".";
          MPBreak; MPText "hint: add "; MPCode ("needs " ^ cap_path);
          MPText " to the module body." ])
  ) extern_cap_uses;
  (* Check 2: every needs declaration must be used *)
  (* The capabilities this module's OWN functions reach TRANSITIVELY —
     including through a stdlib wrapper, which none of the source-level lists
     below can see (the stdlib deliberately declares no `needs`, so
     [env.module_caps] never carries its uses either).  Without this, the
     ceiling and Check 2 contradicted each other on the same line: a
     stdlib-mediated `pmap` REQUIRES `needs IO.Spawn` at the ceiling, and
     Check 2 then said "no function requires Cap(IO.Spawn) — help: remove",
     whose autofix re-breaks the build.  First hit minutes after the ceiling
     became the default (golden g43); filed as
     specs/todos/2026-08-08-unused-cap-warning-contradicts-ceiling.md.

     Same closure table Check 4 uses for imports, and it is [lazy] for the
     same reason: only a module that both declares a `needs` and fails every
     cheaper test below pays for the fixpoint.  Keyed by this module's
     DECLARED function names ([cap_qname], skipping stdlib-span decls) — not
     by key shape: at the entry module the prefix is empty, so prelude
     functions are keyed bare exactly like the user's own, and selecting by
     shape would fold the prelude's IO.Console into every module (the same
     trap [own_caps_of_this_module] documents). *)
  let own_transitive_caps : string list Lazy.t = lazy (
    let tbl = Lazy.force trans_closures in
    List.concat_map (fun (d : Ast.decl) ->
        match d with
        | Ast.DFn (fd, sp) when not (span_is_stdlib sp) ->
          (match Hashtbl.find_opt tbl (cap_qname fd.Ast.fn_name.txt) with
           | Some caps -> caps | None -> [])
        | _ -> [])
      decls
    |> List.sort_uniq String.compare)
  in
  List.iter (fun need ->
    let need_sp =
      let rec find_span = function
        | [] -> mod_name.span
        | Ast.DNeeds (caps, s) :: _
          when List.exists (fun (names, _) -> cap_path_of_names names = need) caps -> s
        | _ :: rest -> find_span rest
      in
      find_span decls
    in
    let used = List.exists (fun (cap_path, _, _) -> cap_subsumes need cap_path) used_caps
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) body_cap_uses
              || List.exists (fun (cap_path, _) -> cap_subsumes need cap_path) extern_cap_uses
              || List.exists (fun (_, req_caps) ->
                   List.exists (fun req_cap -> cap_subsumes need req_cap) req_caps
                 ) env.module_caps
              || List.exists (fun cap_path -> cap_subsumes need cap_path)
                   (Lazy.force own_transitive_caps) in
    if not used then
      Err.warning_with_fix env.errors ~span:need_sp
        ~fix:(Err.FDelete {
          start_line = need_sp.March_ast.Ast.start_line;
          end_line   = need_sp.March_ast.Ast.end_line })
        (render_parts [
          MPText "module "; MPCode mod_name.txt; MPText " declares ";
          MPCode ("needs " ^ need); MPText " but no function requires ";
          cap need; MPText " or a sub-capability.";
          MPBreak; MPText "help: remove the unused capability declaration." ])
  ) (List.filter (fun need -> not (List.mem need unknown_needs)) declared_needs);
  (* Check 3 (hint): Cap(IO) root — suggest narrowing.  Not on `main`: the
     reference calls `fn main(cap : Cap(IO))` the entry-point convention, so
     hinting there tells users to stop following the documented advice. *)
  List.iter (fun (cap_path, fn_name, sp) ->
    if cap_path = "IO" && fn_name <> "main" then
      Err.hint env.errors ~span:sp
        (render_parts [
          MPText "this function takes "; cap "IO";
          MPText " (the root capability); consider narrowing to e.g. ";
          cap "IO.FileRead"; MPText " or "; cap "IO.Console";
          MPText " for least-privilege." ])
  ) used_caps;
  (* Check 4: transitive — every module we `use` that declares `needs` must be covered *)
  List.iter (function
    | Ast.DUse (ud, sp) ->
      let imported = String.concat "." (List.map (fun n -> n.Ast.txt) ud.use_path) in
      (* Demand-driven (see [import_required_caps]): only what the functions
         this module actually references from [imported] require, not the
         imported module's whole set.  The per-cap [covered] loop, the
         diagnostic text and its span are unchanged — only the SET of required
         capabilities narrowed. *)
      (match (match import_required_caps ud sp imported with
              | [] -> None | caps -> Some caps) with
       | None -> ()
       | Some req_caps ->
         List.iter (fun req_cap ->
           let covered =
             List.exists (fun need -> cap_subsumes need req_cap) declared_needs
           in
           if not covered then
             Err.error env.errors ~span:sp
               (render_parts [
                 MPText "module "; MPCode mod_name.txt; MPText " imports ";
                 MPCode imported; MPText " which requires "; cap req_cap;
                 MPText ", but "; MPCode req_cap; MPText " is not declared in ";
                 MPCode "needs"; MPText ".";
                 MPBreak; MPText "help: add "; MPCode ("needs " ^ req_cap);
                 MPText " to the module body." ])
         ) req_caps)
    | _ -> ()
  ) decls;
  (* Check 5: extern blocks require the declared capability to be in `needs` *)
  List.iter (function
    | Ast.DExtern (edef, sp) ->
      let cap_paths = cap_paths_in_surface_ty edef.ext_cap_ty in
      List.iter (fun cap_path ->
        let covered =
          List.exists (fun need -> cap_subsumes need cap_path) declared_needs
        in
        if not covered then
          Err.error env.errors ~span:sp
            (render_parts [
              MPText "extern block "; MPCode ("\"" ^ edef.ext_lib_name ^ "\"");
              MPText " uses "; cap cap_path;
              MPText ", but "; MPCode cap_path; MPText " is not declared in ";
              MPCode "needs"; MPText ".";
              MPBreak; MPText "help: add "; MPCode ("needs " ^ cap_path);
              MPText " to the module body." ])
      ) cap_paths
    | _ -> ()
  ) decls;
  (* Check 6: proof cap production enforcement.
     A function cannot return a proof cap unless it received it as a parameter, EXCEPT
     for public (`fn`) functions in the declaring module — those are the minting surface.
     Private (`pfn`) functions in the declaring module face the same restriction as external
     modules: they may pass a cap through but cannot produce one from nothing. *)
  List.iter (function
    | Ast.DFn (def, sp) ->
      let param_caps : string list =
        List.concat_map (fun c ->
          List.concat_map (fun p ->
            match p with
            | Ast.FPNamed { param_ty = Some t; _ } -> cap_paths_in_surface_ty t
            | _ -> []
          ) c.Ast.fc_params
        ) def.fn_clauses
      in
      let ret_tys = Option.to_list def.fn_ret_ty in
      List.iter (fun ret_ty ->
        List.iter (fun cap_path ->
          match List.assoc_opt cap_path env.proof_caps with
          | Some declaring_mod
            when (declaring_mod <> mod_name.txt
                  || def.fn_vis = Ast.Private)
              && not (List.mem cap_path param_caps) ->
            if declaring_mod = mod_name.txt then
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "private function "; MPCode def.fn_name.txt;
                  MPText " in "; MPCode declaring_mod;
                  MPText " cannot mint "; cap cap_path; MPText ".";
                  MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
                  MPText " can construct "; cap cap_path; MPText ".";
                  MPBreak; MPText "hint: make this function public, or accept ";
                  cap cap_path; MPText " as a parameter and pass it through." ])
            else
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "function "; MPCode def.fn_name.txt;
                  MPText " returns "; cap cap_path;
                  MPText " but "; cap cap_path; MPText " is a proof capability declared in ";
                  MPCode declaring_mod; MPText ".";
                  MPBreak; MPText "Only public functions of "; MPCode declaring_mod;
                  MPText " can construct "; cap cap_path; MPText ".";
                  MPBreak; MPText "hint: accept "; cap cap_path;
                  MPText " as a parameter and pass it through, or call a factory in ";
                  MPCode declaring_mod; MPText "." ])
          | _ -> ()
        ) (cap_paths_in_surface_ty ret_ty)
      ) ret_tys
    | _ -> ()
  ) decls;
  (* Check 7 — realtime exclusion.
     A function with `Tagged(_, Realtime)` cannot also take `Cap(Alloc)`,
     `Cap(IO)`, or `Cap(Panic)` as parameters — those capabilities are excluded
     from realtime contexts by the narrowing rule in §3/§5. *)
  let is_realtime_tagged = function
    | Ast.TyCon ({txt="Tagged";_}, [_; Ast.TyCon ({txt="Realtime";_}, [])]) -> true
    | _ -> false
  in
  let is_excluded_cap = function
    | Ast.TyCon ({txt="Cap";_}, [Ast.TyCon ({txt=("Alloc"|"IO"|"Panic");_}, [])]) -> true
    | _ -> false
  in
  List.iter (function
    | Ast.DFn (def, sp) ->
      let all_param_tys = List.concat_map (fun c ->
        List.filter_map (fun p ->
          match p with
          | Ast.FPNamed { param_ty = Some t; _ } -> Some t
          | _ -> None
        ) c.Ast.fc_params
      ) def.fn_clauses in
      let has_realtime = List.exists is_realtime_tagged all_param_tys in
      if has_realtime then
        List.iter (fun t ->
          if is_excluded_cap t then begin
            let cap_name = match t with
              | Ast.TyCon (_, [Ast.TyCon ({txt;_}, [])]) -> txt
              | _ -> "?" in
            Err.error env.errors ~span:sp
              (render_parts [
                MPText "function "; MPCode def.fn_name.txt;
                MPText " takes "; MPCode "Tagged(_, Realtime)";
                MPText " but also takes "; MPCode ("Cap(" ^ cap_name ^ ")");
                MPText ".";
                MPBreak; MPText "Realtime functions cannot hold ";
                MPCode ("Cap(" ^ cap_name ^ ")");
                MPText " — allocation, IO, and panic are excluded from realtime contexts.";
                MPBreak; MPText "hint: remove "; MPCode ("Cap(" ^ cap_name ^ ")")
              ])
          end
        ) all_param_tys
    | _ -> ()
  ) decls;
  (* Check 8 - migrate_state must be IO-free, Phase5C-C.5.
     State-migration functions, the actor_lower plus _migrate_state naming
     convention, see is_migrate_fn_name, run during the hot-migration window,
     ahead of any pending user messages; doing IO there is dangerous. Use the
     own-caps projection, env.own_cap_closures / fn_own_capability_closures,
     NOT the merged cap_closures: the merged closure folds in the module
     declared needs, typically present for the module handlers, which
     would falsely flag a migrate_state whose own body or signature touches
     no capability at all. *)
  let check_migrate_fn_io_free (qname : string) (sp : Ast.span) =
    let own_caps =
      Option.value ~default:[] (Hashtbl.find_opt env.own_cap_closures qname)
    in
    if own_caps <> [] then
      Err.error env.errors ~span:sp
        (render_parts [
          MPText "migrate_state must be IO-free"; MPBreak;
          MPCode qname; MPText " calls capabilities that need ";
          MPCode (String.concat ", " own_caps); MPText ".";
          MPBreak; MPText "migrate_state runs during the hot-migration window, before user messages.";
          MPBreak; MPText "hint: move side effects into a normal handler that runs after migration completes." ])
  in
  List.iter (function
    | Ast.DFn (def, sp) when is_migrate_fn_name def.fn_name.txt ->
      check_migrate_fn_io_free (cap_qname def.fn_name.txt) sp
    (* An extern-declared fn following the migrate_state naming convention is
       equally recognized: its own caps were recorded under [ef_name.txt] by
       the extern-implied-caps pass above (any extern block is IO.Foreign,
       [blocking] adds IO.Foreign.Blocking), and that alone must fail the
       IO-free bound just like a body-scanned builtin call would for a DFn. *)
    | Ast.DExtern (edef, sp) ->
      List.iter (fun (ef : Ast.extern_fn) ->
        if is_migrate_fn_name ef.Ast.ef_name.txt then
          check_migrate_fn_io_free (cap_qname ef.Ast.ef_name.txt) sp
      ) edef.ext_fns
    | _ -> ()
  ) decls

(** [cap_in_solved_ty t] returns the RENDERED capability type — ["Cap(IO)"],
    ["ActorCap(_)"] — of the first capability found anywhere in the SOLVED
    type [t], or [None].  Callers print it verbatim; it is a whole type, not a
    bare path, because two constructors can appear here.

    Companion to [Cap_surface_ty.caps_in_ty], which walks the surface syntax a
    programmer wrote.  This one walks the internal, post-unification [ty] and
    so must [repr] through every node: a capability that arrives by
    unification rather than by annotation is precisely the case Check A exists
    to catch, and it is invisible without the deref.

    Exhaustive over [ty]'s constructors with no wildcard arm, for the reason
    given at the top of [Cap_surface_ty]. *)
let rec cap_in_solved_ty (t : ty) : string option =
  let first = List.fold_left
      (fun acc x -> match acc with Some _ -> acc | None -> cap_in_solved_ty x) None in
  match repr t with
  (* [ActorCap] is here as well as [Cap] (2026-08-06).  Forging a
     [VCap (pid, epoch)] out of JSON fabricates a live, send-capable reference
     to an ARBITRARY actor at an arbitrary epoch — the same class of hole as
     forging [Cap(IO)], and not covered by the IO lattice. *)
  | TCon (("Cap" | "ActorCap") as con, [inner]) ->
    (* Render the argument for the diagnostic.  An unsolved or structured
       argument renders as `_`: the position is still a capability position
       and still rejected — an un-pinned capability is not a safe capability —
       we simply cannot name it. *)
    Some (con ^ "(" ^ (match repr inner with TCon (p, []) -> p | _ -> "_") ^ ")")
  | TCon (_, args) -> first args
  | TArrow (a, b) -> first [a; b]
  | TTuple ts -> first ts
  | TRecord flds -> first (List.map snd flds)
  | TLin (_, t) -> cap_in_solved_ty t
  | TNatOp (_, a, b) -> first [a; b]
  | TRefine (base, _, _) -> cap_in_solved_ty base
  | TVar _ -> None      (* unsolved: nothing to name, nothing to report *)
  | TNat _ -> None      (* type-level natural *)
  | TChan _ -> None     (* session_ty carries no capability *)
  | TError -> None      (* already-reported error sentinel; stay quiet *)

(** R4a: attenuation must move DOWN the lattice, or stay level.

    This is what stops [cap_narrow] widening now that its argument type is
    [Cap(a)] rather than [Cap(IO)].  Before R4a the argument type did the work
    through unification and there was nothing to bypass; this sweep is weaker
    in kind, so its coverage is the whole guarantee.

    Deferred, not eager, for the same reason as every other capability sweep
    here: the result var is pinned by LATER unification (reject/t155).

    Enforced only when BOTH sides resolve to concrete IO-lattice capabilities:

    - A PROOF cap on either side is left alone.  Proof capabilities are not in
      the IO lattice, and they have their own discipline ([mint_cap]'s gate and
      Check 6).  [cap_narrow(root) : Cap(Db.Migrated)] typechecks today and is
      governed by Check 6 on the way out; making subsumption reject it here
      would silently change proof-cap semantics under cover of an IO change.
    - An UNPINNED side is silent.  A [cap_narrow] whose result never gets
      pinned to a concrete capability is a result never USED as one, so no
      authority is exercised and there is nothing to widen into.  (I proposed
      failing closed here and was wrong: the R3 argument for silence on an
      unresolved [from_json] result applies unchanged, and failing closed would
      reject ordinary code that narrows into a polymorphic position.) *)
let check_cap_narrow_sites (env : env) : unit =
  let concrete t = match repr t with
    | TCon ("Cap", [inner]) ->
      (match repr inner with TCon (p, []) -> Some p | _ -> None)
    | _ -> None
  in
  let is_proof p = List.mem_assoc p env.proof_caps in
  List.iter (fun (sp, f_ty) ->
      match repr f_ty with
      | TArrow (src_ty, dst_ty) ->
        (match concrete src_ty, concrete dst_ty with
         | Some src, Some dst
           when not (is_proof src) && not (is_proof dst)
             && not (March_caps.Cap_lattice.cap_subsumes src dst) ->
           Err.error env.errors ~span:sp
             (render_parts [
               MPCode ("Cap(" ^ src ^ ")");
               MPText " cannot be widened to "; MPCode ("Cap(" ^ dst ^ ")");
               MPText " — "; MPCode "cap_narrow";
               MPText " only attenuates, so the source capability must subsume the target.";
               MPBreak;
               MPText "help: "; MPCode ("Cap(" ^ dst ^ ")");
               MPText " is not below "; MPCode ("Cap(" ^ src ^ ")");
               MPText " in the capability lattice. Receive it from a caller that holds an ancestor of it." ])
         | _ -> ())
      | _ -> ()
    ) !(env.cap_narrow_sites)

(** Capability unforgeability (R3), the call-site half.  [to_json] is checked
    on its argument, the [from_json] family on its result; see
    [env.json_cap_sites] for why this runs deferred and why it inspects the
    instantiated arrow.

    An application whose relevant position never got pinned leaves a [TVar],
    which [cap_in_solved_ty] reports as [None] — silence.  That is deliberate:
    an unpinned result is a program that never used the decoded value as a
    capability, and rejecting it would break ordinary polymorphic JSON code.
    The forge only becomes a forge once something pins the type, and pinning
    is exactly what this sweep waits for. *)
let check_json_cap_sites (env : env) : unit =
  List.iter (fun (sp, f_ty, jname) ->
      let encoding = (jname = "to_json") in
      let inspected =
        match repr f_ty with
        | TArrow (a, b) -> if encoding then a else b
        (* Not an arrow: the builtin was referenced in a shape this recording
           did not anticipate.  Inspect the whole thing rather than skip it —
           silently ignoring an unrecognised shape is how a capability walk
           becomes a hole. *)
        | other -> other
      in
      match cap_in_solved_ty inspected with
      | None -> ()
      | Some cap_rendered ->
        let verb = if encoding then "serialized" else "deserialized" in
        Err.error env.errors ~span:sp
          (render_parts [
            (* Already rendered as `Cap(X)` or `ActorCap(X)` by
               [cap_in_solved_ty] — do not wrap it again. *)
            MPCode cap_rendered;
            MPText (" cannot be " ^ verb ^ " — a capability may only be received, never constructed.");
            MPBreak;
            MPText "hint: "; MPCode jname;
            MPText " places no constraint on the type it produces, so it would fabricate authority from data. Receive the capability as a parameter and pass it through instead." ])
    ) !(env.json_cap_sites)

(** Validate every `proof cap X with T` clause.  Deferred rather than checked
    at the declaration because a capability may name a record type declared
    LATER in the same module, and [check_decl] folds declarations in source
    order.

    Silence when the clause resolves; otherwise say which of the two ways it
    failed, because "unknown type" and "declared, but not a record" want
    different fixes. *)
let check_cap_dict_decls (env : env) : unit =
  List.iter (fun (sp, cap_path, dict_name) ->
      match resolve_cap_dict_type env cap_path with
      | Some _ -> ()
      | None ->
        let qual =
          match List.assoc_opt cap_path env.proof_caps with
          | Some m when m <> "" -> m ^ "." ^ dict_name
          | _ -> dict_name
        in
        let known_type =
          StrMap.mem dict_name env.types || StrMap.mem qual env.types
        in
        if known_type then
          Err.error env.errors ~span:sp
            (render_parts [
              MPText "A capability's dictionary type must be a RECORD type, but ";
              MPCode dict_name; MPText " is not one.";
              MPBreak;
              MPText "hint: a dictionary is the set of operations the capability \
                      authorizes, one function per field — e.g. ";
              MPCode "type Ops = { send : (Int) -> Int }"; MPText "." ])
        else
          Err.error env.errors ~span:sp
            (render_parts [
              MPText "I don't know a type named "; MPCode dict_name;
              MPText " for the dictionary of "; MPCode ("Cap(" ^ cap_path ^ ")");
              MPText ".";
              MPBreak;
              MPText "hint: declare the record type in the same module as the \
                      capability." ])
    ) !(env.cap_dict_decl_sites)

(** Post-checking sweep: enforce the [cap_impl] gate.

    Supplying a dictionary is forging a capability's BEHAVIOUR — the same
    threat model [check_mint_cap_sites] defeats — so the rule starts from that
    gate as precedent and splits by capability kind:

    - PROOF CAP: allowed only inside a public [fn] of the declaring module.
      [mint_cap]'s rule, unchanged.  A dictionary is strictly MORE authority
      than a mint (it decides what the capability does, not merely that it
      exists), so it cannot be looser; and the declaring module already defines
      the meaning of its own operations, so it is not an escalation either.
    - IO CAP: there is no declaring module, so the rule above has nothing to
      bind to.  Admitted only under [--test] ([Typecheck_env.test_build]).

    An UNPINNED result is rejected, not ignored — unlike [check_cap_narrow_sites],
    where silence is right.  The difference: a [cap_impl] whose result never gets
    pinned is precisely the polymorphic-supplier forge ([forall a. _ -> Cap(a)]),
    a supplier that could re-implement every capability at once.  This mirrors
    [check_mint_cap_sites]'s third arm. *)
let check_cap_impl_sites (env : env) : unit =
  List.iter (fun (sp, rty, dict_ty, cur_fn_public, current_module) ->
      let err parts = Err.error env.errors ~span:sp (render_parts parts) in
      match repr rty with
      | TCon ("Cap", [inner]) ->
        (match repr inner with
         | TCon (p, []) ->
           let declaring = List.assoc_opt p env.proof_caps in
           (* Gate first: on a refused site the dictionary's own type is not
              worth a second diagnostic. *)
           let gate_ok =
             match declaring with
             | Some declaring_mod ->
               if declaring_mod = current_module && cur_fn_public then true
               else begin
                 err [
                   MPText "cap_impl "; MPCode ("Cap(" ^ p ^ ")");
                   MPText " is only allowed inside a public function of its declaring module ";
                   MPCode declaring_mod; MPText ".";
                   MPBreak;
                   MPText "hint: supplying a dictionary decides what the capability \
                           DOES, so it is gated exactly like ";
                   MPCode "mint_cap"; MPText ". Expose a public factory in ";
                   MPCode declaring_mod; MPText " and call that instead." ];
                 false
               end
             | None ->
               (* Not a proof cap — an IO capability, which has no declaring
                  module to bind the rule to. *)
               if !test_build then true
               else begin
                 err [
                   MPText "cap_impl "; MPCode ("Cap(" ^ p ^ ")");
                   MPText " is not allowed here: an IO capability has no declaring \
                           module, so there is no module that owns the right to say \
                           what it does.";
                   MPBreak;
                   MPText "hint: mocking an IO capability is admitted only in a test \
                           build ("; MPCode "--test";
                   MPText "). To swap behaviour in ordinary code, declare your own \
                           capability with a dictionary (";
                   MPCode "proof cap Name with Ops";
                   MPText ") and route the operations through it." ];
                 false
               end
           in
           if gate_ok then begin
             match resolve_cap_dict_type env p with
             | None when declaring = None ->
               (* Reachable only under [--test]: the build-mode gate admitted an
                  IO capability, and then there is no declaration to check the
                  dictionary against, because an IO cap has no declaration site
                  a user owns.  Say so precisely rather than reusing the
                  proof-cap message, whose hint does not apply.

                  This is where mocking IO actually stops today, and the reason
                  is upstream of dictionaries: an IO builtin does not CONSUME
                  its capability ([println : String -> ()]; the requirement
                  lives in [Typecheck_builtins.builtin_cap_table]), so even a
                  dictionary that could be attached would never be consulted.
                  Closing this needs the cap-first migration of the builtins,
                  not more machinery here.  See
                  specs/todos/2026-08-31-cap-runtime-dictionaries.md. *)
               err [
                 MPText "There is no way to declare a dictionary type for ";
                 MPCode ("Cap(" ^ p ^ ")");
                 MPText " — an IO capability has no declaration site to carry a ";
                 MPCode "with"; MPText " clause.";
                 MPBreak;
                 MPText "hint: IO builtins do not take their capability as an \
                         argument (";
                 MPCode "println : (String) -> ()";
                 MPText "), so a dictionary attached here would never be \
                         consulted. Declare your own capability instead (";
                 MPCode "proof cap Name with Ops";
                 MPText ") and route the operations through it." ]
             | None ->
               err [
                 MPCode ("Cap(" ^ p ^ ")");
                 MPText " declares no runtime dictionary, so there is nothing for ";
                 MPCode "cap_impl"; MPText " to attach.";
                 MPBreak;
                 MPText "hint: declare one on the capability — ";
                 MPCode ("proof cap " ^ cap_bare_name p ^ " with SomeRecordType"); MPText "." ]
             | Some rec_name ->
               (* Compare by UNIFICATION, not by name.  A record literal infers
                  to a structural [TRecord], while the declaration gives a
                  nominal [TCon], and a record type is registered under both its
                  bare and its module-qualified spelling
                  (typecheck.ml:5900-5901).  Comparing names produced the
                  useless diagnostic "declares its dictionary as `Ops`, but this
                  one is `Ops`"; [unify] already reconciles the two shapes via
                  [expand_record] and reports a precise per-field mismatch. *)
               Typecheck_unify.unify env ~span:sp (TCon (rec_name, [])) dict_ty
           end
         | _ ->
           err [
             MPText "cap_impl here does not have a determinable capability result type.";
             MPBreak;
             MPText "hint: cap_impl must produce a specific ";
             MPCode "Cap(Mod.Name)";
             MPText " fixed at the call site. A cap_impl captured in a generalized \
                     (let-bound) lambda is polymorphic in the capability — a supplier \
                     that could re-implement every capability at once — and is \
                     rejected. Attach directly, or fix the capability type (e.g. \
                     annotate the return)." ])
      | _ -> ()
    ) !(env.cap_impl_sites)

(** Post-checking sweep (Part 2): enforce the [mint_cap] gate for every recorded
    site, now that its result type is pinned by later unification.  [mint_cap(x)]
    typechecks iff its pinned result is [Cap(P)] with [P] a proof cap whose
    declaring module equals the site's enclosing module AND the site's enclosing
    fn is public.  A proof cap from another module or a mint in a private/non-
    declaring fn is rejected (unforgeability); a non-proof (IO) target is
    rejected too — attenuating IO caps is [cap_narrow]'s job.  The enclosing
    fn/module context was captured at record time (unavailable now). *)
let check_mint_cap_sites (env : env) : unit =
  List.iter (fun (sp, rty, cur_fn_public, current_module) ->
      match repr rty with
      | TCon ("Cap", [inner]) ->
        (match repr inner with
         | TCon (p, []) ->
           (match List.assoc_opt p env.proof_caps with
            | Some declaring_mod ->
              if not (declaring_mod = current_module && cur_fn_public) then
                Err.error env.errors ~span:sp
                  (render_parts [
                    MPText "mint_cap "; MPCode ("Cap(" ^ p ^ ")");
                    MPText " is only allowed inside a public function of its declaring module ";
                    MPCode declaring_mod; MPText ".";
                    MPBreak;
                    MPText "hint: to obtain "; MPCode ("Cap(" ^ p ^ ")");
                    MPText " elsewhere, receive it as a parameter and pass it through, or call a public factory in ";
                    MPCode declaring_mod; MPText "." ])
            | None ->
              (* mint_cap used to produce a non-proof (IO) cap — disallow; that's
                 cap_narrow's job. *)
              Err.error env.errors ~span:sp
                (render_parts [
                  MPText "mint_cap is only for proof capabilities; use ";
                  MPCode "cap_narrow"; MPText " to attenuate IO capabilities." ]))
         | _ ->
           (* Result is not a concrete cap constructor — an unbound (generalized)
              cap var that never got pinned to a specific proof cap.  This
              happens when the mint is inside a [let]-bound lambda that gets
              generalized to [forall a. _ -> Cap(a)]: such a value is a
              polymorphic cap producer that could mint ANY cap (a forge vector),
              so it is rejected regardless of the enclosing fn.  A mint whose
              target proof cap is fixed at the call site (direct mint, or an
              immediately-applied / type-annotated lambda) pins the result and
              is checked against the declaring-module + public gate above. *)
           Err.error env.errors ~span:sp
             (render_parts [
               MPText "mint_cap here does not have a determinable proof-capability result type.";
               MPBreak;
               MPText "hint: mint_cap must produce a specific ";
               MPCode "Cap(Mod.Name)";
               MPText " fixed at the call site. A mint captured in a generalized (let-bound) lambda is polymorphic in the capability and is rejected — mint directly, or fix the capability type (e.g. annotate the return or apply the lambda in place)." ]))
      | _ -> ()
    ) !(env.mint_cap_sites)

(** [fn_capability_closures env] returns the per-function inferred IO-capability
    closure recorded by [check_module_needs] for every function checked so far
    in [env]'s lineage: [(fully_qualified_fn_name, normalized_cap_paths)] pairs,
    one per function ("Mod.fn" for [DFn]/actor-owning modules, "Mod.extern_fn"
    for FFI functions declared in an [extern] block). The list combines each
    function's own inferred requirements (Cap-typed signature, body-scanned
    builtin calls, extern-implied [IO.Foreign]/[IO.Foreign.Blocking]) with the
    caps that apply to every function in its module (declared [needs] and
    caps propagated in from imported modules per Check 4), normalized via
    [March_caps.Cap_lattice.normalize]. Order is unspecified (backed by a hashtable).
    Consumed by the (future) hot-deploy capability manifest. *)
let fn_capability_closures (env : env) : (string * string list) list =
  (* Sort by key: [Hashtbl.fold] iteration order is unspecified, so sorting
     gives downstream consumers (and any diagnostics derived from this list)
     a deterministic, run-to-run-stable order. *)
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.cap_closures []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

(** [fn_own_capability_closures env] returns each function's OWN inferred
    IO-capability closure — [(fully_qualified_fn_name, normalized_cap_paths)]
    pairs — WITHOUT the module-wide [needs]/import-propagated merge that
    [fn_capability_closures] performs. Use this projection, not the merged
    one, for any "is this one function IO-free" question (e.g. the
    migrate_state check): the merged closure attributes a module's
    handler-level [needs] to every function in the module, including a pure
    migrate_state, which would falsely fail such a check. Order is
    unspecified (backed by a hashtable). *)
(* [declared_cap_scopes env] — every [needs] declaration's capability paired
    with its optional path scope, as written in source.

    Used by [--cap-sandbox] to emit a SCOPED sandbox profile: an unscoped
    grant becomes a blanket allow, a scoped one becomes a subpath allow.
    Declarations rather than inferred use, because the scope is a policy the
    author states — inference can tell you a module reads files, not which
    directory it is permitted to read. *)

let declared_cap_scopes (env : env) : (string * string option) list =
  List.sort_uniq compare env.mod_need_scopes

let fn_own_capability_closures (env : env) : (string * string list) list =
  (* Sort by key for the same determinism reason as [fn_capability_closures]. *)
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) env.own_cap_closures []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

(** Sorted-by-key public view of [fn_transitive_capability_closures_tbl] (the
    sort is for determinism, like [fn_capability_closures]). *)
let fn_transitive_capability_closures (env : env) : (string * string list) list =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc)
    (fn_transitive_capability_closures_tbl env) []
  |> List.sort (fun (a, _) (b, _) -> compare a b)

