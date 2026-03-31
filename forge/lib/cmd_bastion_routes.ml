(** cmd_bastion_routes.ml — forge bastion routes

    Reads the project's router.march file(s) and prints all registered routes
    in a formatted table.

    Route detection: scans for the comment convention the scaffold emits:
      -- ROUTE: GET /path
    and also for bare match-arm patterns of the form:
      (:get,  [...])  ->
      (:post, [...])  ->
    etc.  The two strategies are combined and de-duplicated so hand-written
    routers (without the comment) are still recognised. *)

(* ------------------------------------------------------------------ helpers *)

let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

let string_trim_left s =
  let i = ref 0 in
  let n = String.length s in
  while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  String.sub s !i (n - !i)

let starts_with prefix s =
  let pl = String.length prefix and sl = String.length s in
  sl >= pl && String.sub s 0 pl = prefix

(* ------------------------------------------------------------------ route types *)

type route = {
  method_str : string;
  path       : string;
  handler    : string;
}

(* ------------------------------------------------------------------ comment-style parser *)

(** Parse "-- ROUTE: GET /path" comments.  Returns [(method, path)] pairs.
    Lines that follow are scanned for the handler (first word ending in "("). *)
let parse_comment_routes lines =
  let n = Array.length lines in
  let routes = ref [] in
  for i = 0 to n - 1 do
    let line = string_trim_left lines.(i) in
    if starts_with "-- ROUTE: " line then begin
      let rest = String.sub line 10 (String.length line - 10) in
      (* rest = "GET /path" or "POST /users" etc. *)
      (match String.split_on_char ' ' rest with
       | meth :: path_parts ->
         let path = String.concat " " path_parts in
         (* look ahead for the handler on the next non-blank line *)
         let handler =
           let found = ref "" in
           let j = ref (i + 1) in
           while !j < n && !found = "" do
             let nl = string_trim_left lines.(!j) in
             if nl <> "" && not (starts_with "--" nl) then begin
               (* extract handler: everything before "(conn" or "->" *)
               let h = match String.index_opt nl '-' with
                 | Some k when k > 0 && nl.[k-1] = ' ' ->
                   String.trim (String.sub nl 0 (k - 1))
                 | _ ->
                   (match String.index_opt nl '(' with
                    | Some k -> String.trim (String.sub nl 0 k)
                    | None   -> String.trim nl)
               in
               if h <> "" then found := h
             end;
             incr j
           done;
           !found
         in
         routes := { method_str = String.uppercase_ascii meth;
                     path;
                     handler } :: !routes
       | _ -> ())
    end
  done;
  List.rev !routes

(* ------------------------------------------------------------------ arm-style parser *)

(** Recognise match arms of the form [(:get, [...]) ->] or [(Get, [...]) ->]
    and extract method + path.  This catches hand-written routers without the
    ROUTE comment, in both atom-style (:get) and constructor-style (Get). *)
let method_of_token s =
  match String.lowercase_ascii (String.trim s) with
  | ":get"    | "get"    -> Some "GET"
  | ":post"   | "post"   -> Some "POST"
  | ":put"    | "put"    -> Some "PUT"
  | ":patch"  | "patch"  -> Some "PATCH"
  | ":delete" | "delete" -> Some "DELETE"
  | ":head"   | "head"   -> Some "HEAD"
  | _                    -> None

(** Extract a rough path string from the path_info list literal.
    E.g. ["users", id] -> "/users/:id"
         []             -> "/" *)
let segment_of_token p =
  let p = String.trim p in
  if String.length p >= 2 && p.[0] = '"' && p.[String.length p - 1] = '"'
  then String.sub p 1 (String.length p - 2)
  else ":" ^ p

