(* ocap phase 8a, Task 1 (specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md):
   the scope-set algebra capture inference solves over. *)

module S = March_caps.Capture_set

let sc ?arg kind = { S.kind; arg }
let set l = S.of_scopes l
let str = Alcotest.(check string)
let yes msg b = Alcotest.(check bool) msg true b
let no msg b = Alcotest.(check bool) msg false b

let read_data = sc ~arg:"./data/" "IO.FileRead"
let read_in = sc ~arg:"./data/in/" "IO.FileRead"
let read_other = sc ~arg:"./other/" "IO.FileRead"

let test_union_drops_covered () =
  str "scoped under unscoped" "IO.FileRead" (S.to_string (S.union (set [ read_data ]) (set [ sc "IO.FileRead" ])));
  str "kind under root" "IO" (S.to_string (S.union (set [ sc "IO.Console" ]) S.full));
  str "narrower path under wider" "IO.FileRead(\"./data/\")"
    (S.to_string (S.union (set [ read_in ]) (set [ read_data ])));
  str "empty" "" (S.to_string (S.union S.empty S.empty));
  yes "unknown absorbs" (S.is_unknown (S.union S.unknown S.full))

let test_union_keeps_unrelated () =
  str "two hosts" "IO.NetConnect(\"a.example.com\"), IO.NetConnect(\"b.example.com\")"
    (S.to_string
       (S.union (set [ sc ~arg:"a.example.com" "IO.NetConnect" ]) (set [ sc ~arg:"b.example.com" "IO.NetConnect" ])));
  str "two kinds" "IO.Console, IO.FileRead(\"./data/\")"
    (S.to_string (S.union (set [ read_data ]) (set [ sc "IO.Console" ])))

let test_covers () =
  yes "IO covers a scope" (S.covers ~sup:S.full (set [ read_data; sc "IO.Console" ]));
  no "IO does not cover unknown" (S.covers ~sup:S.full S.unknown);
  yes "unknown covers unknown" (S.covers ~sup:S.unknown S.unknown);
  yes "unknown covers IO" (S.covers ~sup:S.unknown S.full);
  yes "ancestor kind" (S.covers ~sup:(set [ sc "IO.FileSystem" ]) (set [ sc ~arg:"./x/" "IO.FileRead" ]));
  yes "path prefix" (S.covers ~sup:(set [ read_data ]) (set [ read_in ]));
  no "other path" (S.covers ~sup:(set [ read_data ]) (set [ read_other ]));
  no "scoped does not cover unscoped" (S.covers ~sup:(set [ read_data ]) (set [ sc "IO.FileRead" ]));
  no "sibling kind" (S.covers ~sup:(set [ sc "IO.Console" ]) (set [ sc "IO.Clock" ]));
  yes "host with path prefix"
    (S.covers ~sup:(set [ sc ~arg:"api.x.com" "IO.NetConnect" ]) (set [ sc ~arg:"api.x.com/v1/" "IO.NetConnect" ]));
  no "host path the other way"
    (S.covers ~sup:(set [ sc ~arg:"api.x.com/v1/" "IO.NetConnect" ]) (set [ sc ~arg:"api.x.com" "IO.NetConnect" ]));
  yes "name scope" (S.covers ~sup:(set [ sc ~arg:"a;name=b" "IO.Mut" ]) (set [ sc ~arg:"b" "IO.Mut" ]));
  yes "empty is covered by empty" (S.covers ~sup:S.empty S.empty)

let test_narrow () =
  str "covered element is kept" "IO.FileRead(\"./data/in/\")"
    (S.to_string (S.narrow (set [ read_in ]) ~by:(set [ read_data ])));
  str "unscoped takes the scope beneath it" "IO.FileRead(\"./data/\")"
    (S.to_string (S.narrow (set [ sc "IO.FileRead" ]) ~by:(set [ read_data ])));
  str "ancestor kind takes the entries beneath it" "IO.FileRead(\"./data/\")"
    (S.to_string (S.narrow (set [ sc "IO.FileSystem" ]) ~by:(set [ read_data ])));
  str "unscoped under a scoped ancestor takes its scope" "IO.FileRead(\"/srv\")"
    (S.to_string (S.narrow (set [ sc "IO.FileRead" ]) ~by:(set [ sc ~arg:"/srv" "IO.FileSystem" ])));
  str "unrelated is dropped" "" (S.to_string (S.narrow (set [ sc "IO.Console" ]) ~by:(set [ sc "IO.FileRead" ])));
  str "two scoped lists of one kind: kept whole" "IO.FileRead(\"./other/\")"
    (S.to_string (S.narrow (set [ read_other ]) ~by:(set [ read_data ])));
  str "by full" "IO.Console" (S.to_string (S.narrow (set [ sc "IO.Console" ]) ~by:S.full));
  str "by empty" "" (S.to_string (S.narrow (set [ sc "IO.Console" ]) ~by:S.empty));
  yes "unknown stays" (S.is_unknown (S.narrow S.unknown ~by:S.empty));
  str "by unknown" "IO.Console" (S.to_string (S.narrow (set [ sc "IO.Console" ]) ~by:S.unknown))

(* Whatever both sides cover, the narrowing covers. *)
let test_narrow_is_upper_bound () =
  let pool =
    [| sc "IO"; sc "IO.Console"; sc "IO.Clock"; sc "IO.FileSystem"; sc "IO.FileRead"; read_data; read_in;
       read_other; sc ~arg:"/srv" "IO.FileSystem"; sc "IO.NetConnect"; sc ~arg:"api.x.com" "IO.NetConnect";
       sc ~arg:"api.x.com/v1/" "IO.NetConnect" |]
  in
  let st = Random.State.make [| 8 |] in
  let pick () =
    set (List.init (1 + Random.State.int st 3) (fun _ -> pool.(Random.State.int st (Array.length pool))))
  in
  for _ = 1 to 500 do
    let e = pick () and by = pick () in
    let n = S.narrow e ~by in
    Array.iter
      (fun p ->
         let p = set [ p ] in
         if S.covers ~sup:e p && S.covers ~sup:by p && not (S.covers ~sup:n p) then
           Alcotest.failf "narrow {%s} by {%s} = {%s} loses %s" (S.to_string e) (S.to_string by) (S.to_string n)
             (S.to_string p))
      pool
  done

let tests =
  [ ( "capture_set",
      [ Alcotest.test_case "union drops covered" `Quick test_union_drops_covered;
        Alcotest.test_case "union keeps unrelated scopes" `Quick test_union_keeps_unrelated;
        Alcotest.test_case "covers" `Quick test_covers;
        Alcotest.test_case "narrow" `Quick test_narrow;
        Alcotest.test_case "narrow is an upper bound" `Quick test_narrow_is_upper_bound ] ) ]
