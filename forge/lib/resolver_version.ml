(** Semver version type and operations.

    Implements https://semver.org/ 2.0.0 semantics:
    - Three-component versions: MAJOR.MINOR.PATCH
    - Two- and one-component shorthands allowed in constraint contexts (patch/minor default to 0)
    - Pre-release identifiers: 1.0.0-alpha.1
    - Build metadata: 1.0.0+build.1 (ignored for ordering, stripped on parse)
    - Leading 'v' prefix accepted (v1.0.0 → 1.0.0)

    Ordering: 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0 < 1.0.1 < 1.1.0 < 2.0.0
*)

type t = {
  major : int;
  minor : int;
  patch : int;
  pre   : string list;  (** pre-release identifiers, e.g. ["alpha"; "1"] for -alpha.1 *)
}

let make ?(pre=[]) major minor patch = { major; minor; patch; pre }

let zero = make 0 0 0

(** Compare two pre-release identifier components according to semver rules:
    - Identifiers consisting of only digits are compared numerically.
    - Identifiers with letters or hyphens are compared lexically in ASCII.
    - Numeric identifiers have lower precedence than alphanumeric ones. *)
let compare_pre_id a b =
  match int_of_string_opt a, int_of_string_opt b with
  | Some na, Some nb -> compare na nb
  | Some _, None     -> -1   (* numeric < alphanumeric *)
  | None, Some _     -> 1
  | None, None       -> String.compare a b

let compare a b =
  let c = compare a.major b.major in if c <> 0 then c else
  let c = compare a.minor b.minor in if c <> 0 then c else
  let c = compare a.patch b.patch in if c <> 0 then c else
  (* Pre-release: absent pre > present pre  (1.0.0 > 1.0.0-alpha) *)
  match a.pre, b.pre with
  | [], [] -> 0
  | [], _  -> 1
  | _,  [] -> -1
  | ap, bp ->
    let rec cmp al bl =
      match al, bl with
      | [], [] -> 0
      | [], _  -> -1  (* shorter pre-release < longer one *)
      | _,  [] -> 1
      | x :: xs, y :: ys ->
        let c = compare_pre_id x y in
        if c <> 0 then c else cmp xs ys
    in
    cmp ap bp

let equal a b = compare a b = 0

(** Parse a version string. Accepts:
    - "1.2.3"          → 1.2.3
    - "1.2"            → 1.2.0 (patch defaults to 0)
    - "1"              → 1.0.0 (minor and patch default to 0)
    - "v1.2.3"         → 1.2.3 (leading v stripped)
    - "1.0.0-alpha.1"  → pre-release identifiers
    - "1.0.0+build.1"  → build metadata stripped
    Rejects: "1.0.x", "1.0.0.0", "", "latest" *)
let parse s =
  if String.length s = 0 then Error "empty version string" else
  (* Strip optional leading 'v' *)
  let s = if s.[0] = 'v' then String.sub s 1 (String.length s - 1) else s in
  if String.length s = 0 then Error "empty version string after stripping 'v'" else
  (* Strip build metadata (+...) — ignored for ordering *)
  let s = match String.index_opt s '+' with
    | None   -> s
    | Some i -> String.sub s 0 i
  in
  (* Split pre-release (-...) from core version *)
  let core, pre = match String.index_opt s '-' with
    | None   -> s, []
    | Some i ->
      let c = String.sub s 0 i in
      let p = String.sub s (i + 1) (String.length s - i - 1) in
      c, String.split_on_char '.' p
  in
  (* Validate all pre-release identifiers are non-empty *)
  if List.exists (fun id -> String.length id = 0) pre then
    Error (Printf.sprintf "empty pre-release identifier in '%s'" s)
  else
  match String.split_on_char '.' core with
  | [maj; min; pat] ->
    (match int_of_string_opt maj, int_of_string_opt min, int_of_string_opt pat with
     | Some major, Some minor, Some patch
       when major >= 0 && minor >= 0 && patch >= 0 ->
       Ok { major; minor; patch; pre }
     | _ -> Error (Printf.sprintf "invalid version component in '%s'" core))
  | [maj; min] ->
    (match int_of_string_opt maj, int_of_string_opt min with
     | Some major, Some minor when major >= 0 && minor >= 0 ->
       Ok { major; minor; patch = 0; pre }
     | _ -> Error (Printf.sprintf "invalid version component in '%s'" core))
  | [maj] ->
    (match int_of_string_opt maj with
     | Some major when major >= 0 ->
       Ok { major; minor = 0; patch = 0; pre }
     | _ -> Error (Printf.sprintf "invalid version component in '%s'" core))
  | _ ->
    Error (Printf.sprintf "invalid semver '%s' (expected 1–3 dot-separated components)" core)

let parse_exn s =
  match parse s with
  | Ok v    -> v
  | Error e -> failwith (Printf.sprintf "Resolver_version.parse_exn: %s" e)

let to_string v =
  let base = Printf.sprintf "%d.%d.%d" v.major v.minor v.patch in
  match v.pre with
  | []    -> base
  | parts -> base ^ "-" ^ String.concat "." parts

let pp fmt v = Format.pp_print_string fmt (to_string v)
