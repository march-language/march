(* Content-addressed verdict cache under <root>/.march/cas/vc/.
   Key = BLAKE3 of the VC's canonical assertion block; the solver is consulted
   only on a miss.  Mirrors the git-style <prefix2>/<rest> layout used by the
   rest of the CAS. *)

let key_of_vc (vc : Smt.vc) : string =
  March_cas.Blake3.hash_string (Smt.assertion_block vc)

let string_of_result : Solver.result -> string = function
  | Solver.Unsat -> "unsat"
  | Solver.Unknown -> "unknown"
  | Solver.Sat model ->
      "sat\n"
      ^ String.concat "\n" (List.map (fun (k, v) -> k ^ "\t" ^ v) model)

let result_of_string (s : string) : Solver.result =
  match String.split_on_char '\n' s with
  | "unsat" :: _ -> Solver.Unsat
  | "unknown" :: _ -> Solver.Unknown
  | "sat" :: rest ->
      let model =
        List.filter_map
          (fun line ->
            match String.index_opt line '\t' with
            | Some i ->
                Some
                  ( String.sub line 0 i,
                    String.sub line (i + 1) (String.length line - i - 1) )
            | None -> None)
          rest
      in
      Solver.Sat model
  | _ -> Solver.Unknown

let cache_dir ~root =
  List.fold_left Filename.concat root [ ".march"; "cas"; "vc" ]

let rec mkdir_p dir =
  if dir = "/" || dir = "." || dir = Filename.dirname dir then ()
  else if Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let path_for ~root key =
  let prefix = String.sub key 0 2 in
  let rest = String.sub key 2 (String.length key - 2) in
  Filename.concat (Filename.concat (cache_dir ~root) prefix) rest

let lookup ~root key : Solver.result option =
  let p = path_for ~root key in
  if Sys.file_exists p then
    Some (result_of_string (In_channel.with_open_bin p In_channel.input_all))
  else None

let store ~root key (r : Solver.result) : unit =
  let p = path_for ~root key in
  mkdir_p (Filename.dirname p);
  Out_channel.with_open_bin p (fun oc ->
      Out_channel.output_string oc (string_of_result r))
