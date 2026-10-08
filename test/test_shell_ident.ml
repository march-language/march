(* test/test_shell_ident.ml — the shell identity table's encoding
   (lib/jit/shell_ident.ml, "the table as text") and the client's fetch of
   it (summary, then the groups that differ; the whole table from a node
   that predates the summary).  The node's side of the protocol is
   runtime/march_shell.c (ident_select), exercised end to end by the
   native_shell_* goldens; [serve] below is its selection, line for line. *)

module S = March_jit.Shell_ident

let tbl l = let h = Hashtbl.create 16 in List.iter (fun (k, v) -> Hashtbl.replace h k v) l; h
let sorted h = List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) h [])

let sample () : S.t = {
  S.decls = tbl [
      "f:main", S.hash48 "fn main";
      "<header>", S.hash48 "";
      "t:Shade", S.hash48 "type Shade";
      "List.f:map", S.hash48 "map";
      "List.f:map#2", S.hash48 "map 2";
      "List.<header>", S.hash48 "import";
      "A.B.f:deep", S.hash48 "deep";
      "A.B.impl:Json.ToJson", S.hash48 "impl";
      "A.a:Counter", S.hash48 "actor";
    ];
  tags = tbl [
      "Shade", "Dark=0,Light=1";
      "Odd", "X=0,Y=5,Z=2";
      "Empty", "";
    ];
  fns = tbl [
      "List.length", ("i64(ptr)", "b");
      "Counter_inspect", ("void(ptr)", "-");
    ];
}

let check_same (a : S.t) (b : S.t) =
  Alcotest.(check (list (pair string string))) "decls" (sorted a.decls) (sorted b.decls);
  Alcotest.(check (list (pair string string))) "tags" (sorted a.tags) (sorted b.tags);
  Alcotest.(check (list (pair string (pair string string)))) "fns" (sorted a.fns) (sorted b.fns)

let test_round_trip () =
  let t = sample () in
  let s = S.to_string t in
  check_same t (S.of_string s);
  Alcotest.(check string) "re-encoding is stable" s (S.to_string (S.of_string s));
  (* A module prefix is written once per group, not per key. *)
  Alcotest.(check bool) "no List. in the rows" false
    (List.exists (fun l -> String.length l > 5 && String.sub l 0 5 = "List.")
       (String.split_on_char '\n' s))

let test_hash48 () =
  let h = S.hash48 "some text" in
  Alcotest.(check int) "8 characters" 8 (String.length h);
  (* The same 48 bits as the first 12 hex digits of the format-1 hash. *)
  let hex16 = String.sub (March_cas.Blake3.hash_string "some text") 0 16 in
  let v1 = S.of_string (Printf.sprintf "d List.f:map %s\nt Shade Dark=0,Light=1\nx f i64() -\n" hex16) in
  Alcotest.(check (option string)) "format 1 hash read as hash48" (Some h)
    (Hashtbl.find_opt v1.decls "List.f:map");
  Alcotest.(check (option string)) "format 1 tags" (Some "Dark=0,Light=1")
    (Hashtbl.find_opt v1.tags "Shade")

(* runtime/march_shell.c's ident_select: [None] the summary, [Some gs] the
   named groups. *)
let serve (table : string) (groups : string list option) : string =
  let lines = String.split_on_char '\n' table in
  let in_groups = ref false and keep = ref true in
  List.filteri (fun i l ->
      if i = 0 then true
      else if String.length l > 2 && String.sub l 0 2 = "m " then begin
        in_groups := true;
        keep := (match groups with
            | None -> true
            | Some gs -> List.mem (List.nth (String.split_on_char ' ' l) 1) gs);
        !keep
      end else if !in_groups then groups <> None && !keep
      else groups = None) lines
  |> String.concat "\n"

let node_ask ~log (table : string) verb =
  log := verb :: !log;
  let pre = "IDENT GROUPS " in
  if verb = "IDENT" then Ok table
  else if verb = "IDENT SUMMARY" then Ok (serve table None)
  else if String.length verb > String.length pre
       && String.sub verb 0 (String.length pre) = pre then
    Ok (serve table (Some (String.split_on_char ','
                             (String.sub verb (String.length pre)
                                (String.length verb - String.length pre)))))
  else Error "ERR unknown_verb"

let test_fetch_up_to_date () =
  let node = sample () in
  let log = ref [] in
  match S.fetch ~ask:(node_ask ~log (S.to_string node)) (Hashtbl.copy node.decls) with
  | Error e -> Alcotest.fail e
  | Ok got ->
    Alcotest.(check (list string)) "only the summary" [ "IDENT SUMMARY" ] !log;
    check_same node got

let test_fetch_differing_groups () =
  let node = sample () in
  let client = Hashtbl.copy node.decls in
  Hashtbl.replace client "List.f:map" (S.hash48 "map, edited");
  Hashtbl.replace client "f:main" (S.hash48 "fn main, edited");
  Hashtbl.replace client "Fresh.f:new" (S.hash48 "only here");
  let log = ref [] in
  match S.fetch ~ask:(node_ask ~log (S.to_string node)) client with
  | Error e -> Alcotest.fail e
  | Ok got ->
    (* The two groups that differ, not A.B, A, or the client-only Fresh. *)
    Alcotest.(check (list string)) "requests"
      [ "IDENT GROUPS .,List"; "IDENT SUMMARY" ] !log;
    check_same node got;
    let c = { S.node = got; client_decls = client; regions = [] } in
    Alcotest.(check (list string)) "differing"
      [ "Fresh.f:new"; "List.f:map"; "f:main" ] (S.differing c)

let test_fetch_old_node () =
  (* A node built before format 2: no SUMMARY, a format-1 table. *)
  let node = sample () in
  let v1 = String.concat "\n"
      (Hashtbl.fold (fun k _ acc ->
           Printf.sprintf "d %s %s" k
             (String.sub (March_cas.Blake3.hash_string ("text of " ^ k)) 0 16) :: acc)
          node.decls []) in
  let client = Hashtbl.create 16 in
  Hashtbl.iter (fun k _ -> Hashtbl.replace client k (S.hash48 ("text of " ^ k))) node.decls;
  let log = ref [] in
  let ask verb =
    log := verb :: !log;
    if verb = "IDENT" then Ok v1 else Error "ERR unknown_verb" in
  match S.fetch ~ask client with
  | Error e -> Alcotest.fail e
  | Ok got ->
    Alcotest.(check (list string)) "falls back" [ "IDENT"; "IDENT SUMMARY" ] !log;
    let c = { S.node = got; client_decls = client; regions = [] } in
    Alcotest.(check (list string)) "agrees" [] (S.differing c)

let test_fetch_error () =
  match S.fetch ~ask:(fun _ -> Error "ERR no_ident") (Hashtbl.create 1) with
  | Error e -> Alcotest.(check string) "the reply" "ERR no_ident" e
  | Ok _ -> Alcotest.fail "expected an error"

let tests = [
  Alcotest.test_case "format 2 round trip" `Quick test_round_trip;
  Alcotest.test_case "48-bit hashes, format 1 read" `Quick test_hash48;
  Alcotest.test_case "fetch: up to date, summary only" `Quick test_fetch_up_to_date;
  Alcotest.test_case "fetch: only the differing groups" `Quick test_fetch_differing_groups;
  Alcotest.test_case "fetch: a format-1 node" `Quick test_fetch_old_node;
  Alcotest.test_case "fetch: no identity" `Quick test_fetch_error;
]
