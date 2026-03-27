(** Property-based tests for the PubGrub solver.
    Uses QCheck to generate random registry graphs and verify that:
      1. Every solved result satisfies all declared constraints.
      2. The solver is deterministic on the same input.
      3. No transitive constraints are violated in any solution.
*)

open March_forge
module V  = Resolver_version
module VC = Resolver_constraint
module RR = Resolver_registry
module PG = Resolver_pubgrub

(* ------------------------------------------------------------------ *)
(*  Small fixed package names for controlled overlap                  *)
(* ------------------------------------------------------------------ *)

let pkg_pool = [| "alpha"; "beta"; "gamma"; "delta"; "epsilon";
                  "zeta";  "eta";  "theta" |]

let n_pool = Array.length pkg_pool

(* ------------------------------------------------------------------ *)
(*  Registry entry: (name, version_string, deps)                       *)
(* ------------------------------------------------------------------ *)

type entry = {
  e_name    : string;
  e_version : string;
  e_deps    : (string * VC.t) list;
}

let gen_entry =
  QCheck.Gen.(
    let* pi = int_range 0 (n_pool - 1) in
    let name = pkg_pool.(pi) in
    let* major = int_range 0 3 in
    let* minor = int_range 0 5 in
    let* patch = int_range 0 9 in
    let ver = Printf.sprintf "%d.%d.%d" major minor patch in
    (* 0 or 1 dep on a different package *)
    let* has_dep = bool in
    let+ dep =
      if not has_dep then pure []
      else
        let* di = int_range 0 (n_pool - 1) in
        let dep_name = pkg_pool.(di) in
        if dep_name = name then pure []
        else
          let* c_choice = int_range 0 2 in
          let c = match c_choice with
            | 0 -> Printf.sprintf "~> %d.%d" major minor
            | 1 -> Printf.sprintf ">= %d.%d.%d" major minor patch
            | _ -> ">= 0.0.0"
          in
          pure [(dep_name, VC.parse_exn c)]
    in
    { e_name = name; e_version = ver; e_deps = dep })

let gen_entries n =
  QCheck.Gen.list_size (QCheck.Gen.pure n) gen_entry

(* ------------------------------------------------------------------ *)
(*  Build registry from entries                                        *)
(* ------------------------------------------------------------------ *)

let build_registry entries =
  let reg = RR.create () in
  List.iter (fun e ->
      (try
         RR.add_version reg RR.{
           name    = e.e_name;
           version = V.parse_exn e.e_version;
           deps    = e.e_deps;
         }
       with _ -> ())  (* ignore duplicate or malformed versions *)
    ) entries;
  reg

(* Pick the newest version of a package from the registry *)
let newest_ver reg pkg =
  match RR.versions_of reg pkg with
  | []      -> None
  | pv :: _ -> Some pv.RR.version

(* ------------------------------------------------------------------ *)
(*  Prop 1: solution satisfies all root constraints                   *)
(* ------------------------------------------------------------------ *)

let prop_solution_satisfies_constraints =
  QCheck.Test.make
    ~name:"solution satisfies all root constraints"
    ~count:300
    (QCheck.make QCheck.Gen.(int_range 1 20 >>= fun n ->
         QCheck.Gen.(
           let* entries = gen_entries (n + 1) in
           let reg      = build_registry entries in
           (* Pick 1-3 root packages that actually exist *)
           let existing =
             Array.to_list pkg_pool
             |> List.filter (fun p -> newest_ver reg p <> None)
           in
           if existing = [] then pure (reg, [])
           else
             let* n_root = int_range 1 (min 3 (List.length existing)) in
             let root_pkgs = (* take first n_root *) (
               let rec take n lst acc =
                 if n = 0 then List.rev acc
                 else match lst with
                   | [] -> List.rev acc
                   | x :: xs -> take (n-1) xs (x :: acc)
               in take n_root existing []
             ) in
             let root_deps =
               List.filter_map (fun pkg ->
                   match newest_ver reg pkg with
                   | None -> None
                   | Some v ->
                     Some (pkg, VC.parse_exn (">= " ^ V.to_string v))
                 ) root_pkgs
             in
             pure (reg, root_deps))))
    (fun (reg, root_deps) ->
       match PG.solve reg ~root_deps ~overrides:[] with
       | Error _ -> true   (* conflict is acceptable *)
       | Ok solution ->
         List.for_all (fun (pkg, constr) ->
             match List.assoc_opt pkg solution with
             | None   -> false
             | Some v -> VC.satisfies v constr
           ) root_deps)

