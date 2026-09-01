(* Witness validation for refinement counterexamples.

   When Z3 refutes an obligation, the model it returns is a CANDIDATE: the
   SMT encoding over-approximates (unreflectable path conditions are dropped
   before discharge), so a raw model may describe an input the program can
   never reach.  This module turns candidates into FACTS by executing them:

     decode  — SMT model strings -> March runtime values, typed by the
               function's parameter list, zero-filling Z3's don't-cares
     execute — call the function through the tree-walking interpreter,
               fuel-limited and with effectful builtins vetoed
               ([Eval_prim.builtin_guard])
     check   — evaluate the violated predicate against the actual result
     shrink  — deterministically minimise the confirmed witness

   Only a candidate that survives execute+check is ever reported, which is
   what makes it sound for refine_post/refine_call/division_safety to
   surface models the verdict logic previously had to discard.  Every
   failure inside this module (undecodable type, blocked effect, fuel out,
   panic en route, unevaluable predicate) collapses to [None] — "behave
   exactly as before this module existed".

   Design: specs/2026-08-30-counterexample-surfacing-design.md. *)

module A = March_ast.Ast
module V = March_eval.Eval_types

(* =================================================================
   §1  Module registration: type tables + lazy evaluation env
   ================================================================= *)

(* The module being checked, as handed to [Refine_check.check_module] /
   [Division_safety.check_module] — the FULL desugared program including
   prepended stdlib decls, i.e. exactly what [Eval.eval_module_env] needs. *)
let current_module : A.module_ option ref = ref None

(* ADT name -> constructors (name, arg types); record name -> fields. *)
let type_ctors : (string, (string * A.ty list) list) Hashtbl.t = Hashtbl.create 64
let record_fields : (string, (string * A.ty) list) Hashtbl.t = Hashtbl.create 64

(* Lazily built interpreter environment for [current_module].  [`Failed]
   latches: a module whose decls cannot even be evaluated is not going to
   start working on the next obligation. *)
let env_state : [ `Unset | `Ready of V.env | `Failed ] ref = ref `Unset

(* Per-module wall budget across ALL witness executions, so a pathological
   module cannot stall the compile.  Reset by [set_module]. *)
let wall_budget : int ref = ref 0

let initial_wall_budget = 1_000_000
let per_call_fuel = 100_000

let rec register_types (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, name, _, A.TDVariant vs, _) ->
        Hashtbl.replace type_ctors name.A.txt
          (List.map (fun v -> (v.A.var_name.A.txt, v.A.var_args)) vs)
      | A.DType (_, name, _, A.TDRecord fs, _) ->
        Hashtbl.replace record_fields name.A.txt
          (List.map (fun f -> (f.A.fld_name.A.txt, f.A.fld_ty)) fs)
      | A.DMod (_, _, inner, _) -> register_types inner
      | _ -> ())
    decls

let set_module (m : A.module_) : unit =
  (match !current_module with
   | Some m' when m' == m -> ()   (* same run (check_module then division_safety) *)
   | _ ->
     current_module := Some m;
     env_state := `Unset;
     wall_budget := initial_wall_budget;
     Hashtbl.reset type_ctors;
     Hashtbl.reset record_fields;
     register_types m.A.mod_decls)

(* =================================================================
   §2  Zero values and model decoding
   ================================================================= *)

let rec strip_refine : A.ty -> A.ty = function
  | A.TyRefine (base, _, _) -> strip_refine base
  | A.TyLinear (_, t) -> strip_refine t
  | t -> t

let rec zero_value ~(depth : int) (ty : A.ty) : V.value option =
  if depth <= 0 then None
  else
    match strip_refine ty with
    | A.TyCon ({ A.txt = "Int"; _ }, []) -> Some (V.VInt 0)
    | A.TyCon ({ A.txt = "Float"; _ }, []) -> Some (V.VFloat 0.0)
    | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Some (V.VBool false)
    | A.TyCon ({ A.txt = "String"; _ }, []) -> Some (V.VString "")
    | A.TyCon ({ A.txt = "Unit"; _ }, []) -> Some V.VUnit
    | A.TyCon ({ A.txt = "List"; _ }, [ _ ]) -> Some (V.VCon ("Nil", []))
    | A.TyCon ({ A.txt = "Option"; _ }, [ _ ]) -> Some (V.VCon ("None", []))
    | A.TyTuple ts ->
      let zs = List.map (zero_value ~depth:(depth - 1)) ts in
      if List.for_all Option.is_some zs then
        Some (V.VTuple (List.map Option.get zs))
      else None
    | A.TyCon ({ A.txt = name; _ }, _) ->
      (match Hashtbl.find_opt type_ctors name with
       | Some ctors ->
         (* First constructor whose payload zero-fills; declaration order,
            so the choice is deterministic. *)
         List.find_map
           (fun (cname, args) ->
             let zs = List.map (zero_value ~depth:(depth - 1)) args in
             if List.for_all Option.is_some zs then
               Some (V.VCon (cname, List.map Option.get zs))
             else None)
           ctors
       | None ->
         (match Hashtbl.find_opt record_fields name with
          | Some fields ->
            let zs =
              List.map (fun (f, t) -> (f, zero_value ~depth:(depth - 1) t)) fields
            in
            if List.for_all (fun (_, z) -> Option.is_some z) zs then
              Some (V.VRecord (List.map (fun (f, z) -> (f, Option.get z)) zs))
            else None
          | None -> None))
    | _ -> None

(* A list of [n] zero elements of type [elt]. *)
let zero_list ~(elt : A.ty) (n : int) : V.value option =
  match zero_value ~depth:3 elt with
  | None -> None
  | Some z ->
    let rec build k acc = if k <= 0 then acc else build (k - 1) (V.VCon ("Cons", [ z; acc ])) in
    Some (build n (V.VCon ("Nil", [])))

(* Parse one SMT model value string against an expected base type.  [None]
   means "cannot decode" — never guess. *)
