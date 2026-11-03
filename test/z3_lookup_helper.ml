(* Prints this executable's own z3 lookup as `source:path`, so
   test_z3_lookup can copy it into a release-shaped install and check the
   exe-relative lookup from outside. *)
let () =
  match March_refine.Solver.find_z3 () with
  | Ok (p, March_refine.Solver.Env) -> print_endline ("env:" ^ p)
  | Ok (p, March_refine.Solver.Bundled) -> print_endline ("bundled:" ^ p)
  | Ok (p, March_refine.Solver.Path) -> print_endline ("path:" ^ p)
  | Error e -> print_endline ("error:" ^ e)
