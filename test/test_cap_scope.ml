(* Path scope algebra (lib/caps/cap_scope.ml).

   Pure functions, so these are the cheap tests that must catch the subtle
   cases before anything downstream trusts them: a `..` escape, a raw-prefix
   near-miss, and the subsumption direction (which has been gotten backwards
   twice already in the sandbox work). *)

module S = March_caps.Cap_scope

let test_normalize () =
  Alcotest.(check string) "collapses //" "/etc/ssl" (S.normalize "/etc//ssl");
  Alcotest.(check string) "strips trailing /" "/etc/ssl"
    (S.normalize "/etc/ssl/");
  Alcotest.(check string) "resolves ." "/etc/ssl" (S.normalize "/etc/./ssl");
  Alcotest.(check string) "resolves .." "/shadow"
    (S.normalize "/etc/ssl/../../shadow");
  Alcotest.(check string) "root stays root" "/" (S.normalize "/");
  (* ".." at the root drops rather than escaping above it, matching how the
     kernel resolves "/..". *)
  Alcotest.(check string) ".. at root does not escape" "/etc"
    (S.normalize "/../etc")

let test_within_basic () =
  Alcotest.(check bool) "scope contains itself" true
    (S.within ~scope:"/etc/ssl" "/etc/ssl");
  Alcotest.(check bool) "scope contains a descendant" true
    (S.within ~scope:"/etc" "/etc/ssl/cert.pem");
  Alcotest.(check bool) "scope does not contain an ancestor" false
    (S.within ~scope:"/etc/ssl" "/etc");
  Alcotest.(check bool) "unrelated path" false
    (S.within ~scope:"/etc" "/var/log/x")

let test_within_is_segmentwise () =
  (* The near-miss that a raw string-prefix test would wrongly accept, and the
     reason this compares whole segments. *)
  Alcotest.(check bool) "/etcpasswd is NOT within /etc" false
    (S.within ~scope:"/etc" "/etcpasswd");
  Alcotest.(check bool) "/etc-backup is NOT within /etc" false
    (S.within ~scope:"/etc" "/etc-backup")

let test_within_normalizes_first () =
  (* Without normalization this escapes the scope, which is the whole point of
     normalizing before comparing. *)
  Alcotest.(check bool) "..-escape is not within the scope" false
    (S.within ~scope:"/etc/ssl" "/etc/ssl/../shadow");
  Alcotest.(check bool) "..-that-stays-inside is within" true
    (S.within ~scope:"/etc" "/etc/ssl/../hosts");
  Alcotest.(check bool) "redundant separators still match" true
    (S.within ~scope:"/etc" "/etc//ssl/./cert.pem")

let test_absolute_vs_relative () =
  Alcotest.(check bool) "absolute is absolute" true (S.is_absolute "/etc");
  Alcotest.(check bool) "relative is not" false (S.is_absolute "etc");
  (* Mixing them would compare unrelated roots. *)
  Alcotest.(check bool) "relative path not within absolute scope" false
    (S.within ~scope:"/etc" "etc/ssl")

let test_scope_subsumption_both_directions () =
  (* Unscoped permits everything, including other unscoped. *)
  Alcotest.(check bool) "None subsumes a scope" true
    (S.scope_subsumes None (Some "/etc"));
  Alcotest.(check bool) "None subsumes None" true (S.scope_subsumes None None);
  (* And a scope NEVER subsumes unscoped: narrowing grants strictly less.
     Getting this backwards would let a scoped declaration silently satisfy a
     requirement for unrestricted access. *)
  Alcotest.(check bool) "a scope does NOT subsume None" false
    (S.scope_subsumes (Some "/etc") None);
  Alcotest.(check bool) "broader scope subsumes narrower" true
    (S.scope_subsumes (Some "/etc") (Some "/etc/ssl"));
  Alcotest.(check bool) "narrower does NOT subsume broader" false
    (S.scope_subsumes (Some "/etc/ssl") (Some "/etc"));
  Alcotest.(check bool) "siblings do not subsume" false
    (S.scope_subsumes (Some "/etc") (Some "/var"))

let test_is_scopable () =
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is scopable" c)
        true (S.is_scopable c))
    [ "IO.FileRead"; "IO.FileWrite"; "IO.FileSystem" ];
  (* A scope on a non-filesystem capability is rejected by the caller rather
     than ignored — an ignored scope reads as enforcement that is not there. *)
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is NOT scopable" c)
        false (S.is_scopable c))
    [ "IO.Network"; "IO.Console"; "IO.Process"; "IO" ]

let tests =
  [
    Alcotest.test_case "normalize" `Quick test_normalize;
    Alcotest.test_case "within: basic containment" `Quick test_within_basic;
    Alcotest.test_case "within: segment-wise, not raw prefix" `Quick
      test_within_is_segmentwise;
    Alcotest.test_case "within: normalizes before comparing" `Quick
      test_within_normalizes_first;
    Alcotest.test_case "absolute vs relative" `Quick test_absolute_vs_relative;
    Alcotest.test_case "scope subsumption in both directions" `Quick
      test_scope_subsumption_both_directions;
    Alcotest.test_case "only filesystem caps are scopable" `Quick
      test_is_scopable;
  ]
