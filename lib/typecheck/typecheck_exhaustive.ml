(** Pattern exhaustiveness and redundancy checking — a simplified Maranget
    "Warnings for Pattern Matching" over a pattern matrix, plus the
    redundant-arm and sendability checks that share its machinery.

    Lifted verbatim out of [Typecheck] (§E) on 2026-08-26.  It reads as part
    of inference because [infer_expr] calls it, but the dependency runs the
    other way: exhaustiveness is a DEPENDENCY of inference, not a dependent,
    which is why it sits above [infer_expr] in source order and why it moves
    cleanly.  (A naive `grep infer_expr` over the band reports a hit and would
    conclude the opposite — the hit is [infer_expr]'s own doc comment, which
    belongs to the NEXT definition.  [dep.py], which strips comments first,
    reports zero external dependencies.)

    Note what watches this module: it emits WARNINGS, and `dune build
    @types-check` does not assert on warnings at all.  Tier 2 of
    scripts/types-oracle.sh is the only thing pinning them.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.5). *)

open Typecheck_types
open Typecheck_env

(* ══════════════════════════════════════════════════════════════════
   §E  Pattern exhaustiveness checking
   ══════════════════════════════════════════════════════════════════

   Implements a simplified version of Maranget's "Warnings for
   Pattern Matching" algorithm.  We build a pattern matrix (one row
   per branch, one column per nested level of structure) and look for
   a value that no row matches.  Missing values are reported as
   Warning diagnostics.
*)

(** Simplified pattern for exhaustiveness analysis. *)
type spat =
  | SPWild                          (** _ or any variable binding *)
  | SPCon  of string * spat list    (** Constructor: Some(x), None *)
  | SPLit  of Ast.literal           (** Literal: 0, true, "hi" *)
  | SPTup  of spat list             (** Tuple: (a, b) *)
  | SPRec  of (string * spat) list
      (** Record: { x: p, … }, sorted by field name.  Field lists are OPEN, so
          this may name a SUBSET of the record's fields — an absent field is
          an implicit wildcard.  [spec_rec_mc] fills them in against the field
          list taken from the scrutinee's TYPE, which is what lets two arms
          naming different subsets line up in the same matrix column. *)

