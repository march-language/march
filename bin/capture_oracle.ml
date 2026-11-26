(* The capture soundness oracle (ocap phase 8a,
   specs/2026-11-11-ocap-capture-checking-design.md §18): test
   instrumentation, on only under MARCH_CAPTURE_ORACLE=1 in an interpreted
   run (test/run_captures.ml drives it).

   While a function value created at site S is running, every capability
   operation admitted, by it or by anything it calls or spawns, must be
   inside the grounded capture set of S.  A miss means a rule of the capture
   pass is unsound.  One line per miss and one summary line go to stderr.

   MARCH_CAPTURE_ORACLE_UNSOUND=drop_callee_effect|drop_arg_flow|narrow_values runs the
   pass with one rule deliberately removed, to show the oracle goes red. *)

module C = March_typecheck.Capture
module S = March_caps.Capture_set

let active () = Sys.getenv_opt "MARCH_CAPTURE_ORACLE" <> None

let install (env : March_typecheck.Typecheck.env) (decls : March_ast.Ast.decl list) : unit =
  let unsound =
    match Sys.getenv_opt "MARCH_CAPTURE_ORACLE_UNSOUND" with
    | Some "drop_callee_effect" -> Some `Drop_callee_effect
    | Some "drop_arg_flow" -> Some `Drop_arg_flow
    | Some "narrow_values" -> Some `Narrow_values
    | _ -> None
  in
  let r = March_typecheck.Typecheck.capture_analyse ?unsound ~all:(Sys.getenv_opt "MARCH_CAPTURE_ORACLE_ALL" <> None) env decls in
  (* One body can be several sites (an actor's `init` is walked at each
     spawn): every one of them is checked. *)
  let sites : (March_ast.Ast.span, C.site list) Hashtbl.t = Hashtbl.create 1024 in
  List.iter
    (fun (x : C.site) ->
       Hashtbl.replace sites x.C.s_key (x :: Option.value ~default:[] (Hashtbl.find_opt sites x.C.s_key)))
    r.C.sites;
  let cwd = Sys.getcwd () in
  let stack : C.site list list ref = ref [] in
  let by_actor : (int, C.site list list) Hashtbl.t = Hashtbl.create 16 in
  let calls = ref 0 and ops = ref 0 and checks = ref 0 and misses = ref 0 and tracked = ref 0 in
  let reported = Hashtbl.create 16 in
  let pos (sp : March_ast.Ast.span) =
    Printf.sprintf "%s:%d:%d" (Filename.basename sp.March_ast.Ast.file) sp.March_ast.Ast.start_line
      sp.March_ast.Ast.start_col
  in
  let layer_sets : (string, S.t) Hashtbl.t = Hashtbl.create 8 in
  let layer_set (text : string) : S.t =
    match Hashtbl.find_opt layer_sets text with
    | Some x -> x
    | None ->
      let x =
        match March_caps.Dep_grants.parse_scope_text text with
        | Ok entries -> S.of_entries entries
        | Error _ -> S.unknown
      in
      Hashtbl.replace layer_sets text x;
      x
  in
  let refused = ref 0 in
  let co_op kind target layers =
    incr ops;
    (* A refused operation is not performed: the static set bounds what a
       function value can do, not what it can try (design §10.1). *)
    if not (List.for_all (fun text -> S.admits (layer_set text) ~kind ~target ~cwd) layers) then incr refused
    else
    List.iter
      (fun (x : C.site) ->
         incr checks;
         if not (S.is_unknown x.C.s_ground) then incr tracked;
         if not (S.admits x.C.s_ground ~kind ~target ~cwd) then begin
           incr misses;
           let key = (x.C.s_key, kind) in
           if not (Hashtbl.mem reported key) then begin
             Hashtbl.replace reported key ();
             Printf.eprintf "[capture-oracle] MISS %s on %S is outside the set of the function value at %s: {%s}\n%!" kind
               target (pos x.C.s_span) (S.to_string x.C.s_ground)
           end
         end)
      (List.concat !stack)
  in
  let co_enter key =
    match Hashtbl.find_opt sites key with
    | Some xs ->
      incr calls;
      stack := xs :: !stack;
      true
    | None -> false
  in
  let co_leave () = match !stack with _ :: rest -> stack := rest | [] -> () in
  let co_spawned pid = Hashtbl.replace by_actor pid !stack in
  let co_actor : 'a. int -> (unit -> 'a) -> 'a =
    fun pid k ->
      let saved = !stack in
      stack := Option.value ~default:[] (Hashtbl.find_opt by_actor pid);
      Fun.protect ~finally:(fun () -> stack := saved) k
  in
  March_eval.Eval_prim.capture_oracle := Some { co_op; co_enter; co_leave; co_spawned; co_actor };
  at_exit (fun () ->
      if Sys.getenv_opt "MARCH_CAPTURE_ORACLE_SITES" <> None then
        List.iter
          (fun (x : C.site) ->
             if not (String.length x.C.s_span.March_ast.Ast.file > 0 && x.C.s_span.March_ast.Ast.file.[0] = '/') then
               Printf.eprintf "[capture-oracle] site %s ground {%s}\n" (pos x.C.s_span) (S.to_string x.C.s_ground))
          r.C.sites;
      Printf.eprintf "[capture-oracle] sites=%d calls=%d ops=%d refused=%d checks=%d tracked=%d misses=%d unknown_sites=%d\n%!"
        (List.length r.C.sites) !calls !ops !refused !checks !tracked !misses
        (List.length (List.filter (fun (x : C.site) -> S.is_unknown x.C.s_ground) r.C.sites)))
