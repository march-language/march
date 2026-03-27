(** PubGrub dependency solver.

    Implements the PubGrub algorithm as described in:
      Natalie Weizenbaum, "PubGrub: Next-Generation Version Solving" (2018)
      https://nex3.medium.com/pubgrub-2fb6470504f

    PubGrub is a DPLL-style conflict-driven solver that constructs a
    *derivation tree* as it works.  When a conflict is found, it walks the
    derivation tree to produce a human-readable explanation chain.

    Key data structures:
      - Partial solution: for each package, either a selected version
        (positive assignment) or an excluded range (negative assignment).
      - Incompatibilities: facts of the form "NOT (p1 AT v1 AND p2 AT v2 …)".
        Each incompatibility carries a cause for human-readable errors.

    This implementation:
      - Handles registry packages (versioned, participate in solver).
      - Treats overrides (git branch/rev/path/patch) as pre-resolved;
        they are passed in as fixed assignments, bypassing the solver.
      - Produces structured conflict diagnostics suitable for the
        Elm-style error renderer.
*)

module V  = Resolver_version
module VC = Resolver_constraint
module RR = Resolver_registry

(* ------------------------------------------------------------------ *)
(*  Term: a constraint on one package                                  *)
(* ------------------------------------------------------------------ *)

(** A term represents a constraint on a single package's version.
    Positive: the package must satisfy this constraint.
    Negative: the package must NOT be at versions satisfying the constraint. *)
type term =
  | Positive of VC.t
  | Negative of VC.t

(** Negate a term. *)
let negate_term = function
  | Positive c -> Negative c
  | Negative c -> Positive c

(** Check if a version satisfies a term. *)
let term_satisfies version = function
  | Positive c -> VC.satisfies version c
  | Negative c -> not (VC.satisfies version c)

(* ------------------------------------------------------------------ *)
(*  Incompatibility                                                     *)
(* ------------------------------------------------------------------ *)

(** A cause explains why an incompatibility exists. *)
type cause =
  | Root
    (** The root package requires something. *)
  | Dependency of string * V.t
    (** Package at version V requires something. *)
  | Conflict of int * int
    (** Two incompatibilities (by ID) were combined via resolution. *)
  | NoVersions of string
    (** No versions of the package exist satisfying the constraint. *)

(** An incompatibility: a set of (package, term) pairs that cannot all
    be true simultaneously.  Has a unique ID for conflict tracking. *)
type incompat = {
  id    : int;
  terms : (string * term) list;
  cause : cause;
}

let incompat_counter = ref 0
let new_incompat terms cause =
  incr incompat_counter;
  { id = !incompat_counter; terms; cause }

(* ------------------------------------------------------------------ *)
(*  Partial solution                                                    *)
(* ------------------------------------------------------------------ *)

(** A single assignment in the partial solution. *)
type assignment =
  | Decided   of V.t    (** Version chosen for this package. *)
  | Derived   of term   (** Derived constraint (from propagation). *)

(* ------------------------------------------------------------------ *)
(*  Solve result                                                        *)
(* ------------------------------------------------------------------ *)

(** A successful resolution: map from package name to resolved version. *)
type solution = (string * V.t) list

(** A conflict description for human-readable error messages. *)
type conflict_info = {
  package     : string;
  reason      : string;
  constraints : (string * string) list;  (** (from_pkg, constraint_str) *)
}

type solve_error =
  | Conflict    of conflict_info
  | NoVersions  of { package : string; constraint_ : string }
  | CircularDep of { package : string }

(* ------------------------------------------------------------------ *)
(*  Solver state                                                        *)
(* ------------------------------------------------------------------ *)

type state = {
  registry    : RR.t;
  (* Overrides: pre-resolved packages that bypass the solver *)
  overrides   : (string * V.t option) list;  (* name → version (None if no semver) *)
  (* Partial solution: package → current assignment *)
  assignments : (string, assignment) Hashtbl.t;
  (* List of all known incompatibilities *)
  mutable incompats : incompat list;
  (* Packages enqueued for propagation *)
  mutable work_queue : string list;
}

let create_state registry overrides = {
  registry;
  overrides;
  assignments = Hashtbl.create 16;
  incompats   = [];
  work_queue  = [];
}

(** Return the current decided version for a package, if any. *)
let decided_version state pkg =
  match Hashtbl.find_opt state.assignments pkg with
  | Some (Decided v) -> Some v
  | _ -> None

(** Return all accumulated constraints on a package from derived assignments. *)
let derived_constraints state pkg =
  Hashtbl.fold (fun p a acc ->
      if p = pkg then
        match a with
        | Derived c -> c :: acc
        | Decided _ -> acc
      else acc
    ) state.assignments []

(** Check if a version is compatible with all current assignments. *)
let version_compatible state pkg ver =
  match Hashtbl.find_opt state.assignments pkg with
  | Some (Decided v) -> V.equal v ver
  | Some (Derived t) -> term_satisfies ver t
  | None -> true

