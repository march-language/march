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

(** The builtin ADTs ([Lower.builtin_type_defs]), by their exact bare TIR
    name.  The C runtime builds and reads their values (`string_to_int`'s
    niche-encoded `Option(Int)`, a builtin's `List`), so their layout and
    constructor tags are fixed and a same-short-name user type
    ([Lower_types.builtin_adt_names]: `Inner.Option`, `Main.Result`) never
    makes them colliding.  Forcing the builtin `Option` Boxed and globally
    tagged beside a user `type Option(a)` read `string_to_int`'s raw pointer
    as a tagged cell: SIGSEGV
    (specs/progress/2026-11-11-compiled-derive-on-user-type-named-like-prelude-type.md).
    The user type itself still collides, so it is Boxed and globally tagged
    everywhere. *)
let builtin_adt_names = [ "Option"; "Result"; "List" ]

let is_colliding (cs : (string, string list) Hashtbl.t) (name : string) : bool =
  not (List.mem name builtin_adt_names) && Hashtbl.mem cs (short_name name)

(** A user type that shares its short name with a builtin ADT
    (`Main.Option`, `Shapes.Result`): qualified, short name in
    [builtin_adt_names].  Such a name must never be folded to its short form,
    which would name the builtin and its fixed layout. *)
let shadows_builtin_adt (name : string) : bool =
  String.contains name '.' && List.mem (short_name name) builtin_adt_names
