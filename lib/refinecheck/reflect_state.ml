(** Refinement reflection, phase 1a (specs/2026-10-29-refinement-reflection-design.md
    §3, §4.4): the state the encoder reads.

    This module sits BELOW the encoder ([Refine_encode], [Refine_scope]) so the
    predicate translator and [resolve_sorts] can consult it, and below
    [Refine_reflect], which fills it once per module ([Refine_check.check_module])
    from the §2.1 fixpoint.  It holds no logic beyond lookups: the body
    translator and the unfolding generator live in [Refine_reflect] and reach
    the encoder through [unfold_hook].

    {1 The two stages (§4.4)}

    [arm_on] is false during stage 1, which is today's query byte for byte: the
    predicate translator's reflected-call arm only NOTES that it met a reflected
    function ([frontier_seen]) and fails as it always did.  Stage 2 re-runs the
    same obligation with [arm_on] set: the arm translates the call to the logic
    symbol, and [resolve_sorts] calls [unfold_hook] to add the guarded
    equations.  [Reflect_stage.two_stage] decides which stage's verdicts stand. *)

module Smt = March_refine.Smt

(** One reflected function's logic symbol (§3.1) and polymorphic signature:
    type variables are [Smt.SParam i], [0 <= i < fs_nvars]. *)
type fsig = {
  fs_sym : string;  (** the quoted base symbol, [|r:<origin>:<path>.<name>|] *)
  fs_name : string;  (** display name, [List.append] / [f/go] *)
  fs_params : Smt.sort list;
  fs_ret : Smt.sort;
  fs_nvars : int;
}

(** Reflection is on for the module being checked. *)
let active = ref false

(** Stage 2 is running: the reflected-call arm translates, and
    [resolve_sorts] unfolds. *)
let arm_on = ref false

(** Stage 1 met a call of a reflected function that stage 2 could translate:
    a stage-2 run is worth trying. *)
let frontier_seen = ref false

(** The witness interpreter confirmed a stage-1 violation (I7). *)
let confirmed = ref false

(** By base symbol. *)
let syms : (string, fsig) Hashtbl.t = Hashtbl.create 64

(** Call SITE -> the reflected base symbol it denotes (phase 1a review,
    C-1/C-2).  Keyed by the span of the application node: a call in program
    code is resolved by the termination graph's lexical walk (locals,
    parameters and lambda binders shadow; nested modules resolve innermost
    first; a name that two declarations, or an [alias]/[use] and a module,
    could supply is UNRESOLVED: [Refine_term.graph.ambiguous], and a function
    whose BODY calls such a name is not reflected at all, R6), and a call
    inside a signature's
    refinement predicate is resolved by the same walk in the scope where the
    predicate is written ([Refine_term.graph.pred_sites]).  A site that is not
    here (a local value, a parameter, an unresolved name, a predicate the walk
    never saw) is never unfolded: skip, never guess.  The ONE resolution rule
    of every channel: predicates, path conditions, `let` facts, subjects. *)
let call_sym : (March_ast.Ast.span, string) Hashtbl.t = Hashtbl.create 256

let resolve_site (sp : March_ast.Ast.span) : string option = Hashtbl.find_opt call_sym sp

(** Instance symbol -> (argument sorts, result sort), filled by
    [resolve_sorts] when it renames a base symbol to an instance; read by the
    declaration preamble. *)
let instances : (string, Smt.sort list * Smt.sort) Hashtbl.t = Hashtbl.create 64

(** The opaque program-equality symbol of §3.5 ([eq$T]): one per sort
    instance, Bool-valued, uninterpreted.  Registered like a reflected symbol
    with signature [(T0, T0) -> Bool]. *)
let eq_sym = "|r:eq|"

(** Per stage-2 run: the unfolding budget was hit (§3.9), a depth-1 call was
    left unfolded, and the assumption literals naming each unfolding with the
    display name of the function it defines (the [uses:] note, §2.4). *)
let budget_hit = ref false

let fuel_pending = ref false

let literal_owner : (string, string) Hashtbl.t = Hashtbl.create 32

(** Debug counters ([MARCH_REFLECT_DEBUG=1] prints them, bin/main.ml). *)
let stage2_runs = ref 0

let stage2_queries = ref 0

let stage2_neg_hits = ref 0

(** Filled by [Refine_reflect]: the stage-2 augmentation of a query, given
    its declarations, goal and assumptions BEFORE sort resolution. *)
let unfold_hook :
    ((string * Smt.sort) list -> Smt.term -> Smt.term list -> (string * Smt.sort) list * Smt.term list) ref =
  ref (fun d _ a -> (d, a))