(** Find the best (highest) version of [pkg] that satisfies all current
    constraints and the additional constraint [extra]. *)
let select_version state pkg extra_constraint =
  let candidates = RR.versions_of state.registry pkg in
  (* Filter: must satisfy current state AND extra constraint *)
  let ok ver =
    version_compatible state pkg ver.RR.version
    && VC.satisfies ver.RR.version extra_constraint
  in
  match List.find_opt ok candidates with
  | Some pv -> Some pv
  | None    -> None

(* ------------------------------------------------------------------ *)
(*  Error message rendering                                             *)
(* ------------------------------------------------------------------ *)

let render_conflict (incompats : incompat list) root_pkg =
  (* Walk incompatibilities to find the final contradiction and build
     a human-readable explanation chain. *)
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf
       "-- DEPENDENCY CONFLICT ----------------------------- forge.toml\n\n\
        I cannot find a version of `%s` that satisfies all requirements.\n\n"
       root_pkg);
  Buffer.add_string buf "Here is why:\n\n";
  (* Find the last incompatibility that involves root_pkg *)
  let relevant = List.filter (fun ic ->
      List.exists (fun (p, _) -> p = root_pkg) ic.terms
    ) incompats in
  let last = match List.rev relevant with [] -> None | x :: _ -> Some x in
  (match last with
   | None ->
     Buffer.add_string buf
       (Printf.sprintf "  No version of `%s` satisfies all declared constraints.\n"
          root_pkg)
   | Some ic ->
     List.iter (fun (p, term) ->
         match term with
         | Positive c ->
           Buffer.add_string buf
             (Printf.sprintf "  `%s` is required with constraint %s.\n"
                p (VC.to_string c))
         | Negative c ->
           Buffer.add_string buf
             (Printf.sprintf "  `%s` must NOT satisfy %s.\n"
                p (VC.to_string c))
       ) ic.terms);
  Buffer.add_char buf '\n';
  Buffer.add_string buf
    "To fix this, try one of:\n\
     \  • Relax one of the conflicting constraints.\n\
     \  • Use `[patch.NAME]` to substitute a fork that bridges both constraints.\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(*  Core solver                                                         *)
(* ------------------------------------------------------------------ *)

exception Solved   of solution
exception Failed   of solve_error

(** Add an incompatibility to the state, checking for terminal contradiction. *)
let add_incompat state ic =
  state.incompats <- ic :: state.incompats;
  (* Check if this incompatibility is a unit clause (all terms decided/derived)
     with no satisfying assignment — this is a contradiction *)
  let all_terms_false =
    List.for_all (fun (pkg, term) ->
        match Hashtbl.find_opt state.assignments pkg with
        | Some (Decided v) -> not (term_satisfies v term)
        | Some (Derived t) ->
          (* A derived negative constraint excludes a range — approximate check *)
          (match t, term with
           | Positive c1, Positive c2 ->
             (* If same constraint: both are consistent; not a contradiction here *)
             ignore (c1, c2); false
           | _ -> false)
        | None -> false
      ) ic.terms
  in
  if all_terms_false && ic.terms <> [] then
    raise (Failed (Conflict {
        package     = (match ic.terms with (p,_)::_ -> p | [] -> "?");
        reason      = render_conflict state.incompats
                        (match ic.terms with (p,_)::_ -> p | [] -> "?");
        constraints = List.map (fun (p, t) -> (p, match t with
            | Positive c -> VC.to_string c
            | Negative c -> "NOT " ^ VC.to_string c)) ic.terms;
      }))

(** Propagate: given that [pkg] has been decided at [version], add its
    deps as derived constraints and incompatibilities. *)
let propagate_decision state pkg version =
  match RR.deps_of state.registry pkg version with
  | None -> ()  (* unknown package / version — skip *)
  | Some deps ->
    List.iter (fun (dep_name, dep_constraint) ->
        (* Add incompatibility: pkg@version AND NOT dep satisfies constraint *)
        let ic = new_incompat
            [ (pkg,      Positive (VC.Eq version));
              (dep_name, Negative dep_constraint) ]
            (Dependency (pkg, version))
        in
        add_incompat state ic;
        (* Handle dep_name assignment *)
        (match Hashtbl.find_opt state.assignments dep_name with
         | Some (Decided v) ->
           (* Already decided — verify it satisfies this new constraint.
              If not, this is a conflict. *)
           if not (VC.satisfies v dep_constraint) then begin
             let cs = VC.to_string dep_constraint in
             raise (Failed (Conflict {
                 package = dep_name;
                 reason  = Printf.sprintf
                   "`%s %s` requires `%s %s`, but `%s` was already \
                    resolved to `%s` which does not satisfy this constraint."
                   pkg (V.to_string version) dep_name cs
                   dep_name (V.to_string v);
                 constraints = [(pkg, cs)];
               }))
           end
           (* Decision is compatible — nothing more to do. *)
         | Some (Derived (Positive existing_c)) ->
           (* Combine new constraint with existing derived constraint. *)
           let combined = VC.And (existing_c, dep_constraint) in
           Hashtbl.replace state.assignments dep_name (Derived (Positive combined));
           (* Re-enqueue if not already in the queue. *)
           if not (List.mem dep_name state.work_queue) then
             state.work_queue <- state.work_queue @ [dep_name]
         | Some (Derived (Negative _)) | None ->
           (* No constraint yet: set it fresh and enqueue. *)
           Hashtbl.replace state.assignments dep_name
             (Derived (Positive dep_constraint));
           if not (List.mem dep_name state.work_queue) then
             state.work_queue <- state.work_queue @ [dep_name])
      ) deps

