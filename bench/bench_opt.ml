(** Benchmark for TIR optimization passes.

    Constructs a synthetic TIR module with ~N functions, each containing a mix of:
      - constant arithmetic to fold (1+1, 2*3, etc.)
      - dead let bindings to eliminate
      - identity/zero algebraic patterns to simplify
      - small pure functions eligible for inlining

    Reports: node count before/after, nodes eliminated, time per pass,
    and wall time for the full fixed-point loop. *)

(* ── TIR helpers ──────────────────────────────────────────────────────── *)

open March_tir.Tir

let mk_var name ty = { v_name = name; v_ty = ty; v_lin = Unr }
let ivar name      = AVar (mk_var name TInt)
let ilit n         = ALit (March_ast.Ast.LitInt n)
let flit f         = ALit (March_ast.Ast.LitFloat f)
let fvar name      = AVar (mk_var name TFloat)
let op name args   = EApp (mk_var name (TFn ([], TInt)), args)
let fop name args  = EApp (mk_var name (TFn ([], TFloat)), args)

(** Count all TIR expression nodes recursively. *)
let rec node_count : expr -> int = function
  | EAtom _ | ETuple _ | ERecord _ | EField _ | EUpdate _
  | EAlloc _ | EStackAlloc _ | EIncRC _ | EDecRC _ | EFree _ | EReuse _ -> 1
  | EApp (_, args) | ECallPtr (_, args) -> 1 + List.length args
  | ELet (_, rhs, body)   -> 1 + node_count rhs + node_count body
  | ELetRec (fns, body)   ->
    1 + List.fold_left (fun a fd -> a + node_count fd.fn_body) 0 fns
    + node_count body
  | ECase (_, brs, def) ->
    1 + List.fold_left (fun a b -> a + node_count b.br_body) 0 brs
    + Option.fold ~none:0 ~some:node_count def
  | ESeq (e1, e2) -> 1 + node_count e1 + node_count e2

let total_nodes m =
  List.fold_left (fun acc fd -> acc + node_count fd.fn_body) 0 m.tm_fns

(* ── Synthetic workload ───────────────────────────────────────────────── *)

(** One "unit" of optimization work: a body with several foldable / dead /
    simplifiable sub-expressions.  [i] seeds variable names for uniqueness. *)
let make_work_body i =
  (* Constant fold candidates: 3+4, 2*5, 10-3, 8/2 *)
  let x  = Printf.sprintf "x%d"  i in
  let y  = Printf.sprintf "y%d"  i in
  let z  = Printf.sprintf "z%d"  i in
  let d  = Printf.sprintf "d%d"  i in   (* dead binding *)
  let r  = Printf.sprintf "r%d"  i in
  (* let x = 3+4   → fold to 7 *)
  (* let y = x*1   → simplify to x *)
  (* let z = y+0   → simplify to y *)
  (* let d = 2*5   → fold to 10, then dead (unused) → DCE drops it *)
  (* result = z    *)
  ELet (mk_var x TInt, op "+" [ilit 3; ilit 4],
  ELet (mk_var y TInt, op "*" [ivar x; ilit 1],
  ELet (mk_var z TInt, op "+" [ivar y; ilit 0],
  ELet (mk_var d TInt, op "*" [ilit 2; ilit 5],   (* dead *)
  ELet (mk_var r TInt, op "+" [ivar z; ilit 0],   (* simplify *)
  EAtom (ivar r))))))

(** Float variant with fast-math-relevant patterns. *)
let make_float_body i =
  let a = Printf.sprintf "fa%d" i in
  let b = Printf.sprintf "fb%d" i in
  let c = Printf.sprintf "fc%d" i in
  (* let a = 1.0 +. 2.0   → fold to 3.0 *)
  (* let b = a *. 1.0     → simplify to a *)
  (* let c = b +. 0.0     → simplify to b *)
  (* result = c *)
  ELet (mk_var a TFloat, fop "+." [flit 1.0; flit 2.0],
  ELet (mk_var b TFloat, fop "*." [fvar a; flit 1.0],
  ELet (mk_var c TFloat, fop "+." [fvar b; flit 0.0],
  EAtom (fvar c))))

(** A small pure function suitable for inlining: double(x) = x + x *)
let make_double_fn suffix =
  let x = mk_var ("x_" ^ suffix) TInt in
  { fn_name   = "double_" ^ suffix;
    fn_params = [x];
    fn_ret_ty = TInt;
    fn_body   = op "+" [AVar x; AVar x] }