let rec decode_smt (ty : A.ty) (s : string) : V.value option =
  let s = String.trim s in
  let tokens_of s =
    let n = String.length s in
    if n >= 2 && s.[0] = '(' && s.[n - 1] = ')' then
      Some (Refine_scope.sexp_tokens (String.sub s 1 (n - 2)))
    else None
  in
  match strip_refine ty with
  | A.TyCon ({ A.txt = "Int"; _ }, []) ->
    (match int_of_string_opt s with
     | Some n -> Some (V.VInt n)
     | None ->
       (match tokens_of s with
        | Some [ "-"; d ] ->
          Option.map (fun n -> V.VInt (-n)) (int_of_string_opt d)
        | _ -> None))
  | A.TyCon ({ A.txt = "Bool"; _ }, []) ->
    (match s with "true" -> Some (V.VBool true) | "false" -> Some (V.VBool false) | _ -> None)
  | A.TyCon ({ A.txt = "Float"; _ }, []) ->
    (match float_of_string_opt s with
     | Some f -> Some (V.VFloat f)
     | None ->
       (match tokens_of s with
        | Some [ "-"; d ] ->
          Option.map (fun f -> V.VFloat (-.f)) (float_of_string_opt d)
        | Some [ "/"; a; b ] ->
          (match float_of_string_opt a, float_of_string_opt b with
           | Some a, Some b when b <> 0.0 -> Some (V.VFloat (a /. b))
           | _ -> None)
        | _ -> None (* (fp …) bit patterns: refuse rather than misread *)))
  | A.TyCon ({ A.txt = "List"; _ }, [ elt ]) ->
    (match tokens_of s with
     | Some ("as" :: "nil" :: _) -> Some (V.VCon ("Nil", []))
     | Some [ ("insert" | "cons"); h; t ] ->
       (match decode_smt elt h, decode_smt ty t with
        | Some h, Some t -> Some (V.VCon ("Cons", [ h; t ]))
        | _ -> None)
     | _ -> if s = "nil" then Some (V.VCon ("Nil", [])) else None)
  | A.TyCon ({ A.txt = name; _ }, _) ->
    (match Hashtbl.find_opt type_ctors name with
     | Some ctors ->
       let by_ctor cname args =
         match List.assoc_opt cname ctors with
         | Some tys when List.length tys = List.length args ->
           let ds = List.map2 decode_smt tys args in
           if List.for_all Option.is_some ds then
             Some (V.VCon (cname, List.map Option.get ds))
           else None
         | _ -> None
       in
       (match tokens_of s with
        | Some (cname :: args) -> by_ctor cname args
        | None -> by_ctor s []
        | Some [] -> None)
     | None ->
       (match Hashtbl.find_opt record_fields name, tokens_of s with
        | Some fields, Some (_ctor :: args) when List.length fields = List.length args ->
          let ds = List.map2 (fun (f, t) a -> (f, decode_smt t a)) fields args in
          if List.for_all (fun (_, d) -> Option.is_some d) ds then
            Some (V.VRecord (List.map (fun (f, d) -> (f, Option.get d)) ds))
          else None
        | _ -> None))
  | _ -> None

(* The measure-length fact for [name] in the model, if any: "len$xs" -> 3. *)
let len_fact (model : (string * string) list) (name : string) : int option =
  match List.assoc_opt ("len$" ^ name) model with
  | Some s ->
    (match int_of_string_opt (String.trim s) with
     | Some n when n >= 0 -> Some n
     | _ -> None)
  | None -> None

let decode_model ~(params : (string * A.ty) list)
    ~(model : (string * string) list) : (string * V.value) list option =
  let decode_param (pname, ty) =
    let base = strip_refine ty in
    let direct =
      match List.assoc_opt pname model with
      | Some s -> decode_smt base s
      | None -> None
    in
    let v =
      match direct, base with
      | Some v, _ -> Some v
      | None, A.TyCon ({ A.txt = "String"; _ }, []) ->
        (* String model values are opaque Str!val!N witnesses; the usable
           fact is the length. *)
        (match len_fact model pname with
         | Some n -> Some (V.VString (String.make n 'a'))
         | None -> Some (V.VString ""))
      | None, A.TyCon ({ A.txt = "List"; _ }, [ elt ]) ->
        (match len_fact model pname with
         | Some n -> zero_list ~elt n
         | None -> zero_value ~depth:3 base)
      | None, _ -> zero_value ~depth:3 base
    in
    Option.map (fun v -> (pname, v)) v
  in
  let decoded = List.map decode_param params in
  if List.for_all Option.is_some decoded then Some (List.map Option.get decoded)
  else None

(* =================================================================
   §3  Predicate evaluation and structural equality
   ================================================================= *)

let rec value_eq (a : V.value) (b : V.value) : bool option =
  match a, b with
  | V.VInt a, V.VInt b -> Some (a = b)
  | V.VFloat a, V.VFloat b -> Some (a = b)
  | V.VBool a, V.VBool b -> Some (a = b)
  | V.VString a, V.VString b -> Some (String.equal a b)
  | V.VUnit, V.VUnit -> Some true
  | V.VCon (c1, a1), V.VCon (c2, a2) ->
    if c1 <> c2 then Some false
    else if List.length a1 <> List.length a2 then Some false
    else
      List.fold_left2
        (fun acc x y ->
          match acc, value_eq x y with
          | Some true, Some r -> Some r
          | Some false, _ -> Some false
          | _, None | None, _ -> None)
        (Some true) a1 a2
  | V.VTuple a, V.VTuple b when List.length a = List.length b ->
    value_eq (V.VCon ("", a)) (V.VCon ("", b))
  | V.VRecord a, V.VRecord b when List.length a = List.length b ->
    (try
       List.fold_left
         (fun acc (f, x) ->
           match acc, List.assoc_opt f b with
           | Some true, Some y -> value_eq x y
           | Some false, _ -> Some false
           | _, None -> None
           | None, _ -> None)
         (Some true) a
     with _ -> None)
  | _ -> None

let list_len (v : V.value) : int option =
  let rec go acc = function
    | V.VCon ("Nil", []) -> Some acc
    | V.VCon ("Cons", [ _; t ]) -> go (acc + 1) t
    | _ -> None
  in
  go 0 v

(* Evaluate a refinement predicate structurally over runtime values.
   Covers the reflectable fragment and a little more (nonlinear `*`);
   anything it does not recognise is [None] — unconfirmable, NEVER a
   silent true/false. *)
