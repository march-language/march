(** The two-stage discharge (specs/2026-10-29-refinement-reflection-design.md
    §4.4), around one obligation-filing check ([Refine_call.check_call],
    [Refine_post.check_post]).

    {1 The rule}

    Stage 1 is today's check, run exactly as before ([Reflect_state.arm_on]
    false): its records and diagnostics are what a compiler without reflection
    produced.  When every obligation it filed is proved, or it met no call of
    a reflected function ([Reflect_state.frontier_seen]), that is the answer.

    Otherwise its records and diagnostics are set aside and the check runs
    again as stage 2: the reflected-call arm translates, and every query gains
    the guarded unfoldings of its frontier ([Reflect_state.unfold_hook]).  The
    two runs file the same obligations in the same order (same keys); each
    pair is compared:
    - stage 1 proved: stage 1 stands (stage 2 can only add facts, and a
      stage-1 proof is kept whatever stage 2 says, so no proof is ever lost);
    - stage 1 skipped, stage 2 proved or violated: stage 2 is better;
    - stage 1 violated, stage 2 proved: a WITHDRAWN violation, unless the
      witness interpreter confirmed the stage-1 violation, in which case the
      unfoldings contradict a real run: [reflect_inconsistent] (I7), and the
      violation stays;
    - any pair where stage 2 is worse keeps stage 1 for the whole check.
    Stage 2's records replace stage 1's only when some pair is better and none
    is worse.  When stage 1 stands, a skip stage 2 could not improve takes the
    stage-2 reason [reflect-budget] or [reflect-fuel] when one applies (§3.9).

    Mutable state the check advances (fresh-name counters, "already hinted"
    flags, the promoted-site list) is saved before stage 1 through [savers]
    and restored around stage 2, so every LATER query keeps the exact text a
    compiler without reflection would send. *)

module Err = March_errors.Errors
module RS = Reflect_state

(** Each registered saver snapshots one cell and returns its restorer. *)
let savers : (unit -> unit -> unit) list ref = ref []

let register (f : unit -> unit -> unit) = savers := f :: !savers

let snapshot () : unit -> unit =
  let rs = List.map (fun f -> f ()) !savers in
  fun () -> List.iter (fun r -> r ()) rs

(** Test-only perturbation hooks (the RED controls of the progress note). *)
let disable_stage1 = ref (Sys.getenv_opt "MARCH_REFLECT_PERTURB" = Some "no-stage1")

type cmp = Same | Better | Worse | Inconsistent

let compare_v ~confirmed (v1 : Obligation.verdict) (v2 : Obligation.verdict) : cmp =
  let open Obligation in
  match v1, v2 with
  | Proved, Proved | Violated, Violated | Trusted, Trusted -> Same
  | Skipped _, Skipped _ | Skipped _, Trusted | Trusted, Skipped _ -> Same
  | Proved, _ -> Worse
  | (Skipped _ | Trusted), (Proved | Violated) -> Better
  | Violated, Proved -> if confirmed then Inconsistent else Better
  | Violated, (Skipped _ | Trusted) -> Worse

let key (o : Obligation.t) = (o.Obligation.span, o.Obligation.kind, o.Obligation.callee, o.Obligation.predicate)

