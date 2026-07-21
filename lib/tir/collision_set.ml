(** Collision-set computation for same-short-name types declared in
    different modules — the shared input to Stage 3's three consumers
    (global ctor tags, forced-Boxed repr, dispatch-function codegen /
    mono routing). Computed ONCE per compilation from the module-qualified
    [TDVariant]/[TDRecord] names lowering already produces for
    nested-module type declarations (see [lower.ml]'s [DType] arm under
    [DMod], which sets a type's TIR name to [prefix ^ tname.txt]).

    A short name with only ONE declaring module is the common case and
    must be absent from the returned table (not present with a
    single-element list) — every consumer's collision-conditional gate is
    "member of this table", so the empty/absent case must be cheap and
    exact. *)

let short_name (qualified : string) : string =
  match String.rindex_opt qualified '.' with
  | None -> qualified
  | Some i -> String.sub qualified (i + 1) (String.length qualified - i - 1)

let type_def_name : Tir.type_def -> string = function
  | Tir.TDVariant (n, _) -> n
  | Tir.TDRecord (n, _) -> n
  | Tir.TDClosure (n, _) -> n

(** short_name -> list of full (qualified-or-bare) declaring names, ONLY for
    short names declared 2+ times. *)
let compute (type_defs : Tir.type_def list) : (string, string list) Hashtbl.t =
  let by_short : (string, string list) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun td ->
      let name = type_def_name td in
      let sn = short_name name in
      let existing = match Hashtbl.find_opt by_short sn with Some l -> l | None -> [] in
      (* Dedup exact-name repeats (e.g. stdlib_context + user module both
         registering the same qualified name) — only DISTINCT full names
         count as a collision. *)
      if not (List.mem name existing) then
        Hashtbl.replace by_short sn (name :: existing)
    ) type_defs;
  let result = Hashtbl.create 16 in
  Hashtbl.iter (fun sn names -> if List.length names >= 2 then Hashtbl.replace result sn names)
    by_short;
  result

let is_colliding (cs : (string, string list) Hashtbl.t) (name : string) : bool =
  Hashtbl.mem cs (short_name name)
