(* Law strength (specs/2026-11-04-law-coverage-design.md §5); see the .mli. *)

module A = March_ast.Ast

type edit = { ed_desc : string; ed_span : A.span; ed_fn : A.fn_def }

let max_edits = 20

let span_of = March_typecheck.Typecheck_types.span_of_expr

(* The immediate sub-expressions of [e] with a function rebuilding [e] from
   replacements for them.  Lambdas and local functions are not entered: an
   edit inside one is an edit to a different function. *)
let kids (e : A.expr) : A.expr list * (A.expr list -> A.expr) =
  let same = ([], fun _ -> e) in
  match e with
  | A.EApp (f, args, sp) -> (f :: args, function f :: args -> A.EApp (f, args, sp) | _ -> e)
  | A.ECon (n, args, sp) -> (args, fun args -> A.ECon (n, args, sp))
  | A.ETuple (es, sp) -> (es, fun es -> A.ETuple (es, sp))
  | A.EBlock (es, sp) -> (es, fun es -> A.EBlock (es, sp))
  | A.ELet (b, sp) -> ([ b.A.bind_expr ], function [ x ] -> A.ELet ({ b with A.bind_expr = x }, sp) | _ -> e)
  | A.EIf (c, t, f, sp) -> ([ c; t; f ], function [ c; t; f ] -> A.EIf (c, t, f, sp) | _ -> e)
  | A.EField (x, n, sp) -> ([ x ], function [ x ] -> A.EField (x, n, sp) | _ -> e)
  | A.EAnnot (x, t, sp) -> ([ x ], function [ x ] -> A.EAnnot (x, t, sp) | _ -> e)
  | A.EPipe (a, b, sp) -> ([ a; b ], function [ a; b ] -> A.EPipe (a, b, sp) | _ -> e)
  | A.EMatch (s, brs, sp) ->
    ( s :: List.map (fun (b : A.branch) -> b.A.branch_body) brs,
      function
      | s :: bodies when List.length bodies = List.length brs ->
        A.EMatch (s, List.map2 (fun (b : A.branch) body -> { b with A.branch_body = body }) brs bodies, sp)
      | _ -> e )
  | _ -> same

(* Every single-site rewrite of [e] by [alts], in pre-order: [alts ~bound x]
   lists the replacements for the node [x] (with a description and the
   site), where [bound] holds the variables bound by enclosing match
   patterns, innermost first. *)
let rec rewrites ~(bound : string list) (alts : bound:string list -> A.expr -> (string * A.span * A.expr) list)
    (e : A.expr) : (string * A.span * A.expr) list =
  let here = alts ~bound e in
  let cs, rebuild = kids e in
  let bound_for i =
    match e with
    | A.EMatch (_, brs, _) when i > 0 -> pat_vars (List.nth brs (i - 1)).A.branch_pat @ bound
    | _ -> bound
  in
  let below =
    List.concat
      (List.mapi
         (fun i c ->
           List.map
             (fun (d, sp, c') -> (d, sp, rebuild (List.mapi (fun j x -> if j = i then c' else x) cs)))
             (rewrites ~bound:(bound_for i) alts c))
         cs)
  in
  here @ below

and pat_vars (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) -> List.concat_map pat_vars ps
  | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
  | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
  | _ -> []

let comparison = [ ("<", "<="); ("<=", "<"); (">", ">="); (">=", ">"); ("==", "!="); ("!=", "==") ]

let edits (fd : A.fn_def) : edit list =
  match fd.A.fn_clauses with
  | [ c ] ->
    let self = fd.A.fn_name.A.txt in
    let params =
      List.filter_map (function A.FPNamed p -> Some p | _ -> None) c.A.fc_params
    in
    let ret = Option.map March_ast.Ast.show_ty fd.A.fn_ret_ty in
    let fname = fd.A.fn_name.A.span in
    let with_body b = { fd with A.fn_clauses = [ { c with A.fc_body = b } ] } in
    let return_param =
      List.filter_map
        (fun (p : A.param) ->
          match p.A.param_ty, ret with
          | Some t, Some r when March_ast.Ast.show_ty t = r ->
            Some (Printf.sprintf "return `%s` unchanged" p.A.param_name.A.txt, fname, A.EVar p.A.param_name)
          | _ -> None)
        params
    in
    let kinds : (bound:string list -> A.expr -> (string * A.span * A.expr) list) list =
      [ (fun ~bound:_ e ->
          match e with
          | A.EApp ((A.EVar f as h), a :: b :: rest, sp) when a <> b ->
            [ (Printf.sprintf "swap the arguments of `%s`" f.A.txt, sp, A.EApp (h, b :: a :: rest, sp)) ]
          | _ -> []);
        (fun ~bound:_ e ->
          match e with
          | A.ECon (n, a :: b :: rest, sp) when a <> b ->
            [ (Printf.sprintf "swap the fields of `%s`" n.A.txt, sp, A.ECon (n, b :: a :: rest, sp)) ]
          | _ -> []);
        (fun ~bound:_ e ->
          match e with
          | A.ELit (A.LitInt n, sp) ->
            let n' = if n = 0 then 1 else if n = 1 then 0 else n + 1 in
            [ (Printf.sprintf "change %d to %d" n n', sp, A.ELit (A.LitInt n', sp)) ]
          | _ -> []);
        (fun ~bound:_ e ->
          match e with
          | A.EMatch (s, brs, sp) ->
            let arr = Array.of_list brs in
            List.filter_map
              (fun i ->
                let a = arr.(i) and b = arr.(i + 1) in
                if a.A.branch_body = b.A.branch_body then None
                else
                  let brs' =
                    List.mapi
                      (fun j (br : A.branch) ->
                        if j = i then { br with A.branch_body = b.A.branch_body }
                        else if j = i + 1 then { br with A.branch_body = a.A.branch_body }
                        else br)
                      brs
                  in
                  Some ("swap the results of two match arms", span_of a.A.branch_body, A.EMatch (s, brs', sp)))
              (List.init (max 0 (Array.length arr - 1)) Fun.id)
          | _ -> []);
        (fun ~bound e ->
          match e with
          | A.EApp (A.EVar f, args, sp) when f.A.txt = self -> (
            match List.find_opt (function A.EVar v -> List.mem v.A.txt bound | _ -> false) args with
            | Some a -> [ ("drop the recursive call", sp, a) ]
            | None -> [])
          | _ -> []);
        (fun ~bound:_ e ->
          match e with
          | A.EApp (A.EVar op, ([ _; _ ] as args), sp) when List.mem_assoc op.A.txt comparison ->
            let op' = List.assoc op.A.txt comparison in
            [ (Printf.sprintf "change `%s` to `%s`" op.A.txt op', sp, A.EApp (A.EVar { op with A.txt = op' }, args, sp)) ]
          | _ -> []) ]
    in
    let site_edits =
      List.concat_map
        (fun k -> rewrites ~bound:[] k c.A.fc_body)
        kinds
    in
    let all = return_param @ site_edits in
    List.filteri (fun i _ -> i < max_edits) all
    |> List.map (fun (d, sp, b) -> { ed_desc = d; ed_span = sp; ed_fn = with_body b })
  | _ -> []
