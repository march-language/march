open March_caps

let subsumption_suite =
  [ Alcotest.test_case "root subsumes deep descendant" `Quick (fun () ->
        Alcotest.(check bool) "IO subsumes IO.NetConnect.TLS"
          true (Cap_lattice.cap_subsumes "IO" "IO.NetConnect.TLS"));

    Alcotest.test_case "mid-level subsumes its own child" `Quick (fun () ->
        Alcotest.(check bool) "IO.FileSystem subsumes IO.FileRead"
          true (Cap_lattice.cap_subsumes "IO.FileSystem" "IO.FileRead"));

    Alcotest.test_case "cap subsumes itself" `Quick (fun () ->
        Alcotest.(check bool) "IO.FileRead subsumes IO.FileRead"
          true (Cap_lattice.cap_subsumes "IO.FileRead" "IO.FileRead"));

    Alcotest.test_case "child does not subsume its parent" `Quick (fun () ->
        Alcotest.(check bool) "IO.FileRead does not subsume IO"
          false (Cap_lattice.cap_subsumes "IO.FileRead" "IO"));

    Alcotest.test_case "root cap (IO) has no parent" `Quick (fun () ->
        Alcotest.(check (list string)) "ancestors of IO"
          ["IO"] (Cap_lattice.cap_ancestors "IO"));

    Alcotest.test_case "sibling caps neither subsumes the other" `Quick (fun () ->
        Alcotest.(check bool) "IO.FileRead does not subsume IO.FileWrite"
          false (Cap_lattice.cap_subsumes "IO.FileRead" "IO.FileWrite");
        Alcotest.(check bool) "IO.FileWrite does not subsume IO.FileRead"
          false (Cap_lattice.cap_subsumes "IO.FileWrite" "IO.FileRead"));

    Alcotest.test_case "unrelated top-level roots don't subsume each other" `Quick (fun () ->
        Alcotest.(check bool) "IO.Clock does not subsume IO.Random"
          false (Cap_lattice.cap_subsumes "IO.Clock" "IO.Random"));

    Alcotest.test_case "FFI cap not in the table is its own root" `Quick (fun () ->
        Alcotest.(check (list string)) "ancestors of LibC"
          ["LibC"] (Cap_lattice.cap_ancestors "LibC");
        Alcotest.(check bool) "LibC subsumes LibC"
          true (Cap_lattice.cap_subsumes "LibC" "LibC");
        Alcotest.(check bool) "LibC does not subsume IO"
          false (Cap_lattice.cap_subsumes "LibC" "IO"));
  ]

let normalize_suite =
  [ Alcotest.test_case "drops a cap subsumed by a broader one already present" `Quick (fun () ->
        Alcotest.(check (list string)) "IO subsumes IO.FileRead"
          ["IO"] (Cap_lattice.normalize ["IO"; "IO.FileRead"]));

    Alcotest.test_case "order of input does not matter" `Quick (fun () ->
        Alcotest.(check (list string)) "IO.FileRead first, IO second"
          ["IO"] (Cap_lattice.normalize ["IO.FileRead"; "IO"]));

    Alcotest.test_case "keeps sibling caps that don't subsume each other" `Quick (fun () ->
        Alcotest.(check (list string)) "FileRead and FileWrite both kept"
          ["IO.FileRead"; "IO.FileWrite"]
          (Cap_lattice.normalize ["IO.FileRead"; "IO.FileWrite"]));

    Alcotest.test_case "transitively subsumed cap is dropped" `Quick (fun () ->
        Alcotest.(check (list string)) "IO subsumes IO.NetConnect.TLS via IO.Network/IO.NetConnect"
          ["IO"] (Cap_lattice.normalize ["IO"; "IO.NetConnect.TLS"]));

    Alcotest.test_case "empty list stays empty" `Quick (fun () ->
        Alcotest.(check (list string)) "empty" [] (Cap_lattice.normalize []));
  ]

let () =
  Alcotest.run "march_caps"
    [ "subsumption", subsumption_suite;
      "normalize", normalize_suite ]