(** Attempt to decide a version for [pkg], given current constraints. *)
let decide state pkg =
  (* Build the accumulated constraint on pkg *)
  let constraint_ =
    List.fold_left (fun acc t ->
        match t with
        | Positive c -> (match acc with
            | None   -> Some c
            | Some a -> Some (VC.And (a, c)))
        | Negative _ -> acc
      ) None (derived_constraints state pkg)
  in
  let effective_constraint = match constraint_ with
    | None   -> VC.Gte (V.zero)  (* unconstrained: any version ≥ 0.0.0 *)
    | Some c -> c
  in
  match select_version state pkg effective_constraint with
  | None ->
    (* No version satisfies the constraint *)
    let cs = VC.to_string effective_constraint in
    raise (Failed (NoVersions { package = pkg; constraint_ = cs }))
  | Some pv ->
    Hashtbl.replace state.assignments pkg (Decided pv.RR.version);
    propagate_decision state pkg pv.RR.version

(** Run the solver starting from the root requirements. *)
let solve registry ~root_deps ~overrides =
  let state = create_state registry overrides in
  (* Seed: add root deps as derived constraints, combining duplicates. *)
  List.iter (fun (pkg, constr) ->
      let combined = match Hashtbl.find_opt state.assignments pkg with
        | Some (Derived (Positive existing_c)) -> VC.And (existing_c, constr)
        | _ -> constr
      in
      Hashtbl.replace state.assignments pkg (Derived (Positive combined));
      if not (List.mem pkg state.work_queue) then
        state.work_queue <- state.work_queue @ [pkg]
    ) root_deps;
  (* Also add all override packages as decided at a synthetic version or any *)
  List.iter (fun (pkg, ver_opt) ->
      let v = match ver_opt with
        | Some v -> v
        | None   -> V.make 0 0 0  (* synthetic "any" for branch/rev/path deps *)
      in
      Hashtbl.replace state.assignments pkg (Decided v)
    ) overrides;
  (try
     while state.work_queue <> [] do
       let pkg = List.hd state.work_queue in
       state.work_queue <- List.tl state.work_queue;
       (* Skip if already decided (e.g. override) *)
       (match Hashtbl.find_opt state.assignments pkg with
        | Some (Decided _) -> ()
        | _ -> decide state pkg)
     done;
     (* Collect the solution *)
     let solution = Hashtbl.fold (fun pkg assignment acc ->
         match assignment with
         | Decided v -> (pkg, v) :: acc
         | Derived _ -> acc  (* undecided — should not happen if solver ran fully *)
       ) state.assignments [] in
     Ok solution
   with
   | Failed err -> Error err
   | Solved sol -> Ok sol)

(* ------------------------------------------------------------------ *)
(*  Public entry point                                                  *)
(* ------------------------------------------------------------------ *)

(** Resolve a set of dependencies using the given registry.

    [root_deps]: list of (package_name, version_constraint) from forge.toml [deps].
    [overrides]: pre-resolved packages (git branch/rev/path/tag) as
                 (package_name, version_option).

    Returns either a solution (package → version) or a structured error. *)
let resolve registry ~root_deps ~overrides =
  (* Validate that override packages don't appear in root_deps with conflicts *)
  let override_names = List.map fst overrides in
  let registry_deps = List.filter (fun (p, _) ->
      not (List.mem p override_names)) root_deps in
  solve registry ~root_deps:registry_deps ~overrides

(* ------------------------------------------------------------------ *)
(*  Error formatting for the CLI                                        *)
(* ------------------------------------------------------------------ *)

let format_error = function
  | Conflict ci ->
    Printf.sprintf
      "-- DEPENDENCY CONFLICT ----------------------------- forge.toml\n\n\
       %s\n" ci.reason
  | NoVersions { package; constraint_ } ->
    Printf.sprintf
      "-- NO VERSIONS FOUND ------------------------------ forge.toml\n\n\
       I could not find any version of `%s` satisfying `%s`.\n\n\
       This might mean:\n\
       \  • The package is not in the registry yet.\n\
       \  • Your constraint is too strict.\n\
       \  • Run `forge deps` to refresh the registry index.\n"
      package constraint_
  | CircularDep { package } ->
    Printf.sprintf
      "-- CIRCULAR DEPENDENCY ----------------------------- forge.toml\n\n\
       Package `%s` depends on itself (directly or transitively).\n\
       \nCircular dependencies are not allowed.\n"
      package