(** Instance symbol -> its base symbol ([|r:x@Int|] -> [|r:x|]), filled
    with [instances]. *)
let instance_base : (string, string) Hashtbl.t = Hashtbl.create 64

(** The D17 hash of each reflected function (§7.1, I8), by base symbol: BLAKE3
    over its source text, its R-status and definition, and the [==] reading
    of every type its body compares at.  Filled by [Refine_reflect.install]. *)
let logic_hash : (string, string) Hashtbl.t = Hashtbl.create 64

(** The same, by display name ([inc], [List.length], [Inner.dbl]) and source
    file, for [--dump-impl-hashes] (whose rows are TIR names) and the LSP
    dependency key.  Two functions of one display name ([f/go] twice) keep
    both, sorted. *)
let logic_by_name : (string, (string * string) list) Hashtbl.t = Hashtbl.create 64

(** The display name and declaring file of each reflected base symbol. *)
let sym_origin : (string, string * string) Hashtbl.t = Hashtbl.create 64

(** Every reflected function in the frontier of ANY stage-2 query the
    current check ran (§7.2, I8): the frontier, not the unsat core, so a
    definition a cold run needed and a warm run did not still keys the
    dependents.  Base symbol -> unit; read by [--reflect-deps]. *)
let check_frontier : (string, unit) Hashtbl.t = Hashtbl.create 64

(** The CONTRACT hash of every function of the program (review round 1 of
    phase 1b): BLAKE3 over its attributes, its head's source text (from its
    name to the start of its last clause's body: parameter and return
    refinements included, position-free) and whether it is reflected.  A
    caller's proof relies on a callee's contract and reflectability even
    when no body of the callee is in any frontier, so the LSP keys a file on
    the contract of every cross-file function it calls ([contract_edges])
    as well as on its frontier.  (file, display name, hash), by unit id of
    the termination graph. *)
let contract_defs : (string * string * string) array Lazy.t ref = ref (lazy [||])

