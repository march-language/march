(** Type-directed suggestions (diagnostics-depth plan X8, tier 2).

    When spelling finds nothing for an unknown function, search the names in
    scope for ones whose type fits the call ([search_by_call]); when a call's
    arguments fail to check, try them in another order ([permutation]); when
    a value of type [S] is given where [T] is needed, look for a conversion
    [S -> T] ([conversions]).

    {2 Trial unification that leaves no trace}

    Every fit test here is a real unification, run against a PRIVATE
    substitution ([trial]) instead of the live union-find:

    - A live type is only ever read.  [walk] follows [Link]s without the path
      compression [repr] does, so not even an equivalent rewrite of a live
      [tvar] happens.
    - Binding a variable (a candidate's quantified variable, or an
      unresolved variable in an argument's type) records it in the trial's
      hashtable; the live [tvar ref] is never written.
    - A trial mints no fresh variable ([fresh_id] is not called), so the
      ids, and therefore the display names, of everything inferred later
      are what they would have been without the search.  The placeholder
      variables a lambda argument needs get NEGATIVE ids, which the live
      counter never produces.
    - [try_unify] undoes the bindings of a failed attempt (a trail, as in
      union-find with undo), so one argument position failing leaves the
      bindings the others made intact, and a later position is scored
      against exactly those.

    None of this is reachable outside an error path: a suggestion is only
    computed after a diagnostic has been reported, so inference on an
    accepted program is unchanged by construction. *)

open Typecheck_types
open Typecheck_env

(* ── Trial unification ─────────────────────────────────────────────── *)

type trial = {
  subst : (int, ty) Hashtbl.t;
  mutable trail : int list;  (** ids bound in this trial, newest first *)
}

let new_trial () = { subst = Hashtbl.create 8; trail = [] }

(** Follow live links and refinements without writing anything. *)
let rec walk (t : ty) : ty =
  match t with
  | TVar { contents = Link t' } -> walk t'
  | TRefine (b, _, _) -> walk b
  | TLin (Ast.Unrestricted, b) -> walk b
  | t -> t

(** [walk], then through the trial's own bindings. *)
let rec resolve (tr : trial) (t : ty) : ty =
  match walk t with
  | TVar { contents = Unbound (id, _) } as v ->
    (match Hashtbl.find_opt tr.subst id with
     | Some t' -> resolve tr t'
     | None -> v)
  | t -> t

let rec occurs (tr : trial) (id : int) (t : ty) : bool =
  match resolve tr t with
  | TVar { contents = Unbound (id', _) } -> id = id'
  | TCon (_, ts) | TTuple ts -> List.exists (occurs tr id) ts
  | TArrow (a, b) -> occurs tr id a || occurs tr id b
  | TRecord fs -> List.exists (fun (_, t) -> occurs tr id t) fs
  | TLin (_, t) -> occurs tr id t
  | _ -> false

let bind (tr : trial) (id : int) (t : ty) =
  Hashtbl.replace tr.subst id t;
  tr.trail <- id :: tr.trail

let rec unify (tr : trial) (a : ty) (b : ty) : bool =
  match resolve tr a, resolve tr b with
  | TError, _ | _, TError -> true
  | TVar { contents = Unbound (x, _) }, TVar { contents = Unbound (y, _) } when x = y -> true
  | TVar { contents = Unbound (x, _) }, t | t, TVar { contents = Unbound (x, _) } ->
    if occurs tr x t then false else (bind tr x t; true)
  | TLin (_, x), y | y, TLin (_, x) -> unify tr x y
  | TCon (na, aa), TCon (nb, ab) ->
    na = nb && List.length aa = List.length ab && List.for_all2 (unify tr) aa ab
  | TArrow (a1, r1), TArrow (a2, r2) -> unify tr a1 a2 && unify tr r1 r2
  | TTuple aa, TTuple ab ->
    List.length aa = List.length ab && List.for_all2 (unify tr) aa ab
  | TRecord fa, TRecord fb ->
    List.length fa = List.length fb
    && List.for_all2 (fun (na, ta) (nb, tb) -> na = nb && unify tr ta tb) fa fb
  | TNat x, TNat y -> x = y
  | TChan _, TChan _ -> true
  | _ -> false

(** Unify [a] with [b] in [tr]; on failure, undo every binding the attempt
    made, so the trial is exactly as it was before. *)
let try_unify (tr : trial) (a : ty) (b : ty) : bool =
  let mark = tr.trail in
  if unify tr a b then true
  else begin
    let rec undo l = if l != mark then match l with
        | id :: rest -> Hashtbl.remove tr.subst id; undo rest
        | [] -> () in
    undo tr.trail;
    tr.trail <- mark;
    false
  end

(* ── Shapes ────────────────────────────────────────────────────────── *)

(** Split [t] into [n] parameter types and the result, or [None] when it is
    not an [n]-argument function. *)
let rec split_params (n : int) (t : ty) : (ty list * ty) option =
  if n = 0 then Some ([], t)
  else match walk t with
    | TArrow (p, r) ->
      Option.map (fun (ps, res) -> (p :: ps, res)) (split_params (n - 1) r)
    | _ -> None

let rec count_arrows t = match walk t with TArrow (_, r) -> 1 + count_arrows r | _ -> 0

(** Does [t] say anything (a known head), or is it an unresolved variable? *)
let informative (t : ty) : bool =
  match walk t with TVar _ | TError -> false | _ -> true

(** Placeholder variables for a trial: negative ids, never minted by the
    live counter, so they collide with nothing and name nothing. *)
let placeholder =
  let n = ref 0 in
  fun () -> decr n; TVar (ref (Unbound (!n, max_int)))

(* ── Printing a candidate's signature ──────────────────────────────── *)

(** [pp_ty] names each variable through a global table, so printing a
    candidate with it would shift the names later diagnostics use.  This
    printer names variables locally, in order of appearance. *)
let pp_local () =
  let names = Hashtbl.create 4 in
  let name id =
    match Hashtbl.find_opt names id with
    | Some s -> s
    | None ->
      let i = Hashtbl.length names in
      let s = String.make 1 (Char.chr (Char.code 'a' + i mod 26))
              ^ (if i < 26 then "" else string_of_int (i / 26)) in
      Hashtbl.add names id s; s in
  let rec pp ?(parens = false) t =
    match walk t with
    | TError -> "?"
    | TVar { contents = Unbound (id, _) } -> name id
    | TVar { contents = Link t } -> pp ~parens t
    | TCon (n, []) -> n
    | TCon (n, args) -> Printf.sprintf "%s(%s)" n (String.concat ", " (List.map pp args))
    | TArrow (a, b) ->
      let s = Printf.sprintf "%s -> %s" (pp ~parens:true a) (pp b) in
      if parens then "(" ^ s ^ ")" else s
    | TTuple [] -> "()"
    | TTuple ts -> "(" ^ String.concat ", " (List.map pp ts) ^ ")"
    | TRecord [] -> "{}"
    | TRecord fs ->
      "{ " ^ String.concat ", " (List.map (fun (f, t) -> f ^ " : " ^ pp t) fs) ^ " }"
    | TLin (Ast.Linear, t) -> "linear " ^ pp ~parens:true t
    | TLin (Ast.Affine, t) -> "affine " ^ pp ~parens:true t
    | TLin (Ast.Unrestricted, t) -> pp ~parens t
    | TNat n -> string_of_int n
    | TNatOp _ | TChan _ | TRefine _ -> "_"
  in
  pp ~parens:false

(** `Q.f(P1, P2) : R` *)
let pp_call_sig (name : string) (params : ty list) (res : ty) : string =
  let pp = pp_local () in
  let ps = List.map pp params in
  Printf.sprintf "%s(%s) : %s" name (String.concat ", " ps) (pp res)

(* ── Candidates in scope ───────────────────────────────────────────── *)

(** At most this many names are scanned per search, and this many shown. *)
let max_scanned = 4000
let max_shown = 3

let is_ident (k : string) =
  k <> "" && (match k.[0] with 'a'..'z' | '_' -> true | _ -> false)

(** The arity a candidate is declared with, else the arrows of its type. *)
let arity_of (env : env) (key : string) (body : ty) : int =
  match StrMap.find_opt key env.fn_arities with
  | Some (n, _) -> n
  | None ->
    match StrMap.find_opt key env.qual_fn_arities with
    | Some (n, _) -> n
    | None -> count_arrows body

(** Functions in scope for a search: [Q]'s members ([Q.m] keys, [m] bare)
    for a qualified name, otherwise the unqualified identifiers. *)
let scope_candidates (env : env) (qual : string option) : (string * string * ty) list =
  let prefix = match qual with Some q -> Some (q ^ ".") | None -> None in
  let n = ref 0 in
  StrMap.fold (fun k sch acc ->
      if !n >= max_scanned then acc
      else
        let member = match prefix with
          | Some p when String.starts_with ~prefix:p k ->
            let m = String.sub k (String.length p) (String.length k - String.length p) in
            if String.contains m '.' then None else Some m
          | Some _ -> None
          | None -> if String.contains k '.' then None else Some k in
        match member with
        | Some m when is_ident m && not (is_generated_name m) ->
          incr n; (k, m, scheme_body sch) :: acc
        | _ -> acc) env.vars []
  |> List.rev

(* ── Tier 2a: search by call shape ─────────────────────────────────── *)

type fit = {
  f_key : string;          (** the name as written to call it *)
  f_params : ty list;
  f_result : ty;
  f_misses : int list;     (** 1-based argument positions that do not fit *)
  f_evidence : int;        (** positions where known types met and fit *)
  f_locality : int;
}

(** Score candidate [body] against the call: the argument positions whose
    type does not unify (each tried in order, in one trial, so a variable
    bound by an earlier argument constrains the later ones), and whether the
    result fits [ret]. *)
let score_call (body : ty) (arg_tys : ty list) (ret : ty option)
  : (int list * int * bool * ty list * ty) option =
  match split_params (List.length arg_tys) body with
  | None -> None
  | Some (params, res) ->
    let tr = new_trial () in
    let pairs = List.combine params arg_tys in
    let results = List.map (fun (p, a) -> try_unify tr p a) pairs in
    let misses = List.concat (List.mapi (fun i ok -> if ok then [] else [ i + 1 ]) results) in
    (* Evidence: positions where an argument of known type met a parameter
       of known type.  A parameter that is a bare type variable takes
       anything and says nothing for the candidate. *)
    let evidence = List.fold_left2 (fun n (p, a) ok ->
        if ok && informative p && informative a then n + 1 else n) 0 pairs results in
    let ret_ok, evidence = match ret with
      | Some r when informative r ->
        let ok = try_unify tr res r in
        ok, (if ok && informative res then evidence + 1 else evidence)
      | _ -> true, evidence in
    Some (misses, evidence, ret_ok, params, res)

(** Edit distance from [a] to the closest prefix of [b]: how far the typo
    is from the start of a candidate name (`fodl` is 2 from `fold_left`). *)
let prefix_distance (a : string) (b : string) : int =
  let n = String.length a and m = String.length b in
  let prev = Array.init (m + 1) (fun _ -> 0) in
  (* Row 0: the empty typo is 0 from the empty prefix, j from prefix j. *)
  for j = 0 to m do prev.(j) <- j done;
  let cur = Array.make (m + 1) 0 in
  for i = 1 to n do
    cur.(0) <- i;
    for j = 1 to m do
      let cost = if a.[i - 1] = b.[j - 1] then 0 else 1 in
      cur.(j) <- min (min (prev.(j) + 1) (cur.(j - 1) + 1)) (prev.(j - 1) + cost)
    done;
    Array.blit cur 0 prev 0 (m + 1)
  done;
  Array.fold_left min max_int prev

(** The functions in scope whose type fits a call of [qual.name] with
    arguments of types [arg_tys] (and result [ret], when known): every
    argument fits, or (with three or more arguments) all but one.  Only the
    best tier is returned, and only when it is small enough to be an
    answer (at most [max_shown]); ordered by locality, then name. *)
let search_by_call (env : env) ~(qual : string option) ~(name : string)
    ~(arg_tys : ty list) ~(ret : ty option) : fit list =
  let n_args = List.length arg_tys in
  if n_args = 0 || not (List.exists informative arg_tys) then []
  else
    let locality = match qual with
      | Some q -> module_locality env q
      | None -> 1 in
    let fits = List.filter_map (fun (key, member, body) ->
        if member = name || arity_of env key body <> n_args then None
        else match score_call body arg_tys ret with
          | Some (misses, evidence, true, params, res)
            when evidence > 0
              && (misses = [] || (n_args >= 3 && List.length misses = 1)) ->
            let shown = match qual with Some q -> q ^ "." ^ member | None -> member in
            Some { f_key = shown; f_params = params; f_result = res;
                   f_misses = misses; f_evidence = evidence; f_locality = locality }
          | _ -> None) (scope_candidates env qual) in
    let score f = (List.length f.f_misses, - f.f_evidence) in
    let best = List.fold_left (fun b f -> min b (score f)) (max_int, 0) fits in
    let tier = List.filter (fun f -> score f = best) fits in
    (* Within the tier, the names the typo is a spelling of a prefix of
       (`fodl` and `fold_left`) are the answer when they are few enough. *)
    let name_lo = String.lowercase_ascii name in
    let member_of f = match String.rindex_opt f.f_key '.' with
      | Some i -> String.sub f.f_key (i + 1) (String.length f.f_key - i - 1)
      | None -> f.f_key in
    let closeness f = prefix_distance name_lo (String.lowercase_ascii (member_of f)) in
    let window = spelling_max_dist (String.length name) in
    let close = List.filter (fun f -> closeness f <= window) tier in
    let order l = List.stable_sort (fun a b ->
        compare (closeness a, a.f_locality, a.f_key) (closeness b, b.f_locality, b.f_key)) l in
    if close <> [] && List.length close <= max_shown then order close
    else if tier <> [] && List.length tier <= max_shown then order tier
    else []

(** The note listing [fits], or [None]. *)
let call_fits_note ~(qual : string option) (fits : fit list) : string option =
  match fits with
  | [] -> None
  | _ ->
    let whose = match qual with
      | Some q -> Printf.sprintf "These `%s` functions take" q
      | None -> "These functions in scope take" in
    let all_fit = List.for_all (fun f -> f.f_misses = []) fits in
    let head = if all_fit then whose ^ " these arguments:"
      else whose ^ " arguments like these:" in
    let line f =
      let sg = pp_call_sig f.f_key f.f_params f.f_result in
      match f.f_misses with
      | [] -> "    " ^ sg
      | [ i ] -> Printf.sprintf "    %s  (argument #%d differs)" sg i
      | _ -> "    " ^ sg in
    Some (String.concat "\n" (head :: List.map line fits))

(* ── Tier 2b: argument permutations ────────────────────────────────── *)

(** A read-only type for an argument expression, without inferring it: a
    literal's type, a variable's (its scheme's body), a lambda's arity as an
    arrow of placeholders, a list of such.  [None] when the shape is not
    evident from the syntax. *)
let rec arg_shape (env : env) (e : Ast.expr) : ty option =
  match e with
  | Ast.ELit (Ast.LitInt _, _) -> Some (TCon ("Int", []))
  | Ast.ELit (Ast.LitFloat _, _) -> Some (TCon ("Float", []))
  | Ast.ELit (Ast.LitString _, _) -> Some (TCon ("String", []))
  | Ast.ELit (Ast.LitBool _, _) -> Some (TCon ("Bool", []))
  | Ast.EVar n ->
    (match StrMap.find_opt n.txt env.vars with
     | Some sch when informative (scheme_body sch) -> Some (scheme_body sch)
     | _ -> None)
  | Ast.ELam (ps, _, _) ->
    let k = max 1 (List.length ps) in
    let rec arrows i = if i = 0 then placeholder () else TArrow (placeholder (), arrows (i - 1)) in
    Some (arrows k)
  | Ast.EAnnot (e, _, _) -> arg_shape env e
  | _ -> None

let rec permutations = function
  | [] -> [ [] ]
  | l -> List.concat_map (fun x ->
      List.map (fun p -> x :: p) (permutations (List.filter (fun y -> y != x) l))) l

(** [Some order] when the callee [body] rejects the arguments as written but
    takes them in exactly one other order ([order] lists the original
    0-based positions in the order they should be passed).  Two or three
    arguments, each with an evident shape. *)
let permutation (env : env) (body : ty) (args : Ast.expr list) : int list option =
  let n = List.length args in
  if n < 2 || n > 3 then None
  else
    let shapes = List.map (arg_shape env) args in
    if List.exists Option.is_none shapes then None
    else
      let shapes = Array.of_list (List.map Option.get shapes) in
      let fits order =
        match split_params n body with
        | None -> false
        | Some (params, _) ->
          let tr = new_trial () in
          List.for_all2 (fun p i -> try_unify tr p shapes.(i)) params order in
      let ident = List.init n Fun.id in
      if fits ident then None
      else
        match List.filter (fun o -> o <> ident && fits o) (permutations ident) with
        | [ o ] -> Some o
        | _ -> None

(* ── Tier 2c: conversions ──────────────────────────────────────────── *)

(** In-scope functions taking [provided] to [required], both plain types
    with no parameters (`Int`, `String`, `Bool`, a user's `Celsius`): a
    parameterised target is not a conversion one should reach for (`Int ->
    Pid(a)` exists, and forges a pid).  Candidates are the members of each
    side's own module whose name says the other type ([String.from_int]),
    and unqualified functions whose name says both (`bool_to_string`).  The
    name is the evidence that a function converts: by type alone `String ->
    Int` is also [String.byte_size], and the prelude is full of runtime
    internals of every shape.  The parameter must name [provided] itself (a
    generic [a -> String] says nothing about whether [provided] has an
    instance), and the result exactly [required]: a parse returning
    [Option(Int)] does not fit where an [Int] is needed.  At most
    [max_shown], nearest module first, then name. *)
let conversions (env : env) (provided : ty) (required : ty) : string list =
  match walk provided, walk required with
  | TCon (s, []), TCon (t, []) when s <> t ->
    let s_lo = String.lowercase_ascii s and t_lo = String.lowercase_ascii t in
    (* A whole `_`-separated word: `to_int` names Int, `codepoint_count`
       does not. *)
    let says name word = List.mem word (String.split_on_char '_' name) in
    let seen = Hashtbl.create 8 in
    let cands = List.concat_map (fun qual ->
        List.filter_map (fun (key, member, body) ->
            let named = match qual with
              | None -> says member s_lo && says member t_lo
              | Some q when q = s -> says member t_lo
              | Some _ -> says member s_lo in
            if not named || Hashtbl.mem seen key || arity_of env key body <> 1 then None
            else
              match split_params 1 body with
              | Some ([ p ], r) ->
                (match walk p, walk r with
                 | TCon (ps, []), TCon (rs, []) when ps = s && rs = t ->
                   Hashtbl.add seen key ();
                   let shown = match qual with Some q -> q ^ "." ^ member | None -> member in
                   let loc = match qual with Some q -> module_locality env q | None -> 1 in
                   Some (loc, shown)
                 | _ -> None)
              | _ -> None) (scope_candidates env qual)) [ None; Some s; Some t ] in
    List.sort compare cands
    |> List.filteri (fun i _ -> i < max_shown)
    |> List.map snd
  | _ -> []

(** The conversion note for a mismatch, or [None]. *)
let conversion_note (env : env) (provided : ty) (required : ty) : string option =
  let a_ty t =
    let n = pp_local () t in
    let an = n <> "" && String.contains "AEIOU" n.[0] in
    Printf.sprintf "%s `%s`" (if an then "an" else "a") n in
  match conversions env provided required with
  | [] -> None
  | [ f ] -> Some (Printf.sprintf "Use `%s(x)` to convert %s to %s." f (a_ty provided) (a_ty required))
  | fs ->
    Some (Printf.sprintf "These convert %s to %s: %s." (a_ty provided) (a_ty required)
            (String.concat ", " (List.map (Printf.sprintf "`%s(x)`") fs)))

(* ── Source text, for a fix ────────────────────────────────────────── *)

let source_cache : (string, string option) Hashtbl.t = Hashtbl.create 4

let source_of (file : string) =
  match Hashtbl.find_opt source_cache file with
  | Some s -> s
  | None ->
    let s = try Some (In_channel.with_open_bin file In_channel.input_all) with Sys_error _ -> None in
    Hashtbl.replace source_cache file s;
    s

let offset_of (src : string) (line : int) (col : int) : int option =
  let rec go i l =
    if l <= 1 then Some (i + col)
    else match String.index_from_opt src i '\n' with Some j -> go (j + 1) (l - 1) | None -> None in
  match go 0 line with Some o when o >= 0 && o <= String.length src -> Some o | _ -> None

(** The source text [sp] covers, or [None] when its file cannot be read. *)
let text_of (sp : Ast.span) : string option =
  match source_of sp.Ast.file with
  | None -> None
  | Some src ->
    (match offset_of src sp.Ast.start_line sp.Ast.start_col,
           offset_of src sp.Ast.end_line sp.Ast.end_col with
     | Some a, Some b when b >= a -> Some (String.sub src a (b - a))
     | _ -> None)
