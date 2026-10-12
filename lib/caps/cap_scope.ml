(* Path scopes on filesystem capabilities.  See cap_scope.mli. *)

let is_absolute p = String.length p > 0 && p.[0] = '/'

(* Split on '/', dropping empty segments (which collapses "//" and a trailing
   separator), then fold away "." and "..".  A ".." at the root is dropped
   rather than escaping above it, matching how the kernel resolves "/..". *)
let segments (p : string) : string list =
  String.split_on_char '/' p
  |> List.filter (fun s -> s <> "" && s <> ".")
  |> List.fold_left
       (fun acc seg ->
         if seg = ".." then match acc with [] -> [] | _ :: tl -> tl
         else seg :: acc)
       []
  |> List.rev

let normalize (p : string) : string =
  let segs = segments p in
  if is_absolute p then "/" ^ String.concat "/" segs
  else String.concat "/" segs

(* Segment-wise containment.  A raw string prefix test would accept
   "/etcpasswd" for scope "/etc", which is exactly the kind of near-miss that
   makes a scope look enforced while leaking. *)
let rec segments_prefix (scope : string list) (p : string list) : bool =
  match (scope, p) with
  | [], _ -> true
  | _, [] -> false
  | s :: st, q :: qt -> s = q && segments_prefix st qt

let within ~scope p =
  let s = segments scope and q = segments p in
  (* An absolute scope only contains absolute paths, and vice versa: mixing
     them would compare unrelated roots. *)
  is_absolute scope = is_absolute p && segments_prefix s q

let scope_subsumes (a : string option) (b : string option) : bool =
  match (a, b) with
  | None, _ -> true (* unscoped permits everything *)
  | Some _, None -> false (* a scope grants strictly less than unscoped *)
  | Some sa, Some sb -> within ~scope:sa sb

(* Only filesystem capabilities take a scope.  IO.FileSystem is included: it is
   the parent of FileRead and FileWrite, and file_copy is declared under it. *)
let is_scopable (cap : string) : bool =
  match cap with
  | "IO.FileRead" | "IO.FileWrite" | "IO.FileSystem" -> true
  | _ -> false

(* ── Scope manifest (embedded in compiled binaries) ─────────────────── *)

let fs_classes = [ "IO.FileRead"; "IO.FileWrite" ]

(* Both lattice directions: an ancestor grant (IO.FileSystem, IO) covers the
   class, and a descendant would still need the class open. *)
let related klass cap =
  Cap_lattice.cap_subsumes cap klass || Cap_lattice.cap_subsumes klass cap

let effective_scopes ~(decls : (string * string option) list) (klass : string)
    : string list option =
  let relevant = List.filter (fun (c, _) -> related klass c) decls in
  if relevant = [] || List.exists (fun (_, sc) -> sc = None) relevant then None
  else
    Some
      (List.sort_uniq String.compare
         (List.filter_map (fun (_, sc) -> Option.map normalize sc) relevant))

let json_string (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 || Char.code c = 0x7f ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let manifest_json (decls : (string * string option) list) : string option =
  let fs =
    List.filter (fun (c, _) -> List.exists (fun k -> related k c) fs_classes) decls
    |> List.map (fun (c, sc) -> (c, Option.map normalize sc))
    |> List.sort_uniq compare
  in
  if not (List.exists (fun (_, sc) -> sc <> None) fs) then None
  else
    let entry (c, sc) =
      Printf.sprintf {|{"cap":%s,"scope":%s}|} (json_string c)
        (match sc with None -> "null" | Some s -> json_string s)
    in
    Some
      (Printf.sprintf {|{"v":1,"scopes":[%s]}|}
         (String.concat "," (List.map entry fs)))
