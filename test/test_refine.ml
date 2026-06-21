let smoke_suite =
  [ Alcotest.test_case "library links" `Quick (fun () ->
        Alcotest.(check string) "version" "a0" March_refine.Smt.version) ]

let () = Alcotest.run "march-refine" [ ("smoke", smoke_suite) ]
