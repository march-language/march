(** Callback call-arity: does a function VALUE passed as an argument take as
    many arguments as the callee applies it to?

    March's function TYPES are curried — a two-parameter `fn add(a, b)` and a
    one-parameter function returning a function both have the type
    `a -> b -> c`, and unification cannot tell them apart (there is no
    separate n-ary arrow; see specs/lang/grammar.md §7.2).  At RUNTIME they
    differ: March has no partial application, so a closure is always called
    with exactly the arguments written at the call site.  Passing `add` where
    the callee does `let g = f(x)` then `g(y)` typechecked, then died
    (`arity mismatch` interpreted, SIGSEGV compiled) — the realistic case being
    the stdlib's curried comparators (`Map.insert(m, k, v, cmp)` calls
    `cmp(a)` and then the result).

    This pass recovers the missing arity information syntactically, in the
    same spirit as the call-site arity check on [fn_arities]: for each
    parameter of a module's functions, how many arguments the body applies it
    to, either directly (`f(x)`) or by handing it to another known function's
    parameter whose call-arity is known (`cmp_eq(cmp, a, b)`), iterated to a
    fixpoint over the module.  A parameter applied with two different counts,
    or zero arguments, or never applied, gets [None] and is not checked.  The
    typechecker then rejects a call that passes a named function or a lambda
    of a different, known arity to such a parameter (see [check_arg]).

    Conservative by construction: it only ever reports a pairing that, if the
    call path runs, applies a closure to the wrong number of arguments. *)

module Ast = March_ast.Ast
module Calls = March_ast.Calls

(** The definition's name span and, per parameter, its name and call-arity. *)
type entry = Ast.span * (string * int option) list

(** The named parameters of a single-clause function, [None] for a pattern
    parameter (never analysed). *)
let param_names (def : Ast.fn_def) : string option list option =
  match def.Ast.fn_clauses with
  | [ c ] ->
    Some (List.map (function
        | Ast.FPNamed p -> Some p.Ast.param_name.Ast.txt
        | Ast.FPPat (Ast.PatVar n) -> Some n.Ast.txt
        | Ast.FPPat _ | Ast.FPDefault _ -> None) c.Ast.fc_params)
  | _ -> None

(** [param_arities ~callee_param names sites] is, per parameter in [names],
    the one argument count every use in [sites] applies it with: directly
    (`f(x)` is 1), or by passing it on as argument [j] of a callee whose
    parameter [j] has a known call-arity ([callee_param callee j]).  Mixed
    counts, a zero-argument call, or no use at all give [None]. *)
let param_arities ~(callee_param : string -> int -> int option)
    (names : string option list) (sites : Calls.app_site list)
    : (string * int option) list =
  (* A callee that is one of these parameters is the parameter, never a
     like-named known function. *)
  let callee_param callee j =
    if List.mem (Some callee) names then None else callee_param callee j in
  List.map (fun nm ->
      match nm with
      | None -> ("_", None)
      | Some p ->
        let counts =
          List.concat_map (fun (s : Calls.app_site) ->
              let direct =
                if s.Calls.as_callee = p then [ List.length s.Calls.as_args ]
                else [] in
              let passed =
                List.concat (List.mapi (fun j a ->
                    match a with
                    | Some x when x = p ->
                      (match callee_param s.Calls.as_callee j with
                       | Some m -> [ m ]
                       | None -> [])
                    | _ -> []) s.Calls.as_args) in
              direct @ passed) sites
        in
        (match List.sort_uniq compare counts with
         | [ m ] when m >= 1 -> (p, Some m)
         | _ -> (p, None)))
    names

(** [lambda ~lookup params body] is the call-arity of each parameter of a
    let-bound lambda literal `fn (p1, …) -> body`, so a call of that lambda is
    checked like a call of a module fn.  [lookup name] gives a callee's
    entry (a module fn, a qualified export, an enclosing let-bound lambda),
    or [None]. *)
let lambda ~(lookup : string -> entry option) (params : Ast.param list)
    (body : Ast.expr) : (string * int option) list =
  let names = List.map (fun (p : Ast.param) -> Some p.Ast.param_name.Ast.txt) params in
  let callee_param callee j =
    match lookup callee with
    | Some (_, ps) when j < List.length ps -> snd (List.nth ps j)
    | _ -> None
  in
  param_arities ~callee_param names (Calls.free_app_sites body)

(** [compute ~lookup defs] is the call-arity entry of every analysable fn in
    [defs] (one module's top-level functions).  [lookup name] gives the entry
    of a callee that is NOT one of [defs] (a qualified export already
    checked), or [None]. *)
let compute ~(lookup : string -> entry option) (defs : Ast.fn_def list)
    : (string * entry) list =
  let analysable =
    List.filter_map (fun (def : Ast.fn_def) ->
        match param_names def, def.Ast.fn_clauses with
        | Some names, [ c ] when names <> [] ->
          let sites = Calls.free_app_sites c.Ast.fc_body in
          Some (def.Ast.fn_name.Ast.txt, def.Ast.fn_name.Ast.span, names, sites)
        | _ -> None) defs
  in
  let table : (string, entry) Hashtbl.t = Hashtbl.create 16 in
  List.iter (fun (n, sp, names, _) ->
      Hashtbl.replace table n
        (sp, List.map (fun nm -> (Option.value nm ~default:"_", None)) names))
    analysable;
  let callee_param callee j =
    let e = match Hashtbl.find_opt table callee with
      | Some e -> Some e
      | None -> lookup callee in
    match e with
    | Some (_, ps) when j < List.length ps -> snd (List.nth ps j)
    | _ -> None
  in
  let one_round () =
    let changed = ref false in
    List.iter (fun (fname, sp, names, sites) ->
        let arities = param_arities ~callee_param names sites in
        (match Hashtbl.find_opt table fname with
         | Some (_, old) when old = arities -> ()
         | _ -> changed := true);
        Hashtbl.replace table fname (sp, arities))
      analysable;
    !changed
  in
  let rec loop n = if n > 0 && one_round () then loop (n - 1) in
  loop 8;
  List.map (fun (n, _, _, _) -> (n, Hashtbl.find table n)) analysable
