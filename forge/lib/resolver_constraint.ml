(** Version constraint type and operations.

    Supported constraint forms:
      ~> 1.2.3          pessimistic (>= 1.2.3, < 1.3.0)
      ~> 1.2            pessimistic (>= 1.2.0, < 2.0.0)
      ~> 1              pessimistic (>= 1.0.0, < 2.0.0)
      >= 2.0            lower bound (inclusive)
      <= 2.5.0          upper bound (inclusive)
      > 1.0.0           strict lower bound
      < 3.0             strict upper bound
      1.4.2             exact match
      >= 1.5, < 2.0     AND combination (comma-separated)

    Pre-release selection: a non-pre-release constraint does NOT select
    pre-release versions.  ~> 1.0 does not select 1.1.0-beta.
*)

module V = Resolver_version

type t =
  | Gte of V.t
  | Lte of V.t
  | Gt  of V.t
  | Lt  of V.t
  | Eq  of V.t
  | And of t * t

(** Check whether [version] satisfies [constraint_].

    Pre-release versions are only selected when the constraint itself has
    a pre-release component OR when the version is an exact Eq match.
    This mirrors Cargo and Hex behaviour. *)
let satisfies version c =
  (* Helper: does this constraint reference any pre-release? *)
  let rec constraint_has_pre = function
    | Gte v | Lte v | Gt v | Lt v | Eq v -> v.V.pre <> []
    | And (a, b) -> constraint_has_pre a || constraint_has_pre b
  in
  let pre_ok =
    version.V.pre = []           (* release version: always consider *)
    || constraint_has_pre c      (* constraint explicitly mentions pre: allow *)
  in
  if not pre_ok then false
  else
    let rec check = function
      | Gte v      -> V.compare version v >= 0
      | Lte v      -> V.compare version v <= 0
      | Gt  v      -> V.compare version v > 0
      | Lt  v      -> V.compare version v < 0
      | Eq  v      -> V.compare version v = 0
      | And (a, b) -> check a && check b
    in
    check c

(** Expand ~> v into an And(Gte lower, Lt upper).

    Expansion rules (same as Hex / Elixir):
    - ~> MAJOR.MINOR.PATCH → >= MAJOR.MINOR.PATCH, < MAJOR.(MINOR+1).0
    - ~> MAJOR.MINOR       → >= MAJOR.MINOR.0,     < (MAJOR+1).0.0
    - ~> MAJOR             → >= MAJOR.0.0,          < (MAJOR+1).0.0

    Special case: ~> 0.MINOR uses minor-level upper bound:
    - ~> 0.2               → >= 0.2.0, < 0.3.0

    Note: the `components` parameter tracks how many components were in
    the original version literal in the constraint (1, 2, or 3). *)
let twiddle_wakka ~components v =
  let lower = V.make ~pre:v.V.pre v.V.major v.V.minor v.V.patch in
  let upper = match components with
    | 3 ->
      (* ~> M.N.P  →  < M.(N+1).0 *)
      V.make v.V.major (v.V.minor + 1) 0
    | 2 when v.V.major = 0 ->
      (* ~> 0.N    →  < 0.(N+1).0  — stay within minor when major=0 *)
      V.make 0 (v.V.minor + 1) 0
    | _ ->
      (* ~> M.N or ~> M  →  < (M+1).0.0 *)
      V.make (v.V.major + 1) 0 0
  in
  And (Gte lower, Lt upper)

(** Strip leading and trailing whitespace from a string. *)
let trim = String.trim

(** Parse a single constraint atom: one of
    ~> VER | >= VER | <= VER | > VER | < VER | VER (exact) *)
let parse_atom s =
  let s = trim s in
  (* Count components in a version string to drive ~> expansion *)
  let count_components vs =
    (* strip any pre-release for counting *)
    let core = match String.index_opt vs '-' with
      | None   -> vs
      | Some i -> String.sub vs 0 i
    in
    let core = match String.index_opt core '+' with
      | None   -> core
      | Some i -> String.sub core 0 i
    in
    (* strip leading v *)
    let core = if String.length core > 0 && core.[0] = 'v'
      then String.sub core 1 (String.length core - 1) else core in
    List.length (String.split_on_char '.' core)
  in
  let try_parse_version vs =
    match V.parse vs with
    | Ok v    -> Ok v
    | Error e -> Error (Printf.sprintf "invalid version '%s': %s" vs e)
  in
  let len = String.length s in
  if len >= 3 && String.sub s 0 3 = "~> " then
    let vs = trim (String.sub s 3 (len - 3)) in
    let comps = count_components vs in
    (match try_parse_version vs with
     | Error e -> Error e
     | Ok v    -> Ok (twiddle_wakka ~components:comps v))
  else if len >= 3 && String.sub s 0 2 = ">=" then
    let vs = trim (String.sub s 2 (len - 2)) in
    (match try_parse_version vs with
     | Error e -> Error e
     | Ok v    -> Ok (Gte v))
  else if len >= 3 && String.sub s 0 2 = "<=" then
    let vs = trim (String.sub s 2 (len - 2)) in
    (match try_parse_version vs with
     | Error e -> Error e
     | Ok v    -> Ok (Lte v))
  else if len >= 2 && String.sub s 0 1 = ">" then
    let vs = trim (String.sub s 1 (len - 1)) in
    (match try_parse_version vs with
     | Error e -> Error e
     | Ok v    -> Ok (Gt v))
  else if len >= 2 && String.sub s 0 1 = "<" then
    let vs = trim (String.sub s 1 (len - 1)) in
    (match try_parse_version vs with
     | Error e -> Error e
     | Ok v    -> Ok (Lt v))
  else
    (* exact version or error *)
    (match try_parse_version s with
     | Error e -> Error e
     | Ok v    -> Ok (Eq v))

(** Parse a constraint string, which may be a comma-separated AND combination.
    E.g. ">= 1.5, < 2.0" → And(Gte 1.5.0, Lt 2.0.0) *)
let parse s =
  let parts = String.split_on_char ',' s in
  match parts with
  | []  -> Error "empty constraint string"
  | [single] ->
    parse_atom (trim single)
  | first :: rest ->
    (match parse_atom (trim first) with
     | Error e -> Error e
     | Ok c0   ->
       List.fold_left (fun acc part ->
           match acc with
           | Error e -> Error e
           | Ok c    ->
             (match parse_atom (trim part) with
              | Error e -> Error e
              | Ok c2   -> Ok (And (c, c2)))
         ) (Ok c0) rest)

let parse_exn s =
  match parse s with
  | Ok c    -> c
  | Error e -> failwith (Printf.sprintf "Resolver_constraint.parse_exn: %s" e)

let rec to_string = function
  | Gte v      -> ">= " ^ V.to_string v
  | Lte v      -> "<= " ^ V.to_string v
  | Gt  v      -> "> "  ^ V.to_string v
  | Lt  v      -> "< "  ^ V.to_string v
  | Eq  v      -> "= "  ^ V.to_string v
  | And (a, b) -> to_string a ^ ", " ^ to_string b
