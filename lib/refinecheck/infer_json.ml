(* JSON v1 for `--refine-infer-json`
   (specs/2026-10-20-refinement-suggest-lite-design.md §4.2).

   Hand-rendered, as the driver's other machine outputs are.  Every array is
   sorted by (file, line, col, slot, kind, predicate) so the output diffs
   stably in review; field order is fixed. *)

module A = March_ast.Ast
module IS = Infer_slot
module LD = Ledger_diff
module RI = Refine_infer

let esc s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let str s = "\"" ^ esc s ^ "\""

let rec path_text = function
  | IS.Param x -> "param " ^ x
  | IS.Return -> "return"
  | IS.Elem p -> path_text p ^ "/elem"
  | IS.Arg (i, p) -> Printf.sprintf "%s/elem.%d" (path_text p) i
  | IS.Tuple (i, p) -> Printf.sprintf "%s/tuple.%d" (path_text p) i
  | IS.Lambda_param { line; col; param } -> Printf.sprintf "lambda@%d:%d/param %s" line col param

let kind_text (s : IS.slot) : string =
  if List.mem IS.K6 s.IS.kinds then "abstract"
  else if List.mem IS.K7 s.IS.kinds then "accumulator"
  else if List.mem IS.K5 s.IS.kinds && s.IS.kinds = [ IS.K5 ] && not (IS.scalar s.IS.base) then
    (* a whole relational container type (Refine_infer's [try_rel]) *)
    match s.IS.path with IS.Param _ -> "element-param" | _ -> "element-return"
  else
    match s.IS.path with
    | IS.Param _ -> "precondition"
    | IS.Return -> "return"
    | p -> (match IS.root p with IS.Param _ -> "element-param" | _ -> "element-return")

let pos (sp : A.span) = (sp.A.file, sp.A.start_line, sp.A.start_col)

let site_obj ?(fn = None) (sp : A.span) (extra : (string * string) list) =
  let f, l, c = pos sp in
  "{"
  ^ String.concat ", "
      ((match fn with Some n -> [ "\"fn\": " ^ str n ] | None -> [])
       @ [ "\"file\": " ^ str f; Printf.sprintf "\"line\": %d" l; Printf.sprintf "\"col\": %d" c ]
       @ List.map (fun (k, v) -> Printf.sprintf "%s: %s" (str k) v) extra)
  ^ "}"

let arr xs = "[" ^ String.concat ", " xs ^ "]"

let sort_key (s : IS.slot) pred =
  let f, l, c = pos s.IS.fd.A.fn_name.A.span in
  (f, l, c, path_text s.IS.path, kind_text s, pred)

let in_body (s : IS.slot) (sp : A.span) =
  List.exists (fun (c : A.fn_clause) -> Infer_vocab.within c.A.fc_span sp) s.IS.fd.A.fn_clauses

let to_string ?(edit_of : RI.proposal -> (string * int * int * string) option = fun _ -> None)
    (r : RI.result) : string =
  let violations snap = List.length (List.filter (fun (_, v) -> v = Obligation.Violated) snap) in
  let proposals =
    List.sort (fun (a : RI.proposal) (b : RI.proposal) -> compare (sort_key a.RI.slot a.RI.pred) (sort_key b.RI.slot b.RI.pred)) r.RI.proposals
  in
  let proposal (p : RI.proposal) =
    let f, l, c = pos p.RI.slot.IS.fd.A.fn_name.A.span in
    let closes =
      List.map
        (fun (k : LD.key) -> site_obj k.LD.span [ ("callee", str k.LD.callee); ("predicate", str k.LD.predicate) ])
        (List.sort compare p.RI.closes)
    in
    let caller_closed = List.filter (fun (k : LD.key) -> not (in_body p.RI.slot k.LD.span)) p.RI.closes in
    let impact =
      Printf.sprintf "{\"new_proved\": %d, \"new_skipped\": %d, \"new_violated\": 0, \"sites\": %s}"
        (List.length caller_closed) (List.length p.RI.new_skipped)
        (arr (List.map (fun (k : LD.key) -> site_obj k.LD.span []) (List.sort compare p.RI.new_skipped)))
    in
    let edit =
      match edit_of p with
      | Some (file, start, stop, text) ->
        Printf.sprintf "{\"file\": %s, \"start\": %d, \"end\": %d, \"text\": %s}" (str file) start stop (str text)
      | None -> "null"
    in
    Printf.sprintf
      "{\"id\": %s, \"round\": %d, \"kind\": %s, \"fn\": %s, \"file\": %s, \"line\": %d, \"col\": %d, \"slot\": %s, \"base\": %s, \"predicate\": %s, \"annotation\": %s, \"source\": %s, \"depends_on\": %s, \"external_callers\": %b, \"closes\": %s, \"caller_impact\": %s, \"edit\": %s}"
      (str p.RI.id) p.RI.round (str (kind_text p.RI.slot)) (str p.RI.slot.IS.fn) (str f) l c
      (str (path_text p.RI.slot.IS.path))
      (str (Option.value (IS.render IS.Return p.RI.slot.IS.base) ~default:""))
      (str p.RI.pred) (str p.RI.annotation) (str (Infer_vocab.source_name p.RI.source))
      (arr (List.map str p.RI.depends_on)) p.RI.external_callers (arr closes) impact edit
  in
  let rejected =
    List.sort (fun (a, pa, _, _) (b, pb, _, _) -> compare (sort_key a pa) (sort_key b pb)) r.RI.rejected
    |> List.map (fun ((s : IS.slot), pred, reason, detail) ->
           Printf.sprintf "{\"fn\": %s, \"slot\": %s, \"predicate\": %s, \"reason\": %s, \"detail\": %s}"
             (str s.IS.fn) (str (path_text s.IS.path)) (str pred) (str reason) (str detail))
  in
  let refused =
    List.sort (fun (a, pa, _) (b, pb, _) -> compare (sort_key a pa) (sort_key b pb)) r.RI.refused
    |> List.map (fun ((s : IS.slot), pred, (rf : Precond_infer.refusal)) ->
           Printf.sprintf "{\"fn\": %s, \"slot\": %s, \"predicate\": %s, \"reason\": %s, \"sites\": %s}"
             (str s.IS.fn) (str (path_text s.IS.path)) (str pred) (str rf.Precond_infer.rf_reason)
             (arr (List.map (fun sp -> site_obj sp []) rf.Precond_infer.rf_sites)))
  in
  let notes =
    List.sort compare r.RI.notes
    |> List.map (fun (fn, n) -> Printf.sprintf "{\"fn\": %s, \"note\": %s}" (str fn) (str n))
  in
  let budget_ex = List.sort_uniq compare (List.filter_map (fun (fn, n) -> if n = "budget-exhausted" then Some (str fn) else None) r.RI.notes) in
  Printf.sprintf
    "{\"version\": 1, \"summary\": {\"user_skips_before\": %d, \"user_skips_after\": %d, \"violations_before\": %d, \"violations_after\": %d, \"accepted\": %d, \"rejected\": %d, \"refused\": %d, \"probes\": %d, \"rounds\": %d, \"budget_exhausted\": %s}, \"proposals\": %s, \"rejected\": %s, \"refused\": %s, \"notes\": %s}"
    (LD.debt r.RI.before - violations r.RI.before) (LD.debt r.RI.after - violations r.RI.after)
    (violations r.RI.before) (violations r.RI.after)
    (List.length r.RI.proposals) (List.length r.RI.rejected) (List.length r.RI.refused) r.RI.probes r.RI.rounds
    (arr budget_ex) (arr (List.map proposal proposals)) (arr rejected) (arr refused) (arr notes)