let two_stage ?(ok : ('a -> bool) option) ~(errctx : Err.ctx) (run : unit -> 'a) : 'a =
  if (not !RS.active) || !RS.arm_on then run ()
  else begin
    let saved_log = !Obligation.log in
    let saved_diags = errctx.Err.diagnostics in
    let restore0 = snapshot () in
    let seen0 = !RS.frontier_seen and conf0 = !RS.confirmed in
    RS.frontier_seen := false;
    RS.confirmed := false;
    let r1 = run () in
    let seen = !RS.frontier_seen and confirmed = !RS.confirmed in
    RS.frontier_seen := seen0 || seen;
    RS.confirmed := conf0;
    let o1 = Obligation.rollback_to saved_log in
    let d1 = errctx.Err.diagnostics in
    let replay_stage1 ?(override = fun (o : Obligation.t) -> o) () =
      March_refine.Refine.last_core := [];
      List.iter (fun o -> Obligation.record (override o)) o1;
      errctx.Err.diagnostics <- d1
    in
    let all_proved =
      if o1 = [] then (match ok with Some f -> f r1 | None -> true)
      else List.for_all (fun (o : Obligation.t) -> o.Obligation.verdict = Obligation.Proved) o1
    in
    if (all_proved && not !disable_stage1) || not seen then begin
      replay_stage1 ();
      r1
    end
    else begin
      let restore1 = snapshot () in
      errctx.Err.diagnostics <- saved_diags;
      restore0 ();
      incr RS.stage2_runs;
      RS.arm_on := true;
      RS.budget_hit := false;
      RS.fuel_pending := false;
      RS.fuel_fn := "";
      Hashtbl.reset RS.literal_owner;
      let r2 =
        Fun.protect ~finally:(fun () -> RS.arm_on := false) (fun () -> run ())
      in
      let budget = !RS.budget_hit and fuel = !RS.fuel_pending in
      let frontier_names =
        Hashtbl.fold (fun _ n acc -> n :: acc) RS.literal_owner [] |> List.sort_uniq compare
      in
      let o2 = Obligation.rollback_to saved_log in
      March_refine.Refine.last_core := [];
      let d2 = errctx.Err.diagnostics in
      let pairs =
        if List.length o1 = List.length o2 && List.for_all2 (fun a b -> key a = key b) o1 o2 then
          Some (List.combine o1 o2)
        else None
      in
      let verdicts =
        match pairs with
        | None -> []
        | Some ps ->
          List.map
            (fun ((a : Obligation.t), (b : Obligation.t)) ->
              let v1 = if !disable_stage1 then Obligation.Skipped Obligation.Solver_undecided else a.Obligation.verdict in
              (a, b, compare_v ~confirmed v1 b.Obligation.verdict))
            ps
      in
      if Sys.getenv_opt "MARCH_REFLECT_DEBUG" = Some "2" then begin
        let show (o : Obligation.t) =
          Printf.sprintf "%s:%d:%d %s %s" o.Obligation.span.March_ast.Ast.file o.Obligation.span.March_ast.Ast.start_line
            o.Obligation.span.March_ast.Ast.start_col o.Obligation.predicate
            (match o.Obligation.verdict with
             | Obligation.Skipped r -> "skip:" ^ Obligation.reason_name r
             | v -> Obligation.verdict_name v)
        in
        Printf.eprintf "reflect-stage: s1=[%s] s2=[%s]\n%!" (String.concat "; " (List.map show o1))
          (String.concat "; " (List.map show o2))
      end;
      let inconsistent = List.filter (fun (_, _, c) -> c = Inconsistent) verdicts in
      (* A run that filed nothing (a pre-pass) is judged by its answer. *)
      let answer_better =
        o1 = [] && o2 = [] && match ok with Some f -> f r2 && not (f r1) | None -> false
      in
      let better = answer_better || List.exists (fun (_, _, c) -> c = Better) verdicts in
      let worse = List.exists (fun (_, _, c) -> c = Worse) verdicts in
      if inconsistent = [] && better && not worse then begin
        (* Stage 2 stands. *)
        List.iter
          (fun (o : Obligation.t) ->
            Obligation.record o;
            if o.Obligation.verdict = Obligation.Proved && Obligation.uses_of o = [] then
              Obligation.set_uses o frontier_names)
          o2;
        (* The `uses:` each proof recorded during the run are kept
           ([rollback_to] leaves them); a proof whose core named no
           unfolding (congruence alone, I8) lists the frontier. *)
        errctx.Err.diagnostics <- d2;
        restore1 ();
        r2
      end
      else begin
        errctx.Err.diagnostics <- saved_diags;
        List.iter
          (fun ((a : Obligation.t), _, _) ->
            Err.error ~code:Err.Code.reflect_inconsistent errctx ~span:a.Obligation.span
              (Printf.sprintf
                 "internal error: reflection proved `%s` at a call whose violation the interpreter \
                  confirmed; the logic definition of a reflected function disagrees with the \
                  program. This is a compiler bug; please report it."
                 a.Obligation.predicate))
          inconsistent;
        let d_inc = errctx.Err.diagnostics in
        restore1 ();
        List.iter (fun (o : Obligation.t) -> Hashtbl.remove Obligation.uses_tbl (Obligation.uses_key o)) o2;
        let override (o : Obligation.t) =
          match o.Obligation.verdict with
          | Obligation.Skipped _ when budget -> { o with Obligation.verdict = Obligation.Skipped Obligation.Reflect_budget }
          | Obligation.Skipped _ when fuel ->
            let f = if !RS.fuel_fn <> "" then !RS.fuel_fn else match frontier_names with f :: _ -> f | [] -> "a reflected function" in
            { o with Obligation.verdict = Obligation.Skipped (Obligation.Reflect_fuel f) }
          | _ -> o
        in
        March_refine.Refine.last_core := [];
        List.iter (fun o -> Obligation.record (override o)) o1;
        errctx.Err.diagnostics <- (List.filter (fun d -> not (List.memq d saved_diags)) d_inc) @ d1;
        r1
      end
    end
  end
