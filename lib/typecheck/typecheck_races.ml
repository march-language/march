(** Logical-race warnings (specs/progress/2026-11-16-race-warnings.md).

    March has no memory-level data races: values are immutable, actors share
    nothing, an in-place write happens only to a value with one reference,
    and linear values cannot be shared at all.  Two kinds of race survive,
    because they live above the memory model:

    - a check-then-act on a Vault table: `get` (or `has`) a key, decide, then
      `set` it.  Each call takes the table's lock, but nothing holds it
      between the two, so a concurrent writer's update in that window is
      lost ([vault_check_then_act]);
    - a lambda handed to a parallel combinator (`Parallel.pmap` and its
      family) whose calls touch shared state: every element writing the
      same Vault key ([parallel_shared_write]), or printing to the console,
      whose lines then come out in whatever order the workers ran
      ([parallel_output_order]).

    Both are syntactic and module-local, so they warn rather than reject:
    the read and the write are matched by table and key as written, and a
    helper function counts only when it is defined in the same module.
    Plain I/O inside a parallel lambda (an HTTP fetch per element) is the
    point of `pmap_n`, so it draws nothing; see [Portable]'s seed list in
    lib/tir/portable.ml for the combinators and the argument each runs. *)

module Ast = March_ast.Ast
module Err = March_errors.Errors
module SSet = Set.Make (String)

(* ── Vocabulary ──────────────────────────────────────────────────────── *)

let vault_reads = [ "Vault.get"; "Vault.get_or"; "Vault.has" ]

(* Writes that replace a key's value without looking at it under the same
   lock.  [Vault.update] is here too: the runtime reads, runs the closure
   unlocked, then writes (runtime/march_extras.c, march_vault_update). *)
let vault_writes = [ "Vault.set"; "Vault.put"; "Vault.set_ttl"; "Vault.update" ]

let console_builtins = [ "println"; "print"; "print_line"; "print_stderr" ]