(** Qualified constructor patterns ("MarchType.TBool", "Ast.Query") carry
    their full dotted text; exhaustiveness compares against the scrutinee
    type's BARE ctor names, so keep only the last segment. *)
let bare_ctor_name (txt : string) : string =
  match String.rindex_opt txt '.' with
  | Some i -> String.sub txt (i + 1) (String.length txt - i - 1)
  | None -> txt

(** Normalize an AST pattern to a SINGLE [spat], widening anything [spat]
    cannot represent to [SPWild].

    Only used as the fallback for a pattern whose or-expansion exceeds
    [or_expansion_cap]; [norm_pat_rows] is the entry point everything else
    goes through.  Note that [SPWild] in a coverage matrix means "matches
    everything", i.e. it OVER-reports what the arm covers: safe for
    exhaustiveness (it can only suppress a warning), wrong for redundancy
    (the next arm looks subsumed), which is why the callers that use this
    fallback also skip redundancy checking for the arm. *)
let rec norm_pat (p : Ast.pattern) : spat =
  match p with
  | Ast.PatWild _            -> SPWild
  | Ast.PatVar  _            -> SPWild
  | Ast.PatAs  (p', _, _)    -> norm_pat p'
  | Ast.PatRecord (fs, _)    ->
    SPRec (List.sort (fun (a, _) (b, _) -> String.compare a b)
             (List.map (fun ((n : Ast.name), sub) -> (n.txt, norm_pat sub)) fs))
  | Ast.PatOr _              -> SPWild   (* conservative: see norm_pat_rows *)
  | Ast.PatCon  (n, args)    -> SPCon (bare_ctor_name n.txt, List.map norm_pat args)
  | Ast.PatAtom (n, args, _) -> SPCon (":" ^ n, List.map norm_pat args)
  | Ast.PatTuple (ps, _)     -> SPTup (List.map norm_pat ps)
  | Ast.PatLit  (l, _)       -> SPLit l

(** Upper bound on the number of [spat] rows one arm may expand to.  Nested
    or-patterns multiply — `C(1 | 2, 3 | 4)` denotes four concrete shapes —
    so the cross-product is capped and a pattern beyond it falls back to the
    widening [norm_pat]. *)
let or_expansion_cap = 256

(** How many [spat] rows [p] expands to, saturating at [or_expansion_cap + 1]
    so a pathological pattern is rejected by the cap instead of overflowing
    (or building the list to find out). *)
let rec or_expansion_size (p : Ast.pattern) : int =
  let sat n = min n (or_expansion_cap + 1) in
  match p with
  | Ast.PatOr (alts, _) ->
    sat (List.fold_left (fun acc a -> sat (acc + or_expansion_size a)) 0 alts)
  | Ast.PatAs (p', _, _) -> or_expansion_size p'
  | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
    sat (List.fold_left (fun acc p -> sat (acc * or_expansion_size p)) 1 ps)
  (* A record's field sub-patterns multiply exactly like a tuple's elements —
     `{ a: 1 | 2, b: 3 | 4 }` denotes four shapes. *)
  | Ast.PatRecord (fs, _) ->
    sat (List.fold_left (fun acc (_, p) -> sat (acc * or_expansion_size p)) 1 fs)
  | Ast.PatWild _ | Ast.PatVar _ | Ast.PatLit _ -> 1

(** Every [spat] row [p] covers, distributing or-patterns at ANY depth into
    the cross-product of their alternatives. *)
let rec norm_pat_all (p : Ast.pattern) : spat list =
  match p with
  | Ast.PatWild _ | Ast.PatVar _ -> [SPWild]
  | Ast.PatAs (p', _, _)         -> norm_pat_all p'
  | Ast.PatRecord (fs, _)        ->
    let sorted =
      List.sort (fun ((a : Ast.name), _) ((b : Ast.name), _) ->
          String.compare a.txt b.txt) fs in
    let names = List.map (fun ((n : Ast.name), _) -> n.txt) sorted in
    List.map (fun row -> SPRec (List.combine names row))
      (norm_pat_args (List.map snd sorted))
  | Ast.PatOr (alts, _)          -> List.concat_map norm_pat_all alts
  | Ast.PatCon (n, args)         ->
    List.map (fun a -> SPCon (bare_ctor_name n.txt, a)) (norm_pat_args args)
  | Ast.PatAtom (n, args, _)     ->
    List.map (fun a -> SPCon (":" ^ n, a)) (norm_pat_args args)
  | Ast.PatTuple (ps, _)         -> List.map (fun a -> SPTup a) (norm_pat_args ps)
  | Ast.PatLit (l, _)            -> [SPLit l]

and norm_pat_args (ps : Ast.pattern list) : spat list list =
  List.fold_right (fun p acc ->
      let heads = norm_pat_all p in
      List.concat_map (fun h -> List.map (fun t -> h :: t) acc) heads)
    ps [[]]

(** True when [p]'s or-expansion is too large to enumerate, so [norm_pat_rows]
    falls back to the widening [norm_pat].  Redundancy checking must skip such
    an arm — see [check_redundant_arms]. *)
let pat_or_expansion_capped (p : Ast.pattern) : bool =
  or_expansion_size p > or_expansion_cap

(** Expand a pattern into the set of [spat] rows it covers.  Or-patterns are
    expanded at EVERY depth, not just the top level: nesting one inside a
    constructor argument or tuple element used to normalise it to [SPWild],
    which in a coverage matrix means "matches everything" — so `Some(1 | 2)`
    silently claimed to cover all of `Some(_)`, suppressing a real
    non-exhaustiveness warning AND reporting the following arm unreachable.
    (The old comment here claimed the widening was conservative; [SPWild] is
    an over-report, not an under-report, in both consumers.)

    Beyond [or_expansion_cap] rows the enumeration is abandoned and the
    widening [norm_pat] is used instead — see [pat_or_expansion_capped]. *)
let norm_pat_rows (p : Ast.pattern) : spat list =
  if pat_or_expansion_capped p then [norm_pat p] else norm_pat_all p

(** All [(ctor_name, arity)] pairs for a type name, in declaration order.
    Qualified aliases (keys containing '.') are skipped so that exhaustiveness
    analysis only sees each constructor once under its bare name. *)
let ctors_for_type (env : env) type_name =
  (* Gather (ctor_key, ci) for every bare-keyed constructor whose parent type's
     BARE name is [type_name].  Because [ci_type] is bare (kept so for
     cross-module unification), two same-named types from DIFFERENT modules both
     match here — the linear-L4 ctor cross-talk, where a user `type Handle =
     H(Int)` and stdlib's `type Handle = Handle(Int)` merge into one expected
     universe so `match … H(n)` spuriously reports `missing case: Handle(_)`.
     Disambiguate with [ci_module]: if the CURRENT module declares its OWN type
     of this name (a matched ctor carries ci_module = current_module) AND a
     foreign same-named type is also present, the local declaration shadows the
     import, so restrict the universe to the current module's own constructors.
     A single declaration (no cross-module clash) is left exactly as before, so
     this is behavior-preserving except on the collision it fixes; and it feeds
     only this exhaustiveness diagnostic, never codegen. *)
  let matches =
    StrMap.fold (fun k cis acc ->
      if String.contains k '.' then acc
      else
        match List.find_opt (fun (ci : ctor_info) -> ci.ci_type = type_name) cis with
        | Some ci -> (k, ci) :: acc
        | None -> acc
    ) env.ctors []
  in
  let local_shadow =
    env.current_module <> ""
    && List.exists (fun (_, ci) -> ci.ci_module = env.current_module) matches
    && List.exists (fun (_, ci) -> ci.ci_module <> env.current_module) matches
  in
  let matches =
    if local_shadow
    then List.filter (fun (_, ci) -> ci.ci_module = env.current_module) matches
    else matches
  in
  List.map (fun (k, (ci : ctor_info)) -> (k, List.length ci.ci_arg_tys)) matches

(** Instantiate a surface type with a substitution from param names to internal
    types.  Used to reconstruct constructor argument types. *)
let rec inst_ty (subst : (string * ty) list) (surf : Ast.ty) : ty =
  match surf with
  | Ast.TyVar name ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TError)  (* unresolved type param — use error sentinel *)
  | Ast.TyCon (name, []) ->
    (match List.assoc_opt name.txt subst with
     | Some t -> t
     | None   -> TCon (name.txt, []))
  | Ast.TyCon (name, args) ->
    TCon (name.txt, List.map (inst_ty subst) args)
  | Ast.TyArrow (a, b) -> TArrow (inst_ty subst a, inst_ty subst b)
  | Ast.TyTuple ts     -> TTuple (List.map (inst_ty subst) ts)
  | _                  -> TError

(** Instantiated argument types for [ctor_name] given the parent type's
    concrete type arguments (e.g. [Int] for Option(Int)). *)
let ctor_arg_tys (env : env) ctor_name parent_args =
  match lookup_ctor ctor_name env with
  | None -> []
  | Some ci ->
    let n = List.length ci.ci_params in
    let m = List.length parent_args in
    if n <> m then List.map (fun _ -> TError) ci.ci_arg_tys
    else
      let subst = List.combine ci.ci_params parent_args in
      List.map (inst_ty subst) ci.ci_arg_tys

(** Specialize the pattern matrix for constructor [c] with [a] sub-columns.
    - Wildcard rows → a wildcards prepended to remaining columns.
    - Matching [c] rows → their args prepended to remaining columns.
    - Other constructor rows → dropped. *)
let spec_ctor_mc (c : string) (a : int) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPCon (d, ps) when d = c -> Some (ps @ rest)
      | SPCon _ | SPLit _ | SPTup _ | SPRec _ -> None
  ) matrix

(** Specialize the pattern matrix for a tuple of [a] components. *)
let spec_tup_mc (a : int) (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild               -> Some (List.init a (fun _ -> SPWild) @ rest)
      | SPTup ps when List.length ps = a -> Some (ps @ rest)
      | _ -> None
  ) matrix

(** Specialize the pattern matrix for a record with exactly [fields] (sorted
    field names, taken from the scrutinee's TYPE, not from any one pattern).

    A record is irrefutable at the top level — one shape, no tag — so this is
    the tuple case with names instead of positions, plus one twist: field
    lists are OPEN, so a row may name only some of [fields].  Absent fields
    become wildcards, which is what lets `{ code: 404 }` and `{ msg: m }`
    occupy the same column. *)
let spec_rec_mc (fields : string list) (matrix : spat list list)
    : spat list list =
  let wilds = List.map (fun _ -> SPWild) fields in
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild        -> Some (wilds @ rest)
      | SPRec assoc   ->
        Some (List.map (fun f ->
                match List.assoc_opt f assoc with
                | Some sp -> sp
                | None    -> SPWild) fields
              @ rest)
      | SPCon _ | SPLit _ | SPTup _ -> None
  ) matrix

(** Specialize the pattern matrix for a literal value [lit].
    Wildcard rows and matching literal rows pass through (minus first col). *)
let spec_lit_mc (lit : Ast.literal) (matrix : spat list list)
    : spat list list =
  List.filter_map (fun row ->
    match row with
    | [] -> None
    | p :: rest ->
      match p with
      | SPWild           -> Some rest
      | SPLit l when l = lit -> Some rest
      | _ -> None
  ) matrix

(** Default matrix: rows whose first column is a wildcard, with that
    column removed.  Used for infinite-domain types that need a catch-all. *)
let default_mc (matrix : spat list list) : spat list list =
  List.filter_map (fun row ->
    match row with
    | SPWild :: rest -> Some rest
    | _ -> None
  ) matrix

(** Split a list into the first [n] elements and the remainder. *)
let split_at n lst =
  let rec go acc i = function
    | []       -> (List.rev acc, [])
    | x :: rest ->
      if i >= n then (List.rev acc, x :: rest)
      else go (x :: acc) (i + 1) rest
  in
  go [] 0 lst

(** Produce a concise human-readable example value for [ty].
    Used only to build warning messages, not for type-checking. *)
let rec example_of (ty : ty) : string =
  match repr ty with
  | TCon ("Int",    []) -> "0"
  | TCon ("Float",  []) -> "0.0"
  | TCon ("String", []) -> "\"\""
  | TCon ("Bool",   []) -> "true"
  | TCon ("Char",   []) -> "' '"
  | TCon (n, _)         -> n
  | TTuple []           -> "()"
  | TTuple ts           -> "(" ^ String.concat ", " (List.map example_of ts) ^ ")"
  | TVar _              -> "_"
  | TError              -> "_"
  | TArrow _            -> "<fn>"
  | TRecord fs          ->
    "{ " ^ String.concat ", "
             (List.map (fun (n, t) -> n ^ ": " ^ example_of t) fs) ^ " }"
  | TChan _             -> "<chan>"
  | TLin (_, t)         -> example_of t
  | TNat n              -> string_of_int n
  | TNatOp _            -> "_"
  | TRefine (base, _, _) -> example_of base  (* unreachable: repr strips it *)

(** Core exhaustiveness algorithm (Maranget-style).

    [find_missing_mc env tys matrix] tries to find an example value
    (represented as a list of strings, one per column) that is not
    matched by any row in [matrix].

    Returns [None] if the matrix is exhaustive for [tys], or
    [Some examples] (a list of column examples) if non-exhaustive.

    Invariant: when called with k columns, a [Some] result contains
    exactly k strings (for the outermost call, k = 1). *)
let rec find_missing_mc (env : env) (tys : ty list) (matrix : spat list list)
    : string list option =
  match tys with
  | [] ->
    (* No columns left: exhaustive iff matrix has ≥1 row covering this point. *)
    if matrix = [] then Some [] else None
  | ty :: rest_tys ->
    let ty = repr ty in
    (* If any row starts with a wildcard, it covers all values in this column.
       Check the wildcard rows' remaining columns via the default matrix. *)
    let has_first_wild =
      List.exists
        (fun row -> match row with SPWild :: _ -> true | _ -> false)
        matrix
    in
    if has_first_wild then begin
      let def = default_mc matrix in
      match find_missing_mc env rest_tys def with
      | None -> None
      | Some rest_exs ->
        (* First column is covered; use a placeholder for the counterexample. *)
        Some ("_" :: rest_exs)
    end else
    match ty with
    | TError -> None   (* error recovery — skip *)
    | TRefine _ -> None  (* unreachable: [ty] was repr'd above, which strips it *)
    | TVar _ ->
      (* Unknown type: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon ("Bool", []) ->
      (* Bool has exactly two values: true and false (literal patterns). *)
      let check_lit b =
        let sub = spec_lit_mc (Ast.LitBool b) matrix in
        match find_missing_mc env rest_tys sub with
        | None -> None
        | Some rest_exs ->
          Some ((if b then "true" else "false") :: rest_exs)
      in
      (match check_lit true with
       | Some _ as s -> s
       | None        -> check_lit false)
    | TCon (("Int" | "Float" | "String" | "Char" | "Atom"), _) ->
      (* Infinite domains require a wildcard catch-all.
         (No wildcards exist here — checked above — so report missing.) *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))
    | TCon (name, parent_args) ->
      let ctors = ctors_for_type env name in
      if ctors = [] then
        (* Opaque / unknown type: conservative skip. *)
        let def = default_mc matrix in
        (match find_missing_mc env rest_tys def with
         | None -> None
         | Some rest_exs -> Some ("_" :: rest_exs))
      else begin
        (* Collect which constructors appear in the first column. *)
        let seen =
          List.filter_map
            (fun row -> match row with SPCon (c, _) :: _ -> Some c | _ -> None)
            matrix
        in
        (* Is the signature complete? (All ctors present — no wildcards since
           those were handled above.) *)
        let is_complete =
          List.for_all (fun (c, _) -> List.mem c seen) ctors
        in
        if is_complete then
          (* Every constructor appears: check each one's sub-matrix. *)
          List.find_map (fun (ctor_name, arity) ->
            let arg_tys = ctor_arg_tys env ctor_name parent_args in
            let sub      = spec_ctor_mc ctor_name arity matrix in
            let full_tys = arg_tys @ rest_tys in
            match find_missing_mc env full_tys sub with
            | None -> None
            | Some exs ->
              let ctor_exs, rest_exs = split_at arity exs in
              let ctor_str =
                if arity = 0 then ctor_name
                else
                  Printf.sprintf "%s(%s)" ctor_name
                    (String.concat ", " ctor_exs)
              in
              Some (ctor_str :: rest_exs)
          ) ctors
        else begin
          (* Some constructor missing from first col and no wildcards:
             find one and report it. *)
          let def = default_mc matrix in
          match find_missing_mc env rest_tys def with
          | None -> None
          | Some rest_exs ->
            let missing_ctor =
              List.find_opt (fun (c, _) -> not (List.mem c seen)) ctors
            in
            let first_ex = match missing_ctor with
              | Some (c, 0) -> c
              | Some (c, _) ->
                let args = ctor_arg_tys env c parent_args in
                Printf.sprintf "%s(%s)" c
                  (String.concat ", " (List.map example_of args))
              | None -> "_"
            in
            Some (first_ex :: rest_exs)
        end
      end
    | TTuple [] -> None   (* unit — always covered *)
    | TTuple inner_tys ->
      let arity = List.length inner_tys in
      let any_tup =
        List.exists
          (fun row -> match row with SPTup _ :: _ -> true | _ -> false)
          matrix
      in
      if any_tup then begin
        (* At least one tuple pattern: specialize and recurse. *)
        let sub      = spec_tup_mc arity matrix in
        let full_tys = inner_tys @ rest_tys in
        match find_missing_mc env full_tys sub with
        | None -> None
        | Some exs ->
          let tup_exs, rest_exs = split_at arity exs in
          let tup_str =
            Printf.sprintf "(%s)" (String.concat ", " tup_exs)
          in
          Some (tup_str :: rest_exs)
      end else begin
        (* No tuple patterns and no wildcards: entirely missing. *)
        let def = default_mc matrix in
        match find_missing_mc env rest_tys def with
        | None -> None
        | Some rest_exs ->
          let tup_ex =
            Printf.sprintf "(%s)"
              (String.concat ", " (List.map example_of inner_tys))
          in
          Some (tup_ex :: rest_exs)
      end
    | TRecord [] -> None   (* the empty record has one value — always covered *)
    | TRecord field_tys ->
      (* A record is single-shape, so this mirrors the tuple case: specialize
         into one column per field and recurse.  The field list comes from the
         TYPE (every field, sorted), not from any one pattern — patterns name
         open subsets and [spec_rec_mc] fills the gaps with wildcards. *)
      let fields    = List.map fst field_tys in
      let inner_tys = List.map snd field_tys in
      let arity     = List.length fields in
      let any_rec =
        List.exists
          (fun row -> match row with SPRec _ :: _ -> true | _ -> false)
          matrix
      in
      if any_rec then begin
        let sub      = spec_rec_mc fields matrix in
        let full_tys = inner_tys @ rest_tys in
        match find_missing_mc env full_tys sub with
        | None -> None
        | Some exs ->
          let fld_exs, rest_exs = split_at arity exs in
          let rec_str =
            Printf.sprintf "{ %s }"
              (String.concat ", " (List.map2 (fun f e -> f ^ ": " ^ e)
                                     fields fld_exs))
          in
          Some (rec_str :: rest_exs)
      end else begin
        (* No record patterns and no wildcards: entirely missing. *)
        let def = default_mc matrix in
        match find_missing_mc env rest_tys def with
        | None -> None
        | Some rest_exs -> Some (example_of (TRecord field_tys) :: rest_exs)
      end
    | TArrow _ | TChan _ | TLin _ | TNat _ | TNatOp _ ->
      (* Non-enumerable types: treat like infinite domain. *)
      let def = default_mc matrix in
      (match find_missing_mc env rest_tys def with
       | None -> None
       | Some rest_exs -> Some ("_" :: rest_exs))

let span_of_pat : Ast.pattern -> Ast.span = function
  | Ast.PatWild sp          -> sp
  | Ast.PatVar  name        -> name.Ast.span
  | Ast.PatCon  (name, _)   -> name.Ast.span
  | Ast.PatAtom (_, _, sp)  -> sp
  | Ast.PatTuple (_, sp)    -> sp
  | Ast.PatLit  (_, sp)     -> sp
  | Ast.PatRecord (_, sp)   -> sp
  | Ast.PatAs   (_, _, sp)  -> sp
  | Ast.PatOr   (_, sp)     -> sp

(** Check if [row] is useful relative to [matrix] for scrutinee types [tys].
    Returns false iff every value matched by [row] is already covered by [matrix]. *)
let rec is_useful (env : env) (tys : ty list) (matrix : spat list list)
    (row : spat list) : bool =
  match tys, row with
  | [], _ | _, [] -> matrix = []
  | ty :: rest_tys, q :: row_rest ->
    let ty = repr ty in
    (match q with
     | SPWild ->
       (match ty with
        | TCon ("Bool", []) ->
          (* Use Maranget's signature-completeness: only expand if the matrix
             first column covers both literals; otherwise take the default path.
             This prevents infinite loops on recursive types. *)
          let sigma_t = List.exists (fun row ->
            match row with SPLit (Ast.LitBool true) :: _ -> true | _ -> false) matrix in
          let sigma_f = List.exists (fun row ->
            match row with SPLit (Ast.LitBool false) :: _ -> true | _ -> false) matrix in
          if sigma_t && sigma_f then
            let check_lit b =
              let sub_m = spec_lit_mc (Ast.LitBool b) matrix in
              is_useful env rest_tys sub_m row_rest
            in
            check_lit true || check_lit false
          else
            is_useful env rest_tys (default_mc matrix) row_rest
        | TCon (name, parent_args) when ctors_for_type env name <> [] ->
          let ctors = ctors_for_type env name in
          (* sigma = constructors EXPLICITLY listed in the matrix's first column
             (wildcards are NOT counted — this is the termination invariant). *)
          let sigma = List.filter_map (fun row ->
            match row with SPCon (c, _) :: _ -> Some c | _ -> None) matrix in
          let is_complete =
            List.for_all (fun (c, _) -> List.mem c sigma) ctors in
          if is_complete then
            List.exists (fun (ctor_name, arity) ->
              let arg_tys = ctor_arg_tys env ctor_name parent_args in
              let sub_m = spec_ctor_mc ctor_name arity matrix in
              let wild_args = List.init arity (fun _ -> SPWild) in
              is_useful env (arg_tys @ rest_tys) sub_m (wild_args @ row_rest)
            ) ctors
          else
            is_useful env rest_tys (default_mc matrix) row_rest
        | TTuple inner_tys ->
          let arity = List.length inner_tys in
          let sub_m = spec_tup_mc arity matrix in
          let wild_args = List.init arity (fun _ -> SPWild) in
          is_useful env (inner_tys @ rest_tys) sub_m (wild_args @ row_rest)
        | TRecord field_tys when field_tys <> [] ->
          (* Single-shape like a tuple: always expand, never take the default
             path.  A record has no "other constructor" for the default path
             to stand for, so expanding is both safe and strictly sharper. *)
          let fields = List.map fst field_tys in
          let sub_m = spec_rec_mc fields matrix in
          let wild_args = List.map (fun _ -> SPWild) fields in
          is_useful env (List.map snd field_tys @ rest_tys) sub_m
            (wild_args @ row_rest)
        | _ ->
          let def = default_mc matrix in
          is_useful env rest_tys def row_rest)
     | SPCon (name, sub_pats) ->
       let arity = List.length sub_pats in
       let parent_args = match ty with TCon (_, args) -> args | _ -> [] in
       let arg_tys = ctor_arg_tys env name parent_args in
       let sub_m = spec_ctor_mc name arity matrix in
       is_useful env (arg_tys @ rest_tys) sub_m (sub_pats @ row_rest)
     | SPTup sub_pats ->
       let arity = List.length sub_pats in
       let inner_tys = match ty with TTuple ts -> ts | _ -> List.init arity (fun _ -> TError) in
       let sub_m = spec_tup_mc arity matrix in
       is_useful env (inner_tys @ rest_tys) sub_m (sub_pats @ row_rest)
     | SPRec assoc ->
       (* Expand against the TYPE's field list, not this pattern's — the row
          being tested may name a different subset than the matrix rows do,
          and both must land in the same columns. *)
       let field_tys = match ty with
         | TRecord fs -> fs
         | _ -> List.map (fun (n, _) -> (n, TError)) assoc
       in
       let fields = List.map fst field_tys in
       let sub_m  = spec_rec_mc fields matrix in
       let row_args =
         List.map (fun f ->
             match List.assoc_opt f assoc with
             | Some sp -> sp
             | None    -> SPWild) fields
       in
       is_useful env (List.map snd field_tys @ rest_tys) sub_m
         (row_args @ row_rest)
     | SPLit lit ->
       let sub_m = spec_lit_mc lit matrix in
       is_useful env rest_tys sub_m row_rest)

(** Emit Warnings for redundant (unreachable) arms.
    Guarded arms are never flagged, and their patterns are excluded from the
    prefix so that subsequent arms aren't mistakenly flagged as subsumed.
    Arms whose or-expansion exceeded [or_expansion_cap] get the same treatment,
    since those fall back to the widening [norm_pat] and would mis-subsume the
    following arm.

    Record arms used to be excluded here too: [spat] had no record shape, so
    [norm_pat] collapsed them to [SPWild] ("matches everything") and the arm
    after a record arm was reported unreachable on code that plainly runs it.
    [SPRec] removed the cause rather than the symptom — record arms are now
    analysed like any other, so a genuinely unreachable one is finally
    caught. *)
let check_redundant_arms (env : env) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let prefix = ref [] in
  List.iter (fun (br : Ast.branch) ->
    (* An or-pattern contributes one row per alternative (at every depth); the
       arm is redundant only if EVERY alternative is already subsumed by the
       prefix — a single live alternative keeps the whole arm reachable. *)
    let arm_rows = List.map (fun r -> [r]) (norm_pat_rows br.branch_pat) in
    if br.branch_guard = None
       && not (pat_or_expansion_capped br.branch_pat) then begin
      if not (List.exists (fun row -> is_useful env [scrut_ty] !prefix row) arm_rows) then begin
        let pat_sp   = span_of_pat br.branch_pat in
        let body_sp  = span_of_expr br.branch_body in
        let arm_span = { pat_sp with
          March_ast.Ast.end_line = body_sp.March_ast.Ast.end_line;
          March_ast.Ast.end_col  = body_sp.March_ast.Ast.end_col } in
        Err.report env.errors
          { Err.severity = Warning; span = pat_sp;
            message = "This pattern can never be reached.";
            labels  = [];
            notes   = ["An earlier arm already covers all values this pattern matches."];
            code    = Some "redundant_arm";
            fix     = Some (Err.FDelete {
              start_line = arm_span.March_ast.Ast.start_line;
              end_line   = arm_span.March_ast.Ast.end_line }) }
      end;
      prefix := !prefix @ arm_rows
    end
  ) branches

(** Emit a Warning if the match on [scrut_ty] with [branches] is non-exhaustive.

    When any branch carries a [when] guard, exact coverage is undecidable in
    general (we cannot know at typecheck time whether a guard succeeds), so we do
    NOT emit the ordinary Warning. But a guarded match can still DEFINITELY panic:
    a branch whose pattern is only reachable behind a guard cannot be relied on to
    match, so it contributes nothing to GUARANTEED coverage. If the GUARDLESS
    branches alone are non-exhaustive, then when every guard happens to fail at
    runtime no arm matches and the match panics ("no matching clause"). For the
    guarded case we therefore compute exhaustiveness over the guardless branches
    only and, if that sub-match is non-exhaustive, RECORD the span (so
    [check_no_panic_module] can promote it to an error inside a `cap no_panic`
    module) WITHOUT emitting a global Warning — guarded matches are common in
    ordinary code and get no such warning today, so only `cap no_panic` modules
    (which opt into strictness) are made stricter. *)
let check_exhaustiveness (env : env) (span : Ast.span) (scrut_ty : ty)
    (branches : Ast.branch list) =
  let has_guards =
    List.exists (fun (br : Ast.branch) -> br.branch_guard <> None) branches
  in
  if has_guards then begin
    (* Coverage guaranteed by the GUARDLESS branches only (an all-guarded match
       yields an empty matrix, which [find_missing_mc] correctly reports as
       non-exhaustive rather than crashing). If those alone are exhaustive the
       match can never fall through → safe. Otherwise record the span so
       [check_no_panic_module] rejects it; no global Warning here. *)
    let guardless_matrix =
      List.concat_map
        (fun (br : Ast.branch) ->
          match br.branch_guard with
          | None   -> List.map (fun r -> [r]) (norm_pat_rows br.branch_pat)
          | Some _ -> [])
        branches
    in
    match find_missing_mc env [scrut_ty] guardless_matrix with
    | None -> ()
    | Some _ ->
      env.nonexhaustive_match_spans := span :: !(env.nonexhaustive_match_spans)
  end
  else begin
    let matrix =
      List.concat_map
        (fun (br : Ast.branch) ->
          List.map (fun r -> [r]) (norm_pat_rows br.branch_pat))
        branches
    in
    match find_missing_mc env [scrut_ty] matrix with
    | None -> ()
    | Some missing ->
      (* Record the non-exhaustive match's span so [check_no_panic_module] can
         reject it as a runtime panic surface inside a `cap no_panic` module.
         Recording is unconditional (cheap, non-error); attribution/promotion to
         an error is gated there by span containment. *)
      env.nonexhaustive_match_spans := span :: !(env.nonexhaustive_match_spans);
      (match missing with
       | ex :: _ ->
         Err.report env.errors
           { Err.severity = Warning; span;
             message = Printf.sprintf "Non-exhaustive pattern match — missing case: %s" ex;
             labels  = [];
             notes   = [ "Add a branch for this case, or use `_ -> ...` as a catch-all." ];
             code    = None; fix = None }
       | [] ->
         Err.report env.errors
           { Err.severity = Warning; span;
             message = "Non-exhaustive pattern match";
             labels  = [];
             notes   = [ "Add a catch-all branch `_ -> ...` to handle any remaining cases." ];
             code    = None; fix = None })
  end

(** Unfold one step of a recursive session type.
    [SRec(x, body)] becomes [body] with every [SVar x] replaced by [SRec(x, body)].
    Keeps unfolding until the outermost constructor is no longer [SRec],
    so callers can pattern-match directly on [SSend] / [SRecv] / etc. *)
let rec unfold_srec s =
  match s with
  | SRec (x, body) ->
    let rec subst_inner s =
      match s with
      | SVar y when y = x          -> SRec (x, body)
      | SSend (t, s')              -> SSend (t, subst_inner s')
      | SRecv (t, s')              -> SRecv (t, subst_inner s')
      | SChoose bs                 -> SChoose (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SOffer  bs                 -> SOffer  (List.map (fun (l, s') -> (l, subst_inner s')) bs)
      | SMSend (r, t, s')          -> SMSend (r, t, subst_inner s')
      | SMRecv (r, t, s')          -> SMRecv (r, t, subst_inner s')
      | SRec (y, s') when y <> x  -> SRec (y, subst_inner s')
      | other                      -> other
    in
    unfold_srec (subst_inner body)
  | _ -> s

(** Reject a [Chan.*] operation on a channel whose session ref came from an
    [offer] with differing branch continuations and has not been refined by a
    `match` on the paired label (F5 residual). *)
let offer_unrefined_error env span (r : session_ty ref) op =
  if offer_ref_unrefined env r then begin
    Err.error env.errors ~span
      (offer_unrefined_message (Printf.sprintf "%s: this channel" op));
    true
  end else false

(** Type constructor names that cannot appear in actor message payloads.
    These types carry mutable state that must remain owned by a single actor.
    NativeIntArr/NativeFloatArr/NativeF32Arr/NativeI32Arr/NativeU8Arr are
    NativeArray's real backing types -- the NativeArray stdlib module
    (stdlib/native_array.march) is a function namespace over these opaque
    0-arity constructors, not a type of its own, so "NativeArray" itself
    would be a silent no-op entry here (see where
    native_int_arr_make/native_float_arr_make are registered, this
    file, around the NativeArray builtins section). *)
let non_sendable_types =
  ["RingBuf"; "NativeIntArr"; "NativeFloatArr";
   "NativeF32Arr"; "NativeI32Arr"; "NativeU8Arr"]

(** [check_sendable errors span ty] walks [ty] and emits an error for every
    non-sendable type constructor it finds. Called from the [ECon] arm on
    an actor message constructor's instantiated argument types (guarded by
    [ci_is_actor_msg]) -- at message-CONSTRUCTION time, not at each place a
    message value is later sent. *)
let rec check_sendable errors span ty =
  match repr ty with
  | TCon (name, args) ->
    if List.mem name non_sendable_types then
      Err.error errors ~span
        (Printf.sprintf
           "Values of type `%s` cannot be sent in actor messages.\n\
            `%s` is a mutable buffer that must be owned by a single actor.\n\
            Pass it as initial actor state at spawn time instead of sending it."
           name name)
    else List.iter (check_sendable errors span) args
  | TArrow (a, b)     -> check_sendable errors span a; check_sendable errors span b
  | TTuple ts         -> List.iter (check_sendable errors span) ts
  | TRecord flds      -> List.iter (fun (_, t) -> check_sendable errors span t) flds
  | TLin (_, t)       -> check_sendable errors span t
  | TNatOp (_, a, b)  -> check_sendable errors span a; check_sendable errors span b
  | TRefine (base, _, _) -> check_sendable errors span base
  | TVar _ | TChan _ | TNat _ | TError -> ()
