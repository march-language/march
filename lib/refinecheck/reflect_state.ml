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
    could supply is UNRESOLVED: [Refine_term.graph.ambiguous]), and a call
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

let reset () =
  active := false;
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