let rec eval_pred ~(lookup : string -> V.value option) (e : A.expr) : bool option =
  match e with
  | A.ELit (A.LitBool b, _) -> Some b
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) ->
    (match eval_pred ~lookup a, eval_pred ~lookup b with
     | Some false, _ | _, Some false -> Some false
     | Some true, Some true -> Some true
     | _ -> None)
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) ->
    (match eval_pred ~lookup a, eval_pred ~lookup b with
     | Some true, _ | _, Some true -> Some true
     | Some false, Some false -> Some false
     | _ -> None)
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    Option.map not (eval_pred ~lookup a)
  | A.EApp (A.EVar { A.txt = ("==" | "!=" | "<" | "<=" | ">" | ">=") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some va, Some vb ->
       (match op with
        | "==" -> value_eq va vb
        | "!=" -> Option.map not (value_eq va vb)
        | _ ->
          (match va, vb with
           | V.VInt x, V.VInt y ->
             Some (match op with "<" -> x < y | "<=" -> x <= y | ">" -> x > y | _ -> x >= y)
           | V.VFloat x, V.VFloat y ->
             Some (match op with "<" -> x < y | "<=" -> x <= y | ">" -> x > y | _ -> x >= y)
           | _ -> None))
     | _ -> None)
  (* A bare boolean-valued operand position: `{Bool | _}`-shaped or a tester. *)
  | _ ->
    (match eval_operand ~lookup e with
     | Some (V.VBool b) -> Some b
     | _ -> None)

and eval_operand ~(lookup : string -> V.value option) (e : A.expr) : V.value option =
  match e with
  | A.ELit (A.LitInt n, _) -> Some (V.VInt n)
  | A.ELit (A.LitFloat f, _) -> Some (V.VFloat f)
  | A.ELit (A.LitBool b, _) -> Some (V.VBool b)
  | A.ELit (A.LitString s, _) -> Some (V.VString s)
  | A.EVar { A.txt; _ } -> lookup txt
  | A.EField (recv, { A.txt = fname; _ }, _) ->
    (match eval_operand ~lookup recv with
     | Some (V.VRecord fields) -> List.assoc_opt fname fields
     | _ -> None)
  | A.ECon ({ A.txt = ctor; _ }, args, _) ->
    let vs = List.map (eval_operand ~lookup) args in
    if List.for_all Option.is_some vs then
      Some (V.VCon (ctor, List.map Option.get vs))
    else None
  | A.EApp (A.EVar { A.txt = ("len" | "List.length" | "String.length"); _ }, [ a ], _) ->
    (match eval_operand ~lookup a with
     | Some (V.VString s) -> Some (V.VInt (String.length s))
     | Some v -> Option.map (fun n -> V.VInt n) (list_len v)
     | None -> None)
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) ->
    (match eval_operand ~lookup a with
     | Some (V.VInt n) -> Some (V.VInt (-n))
     | Some (V.VFloat f) -> Some (V.VFloat (-.f))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = ("+" | "-" | "*") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some (V.VInt x), Some (V.VInt y) ->
       Some (V.VInt (match op with "+" -> x + y | "-" -> x - y | _ -> x * y))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = ("+." | "-." | "*." | "/.") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some (V.VFloat x), Some (V.VFloat y) ->
       Some (V.VFloat (match op with "+." -> x +. y | "-." -> x -. y | "*." -> x *. y | _ -> x /. y))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _)
    when Refine_scope.ctor_of_tester m <> None ->
    (match eval_operand ~lookup a, Refine_scope.ctor_of_tester m with
     | Some (V.VCon (c, _)), Some tc -> Some (V.VBool (String.equal c tc))
     | _ -> None)
  | _ -> None

(* =================================================================
   §4  Rendering: runtime value -> March source syntax
   ================================================================= *)

let render_float (f : float) : string =
  let s = Printf.sprintf "%.12g" f in
  if String.exists (fun c -> c = '.' || c = 'e' || c = 'E') s then s else s ^ ".0"