(** Extract segments from a Cons-chain: Cons("a", Cons("b", Nil)) -> ["a";"b"] *)
let rec segments_of_cons s =
  let s = String.trim s in
  if s = "Nil" || s = "" then []
  else if starts_with "Cons(" s then begin
    (* strip "Cons(" prefix *)
    let inner = String.sub s 5 (String.length s - 5) in
    (* find the first comma separating head from tail *)
    let depth = ref 0 in
    let comma = ref (-1) in
    String.iteri (fun i c ->
        if !comma >= 0 then ()
        else if c = '(' || c = '[' then incr depth
        else if c = ')' || c = ']' then decr depth
        else if c = ',' && !depth = 0 then comma := i
      ) inner;
    if !comma < 0 then []
    else
      let head = String.trim (String.sub inner 0 !comma) in
      let tail = String.trim (String.sub inner (!comma + 1)
                                (String.length inner - !comma - 1)) in
      (* strip trailing ")" from tail *)
      let tail = if String.length tail > 0 && tail.[String.length tail - 1] = ')'
        then String.sub tail 0 (String.length tail - 1)
        else tail
      in
      segment_of_token head :: segments_of_cons tail
  end
  else []

let path_of_list_literal s =
  let s = String.trim s in
  (* Nil — empty list *)
  if s = "Nil" then "/"
  (* Cons(head, tail) — linked-list form *)
  else if starts_with "Cons(" s then
    "/" ^ String.concat "/" (segments_of_cons s)
  else
  (* [ ... ] bracket form *)
  let inner =
    if String.length s >= 2 && s.[0] = '[' && s.[String.length s - 1] = ']'
    then String.sub s 1 (String.length s - 2)
    else s
  in
  let inner = String.trim inner in
  if inner = "" then "/"
  else begin
    let parts = String.split_on_char ',' inner in
    let segments = List.map (fun p ->
        let p = String.trim p in
        (* string literal "segment" -> segment, bare atom/var -> :var *)
        if String.length p >= 2 && p.[0] = '"' && p.[String.length p - 1] = '"'
        then String.sub p 1 (String.length p - 2)
        else ":" ^ p
      ) parts
    in
    "/" ^ String.concat "/" segments
  end

let parse_arm_routes lines =
  let routes = ref [] in
  let n = Array.length lines in
  for i = 0 to n - 1 do
    let line = string_trim_left lines.(i) in
    (* Pattern: (:METHOD, [...]) ->  or  (Get, [...]) ->  etc. *)
    let is_arm =
      starts_with "(:" line ||
      (String.length line > 1 && line.[0] = '(' &&
       (let rest = String.sub line 1 (String.length line - 1) in
        starts_with "Get," rest || starts_with "Post," rest ||
        starts_with "Put," rest || starts_with "Patch," rest ||
        starts_with "Delete," rest || starts_with "Head," rest ||
        starts_with "Get," (String.trim rest) ||
        starts_with "Post," (String.trim rest) ||
        starts_with "Put," (String.trim rest) ||
        starts_with "Patch," (String.trim rest) ||
        starts_with "Delete," (String.trim rest) ||
        starts_with "Head," (String.trim rest)))
    in
    if is_arm then begin
      (* extract up to the first "->" *)
      let s = match String.index_opt line '>' with
        | Some k when k > 0 && line.[k-1] = '-' ->
          String.trim (String.sub line 0 (k - 1))
        | _ -> line
      in
      (* parse (:method, [path_list]) or (Method, [path_list]) *)
      (match String.index_opt s ',' with
       | None -> ()
       | Some comma ->
         let atom_part = String.trim (String.sub s 1 (comma - 1)) in
         let rest      = String.trim (String.sub s (comma + 1) (String.length s - comma - 1)) in
         (* rest should be something like "[...])" — strip trailing ")" *)
         let rest = if String.length rest > 0 && rest.[String.length rest - 1] = ')' then
             String.sub rest 0 (String.length rest - 1)
           else rest
         in
         (match method_of_token atom_part with
          | None -> ()
          | Some meth ->
            let path = path_of_list_literal rest in
            (* skip internal bastion routes we emit automatically *)
            let is_bastion = starts_with "/_bastion" path in
            if not is_bastion then begin
              (* look ahead for handler *)
              let handler =
                let found = ref "" in
                let j = ref (i) in
                (* handler may be on the same line (after ->) or next line *)
                let full_line = if i < n then lines.(i) else "" in
                (match String.index_opt full_line '>' with
                 | Some k ->
                   let after = String.trim (String.sub full_line (k+1)
                                              (String.length full_line - k - 1)) in
                   let h = match String.index_opt after '(' with
                     | Some p -> String.trim (String.sub after 0 p)
                     | None   -> String.trim after
                   in
                   if h <> "" then found := h
                 | None -> ());
                while !j < n && !found = "" do
                  let nl = string_trim_left lines.(!j) in
                  if nl <> "" && not (starts_with "--" nl) && not (starts_with "(:" nl) then begin
                    let h = match String.index_opt nl '(' with
                      | Some k -> String.trim (String.sub nl 0 k)
                      | None   -> String.trim nl
                    in
                    if h <> "" then found := h
                  end;
                  incr j
                done;
                !found
              in
              routes := { method_str = meth; path; handler } :: !routes
            end))
    end  (* is_arm *)
  done;
  List.rev !routes

