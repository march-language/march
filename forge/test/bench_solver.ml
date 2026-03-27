(** Solver performance benchmarks.

    Generates synthetic registries of varying sizes and measures how long
    the PubGrub solver takes to resolve them.  Run with:

        dune exec forge/test/bench_solver.exe

    Thresholds from specs/plans/forge-dependency-resolution-plan.md §10.10:
      - 100 packages: < 100 ms
      - 500 packages: < 1 s
*)

open March_forge
module V  = Resolver_version
module VC = Resolver_constraint
module RR = Resolver_registry
module PG = Resolver_pubgrub

(* ------------------------------------------------------------------ *)
(*  Registry builder                                                   *)
(* ------------------------------------------------------------------ *)

(** Build a synthetic registry with [n_pkgs] packages.
    Each package has 3 versions: 1.0.0, 1.1.0, 2.0.0.
    Each version depends on the next package in a chain (modulo n_pkgs)
    with a ~> 1.0 constraint, ensuring a solvable graph. *)
let build_chain_registry n_pkgs =
  let reg = RR.create () in
  for i = 0 to n_pkgs - 1 do
    let name = Printf.sprintf "pkg%04d" i in
    let next = Printf.sprintf "pkg%04d" ((i + 1) mod n_pkgs) in
    (* Three versions — oldest has no deps to avoid circularity on the chain *)
    RR.add_version reg RR.{
      name; version = V.parse_exn "1.0.0";
      deps = if i < n_pkgs - 1 then [(next, VC.parse_exn "~> 1.0")] else []
    };
    RR.add_version reg RR.{
      name; version = V.parse_exn "1.1.0";
      deps = if i < n_pkgs - 1 then [(next, VC.parse_exn "~> 1.0")] else []
    };
    RR.add_version reg RR.{
      name; version = V.parse_exn "2.0.0";
      deps = if i < n_pkgs - 1 then [(next, VC.parse_exn "~> 1.0")] else []
    };
  done;
  reg

(** Build a diamond registry: [width] packages all depending on a single
    shared package, with [depth] layers of transitive deps. *)
let build_diamond_registry ~width ~depth =
  let reg = RR.create () in
  (* Shared leaf at depth 0 *)
  RR.add_version reg RR.{
    name = "leaf"; version = V.parse_exn "1.0.0"; deps = []
  };
  (* depth layers of width-wide dependencies *)
  for d = 0 to depth - 1 do
    for w = 0 to width - 1 do
      let name = Printf.sprintf "layer%d_pkg%d" d w in
      let dep  = if d = 0 then "leaf"
                 else Printf.sprintf "layer%d_pkg%d" (d - 1) w in
      List.iter (fun ver ->
          RR.add_version reg RR.{
            name; version = V.parse_exn ver;
            deps = [(dep, VC.parse_exn "~> 1.0")]
          }
        ) ["1.0.0"; "1.1.0"; "2.0.0"]
    done
  done;
  reg

(* ------------------------------------------------------------------ *)
(*  Timing                                                             *)
(* ------------------------------------------------------------------ *)

let time_solve reg root_deps label threshold_ms =
  let root = List.map (fun (n, c) -> (n, VC.parse_exn c)) root_deps in
  let t0   = Unix.gettimeofday () in
  let result = PG.solve reg ~root_deps:root ~overrides:[] in
  let t1   = Unix.gettimeofday () in
  let ms   = (t1 -. t0) *. 1000.0 in
  let ok   = match result with Ok _ -> true | Error _ -> false in
  Printf.printf "  %-50s %6.1f ms  [%s]  [%s]\n%!"
    label ms
    (if ok then "solved" else "conflict")
    (if ms < float_of_int threshold_ms then "PASS" else "FAIL");
  ms < float_of_int threshold_ms

(* ------------------------------------------------------------------ *)
(*  Benchmark suite                                                    *)
(* ------------------------------------------------------------------ *)

let () =
  Printf.printf "\nforge solver benchmarks\n";
  Printf.printf "=======================\n\n";

  let all_pass = ref true in

  (* Chain: 100 packages *)
  let reg100 = build_chain_registry 100 in
  let root100 = [("pkg0000", "~> 1.0")] in
  if not (time_solve reg100 root100 "chain-100: 100-pkg linear chain" 100) then
    all_pass := false;

  (* Chain: 500 packages *)
  let reg500 = build_chain_registry 500 in
  let root500 = [("pkg0000", "~> 1.0")] in
  if not (time_solve reg500 root500 "chain-500: 500-pkg linear chain" 1000) then
    all_pass := false;

  (* Diamond: 10 wide, 10 deep *)
  let reg_d10 = build_diamond_registry ~width:10 ~depth:10 in
  let root_d10 = List.init 10 (fun w ->
      (Printf.sprintf "layer9_pkg%d" w, "~> 1.0")) in
  if not (time_solve reg_d10 root_d10 "diamond-10x10: 10-wide 10-deep" 100) then
    all_pass := false;

  (* Diamond: 20 wide, 20 deep *)
  let reg_d20 = build_diamond_registry ~width:20 ~depth:20 in
  let root_d20 = List.init 20 (fun w ->
      (Printf.sprintf "layer19_pkg%d" w, "~> 1.0")) in
  if not (time_solve reg_d20 root_d20 "diamond-20x20: 20-wide 20-deep" 500) then
    all_pass := false;

  Printf.printf "\n";
  if !all_pass then
    (Printf.printf "All benchmarks within thresholds.\n%!"; exit 0)
  else
    (Printf.printf "One or more benchmarks exceeded thresholds.\n%!"; exit 1)