let rec render_value (v : V.value) : string option =
  match v with
  | V.VInt n -> Some (string_of_int n)
  | V.VFloat f -> Some (render_float f)
  | V.VBool b -> Some (if b then "true" else "false")
  | V.VString s -> Some ("\"" ^ String.escaped s ^ "\"")
  | V.VUnit -> Some "()"
  | V.VCon (("Nil" | "Cons"), _) ->
    let rec elems acc = function
      | V.VCon ("Nil", []) -> Some (List.rev acc)
      | V.VCon ("Cons", [ h; t ]) ->
        (match render_value h with Some s -> elems (s :: acc) t | None -> None)
      | _ -> None
    in
    Option.map (fun es -> "[" ^ String.concat ", " es ^ "]") (elems [] v)
  | V.VCon (c, []) -> Some c
  | V.VCon (c, args) ->
    let rs = List.map render_value args in
    if List.for_all Option.is_some rs then
      Some (c ^ "(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
    else None
  | V.VTuple vs ->
    let rs = List.map render_value vs in
    if List.for_all Option.is_some rs then
      Some ("(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
    else None
  | V.VRecord fields ->
    let rs = List.map (fun (f, v) -> Option.map (fun s -> f ^ ": " ^ s) (render_value v)) fields in
    if List.for_all Option.is_some rs then
      Some ("{ " ^ String.concat ", " (List.map Option.get rs) ^ " }")
    else None
  | _ -> None

let render_call (fn : string) (args : (string * V.value) list) : string option =
  let rs = List.map (fun (_, v) -> render_value v) args in
  if List.for_all Option.is_some rs then
    Some (fn ^ "(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
  else None

(* =================================================================
   §5  Execution: fuel-limited, effect-denied interpretation
   ================================================================= *)

(* Builtin names vetoed during witness execution.  Exact names come from the
   typechecker's capability table (the canonical list of IO builtins); the
   prefixes cover the runtime families (sockets, processes, tasks, actors,
   websockets, TLS) wholesale — over-blocking is safe, it only widens
   "unconfirmable".  Time and randomness are blocked for determinism, not
   safety. *)
let blocked_prefixes =
  [ "tcp_"; "tls_"; "ws_"; "http_"; "process_"; "task_"; "actor_"; "file_"
  ; "dir_"; "socket_"; "udp_"; "signal_"; "vault_"; "channel_" ]

let blocked_exact =
  [ "random_bytes"; "stdlib_random_bytes"; "unix_time"; "unix_time_ms"
  ; "sys_uptime_ms"; "send_checked"; "mint_cap"; "cap_narrow" ]

let blocked_name : string -> bool =
  let table = lazy (
    let t = Hashtbl.create 256 in
    List.iter
      (fun (n, _) -> Hashtbl.replace t n ())
      March_typecheck.Typecheck_builtins.builtin_cap_table;
    List.iter (fun n -> Hashtbl.replace t n ()) blocked_exact;
    t)
  in
  fun name ->
    Hashtbl.mem (Lazy.force table) name
    || List.exists
         (fun p ->
           String.length name > String.length p
           && String.sub name 0 (String.length p) = p)
         blocked_prefixes

type exec_result =
  | Ret of V.value
  | Panicked of string
      (** A USER-level panic, carrying the user's own message with the
          builtin's marker prefix stripped — see [user_panic_message]. *)
  | Unconfirmable  (* blocked effect, fuel out, evaluator error, missing fn, … *)

(* Is this [Eval_error] message a user panic, and if so what did the user
   write?

   [Eval_error] is NOT the panic exception.  It is the evaluator's general
   failure channel: [Eval_prim.eval_error] raises it, and ~860 internal sites
   across `lib/eval/` use it for unbound variables, arity mismatches, desugar
   residue ("EResultRef reached evaluator") and every other internal
   limitation.  Confirming one of those as "the program panics" would report a
   failure in a program that has none — a false positive with nothing to do
   with the model.

   The four user-facing panic builtins are distinguished by a message prefix
   they alone produce (`lib/eval/eval_builtins.ml`, the `panic` / `panic_` /
   `todo_` / `unreachable_` entries); no other [eval_error] call site in
   `lib/eval/` begins with one.  That is a soft contract — a reformat of those
   entries would silently turn every user panic into a decline — so the unit
   suite pins BOTH directions: a real `panic("…")` confirms with the user's
   text, and a provoked internal error declines.

   Deliberately NOT classified as panics: [Eval.Match_failure] and
   [Eval.Assert_failure] (declared in `lib/eval/eval.ml`, not in `eval_prim.ml`
   which declares only [Eval_error] and [Blocked_builtin]), which are separate
   exceptions and genuinely ARE user-level failures.  They keep declining (via the catch-all below).  That
   is a coverage gap, not a soundness one, and closing it means deciding
   whether "let binding pattern failed: …" is a requirement a caller can be
   asked to declare — a Task 6 question, not this one. *)
let user_panic_message (msg : string) : string option =
  let strip p =
    let lp = String.length p in
    if String.length msg >= lp && String.sub msg 0 lp = p then
      Some (String.sub msg lp (String.length msg - lp))
    else None
  in
  match strip "panic: " with
  | Some m -> Some m
  | None ->
    (match strip "todo: " with
     | Some m -> Some m
     | None ->
       (match strip "unreachable: " with
        | Some m -> Some m
        | None -> if msg = "panic" then Some "panic" else None))

(* Run [f] with the guard installed and [per_call_fuel] reductions available,
   charging the module-wide [wall_budget].  Restores both hooks on every
   path — the caller may be the LSP or a test binary that goes on to run the
   real interpreter. *)
let with_harness (f : unit -> 'a) : ('a, exec_result) result =
  if !wall_budget <= 0 then Error Unconfirmable
  else begin
    let fuel = min per_call_fuel !wall_budget in
    March_eval.Eval_prim.builtin_guard :=
      Some (fun name ->
        if blocked_name name then
          raise (March_eval.Eval_prim.Blocked_builtin name));
    March_eval.Eval.arm_reduction_budget fuel;
    Fun.protect
      ~finally:(fun () ->
        (* Charge what this execution actually used, so a module full of
           expensive candidates still terminates. *)
        wall_budget :=
          !wall_budget - max 1 (March_eval.Eval.reductions_used fuel);
        March_eval.Eval.set_reduction_counting false;
        March_eval.Eval_prim.builtin_guard := None)
      (fun () ->
        try Ok (f ())
        with
        | March_eval.Eval.Yield -> Error Unconfirmable
        | March_eval.Eval_prim.Blocked_builtin _ -> Error Unconfirmable
        | March_eval.Eval_prim.Eval_error msg ->
          (* Only a USER panic is a confirmable failure; every other
             [Eval_error] is an evaluator limitation.  See
             [user_panic_message]. *)
          (match user_panic_message msg with
           | Some m -> Error (Panicked m)
           | None -> Error Unconfirmable)
        | _ -> Error Unconfirmable)
  end

(* The interpreter environment for [current_module], built on first use under
   the harness (module initialisation itself must be inert and bounded). *)
let module_env () : V.env option =
  match !env_state with
  | `Ready env -> Some env
  | `Failed -> None
  | `Unset ->
    (match !current_module with
     | None -> env_state := `Failed; None
     | Some m ->
       (match with_harness (fun () -> March_eval.Eval.eval_module_env m) with
        | Ok env -> env_state := `Ready env; Some env
        | Error _ -> env_state := `Failed; None))

(* Find a function value by bare name: an exact binding wins; otherwise a
   single qualified "Mod.name" binding is unambiguous; several such bindings
   mean we cannot tell which definition the obligation is about — skip. *)
let lookup_fn (env : V.env) (name : string) : V.value option =
  match List.assoc_opt name env with
  | Some v -> Some v
  | None ->
    let suffix = "." ^ name in
    let sl = String.length suffix in
    let matches =
      List.filter
        (fun (k, _) ->
          let kl = String.length k in
          kl > sl && String.sub k (kl - sl) sl = suffix)
        env
    in
    (* Deduplicate by key: the assoc list carries shadowed rebindings. *)
    let keys = List.sort_uniq compare (List.map fst matches) in
    (match keys with
     | [ k ] -> List.assoc_opt k env
     | _ -> None)

let call_fn ~(name : string) ~(args : V.value list) : exec_result =
  match module_env () with
  | None -> Unconfirmable
  | Some env ->
    (match lookup_fn env name with
     | None -> Unconfirmable
     | Some f ->
       (match with_harness (fun () -> March_eval.Eval.apply f args) with
        | Ok v -> Ret v
        | Error e -> e))

(* =================================================================
   §6  Confirmation: admissibility + execute + check
   ================================================================= *)

(* Every parameter whose declared type carries a refinement must satisfy it —
   a "witness" the contract already excludes would blame the caller for an
   input the function never promises to handle.  Zero-filled don't-cares are
   exactly how such inputs arise. *)
let admissible ~(params : (string * A.ty) list) (args : (string * V.value) list) : bool =
  List.for_all
    (fun (pname, ty) ->
      match ty with
      | A.TyRefine (_, binder, pred) ->
        let bname = match binder with Some b -> b.A.txt | None -> "_" in
        let self = List.assoc_opt pname args in
        let lookup n =
          if n = bname || n = "_" then self else List.assoc_opt n args
        in
        (match self with
         | None -> false
         | Some _ -> eval_pred ~lookup pred = Some true)
      | _ -> true)
    params

(* One execute+check round: run the function on [args] and decide whether the
   return predicate is VIOLATED by the actual result. *)
let violates_post ~(fn_name : string) ~(binder : string) ~(ret_pred : A.expr)
    (args : (string * V.value) list) : V.value option =
  match call_fn ~name:fn_name ~args:(List.map snd args) with
  | Ret v ->
    let lookup n =
      if n = binder || n = "_" then Some v else List.assoc_opt n args
    in
    if eval_pred ~lookup ret_pred = Some false then Some v else None
  | Panicked _ | Unconfirmable -> None

let annotated_params (fn_params : (string * A.ty option) list)
    : (string * A.ty) list option =
  let ps = List.map (fun (n, t) -> Option.map (fun t -> (n, t)) t) fn_params in
  if List.for_all Option.is_some ps then Some (List.map Option.get ps) else None

(* =================================================================
   §7  Shrinking

   QuickCheck-style minimisation with the confirmation pipeline itself as
   the oracle: a candidate replaces the current witness only if it is still
   admissible AND still observed to violate.  Fully deterministic — fixed
   probe order, no randomness — because the witness text is pinned by test
   fixtures and the types-oracle.  Bounded by [shrink_attempts] oracle
   invocations. *)

let shrink_attempts = 64

(* Candidate replacements for one value, most-preferred first. *)
let rec shrink_candidates (v : V.value) : V.value list =
  match v with
  | V.VInt 0 -> []
  | V.VInt n ->
    (* Fixed probes make the endpoint independent of the model Z3 chose
       (any start converges to the first violating probe), then halving
       covers the far cases. *)
    let probes = [ 0; 1; -1; 2; -2 ] in
    let halves =
      let rec go n acc = if n = 0 || n = -1 || n = 1 then List.rev acc else go (n / 2) (n / 2 :: acc) in
      go n []
    in
    List.filter_map
      (fun i -> if i = n then None else Some (V.VInt i))
      (probes @ halves)
  | V.VFloat 0.0 -> []
  | V.VFloat f ->
    List.filter (fun c -> c <> v)
      [ V.VFloat 0.0; V.VFloat 1.0; V.VFloat (-1.0); V.VFloat (f /. 2.0) ]
  | V.VString "" -> []
  | V.VString s ->
    [ V.VString ""; V.VString (String.sub s 0 (String.length s - 1)) ]
  | V.VCon ("Nil", []) -> []
  | V.VCon ("Cons", [ h; t ]) ->
    (* Drop the whole list, drop the head, then shrink head/tail pointwise. *)
    (V.VCon ("Nil", []) :: (if t <> V.VCon ("Nil", []) then [ t ] else []))
    @ List.map (fun h' -> V.VCon ("Cons", [ h'; t ])) (shrink_candidates h)
    @ List.map (fun t' -> V.VCon ("Cons", [ h; t' ])) (shrink_candidates t)
  | V.VCon (c, args) ->
    List.concat
      (List.mapi
         (fun i a ->
           List.map
             (fun a' -> V.VCon (c, List.mapi (fun j x -> if j = i then a' else x) args))
             (shrink_candidates a))
         args)
  | V.VTuple args ->
    List.concat
      (List.mapi
         (fun i a ->
           List.map
             (fun a' -> V.VTuple (List.mapi (fun j x -> if j = i then a' else x) args))
             (shrink_candidates a))
         args)
  | V.VRecord fields ->
    List.concat
      (List.map
         (fun (f, a) ->
           List.map
             (fun a' ->
               V.VRecord (List.map (fun (g, x) -> (g, if g = f then a' else x)) fields))
             (shrink_candidates a))
         fields)
  | _ -> []

(* Structural size of a value; the shrink loop only accepts a candidate of
   STRICTLY smaller total weight, which is what makes it terminate (probes
   like 1 and -1 can each confirm, and without an ordering the loop would
   oscillate between them forever).  Negatives weigh one more than their
   absolute value so 1 canonically beats -1. *)
let rec weight (v : V.value) : int =
  match v with
  | V.VInt n -> (2 * abs n) + (if n < 0 then 1 else 0)
  | V.VFloat f ->
    if f = 0.0 then 0
    else if f = 1.0 then 2
    else if f = -1.0 then 3
    else 4 + (if f < 0.0 then 1 else 0)
  | V.VBool b -> if b then 1 else 0
  | V.VString s -> String.length s
  | V.VUnit -> 0
  | V.VCon ("Nil", []) -> 0
  | V.VCon (_, args) -> 1 + List.fold_left (fun a v -> a + weight v) 0 args
  | V.VTuple args -> List.fold_left (fun a v -> a + weight v) 0 args
  | V.VRecord fields -> List.fold_left (fun a (_, v) -> a + weight v) 0 fields
  | _ -> 0

let args_weight (args : (string * V.value) list) : int =
  List.fold_left (fun a (_, v) -> a + weight v) 0 args

(* Greedy outer loop: repeatedly take the first strictly-smaller confirming
   candidate at the first position that has one, until a full pass finds
   none or the attempt budget runs out.  [run] returns [Some ret] iff the
   candidate is a confirmed witness. *)
let shrink ~(run : (string * V.value) list -> V.value option)
    (args : (string * V.value) list) (ret : V.value)
    : (string * V.value) list * V.value =
  let budget = ref shrink_attempts in
  let rec pass args ret =
    let w = args_weight args in
    let rec try_positions before after =
      match after with
      | [] -> None
      | (pname, v) :: rest ->
        let try_cand c =
          if !budget <= 0 then None
          else begin
            let cand = List.rev_append before ((pname, c) :: rest) in
            if args_weight cand >= w then None
            else begin
              decr budget;
              Option.map (fun r -> (cand, r)) (run cand)
            end
          end
        in
        (match List.find_map try_cand (shrink_candidates v) with
         | Some improved -> Some improved
         | None -> try_positions ((pname, v) :: before) rest)
    in
    if !budget <= 0 then (args, ret)
    else
      match try_positions [] args with
      | Some (args', ret') -> pass args' ret'
      | None -> (args, ret)
  in
  pass args ret

(* =================================================================
   §7b Enumerative battery

   For obligations the solver never sees (an unreflectable tail such as
   `x * y`, or an unreflectable predicate) there is no model to confirm —
   but the same execute+check oracle can probe a fixed, ordered battery of
   small inputs.  First confirmed combination wins and is then shrunk, so
   the reported witness is canonical regardless of battery order details.
   Bounded: at most [battery_cap] combinations, each fuel-limited. *)

let battery_cap = 48

let battery_values (ty : A.ty) : V.value list =
  match strip_refine ty with
  | A.TyCon ({ A.txt = "Int"; _ }, []) ->
    [ V.VInt 0; V.VInt 1; V.VInt (-1); V.VInt 2; V.VInt 10 ]
  | A.TyCon ({ A.txt = "Float"; _ }, []) ->
    [ V.VFloat 0.0; V.VFloat 1.0; V.VFloat (-1.0) ]
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> [ V.VBool false; V.VBool true ]
  | A.TyCon ({ A.txt = "String"; _ }, []) -> [ V.VString ""; V.VString "a" ]
  | A.TyCon ({ A.txt = "List"; _ }, [ elt ]) as t ->
    (match zero_value ~depth:3 elt with
     | Some z ->
       [ V.VCon ("Nil", []); V.VCon ("Cons", [ z; V.VCon ("Nil", []) ]) ]
     | None -> (match zero_value ~depth:3 t with Some v -> [ v ] | None -> []))
  | t -> (match zero_value ~depth:3 t with Some v -> [ v ] | None -> [])

(* Cartesian product in declaration order, last parameter varying fastest,
   truncated to [battery_cap]. *)
let battery ~(params : (string * A.ty) list) : (string * V.value) list list =
  let rec product = function
    | [] -> [ [] ]
    | (n, vs) :: rest ->
      let tails = product rest in
      List.concat_map (fun v -> List.map (fun t -> (n, v) :: t) tails) vs
  in
  let all = product (List.map (fun (n, t) -> (n, battery_values t)) params) in
  List.filteri (fun i _ -> i < battery_cap) all

let confirm_enumerative ~(fn_name : string)
    ~(fn_params : (string * A.ty option) list) ~(binder : string)
    ~(ret_pred : A.expr) : ((string * V.value) list * V.value) option =
  match annotated_params fn_params with
  | None -> None
  | Some params ->
    if params = [] then None
    else
      let run cand =
        if admissible ~params cand then
          violates_post ~fn_name ~binder ~ret_pred cand
        else None
      in
      List.find_map
        (fun cand -> Option.map (fun ret -> (cand, ret)) (run cand))
        (battery ~params)
      |> Option.map (fun (args, ret) -> shrink ~run args ret)

(* =================================================================
   §8  Call-site preconditions

   Different shape from return contracts: the violation verdict is already
   sound (it requires the negated goal to be VALID), so no function is
   executed — the job is to turn the raw model into a validated, shrunk,
   source-syntax example.  The assignment must satisfy every refinement in
   the caller's scope and every path fact, and the argument expression
   evaluated under it must violate the predicate; anything unevaluable
   falls back to the raw rendering at the site. *)

let free_vars (e : A.expr) : string list =
  let acc = ref [] in
  let add n = if n <> "_" && not (List.mem n !acc) then acc := n :: !acc in
  let rec go = function
    | A.EVar { A.txt; _ } -> add txt
    | A.EApp (f, args, _) -> go f; List.iter go args
    | A.ECon (_, args, _) -> List.iter go args
    | A.EField (r, _, _) -> go r
    | A.ETuple (es, _) -> List.iter go es
    | _ -> ()
  in
  go e;
  List.rev !acc

(* Decode ONE caller-scope variable from the model, guided by its scope sort
   marker ([None] = Int for a refined scalar; "$Str"/"$Bool"/"$Float"; a
   [len$name] fact marks a sequence).  Unrefined names fall back to what the
   model literally says, or 0. *)
let decode_scope_var ~(sc : (string * (string * A.expr * string option)) list)
    ~(model : (string * string) list) (name : string) : V.value option =
  let marker = Option.map (fun (_, _, s) -> s) (List.assoc_opt name sc) in
  let direct ty = Option.bind (List.assoc_opt name model) (decode_smt ty) in
  let t_int = A.TyCon ({ A.txt = "Int"; A.span = A.dummy_span }, []) in
  let t_bool = A.TyCon ({ A.txt = "Bool"; A.span = A.dummy_span }, []) in
  let t_float = A.TyCon ({ A.txt = "Float"; A.span = A.dummy_span }, []) in
  match marker with
  | Some (Some "$Str") ->
    Some (V.VString (String.make (Option.value ~default:0 (len_fact model name)) 'a'))
  | _ when len_fact model name = Some 0 ->
    (* A `len$name = 0` fact identifies an empty sequence whatever sort the
       scope declared it at (lists ride the ADT sorts). *)
    Some (V.VCon ("Nil", []))
  | _ when len_fact model name <> None ->
    (* A non-empty sequence with unknown element type would have to be
       rendered with guessed elements — refuse rather than lie. *)
    None
  | Some (Some "$Bool") -> Some (Option.value ~default:(V.VBool false) (direct t_bool))
  | Some (Some "$Float") -> Some (Option.value ~default:(V.VFloat 0.0) (direct t_float))
  | Some (Some _) -> None (* ADT/record-sorted scope var: not decoded in v1 *)
  | Some None | None ->
    (match direct t_int with
     | Some v -> Some v
     | None ->
       (match direct t_bool with
        | Some v -> Some v
        | None -> Some (V.VInt 0)))

let confirm_precond ~(sc : (string * (string * A.expr * string option)) list)
    ~(path : (A.expr * bool) list) ~(pred : A.expr) ~(binder : string)
    ~(arg : A.expr) ~(model : (string * string) list)
    : (string * V.value) list option =
  let ident_ok n =
    n <> "" && (match n.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false)
  in
  let domain =
    List.sort_uniq compare
      (List.map fst sc
      @ free_vars arg
      @ List.filter (fun k -> ident_ok k && not (String.contains k '$')) (List.map fst model))
  in
  let render_set = free_vars arg in
  if render_set = [] then None
  else
    let decoded = List.map (fun n -> Option.map (fun v -> (n, v)) (decode_scope_var ~sc ~model n)) domain in
    if not (List.for_all Option.is_some decoded) then None
    else
      let assignment = List.map Option.get decoded in
      let ok (asg : (string * V.value) list) : bool =
        let lookup n = List.assoc_opt n asg in
        (* Every scope refinement must hold under its own binder… *)
        List.for_all
          (fun (name, (b, p, _)) ->
            match List.assoc_opt name asg with
            | None -> false
            | Some self ->
              let lk n = if n = b || n = "_" then Some self else lookup n in
              eval_pred ~lookup:lk p = Some true)
          sc
        (* …every path fact must hold with its recorded polarity… *)
        && List.for_all
             (fun (cond, negated) -> eval_pred ~lookup cond = Some (not negated))
             path
        (* …and the argument must genuinely violate the predicate. *)
        &&
        match eval_operand ~lookup arg with
        | None -> false
        | Some av ->
          let lk n = if n = binder || n = "_" then Some av else lookup n in
          eval_pred ~lookup:lk pred = Some false
      in
      if not (ok assignment) then None
      else
        let run cand = if ok cand then Some V.VUnit else None in
        let shrunk, _ = shrink ~run assignment V.VUnit in
        let entries = List.filter (fun (n, _) -> List.mem n render_set) shrunk in
        if entries = [] then None else Some entries

let render_entries (entries : (string * V.value) list) : string option =
  let rs =
    List.map (fun (n, v) -> Option.map (fun s -> n ^ " = " ^ s) (render_value v)) entries
  in
  if List.for_all Option.is_some rs then
    Some (String.concat ", " (List.map Option.get rs))
  else None

(* =================================================================
   §8b  Reachable call-site precondition confirmation

   [confirm_precond] above validates a candidate against the RECORDED path
   facts.  That is sound where the solver already settled the verdict — the
   witness is illustrative decoration on a proof.  It is unsound as a
   PROMOTION gate for the undecided bucket, and unsound exactly where that
   bucket is most populated: undecidedness there is caused by a MISSING fact,
   and a missing fact is by definition not in [path] to be checked against, so
   a candidate violating it sails through.  `stdlib/list.march`'s `last` is the
   worked case: `t = Nil` satisfies every recorded fact in the `Cons(_, t)`
   arm, and the arm exclusion that rules it out is precisely the fact the
   checker never derived.

   The gate below never assumes reachability, it demonstrates it: run the
   ENCLOSING function from its entry on arguments the model assigns to that
   function's own parameters, and confirm only on an actual panic.  See
   specs/2026-09-01-refinement-error-diagnosis-design.md §2.

   Placed here rather than beside [violates_post] because it consumes
   [annotated_params], [shrink], [battery] and [free_vars], all defined below
   that point.  (Names, not line numbers: the numbers rot on every edit.)
   ================================================================= *)

(* A parameter type is *witness-safe* when [admissible] genuinely decides it.

   [admissible] pattern-matches a single [A.TyRefine] at the top of the
   declared type; a refinement anywhere else is silently unchecked.  Three
   such places exist and all three parse today: a type argument
   (`List({Int | _ > 0})`), a record field (`type Box = { v : {Int | _ > 0} }`)
   and a [TyLinear] wrapper around the outer refinement (which [strip_refine]
   sees through and [admissible] does not).  A zero-filled decode may then
   produce a value the DECLARED type excludes, and confirming a panic on it
   would report a requirement the caller never had.

   Stated precisely, because the obvious phrasing overclaims: the checker does
   not enforce nested refinements TODAY — `g([0, -5])` against
   `List({Int | _ > 0})` passes `--check` in silence — so such a value is not
   currently unconstructible, and this walk is defence-in-depth rather than a
   live bug fix.  It closes the hole the moment nested enforcement lands, at
   the cost of declining a promotion whose parameters carry one.

   So the walk rejects any refinement below the outermost position, and treats
   an unknown type name as unsafe — an unregistered name may expand to
   anything.

   A type VARIABLE carries no refinement and is allowed here; a parameter
   actually typed by one is declined further down by [decode_model], which has
   no zero value for it. *)
let rec refinement_free ~(seen : string list) (ty : A.ty) : bool =
  match ty with
  | A.TyRefine _ -> false
  | A.TyLinear (_, t) -> refinement_free ~seen t
  | A.TyVar _ | A.TyArrow _ | A.TyNat _ | A.TyNatOp _ | A.TyChan _ -> true
  | A.TyTuple ts -> List.for_all (refinement_free ~seen) ts
  | A.TyRecord fs -> List.for_all (fun (_, t) -> refinement_free ~seen t) fs
  | A.TyCon (n, args) ->
    List.for_all (refinement_free ~seen) args
    && named_refinement_free ~seen n.A.txt

(* A REGISTERED definition always wins over the built-in allowlist below: a
   user is free to declare `type Option = Weird({Int | _ > 0})`, and
   [zero_value] would build `Weird(0)` from that definition, so answering from
   the allowlist would declare safe a type whose own definition is refined. *)
and named_refinement_free ~(seen : string list) (name : string) : bool =
  (* A recursive type is being proved by the frame that pushed it. *)
  if List.mem name seen then true
  else
    let seen' = name :: seen in
    match Hashtbl.find_opt type_ctors name with
    | Some ctors ->
      List.for_all
        (fun (_, ats) -> List.for_all (refinement_free ~seen:seen') ats)
        ctors
    | None ->
      (match Hashtbl.find_opt record_fields name with
       | Some fs -> List.for_all (fun (_, t) -> refinement_free ~seen:seen' t) fs
       | None ->
         (* Not declared in this program: the primitives and the containers
            [zero_value] builds structurally, whose arguments the caller
            already walked.  Anything else may expand to anything. *)
         (match name with
          | "Int" | "Float" | "Bool" | "String" | "Char" | "Bytes" | "Unit"
          | "List" | "Option" -> true
          | _ -> false))

(* [admissible] decides this parameter, and nothing below it hides a
   refinement it cannot see. *)
let witness_safe_param ((_, ty) : string * A.ty) : bool =
  match ty with
  | A.TyRefine (base, _, _) -> refinement_free ~seen:[] base
  | t -> refinement_free ~seen:[] t

(* One clause parameter as [annotated_params] wants it. *)
let clause_param (fp : A.fn_param) : string * A.ty option =
  match fp with
  | A.FPNamed p | A.FPDefault (p, _) -> (p.A.param_name.A.txt, p.A.param_ty)
  (* A pattern head binds no name we could hand an argument to; the [None]
     type makes [annotated_params] decline. *)
  | A.FPPat _ -> ("_", None)

(* The name under which [fn] is BOUND in the interpreter environment.

   [call_fn] resolves by name and [lookup_fn] prefers an EXACT bare-name
   binding, so handing it `fn.fn_name.txt` runs the wrong definition whenever
   the enclosing function lives in a nested `mod` and a top-level function
   shares its short name:

     mod P7 do
       fn f(ys : List(Int)) : Int do panic("outer boom") end
       mod Inner do fn f(ys : List(Int)) : Int do 0 end end
     end

   `Inner.f` returns 0 on every input, but the bare lookup finds the
   top-level `f` and reports its panic against `Inner.f`.  That is exactly the
   failure this gate exists to prevent — a confirmation for a function that
   cannot reach the panic — and it is the NORMAL shape of the AST, not a
   contrivance: [Refine_check] walks [A.DMod] (so a nested function really is
   the enclosing one) and prepends the whole stdlib as [A.DMod]s.

   So resolve by IDENTITY instead: find where this very [fn_def] sits in the
   module tree and qualify it with that path, which is how [Eval]'s [DMod] arm
   exports nested members.  Not found, or found twice, means we cannot say
   which definition would run — decline. *)
let qualified_fn_name (fn : A.fn_def) : string option =
  match !current_module with
  | None -> None
  | Some m ->
    let found = ref [] in
    let rec walk prefix decls =
      List.iter
        (function
          | A.DFn (fd, _) when fd == fn ->
            found := (prefix ^ fd.A.fn_name.A.txt) :: !found
          | A.DMod (name, _, inner, _) -> walk (prefix ^ name.A.txt ^ ".") inner
          | _ -> ())
        decls
    in
    walk "" m.A.mod_decls;
    (match !found with [ q ] -> Some q | _ -> None)

(* Confirm a call-site precondition failure by DEMONSTRATING reachability:
   run the enclosing function on arguments the model assigns to its own
   parameters and observe an actual panic.  Returns the shrunk argument
   assignment paired with the user's panic message, or [None].

   [pred]/[binder]/[arg] describe the obligation exactly as [confirm_precond]
   takes them: the callee's precondition, its binder, and the argument
   expression at the call site.

   Five things must hold and none is assumed:

     - the model assigns the enclosing function's own PARAMETERS (a match
       binder or a let-bound temporary is not one, which is what makes the
       `List.last` shape decline),
     - those arguments are admissible under the function's OWN refinements
       (else we would blame a caller for an input the function never promised
       to accept),
     - the argument expression, evaluated from those parameters alone, really
       does VIOLATE the callee's precondition,
     - executing the enclosing function actually panics, and
     - repairing ONLY the subject makes the panic go away.

   The last two are separate requirements because the interpreter cannot tell
   us where a panic came from.  [Eval_prim.Eval_error] carries a string and
   nothing else — no span, no function identity — so "the panic originated at
   this call" is not a question that can be asked.  Without the repair check,
   this confirms a panic from an unrelated branch:

     fn go(ys : List(Int), n : Int) : Int do
       if n == 0 do panic("unrelated") else head(ys) end
     end

   where the don't-care `n` zero-fills to 0, `head(ys)` is never evaluated,
   and Task 6 would pair `head`'s requirement with a panic that declaring it
   would not remove.  Re-running with the subject repaired to a value the
   precondition ACCEPTS still panics there, so it declines; in the real shape
   `go(ys) = head(ys)` the repaired run returns and it confirms.

   RESIDUAL IMPRECISION, stated plainly: this demonstrates that the panic is
   attributable to the subject's value, not that it was raised inside the
   callee.  A function that panics for its own reasons on exactly the inputs
   the precondition rejects would still confirm.  Both halves of the reported
   sentence are nonetheless true — the input violates the requirement, and the
   function panics on it, and not on the repaired one. *)
let confirm_precond_reachable ~(fn : A.fn_def) ~(pred : A.expr)
    ~(binder : string) ~(arg : A.expr) ~(model : (string * string) list)
    : ((string * V.value) list * string) option =
  match fn.A.fn_clauses, qualified_fn_name fn with
  | [ clause ], Some fname when clause.A.fc_guard = None ->
    (* A guard is a second acceptance condition that [admissible] does not
       model: a candidate failing it crashes with a clause-match error rather
       than with the requirement we would be reporting.  Decline. *)
    (match annotated_params (List.map clause_param clause.A.fc_params) with
     | None -> None
     | Some params ->
       (* Nullary: there is no argument for a caller to have got wrong, and no
          parameter for the suggested precondition to land on. *)
       if params = [] then None
       else if not (List.for_all witness_safe_param params) then None
       else
         (* The parameters the call-site argument is actually built from.  If
            it mentions none of them — a literal, a `let`-bound temporary, a
            match binder — then the enclosing function's entry cannot control
            it and there is nothing to demonstrate. *)
         let subjects =
           let fv = free_vars arg in
           List.filter (fun (n, _) -> List.mem n fv) params
         in
         if subjects = [] then None
         else
           (* [Some true] / [Some false] / [None] for "the argument computed
              from [cand] satisfies the callee's precondition". *)
           let holds cand =
             let lookup n = List.assoc_opt n cand in
             match eval_operand ~lookup arg with
             | None -> None
             | Some av ->
               let lk n = if n = binder || n = "_" then Some av else lookup n in
               eval_pred ~lookup:lk pred
           in
           let panic_of cand =
             match call_fn ~name:fname ~args:(List.map snd cand) with
             | Panicked msg -> Some msg
             | Ret _ | Unconfirmable -> None
           in
           (* One confirmation round: admissible, genuinely violating, and
              observed to panic. *)
           let run cand =
             if admissible ~params cand && holds cand = Some false then
               Option.map (fun _ -> V.VUnit) (panic_of cand)
             else None
           in
           (match decode_model ~params ~model with
            | None -> None
            | Some args ->
              (match run args with
               | None -> None
               | Some _ ->
                 (* Shrink with the same oracle, then re-read the panic from
                    the shrunk candidate: a smaller input may panic in a
                    different place, and quoting the original message beside
                    the shrunk arguments would be a lie. *)
                 let shrunk, _ = shrink ~run args V.VUnit in
                 (* Causality: some assignment differing from the witness ONLY
                    in the subject, admissible and satisfying the callee's
                    precondition, must run without panicking.  Bounded by
                    [battery]'s own cap. *)
                 let repaired_runs_clean sub =
                   let cand =
                     List.map
                       (fun (n, v) ->
                         match List.assoc_opt n sub with
                         | Some v' -> (n, v')
                         | None -> (n, v))
                       shrunk
                   in
                   admissible ~params cand
                   && holds cand = Some true
                   (* An actual RETURN, not merely "no panic observed".
                      [panic_of] collapses [Unconfirmable] into [None], and a
                      repaired run can be unconfirmable for reasons that say
                      nothing about the panic: fuel exhaustion, a blocked
                      builtin, an internal [Eval_error], or — the nastiest —
                      a spent [wall_budget], after which EVERY later call
                      short-circuits to [Unconfirmable].  Scoring any of those
                      as "the panic went away" makes the demonstration
                      vacuous and restores the unrelated-branch false
                      positive this check exists to stop. *)
                   && (match
                         call_fn ~name:fname ~args:(List.map snd cand)
                       with
                       | Ret _ -> true
                       | Panicked _ | Unconfirmable -> false)
                 in
                 if not (List.exists repaired_runs_clean (battery ~params:subjects))
                 then None
                 else Option.map (fun msg -> (shrunk, msg)) (panic_of shrunk))))
  (* A multi-head function is several clauses after desugar; executing it is
     still well defined, but which clause the panic came from is not, and the
     message would have to guess. *)
  | _ -> None

(* =================================================================
   §9  Division safety

   Confirm that an ADMISSIBLE assignment (params satisfy their own Int
   refinements, path facts hold) makes the divisor variable zero.  All
   division-safety obligations are over Int-refined parameters, so the
   assignment is Int-only; the informative entry is the divisor itself. *)

let confirm_div ~(params : (string * string * A.expr) list)
    ~(path : (A.expr * bool) list) ~(divisor : string)
    ~(model : (string * string) list) : (string * V.value) list option =
  let t_int = A.TyCon ({ A.txt = "Int"; A.span = A.dummy_span }, []) in
  let ident_ok n =
    n <> "" && (match n.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false)
  in
  let domain =
    List.sort_uniq compare
      ((divisor :: List.map (fun (n, _, _) -> n) params)
      @ List.filter (fun k -> ident_ok k && not (String.contains k '$')) (List.map fst model))
  in
  let assignment =
    List.map
      (fun n ->
        match Option.bind (List.assoc_opt n model) (decode_smt t_int) with
        | Some v -> (n, v)
        | None -> (n, V.VInt 0))
      domain
  in
  let ok (asg : (string * V.value) list) : bool =
    let lookup n = List.assoc_opt n asg in
    List.assoc_opt divisor asg = Some (V.VInt 0)
    && List.for_all
         (fun (name, b, p) ->
           match List.assoc_opt name asg with
           | None -> false
           | Some self ->
             let lk n = if n = b || n = "_" then Some self else lookup n in
             eval_pred ~lookup:lk p = Some true)
         params
    && List.for_all
         (fun (cond, negated) -> eval_pred ~lookup cond = Some (not negated))
         path
  in
  if not (ok assignment) then None
  else
    let run cand = if ok cand then Some V.VUnit else None in
    let shrunk, _ = shrink ~run assignment V.VUnit in
    match List.assoc_opt divisor shrunk with
    | Some v -> Some [ (divisor, v) ]
    | None -> None

(* Confirm a Refuted model against a return contract: decoded, admissible,
   executed, observed to violate the predicate, then shrunk — or [None]. *)
let confirm_post ~(fn_name : string) ~(fn_params : (string * A.ty option) list)
    ~(binder : string) ~(ret_pred : A.expr)
    ~(model : (string * string) list)
    : ((string * V.value) list * V.value) option =
  match annotated_params fn_params with
  | None -> None
  | Some params ->
    (match decode_model ~params ~model with
     | None -> None
     | Some args ->
       let run cand =
         let dbg = Sys.getenv_opt "MARCH_WITNESS_DEBUG" <> None in
         if dbg then
           Printf.eprintf "[witness] run cand: %s adm=%b\n%!"
             (Option.value ~default:"?" (render_call fn_name cand))
             (admissible ~params cand);
         if admissible ~params cand then begin
           let r = violates_post ~fn_name ~binder ~ret_pred cand in
           if dbg then
             Printf.eprintf "[witness]   violates -> %s\n%!"
               (match r with Some v -> Option.value ~default:"?" (render_value v) | None -> "no");
           r
         end
         else None
       in
       if not (admissible ~params args) then None
       else
         Option.map (fun ret -> shrink ~run args ret)
           (violates_post ~fn_name ~binder ~ret_pred args))