(** A caller that calls double N times — inlining candidates. *)
let make_caller_body suffix n =
  (* call double_suffix(i) for i = 1..n, chain adds *)
  let rec build k acc_name =
    if k > n then EAtom (ivar acc_name)
    else
      let call_v = mk_var (Printf.sprintf "c_%s_%d" suffix k) TInt in
      let sum_v  = mk_var (Printf.sprintf "s_%s_%d" suffix k) TInt in
      ELet (call_v,
        EApp (mk_var ("double_" ^ suffix) (TFn ([TInt], TInt)), [ilit k]),
        ELet (sum_v, op "+" [AVar call_v; ivar acc_name],
          build (k+1) sum_v.v_name))
  in
  ELet (mk_var (Printf.sprintf "s_%s_0" suffix) TInt, EAtom (ilit 0),
    build 1 (Printf.sprintf "s_%s_0" suffix))

(** Build a module with [n_groups] groups, each containing:
    - 2 work functions (int + float)
    - 1 small inlinable function (double_i)
    - 1 caller function *)
let build_module n_groups =
  let fns = ref [] in
  for i = 0 to n_groups - 1 do
    let s = string_of_int i in
    (* work functions *)
    fns := { fn_name = "work_int_"   ^ s; fn_params = [];
              fn_ret_ty = TInt;   fn_body = make_work_body i } :: !fns;
    fns := { fn_name = "work_float_" ^ s; fn_params = [];
              fn_ret_ty = TFloat; fn_body = make_float_body i } :: !fns;
    (* inlinable + caller *)
    fns := make_double_fn s :: !fns;
    fns := { fn_name = "caller_" ^ s; fn_params = [];
              fn_ret_ty = TInt;
              fn_body   = make_caller_body s 4 } :: !fns;
  done;
  (* add a main that calls all work functions *)
  fns := { fn_name = "main"; fn_params = [];
            fn_ret_ty = TUnit;
            fn_body = EAtom (ilit 0) } :: !fns;
  { tm_name = "bench"; tm_fns = List.rev !fns; tm_types = []; tm_externs = [] }

(* ── Timing ──────────────────────────────────────────────────────────── *)

let time label f =
  let t0 = Unix.gettimeofday () in
  let r  = f () in
  let dt = Unix.gettimeofday () -. t0 in
  Printf.printf "  %-30s  %6.3f ms\n%!" label (dt *. 1000.0);
  (r, dt)

(* ── Run a single pass and report ────────────────────────────────────── *)

let run_pass label pass m =
  let changed = ref false in
  let (m', _dt) = time label (fun () -> pass ~changed m) in
  let before = total_nodes m  in
  let after  = total_nodes m' in
  Printf.printf "    nodes: %d → %d  (-%d)\n%!" before after (before - after);
  m'

(* ── Main ──────────────────────────────────────────────────────────────── *)

let () =
  let n_groups = 500 in   (* 500 × 4 fns + main = ~2001 functions *)
  Printf.printf "\nBuilding synthetic TIR module (%d groups × 4 fns)...\n%!" n_groups;
  let m = build_module n_groups in
  Printf.printf "  Functions : %d\n%!" (List.length m.tm_fns);
  Printf.printf "  Total nodes (before opt): %d\n\n%!" (total_nodes m);

  Printf.printf "── Individual passes (single iteration) ─────────────────────\n%!";
  let m_after_fold     = run_pass "fold"       March_tir.Fold.run     m in
  let m_after_simplify = run_pass "simplify"   March_tir.Simplify.run m_after_fold in
  let m_after_inline   = run_pass "inline"     March_tir.Inline.run   m in
  let m_after_dce      = run_pass "dce"        March_tir.Dce.run      m_after_simplify in
  ignore m_after_inline; ignore m_after_dce;

  Printf.printf "\n── Fixed-point coordinator (max 5 iterations) ────────────────\n%!";
  let nodes_before = total_nodes m in
  let (m_opt, _) = time "opt.run (full)" (fun () -> March_tir.Opt.run m) in
  let nodes_after  = total_nodes m_opt in
  Printf.printf "  nodes: %d → %d  (-%d,  %.1f%% reduction)\n%!"
    nodes_before nodes_after (nodes_before - nodes_after)
    (100.0 *. float_of_int (nodes_before - nodes_after) /. float_of_int nodes_before);

  Printf.printf "\n── Scale sensitivity ─────────────────────────────────────────\n%!";
  List.iter (fun n ->
    let m_n = build_module n in
    let nodes_before_n = total_nodes m_n in
    let (m_n', dt) = time (Printf.sprintf "%5d groups" n) (fun () -> March_tir.Opt.run m_n) in
    let nodes_after_n = total_nodes m_n' in
    Printf.printf "    %5d fns  %7d → %7d nodes  (%.1f%% reduction)\n%!"
      (List.length m_n.tm_fns)
      nodes_before_n nodes_after_n
      (100.0 *. float_of_int (nodes_before_n - nodes_after_n) /. float_of_int nodes_before_n);
    ignore dt
  ) [10; 50; 100; 250; 500; 1000]