(* ------------------------------------------------------------------ printer *)

let pad s n =
  let len = String.length s in
  if len >= n then s else s ^ String.make (n - len) ' '

let print_routes routes =
  if routes = [] then
    Printf.printf "No routes found.\n%!"
  else begin
    let col1 = List.fold_left (fun acc r -> max acc (String.length r.method_str)) 6 routes in
    let col2 = List.fold_left (fun acc r -> max acc (String.length r.path))    4 routes in
    let sep  = String.make (col1 + col2 + String.length "  CONTROLLER" + 6) '-' in
    Printf.printf "%s  %s  %s\n%!" (pad "METHOD" col1) (pad "PATH" col2) "CONTROLLER";
    Printf.printf "%s\n%!" sep;
    List.iter (fun r ->
        Printf.printf "%s  %s  %s\n%!"
          (pad r.method_str col1)
          (pad r.path col2)
          r.handler
      ) routes
  end

(* ------------------------------------------------------------------ de-dup *)

let dedup routes =
  let seen = Hashtbl.create 16 in
  List.filter (fun r ->
      let key = r.method_str ^ " " ^ r.path in
      if Hashtbl.mem seen key then false
      else begin Hashtbl.add seen key (); true end
    ) routes

(* ------------------------------------------------------------------ run *)

let find_router_files proj =
  (* Primary: lib/<name>/router.march *)
  let root    = proj.Project.root in
  let lib_dir = Filename.concat root "lib" in
  let primary = Filename.concat lib_dir
      (Filename.concat proj.Project.name "router.march") in
  if Sys.file_exists primary then [primary]
  else begin
    (* Fall back: scan lib/<name>/ for any router*.march *)
    let sub = Filename.concat lib_dir proj.Project.name in
    if Sys.file_exists sub && Sys.is_directory sub then
      Array.to_list (Sys.readdir sub)
      |> List.filter_map (fun f ->
          if Filename.check_suffix f "router.march" ||
             (starts_with "router" f && Filename.check_suffix f ".march")
          then Some (Filename.concat sub f)
          else None)
    else []
  end

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let files = find_router_files proj in
    if files = [] then begin
      Printf.printf "No router file found (expected lib/%s/router.march).\n%!"
        proj.Project.name;
      Ok ()
    end else begin
      let all_routes = List.concat_map (fun path ->
          let src   = read_file path in
          let lines = Array.of_list (String.split_on_char '\n' src) in
          let comment_routes = parse_comment_routes lines in
          let arm_routes     = parse_arm_routes lines in
          (* comment routes take priority; arm routes fill in the rest *)
          let known_paths = List.map (fun r -> r.method_str ^ r.path) comment_routes in
          let extra = List.filter (fun r ->
              not (List.mem (r.method_str ^ r.path) known_paths)
            ) arm_routes in
          comment_routes @ extra
        ) files
      in
      print_routes (dedup all_routes);
      Ok ()
    end