(* The parallel combinators and the (0-based) argument positions each calls
   once per element, from lib/tir/portable.ml's seed list. *)
let parallel_combinators = [
  "List.pmap", [ 1 ]; "List.pmap_n", [ 1 ]; "List.pfilter", [ 1 ];
  "List.preduce", [ 2 ];
  "Parallel.pmap", [ 1 ]; "Parallel.pmap_n", [ 1 ];
  "Parallel.preduce", [ 2; 3 ]; "Parallel.preduce_n", [ 2; 3 ];
  "Parallel.pcount", [ 1 ]; "Parallel.pany", [ 1 ]; "Parallel.pall", [ 1 ];
  "Task.async_stream", [ 1 ]; "Task.async_stream_n", [ 1 ];
]

(* ── Expression helpers ──────────────────────────────────────────────── *)

(* A call's head name and arguments, a pipe's left side counted as the first
   argument (`xs |> Parallel.pmap(f)`), in case the pipe is still present. *)
let call_of (e : Ast.expr) : (string * Ast.expr list * Ast.span) option =
  match e with
  | Ast.EApp (Ast.EVar n, args, sp) -> Some (n.Ast.txt, args, sp)
  | Ast.EPipe (l, Ast.EApp (Ast.EVar n, args, _), sp) -> Some (n.Ast.txt, l :: args, sp)
  | Ast.EPipe (l, Ast.EVar n, sp) -> Some (n.Ast.txt, [ l ], sp)
  | _ -> None

(* A span-free rendering of a simple expression, so the table and key of a
   read and a write can be compared as written.  [None] for anything that
   is not a name, literal, field, constructor, tuple or call of those: two
   such expressions are not assumed to be the same value. *)
let is_operator name =
  name <> "" && not (Char.equal name.[0] '_')
  && String.for_all (fun c -> not (Char.equal c '_' || ('a' <= c && c <= 'z')
                                   || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9') || c = '.')) name

let rec key_of (e : Ast.expr) : string option =
  let all es =
    let ks = List.filter_map key_of es in
    if List.length ks = List.length es then Some (String.concat ", " ks) else None in
  match e with
  | Ast.EVar n -> Some n.Ast.txt
  | Ast.ELit (Ast.LitInt i, _) -> Some (string_of_int i)
  | Ast.ELit (Ast.LitFloat f, _) -> Some (string_of_float f)
  | Ast.ELit (Ast.LitString s, _) -> Some (Printf.sprintf "%S" s)
  | Ast.ELit (Ast.LitBool b, _) -> Some (string_of_bool b)
  | Ast.ELit (Ast.LitAtom a, _) -> Some (":" ^ a)
  | Ast.EField (x, f, _) -> Option.map (fun k -> k ^ "." ^ f.Ast.txt) (key_of x)
  | Ast.ETuple (es, _) -> Option.map (fun k -> "(" ^ k ^ ")") (all es)
  | Ast.ECon (c, [], _) -> Some c.Ast.txt
  | Ast.ECon (c, es, _) -> Option.map (fun k -> c.Ast.txt ^ "(" ^ k ^ ")") (all es)
  | Ast.EApp (Ast.EVar op, [ a; b ], _) when is_operator op.Ast.txt ->
    (match key_of a, key_of b with
     | Some a, Some b -> Some (a ^ " " ^ op.Ast.txt ^ " " ^ b)
     | _ -> None)
  | Ast.EApp (f, args, _) ->
    (match key_of f, all args with
     | Some f, Some a -> Some (f ^ "(" ^ a ^ ")")
     | _ -> None)
  | Ast.EAnnot (x, _, _) -> key_of x
  | _ -> None

(* ── Check 1: check-then-act on a Vault ──────────────────────────────── *)

type vault_call = { vc_fn : string; vc_table : string; vc_key : string; vc_span : Ast.span;
                    vc_args : Ast.expr list }

let vault_calls ~iter_expr names (root : Ast.expr) : vault_call list =
  let acc = ref [] in
  iter_expr (fun e ->
      match call_of e with
      | Some (f, (t :: k :: _ as args), sp) when List.mem f names ->
        (match key_of t, key_of k with
         | Some tk, Some kk ->
           acc := { vc_fn = f; vc_table = tk; vc_key = kk; vc_span = sp; vc_args = args } :: !acc
         | _ -> ())
      | _ -> ())
    root;
  List.rev !acc

let span_before (a : Ast.span) (b : Ast.span) =
  (a.Ast.start_line, a.Ast.start_col) < (b.Ast.start_line, b.Ast.start_col)

(* Does the written value do arithmetic on something?  Then `Vault.incr`
   is the atomic form to name. *)
let looks_like_count ~iter_expr (e : Ast.expr) =
  let found = ref false in
  iter_expr (function
      | Ast.EApp (Ast.EVar { Ast.txt = "+" | "-"; _ }, _, _) -> found := true
      | _ -> ())
    e;
  !found

let within (inner : Ast.span) (outer : Ast.span) =
  (outer.Ast.start_line, outer.Ast.start_col) <= (inner.Ast.start_line, inner.Ast.start_col)
  && (inner.Ast.end_line, inner.Ast.end_col) <= (outer.Ast.end_line, outer.Ast.end_col)

let span_of = Typecheck_types.span_of_expr

(* Is the write [w] decided by the value the read [r] returned?  Only then
   is the pair a check-then-act; a function that reads one key early and
   writes it again for an unrelated reason is left alone.  It is, when:
   - [r] and [w] are in the same function body (not split across lambdas,
     which may run at different times), and
   - [r] is inside [w]'s arguments, or a `let` binds [r]'s result (directly
     or through further lets) to a name [w]'s arguments use, or [w] sits in
     a branch of an `if` / `match` whose condition or scrutinee contains [r]
     or one of those names. *)
let depends_on ~iter_expr (root : Ast.expr) (r : vault_call) (w : vault_call) =
  let lams = ref [] in
  iter_expr (function
      | (Ast.ELam _ | Ast.ELetFn _) as e -> lams := span_of e :: !lams
      | _ -> ())
    root;
  let scope_of sp =
    List.fold_left (fun best l ->
        if within sp l then match best with
          | Some b when within b l -> best
          | _ -> Some l
        else best)
      None !lams in
  let same_scope sp = scope_of sp = scope_of r.vc_span in
  if not (same_scope w.vc_span) then false
  else begin
    let mentions names e =
      let hit = ref false in
      iter_expr (function Ast.EVar n when SSet.mem n.Ast.txt names -> hit := true | _ -> ()) e;
      !hit in
    let carries names e = within r.vc_span (span_of e) || mentions names e in
    (* Names that hold (something computed from) the read's result, in
       source order, so a chain of lets is followed. *)
    let tainted = ref SSet.empty in
    iter_expr (function
        | Ast.ELet (b, sp) when same_scope sp && carries !tainted b.Ast.bind_expr ->
          List.iter (fun v -> tainted := SSet.add v !tainted)
            (March_ast.Calls.pattern_vars [] b.Ast.bind_pat)
        | _ -> ())
      root;
    let in_args = List.exists (carries !tainted) w.vc_args in
    let guarded = ref false in
    iter_expr (fun e ->
        let sp = span_of e in
        if same_scope sp && within w.vc_span sp then
          match e with
          | Ast.EIf (c, _, _, _) when carries !tainted c && not (within w.vc_span (span_of c)) ->
            guarded := true
          | Ast.EMatch (s, _, _) when carries !tainted s && not (within w.vc_span (span_of s)) ->
            guarded := true
          | Ast.ECond (arms, _) when List.exists (fun (c, _) -> carries !tainted c) arms ->
            guarded := true
          | _ -> ())
      root;
    in_args || !guarded
  end

let check_then_act ~iter_expr (errors : Err.ctx) (root : Ast.expr) =
  let reads = vault_calls ~iter_expr vault_reads root in
  if reads <> [] then begin
    let writes = vault_calls ~iter_expr vault_writes root in
    List.iter (fun (w : vault_call) ->
        match List.find_opt (fun (r : vault_call) ->
            r.vc_table = w.vc_table && r.vc_key = w.vc_key
            && (span_before r.vc_span w.vc_span || within r.vc_span w.vc_span)
            && depends_on ~iter_expr root r w)
            reads with
        | None -> ()
        | Some r ->
          let short f = match String.rindex_opt f '.' with
            | Some i -> String.sub f (i + 1) (String.length f - i - 1) | None -> f in
          let value = match w.vc_args with _ :: _ :: v :: _ -> Some v | _ -> None in
          let advice =
            if w.vc_fn = "Vault.update" then
              "`Vault.update` is not atomic either: it reads, runs the function, then writes. \
               For a counter use `Vault.incr(table, key, delta)`; for anything else, keep the \
               table in an actor, whose handlers run one message at a time."
            else if r.vc_fn = "Vault.has"
                 || (r.vc_fn = "Vault.get" && not (Option.fold ~none:false ~some:(looks_like_count ~iter_expr) value)) then
              "To store a value only when the key is absent, use \
               `Vault.put_new(table, key, value)`: it checks and inserts under one lock and \
               returns whether it won. For an update that depends on the old value, keep the \
               table in an actor, whose handlers run one message at a time."
            else if Option.fold ~none:false ~some:(looks_like_count ~iter_expr) value then
              "For a counter, `Vault.incr(table, key, delta)` adds and returns the new value \
               under one lock, so concurrent increments are never lost."
            else
              "Keep the table in an actor, whose handlers run one message at a time, or use \
               `Vault.incr` (counters), `Vault.put_new` (insert if absent) or \
               `Vault.push_capped` (bounded lists), which each read and write under one lock." in
          Err.report errors
            { Err.severity = Err.Warning; span = w.vc_span; code = Err.Code.vault_check_then_act;
              fix = None;
              labels = [ { Err.lbl_span = r.vc_span;
                           lbl_message = Printf.sprintf "`%s` read here" w.vc_key } ];
              notes = [
                Printf.sprintf
                  "`Vault.%s` and `Vault.%s` each take the table's lock, but nothing holds it \
                   between them. If another task or actor writes `%s` in that window, this write \
                   replaces its value and that update is lost."
                  (short r.vc_fn) (short w.vc_fn) w.vc_key;
                advice;
                "If only one task ever writes this table, mark the function `@[no_warn_race]`." ];
              message =
                Printf.sprintf "This writes `%s` in `%s` based on a value read from it earlier, \
                                and another writer can change it in between."
                  w.vc_key w.vc_table })
      writes
  end

(* ── Check 2: parallel lambdas that touch shared state ───────────────── *)

(* Names bound inside a lambda: its parameters and every let, match-arm,
   let?/let* and inner-lambda binder in its body.  A Vault key built from
   one of these differs per element; a key built only from captured names
   or literals is the same key for every element. *)
let lambda_binders ~iter_expr (params : string list) (body : Ast.expr) : SSet.t =
  let s = ref (SSet.of_list params) in
  let add_pat p = List.iter (fun v -> s := SSet.add v !s) (March_ast.Calls.pattern_vars [] p) in
  iter_expr (function
      | Ast.ELet (b, _) -> add_pat b.Ast.bind_pat
      | Ast.EMatch (_, brs, _) -> List.iter (fun (br : Ast.branch) -> add_pat br.Ast.branch_pat) brs
      | Ast.ELetQ (p, _, _, _) | Ast.ELetStar (p, _, _, _) -> add_pat p
      | Ast.ELam (ps, _, _) -> List.iter (fun (p : Ast.param) -> s := SSet.add p.Ast.param_name.Ast.txt !s) ps
      | Ast.ELetFn (n, ps, _, _, _) ->
        s := SSet.add n.Ast.txt !s;
        List.iter (fun (p : Ast.param) -> s := SSet.add p.Ast.param_name.Ast.txt !s) ps
      | _ -> ())
    body;
  !s

let mentions_any ~iter_expr (names : SSet.t) (e : Ast.expr) =
  let found = ref false in
  iter_expr (function Ast.EVar n when SSet.mem n.Ast.txt names -> found := true | _ -> ()) e;
  !found

(* What a body does that a parallel caller should hear about. *)
type race_effect = { console : Ast.span option; shared_write : (string * Ast.span) option }

let no_effect = { console = None; shared_write = None }

(* A body's own effects: a console builtin call; a Vault write whose key
   mentions none of [local] (the names that differ per call). *)
let own_effects ~iter_expr ~(local : SSet.t) (body : Ast.expr) : race_effect =
  let eff = ref no_effect in
  iter_expr (fun e ->
      match call_of e with
      | Some (f, _, sp) when List.mem f console_builtins && !eff.console = None ->
        eff := { !eff with console = Some sp }
      | Some (f, _ :: k :: _, sp) when List.mem f vault_writes && !eff.shared_write = None
                                    && not (mentions_any ~iter_expr local k) ->
        eff := { !eff with shared_write = Some (Option.value (key_of k) ~default:"the key", sp) }
      | _ -> ())
    body;
  !eff

(* The module's own functions by bare name: their parameter names and
   bodies.  A helper's effects count when a parallel lambda calls it. *)
let module_fns (decls : Ast.decl list) : (string, string list * Ast.expr list) Hashtbl.t =
  let t = Hashtbl.create 16 in
  List.iter (function
      | Ast.DFn (def, _) ->
        let params = List.concat_map (fun (c : Ast.fn_clause) ->
            List.concat_map (function
                | Ast.FPNamed p | Ast.FPDefault (p, _) -> [ p.Ast.param_name.Ast.txt ]
                | Ast.FPPat p -> March_ast.Calls.pattern_vars [] p)
              c.Ast.fc_params) def.Ast.fn_clauses in
        let bodies = List.map (fun (c : Ast.fn_clause) -> c.Ast.fc_body) def.Ast.fn_clauses in
        Hashtbl.replace t def.Ast.fn_name.Ast.txt (params, bodies)
      | _ -> ())
    decls;
  t

(* Each module function's effects, through calls to other module functions,
   to a fixpoint.  A helper's Vault write counts as shared when its key
   mentions none of the helper's own parameters or locals. *)
let fn_effects ~iter_expr (fns : (string, string list * Ast.expr list) Hashtbl.t)
  : (string, race_effect) Hashtbl.t =
  let eff = Hashtbl.create 16 in
  let callees body =
    let acc = ref [] in
    iter_expr (fun e ->
        match call_of e with
        | Some (f, _, sp) when Hashtbl.mem fns f -> acc := (f, sp) :: !acc
        | _ -> ())
      body;
    List.rev !acc in
  let base = Hashtbl.create 16 in
  Hashtbl.iter (fun name (params, bodies) ->
      let e = List.fold_left (fun (acc : race_effect) body ->
          let local = lambda_binders ~iter_expr params body in
          let o = own_effects ~iter_expr ~local body in
          { console = (if acc.console <> None then acc.console else o.console);
            shared_write = (if acc.shared_write <> None then acc.shared_write else o.shared_write) })
          no_effect bodies in
      Hashtbl.replace base name (e, List.concat_map callees bodies))
    fns;
  Hashtbl.iter (fun n (e, _) -> Hashtbl.replace eff n e) base;
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter (fun n (_, calls) ->
        let cur = Hashtbl.find eff n in
        let next = List.fold_left (fun (acc : race_effect) (g, sp) ->
            let ge = Hashtbl.find eff g in
            { console = (if acc.console = None && ge.console <> None then Some sp else acc.console);
              shared_write = (match acc.shared_write, ge.shared_write with
                  | None, Some (k, _) -> Some (k, sp) | x, _ -> x) })
            cur calls in
        if next <> cur then (Hashtbl.replace eff n next; changed := true))
      base
  done;
  eff

let check_parallel_arg ~iter_expr (errors : Err.ctx) ~combinator
    (fns : (string, string list * Ast.expr list) Hashtbl.t)
    (effs : (string, race_effect) Hashtbl.t) (arg : Ast.expr) =
  (* (effect, a description of where it comes from) *)
  let found =
    match arg with
    | Ast.ELam (params, body, _) ->
      let local = lambda_binders ~iter_expr
          (List.map (fun (p : Ast.param) -> p.Ast.param_name.Ast.txt) params) body in
      let own = own_effects ~iter_expr ~local body in
      (* Calls to module helpers inside the lambda. *)
      let via = ref no_effect and via_name = ref [] in
      iter_expr (fun e ->
          match call_of e with
          | Some (f, _, sp) when Hashtbl.mem effs f ->
            let ge = Hashtbl.find effs f in
            if !via.console = None && ge.console <> None then begin
              via := { !via with console = Some sp }; via_name := ("console", f) :: !via_name end;
            (match !via.shared_write, ge.shared_write with
             | None, Some (k, _) ->
               via := { !via with shared_write = Some (k, sp) };
               via_name := ("write", f) :: !via_name
             | _ -> ())
          | _ -> ())
        body;
      let pick a b = match a with Some _ -> a | None -> b in
      Some ({ console = pick own.console !via.console;
              shared_write = pick own.shared_write !via.shared_write },
            (fun kind -> if (kind = "console" && own.console <> None)
                         || (kind = "write" && own.shared_write <> None) then None
              else List.assoc_opt kind !via_name))
    | Ast.EVar n when Hashtbl.mem fns n.Ast.txt ->
      let e = Hashtbl.find effs n.Ast.txt in
      Some ({ console = Option.map (fun _ -> n.Ast.span) e.console;
              shared_write = Option.map (fun (k, _) -> (k, n.Ast.span)) e.shared_write },
            (fun _ -> Some n.Ast.txt))
    | _ -> None in
  match found with
  | None -> ()
  | Some (eff, via) ->
    let through kind = match via kind with
      | Some f -> Printf.sprintf " (through `%s`)" f | None -> "" in
    (match eff.shared_write with
     | Some (key, sp) ->
       Err.report errors
         { Err.severity = Err.Warning; span = sp; code = Err.Code.parallel_shared_write; fix = None;
           labels = [];
           notes = [
             Printf.sprintf
               "`%s` runs this function on many elements at once, and every call writes the same \
                key `%s`%s. The calls finish in no fixed order, so which value is left is a race, \
                and a read-then-write of the key loses updates."
               combinator key (through "write");
             "Return the values from the function and combine the results after the parallel \
              call, or key each write by the element. For a shared counter use \
              `Vault.incr`, which adds under one lock." ];
           message = Printf.sprintf
               "Every parallel call writes the same Vault key `%s`." key }
     | None -> ());
    (match eff.console with
     | Some sp ->
       Err.report errors
         { Err.severity = Err.Warning; span = sp; code = Err.Code.parallel_output_order; fix = None;
           labels = [];
           notes = [
             Printf.sprintf
               "`%s` runs this function on many elements at once%s, so the lines come out in \
                whatever order the calls happen to run, and differ from run to run."
               combinator (through "console");
             "Return the text from the function and print the results after the parallel call: \
              they come back in input order." ];
           message = "This prints from inside a parallel call, so the output order is not fixed." }
     | None -> ())

(* ── Entry point ─────────────────────────────────────────────────────── *)

(** Run both checks over a module's declarations, nested modules included.
    [iter_expr] is the typechecker's exhaustive sub-expression walker;
    [own_exprs] is [Typecheck_caps.module_own_exprs]. *)
let rec check_module ~iter_expr ~(own_exprs : Ast.decl list -> Ast.expr list)
    (errors : Err.ctx) (decls : Ast.decl list) : unit =
  (* `@[no_warn_race]` on a function: its author knows it runs on one task. *)
  let checked = List.filter (function
      | Ast.DFn (def, _) -> not (List.mem "no_warn_race" def.Ast.fn_attrs)
      | _ -> true) decls in
  (* The stdlib's own code is not the user's to change, and its self-check
     runs must stay clean; its Vault use is reviewed where it is written. *)
  let roots = List.filter (fun e -> not (Typecheck_builtins.span_is_stdlib (span_of e)))
      (own_exprs checked) in
  List.iter (check_then_act ~iter_expr errors) roots;
  let fns = module_fns decls in
  let effs = lazy (fn_effects ~iter_expr fns) in
  List.iter (fun root ->
      iter_expr (fun e ->
          match call_of e with
          | Some (f, args, _) ->
            (match List.assoc_opt f parallel_combinators with
             | Some idxs ->
               List.iteri (fun i a ->
                   if List.mem i idxs then
                     check_parallel_arg ~iter_expr errors ~combinator:f fns (Lazy.force effs) a)
                 args
             | None -> ())
          | None -> ())
        root)
    roots;
  List.iter (function
      | Ast.DMod (_, _, inner, _) -> check_module ~iter_expr ~own_exprs errors inner
      | _ -> ())
    decls