(** The call and reference edges of the termination graph, (source unit,
    destination unit): a callee's reflectability rests on its own callees,
    so a caller's key covers every function it reaches. *)
let contract_edges : (int * int) list Lazy.t ref = ref (lazy [])

(** The units reachable from any unit declared in [file] (itself excluded:
    the file's own functions are its definitions, not its dependencies). *)
let contract_reach (file : string) : (string * string * string) list =
  let defs = Lazy.force !contract_defs in
  let n = Array.length defs in
  let succ = Array.make n [] in
  List.iter (fun (a, b) -> if a < n && b < n then succ.(a) <- b :: succ.(a)) (Lazy.force !contract_edges);
  let seen = Array.make n false in
  let rec go v = if not seen.(v) then begin seen.(v) <- true; List.iter go succ.(v) end in
  Array.iteri (fun i (f, _, _) -> if f = file then go i) defs;
  List.filter_map (fun i -> let (f, _, _) as d = defs.(i) in if seen.(i) && f <> file then Some d else None)
    (List.init n Fun.id)

(** The base symbol of a reflected application's head (base or instance). *)
let base_of (f : string) : string option =
  if Hashtbl.mem logic_hash f then Some f
  else match Hashtbl.find_opt instance_base f with Some b -> Some b | None -> None

(** The D17 comment lines of a stage-2 query (§7.1): one per reflected
    definition in its frontier, read off the unfolding facts
    ([lit => equations], the left-hand side of each equation naming the
    function), sorted.  [""] for a query with no unfolding, so no other
    query's text moves. *)
let d17_lines (assumptions : Smt.term list) : string =
  let acc = ref [] in
  let rec lhs (t : Smt.term) =
    match t with
    | Smt.And (a, b) -> lhs a; lhs b
    | Smt.Implies (_, e) -> lhs e
    | Smt.Eq (Smt.App (f, _), _) -> (
      match base_of f with
      | Some b when not (List.mem b !acc) -> acc := b :: !acc
      | _ -> ())
    | _ -> ()
  in
  List.iter
    (function
      | Smt.Implies (Smt.Const lit, body) when String.length lit > 5 && String.sub lit 0 5 = "|$ru_" -> lhs body
      | _ -> ())
    assumptions;
  String.concat ""
    (List.map
       (fun b -> Printf.sprintf "; reflect %s blake3=%s\n" b (Option.value ~default:"-" (Hashtbl.find_opt logic_hash b)))
       (List.sort compare !acc))

(** The logic hash a post-TIR function named [tir_name] carries in
    [--dump-impl-hashes] (§7.2, I9): its reflected function's D17 hash, or
    [None] ([-]) for an unreflected one.  The entry module's functions are
    unprefixed in TIR exactly as their display names are; a specialisation
    of a polymorphic reflected function ([f$Int]) carries [f]'s hash.  Two
    functions of one display name give the hash of both (the conservative
    side: either body's edit changes it). *)
let logic_hash_of_name (tir_name : string) : string option =
  let of_entries = function
    | [] -> None
    | [ (_, h) ] -> Some h
    | es -> Some (March_cas.Blake3.hash_string (String.concat "\000" (List.map snd es)))
  in
  match Hashtbl.find_opt logic_by_name tir_name with
  | Some es -> of_entries es
  | None -> (
    match String.index_opt tir_name '$' with
    | Some i when i > 0 -> (
      let base = String.sub tir_name 0 i in
      let poly =
        Hashtbl.fold
          (fun sym (n, _) acc -> acc || (n = base && match Hashtbl.find_opt syms sym with Some fs -> fs.fs_nvars > 0 | None -> false))
          sym_origin false
      in
      if poly then of_entries (Option.value ~default:[] (Hashtbl.find_opt logic_by_name base)) else None)
    | _ -> None)

let reset () =
  active := false;
  Hashtbl.reset instance_base;
  Hashtbl.reset logic_hash;
  Hashtbl.reset logic_by_name;
  Hashtbl.reset sym_origin;
  Hashtbl.reset check_frontier;
  contract_defs := lazy [||];
  contract_edges := lazy [];
  arm_on := false;
  frontier_seen := false;
  confirmed := false;
  Hashtbl.reset syms;
  Hashtbl.reset call_sym;
  Hashtbl.reset instances;
  Hashtbl.reset literal_owner;
  ()

let is_sym (f : string) = Hashtbl.mem syms f || f = eq_sym

(** The instance symbol of base [base] at [tag]: [|r:x|] -> [|r:x@tag|]. *)
let instance_name (base : string) (tag : string) : string =
  let n = String.length base in
  if n >= 2 && base.[n - 1] = '|' then String.sub base 0 (n - 1) ^ "@" ^ tag ^ "|" else base ^ "@" ^ tag

let is_instance (f : string) = Hashtbl.mem instances f

(** The signature of a base symbol, [eq_sym] included. *)
let sig_of (f : string) : fsig option =
  if f = eq_sym then
    Some { fs_sym = eq_sym; fs_name = "=="; fs_params = [ Smt.SParam 0; Smt.SParam 0 ]; fs_ret = Smt.SBool; fs_nvars = 1 }
  else Hashtbl.find_opt syms f

(** A Bool-valued logic application (base or instance): a formula. *)
let returns_bool (f : string) : bool =
  match sig_of f with
  | Some s -> s.fs_ret = Smt.SBool
  | None -> ( match Hashtbl.find_opt instances f with Some (_, r) -> r = Smt.SBool | None -> false)

(** The prefix of a stage-2 assumption literal: [|$ru_<k>:<function>|]. *)
let literal_prefix = "$ru_"

(** The function of the first call left unfolded in this stage-2 run. *)
let fuel_fn = ref ""

(** Register a reflected function's symbol. *)
let register (fs : fsig) : unit = Hashtbl.replace syms fs.fs_sym fs

(** The function a stage-2 literal (as z3 prints it, unquoted) names. *)
let literal_function (lit : string) : string option =
  if String.starts_with ~prefix:literal_prefix lit then
    match String.index_opt lit ':' with
    | Some i -> Some (String.sub lit (i + 1) (String.length lit - i - 1))
    | None -> None
  else None

(** Why a function that exists is not reflected, by display name (its first
    blocker, §2.4): the text of the predicate warning. *)
let blocked_by_name : (string, string * March_ast.Ast.span) Hashtbl.t = Hashtbl.create 64

(** At the call site [sp], in a position stage 2 translates: does it denote a
    reflected function AND is this stage 2?  In stage 1 such a site only
    records that stage 2 has a frontier. *)
let stage2_call_at (sp : March_ast.Ast.span) : bool =
  !active
  && resolve_site sp <> None
  &&
  if !arm_on then true
  else begin
    frontier_seen := true;
    false
  end

(** Is the `negate` applied at [sp] the builtin (phase 1a review C-3)?  A
    literal `-2` is `negate(2)`, which a user `fn negate` captures.  Set per
    module from the termination graph's resolution of that site; the default
    (no module set up) is the builtin. *)
let negate_builtin_at : (March_ast.Ast.span -> bool) ref = ref (fun _ -> true)

(** Type names (bare) with a hand-written [impl Eq] (§3.5): the
    [predicate_eq_structural] warning reads it. *)
let hand_eq : (string, unit) Hashtbl.t = Hashtbl.create 16