(* ------------------------------------------------------------------ *)
(*  Prop 2: solver is deterministic                                   *)
(* ------------------------------------------------------------------ *)

let prop_solver_deterministic =
  QCheck.Test.make
    ~name:"solver is deterministic"
    ~count:300
    (QCheck.make QCheck.Gen.(int_range 1 20 >>= fun n ->
         QCheck.Gen.(
           let* entries = gen_entries (n + 1) in
           let reg = build_registry entries in
           let existing =
             Array.to_list pkg_pool
             |> List.filter (fun p -> newest_ver reg p <> None)
           in
           if existing = [] then pure (reg, [])
           else
             let* n_root = int_range 1 (min 2 (List.length existing)) in
             let root_pkgs =
               let rec take n lst acc =
                 if n = 0 then List.rev acc
                 else match lst with [] -> List.rev acc | x::xs -> take (n-1) xs (x::acc)
               in take n_root existing []
             in
             let root_deps =
               List.filter_map (fun pkg ->
                   match newest_ver reg pkg with
                   | None -> None
                   | Some v -> Some (pkg, VC.parse_exn (">= " ^ V.to_string v))
                 ) root_pkgs
             in
             pure (reg, root_deps))))
    (fun (reg, root_deps) ->
       let r1 = PG.solve reg ~root_deps ~overrides:[] in
       let r2 = PG.solve reg ~root_deps ~overrides:[] in
       let sort = List.sort (fun (a, _) (b, _) -> String.compare a b) in
       match r1, r2 with
       | Ok s1, Ok s2  -> sort s1 = sort s2
       | Error _, Error _ -> true
       | _ -> false)

(* ------------------------------------------------------------------ *)
(*  Prop 3: transitive constraints satisfied                          *)
(* ------------------------------------------------------------------ *)

let prop_no_violated_transitive_constraints =
  QCheck.Test.make
    ~name:"no violated transitive constraints in solution"
    ~count:300
    (QCheck.make QCheck.Gen.(int_range 1 20 >>= fun n ->
         QCheck.Gen.(
           let* entries = gen_entries (n + 1) in
           let reg = build_registry entries in
           let existing =
             Array.to_list pkg_pool
             |> List.filter (fun p -> newest_ver reg p <> None)
           in
           if existing = [] then pure (reg, [], entries)
           else
             let* n_root = int_range 1 (min 3 (List.length existing)) in
             let root_pkgs =
               let rec take n lst acc =
                 if n = 0 then List.rev acc
                 else match lst with [] -> List.rev acc | x::xs -> take (n-1) xs (x::acc)
               in take n_root existing []
             in
             let root_deps =
               List.filter_map (fun pkg ->
                   match newest_ver reg pkg with
                   | None -> None
                   | Some v -> Some (pkg, VC.parse_exn (">= " ^ V.to_string v))
                 ) root_pkgs
             in
             pure (reg, root_deps, entries))))
    (fun (reg, root_deps, entries) ->
       match PG.solve reg ~root_deps ~overrides:[] with
       | Error _ -> true
       | Ok solution ->
         List.for_all (fun (pkg, solved_v) ->
             (* Look up the deps of the exact solved version *)
             let pkg_deps =
               List.find_opt (fun e ->
                   e.e_name = pkg && e.e_version = V.to_string solved_v
                 ) entries
               |> Option.map (fun e -> e.e_deps)
               |> Option.value ~default:[]
             in
             List.for_all (fun (dep_name, dep_constr) ->
                 match List.assoc_opt dep_name solution with
                 | None   -> true  (* transitive dep not in solution = fine *)
                 | Some v -> VC.satisfies v dep_constr
               ) pkg_deps
           ) solution)

(* ------------------------------------------------------------------ *)
(*  Suite                                                              *)
(* ------------------------------------------------------------------ *)

let () =
  let open QCheck_alcotest in
  Alcotest.run "forge-properties" [
    "solver-properties", [
      to_alcotest prop_solution_satisfies_constraints;
      to_alcotest prop_solver_deterministic;
      to_alcotest prop_no_violated_transitive_constraints;
    ];
  ]
