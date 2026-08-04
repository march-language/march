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
