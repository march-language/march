(** The parity net (specs/2026-10-29-refinement-reflection-design.md §9.2, D16):
    each reflected function's LOGIC definition against the interpreter.

    The rules of §2.1 make a reflected function's definition a theorem; they
    do not prove that [Refine_reflect]'s body translator rendered it
    correctly.  A wrong selector, a wrong arm order, a truncation mismatch in
    [/], or a guard that falls through would be an unsound equation no rule
    notices.  This net compares, on generated inputs:

    - the LOGIC side: the function's guarded cases ([Refine_reflect.templates])
      evaluated on the ground input by [eval] below, an evaluator of the
      encoded term (§9.2 allows z3 or evaluating the encoded term; a ground
      argument always decides every guard, so evaluation is exact), with
      unbounded-Int semantics: an intermediate that leaves OCaml's 63-bit
      range is [Logic_overflow], never a wrapped value; reflected callees are
      evaluated through their own definitions, at most [step_cap] calls;
    - the PROGRAM side: the interpreter on the same input
      ([Witness.call_fn_classified]: the witness interpreter's fuel and
      effect veto).

    Per input, in this order:
    - an input outside the function's refined domain ([pre_f] false) is not
      an input of the definition: skipped, not counted;
    - the interpreter overflowed (#1042: `+ - *` and negation panic out of
      range): [overflow?] (D8: the logic's Int is unbounded), never a
      mismatch.  When only this evaluator's 63-bit intermediates overflow
      (the program returned), the input is undecided, not compared;
    - any other interpreter FAILURE (a panic, a match failure, the fuel
      running out) on an input inside [pre_f]: RED, a reflectability bug (R2
      or R5 admitted something it must not, C2), whatever the logic says;
    - both returned and the values differ: RED, an encoding mismatch (a
      compiler bug, never a user error);
    - the logic could not evaluate (an opaque [==], a callee with no
      definition, the step cap, an input no case covers) or the interpreter
      did not run (a blocked effect, an evaluator limitation): "not
      compared", never agreement.

    Inputs: every Int parameter takes 0, ±1, the maximum and minimum 63-bit
    Int and their neighbours (the other parameters at a small fixed value),
    then [draws] random tuples from a fixed seed (recorded in the report).
    Generators exist for Int, Bool, type variables (drawn as Int), and every
    registered data type whose constructors' field sorts are known and whose
    constructor names no other data type declares; a function with another
    parameter sort is "not compared" as a whole. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module RS = Reflect_state
module RE = Refine_encode
module V = March_eval.Eval_types

let seed = 20261031

let draws = 100

let step_cap = 10_000

(* A ground logic value. *)
type lv = LInt of int | LBool of bool | LCon of string * lv list

exception Logic_overflow
exception Unsupported of string

let rec show = function
  | LInt n -> string_of_int n
  | LBool b -> string_of_bool b
  | LCon (c, []) -> RE.ctor_display c
  | LCon (c, xs) -> RE.ctor_display c ^ "(" ^ String.concat ", " (List.map show xs) ^ ")"

(* ── The logic side ──────────────────────────────────────────────────────── *)

let add x y =
  let s = x + y in
  if (x >= 0) = (y >= 0) && (s >= 0) <> (x >= 0) then raise Logic_overflow else s

let sub x y = if y = min_int then raise Logic_overflow else add x (-y)

let mul x y =
  if x = 0 || y = 0 then 0
  else
    let p = x * y in
    if p / y <> x || (x = -1 && y = min_int) || (y = -1 && x = min_int) then raise Logic_overflow else p

let neg x = if x = min_int then raise Logic_overflow else -x

(* SMT-LIB [div]/[mod]: [x = k*q + r], [0 <= r < |k|]. *)
let euclid x k =
  if k = 0 then raise (Unsupported "division by zero in the logic");
  let ak = if k = min_int then raise Logic_overflow else abs k in
  let r = ((x mod ak) + ak) mod ak in
  let q = (x - r) / k in
  (q, r)

(* The constructor a selector [C_i] reads, and the field index. *)
let selector (f : string) : (string * int) option =
  match String.rindex_opt f '_' with
  | Some i when i > 0 && i < String.length f - 1 -> (
    let c = String.sub f 0 i and k = String.sub f (i + 1) (String.length f - i - 1) in
    match int_of_string_opt k with
    | Some k when Hashtbl.mem RE.ctor_field_sorts c -> Some (c, k)
    | _ -> None)
  | _ -> None

let steps = ref 0

let rec eval (env : (string * lv) list) (t : Smt.term) : lv =
  let int t = match eval env t with LInt n -> n | v -> raise (Unsupported ("not an Int: " ^ show v)) in
  let bool t = match eval env t with LBool b -> b | v -> raise (Unsupported ("not a Bool: " ^ show v)) in
  match t with
  | Smt.IntLit n -> LInt n
  | Smt.BoolLit b -> LBool b
  | Smt.Const c -> ( match List.assoc_opt c env with Some v -> v | None -> raise (Unsupported ("free " ^ c)))
  | Smt.Ctor (c, _, args) -> LCon (c, List.map (eval env) args)
  | Smt.IsCtor (c, a) | Smt.IsCtorAt (c, _, _, a) -> (
    match eval env a with LCon (c', _) -> LBool (c = c') | v -> raise (Unsupported ("a tester on " ^ show v)))
  | Smt.Add (a, b) -> LInt (add (int a) (int b))
  | Smt.Sub (a, b) -> LInt (sub (int a) (int b))
  | Smt.Mul (a, b) -> LInt (mul (int a) (int b))
  | Smt.MulLit (k, a) -> LInt (mul k (int a))
  | Smt.Neg a -> LInt (neg (int a))
  | Smt.DivLit (a, k) -> LInt (fst (euclid (int a) k))
  | Smt.ModLit (a, k) -> LInt (snd (euclid (int a) k))
  | Smt.Div (a, b) -> LInt (fst (euclid (int a) (int b)))
  | Smt.Mod (a, b) -> LInt (snd (euclid (int a) (int b)))
  | Smt.Ite (c, a, b) -> if bool c then eval env a else eval env b
  | Smt.And (a, b) -> LBool (bool a && bool b)
  | Smt.Or (a, b) -> LBool (bool a || bool b)
  | Smt.Not a -> LBool (not (bool a))
  | Smt.Implies (a, b) -> LBool ((not (bool a)) || bool b)
  | Smt.Eq (a, b) -> LBool (eval env a = eval env b)
  | Smt.Ne (a, b) -> LBool (eval env a <> eval env b)
  | Smt.Lt (a, b) -> LBool (int a < int b)
  | Smt.Le (a, b) -> LBool (int a <= int b)
  | Smt.Gt (a, b) -> LBool (int a > int b)
  | Smt.Ge (a, b) -> LBool (int a >= int b)
  | Smt.App (f, [ a ]) when f = RE.list_len_measure ->
    let rec len n = function
      | LCon (c, []) when c = RE.list_nil () -> n
      | LCon (c, [ _; t ]) when c = RE.list_cons () -> len (n + 1) t
      | v -> raise (Unsupported ("len of " ^ show v))
    in
    LInt (len 0 (eval env a))
  | Smt.App (f, _) when f = RS.eq_sym -> raise (Unsupported "an opaque == (a hand-written or Float Eq)")
  | Smt.App (f, args) when Hashtbl.mem Refine_reflect.templates f -> call f (List.map (eval env) args)
  | Smt.App (f, [ a ]) when selector f <> None -> (
    let c, k = Option.get (selector f) in
    match eval env a with
    | LCon (c', fs) when c = c' && k < List.length fs -> List.nth fs k
    | v -> raise (Unsupported (Printf.sprintf "selector %s on %s" f (show v))))
  | Smt.App (f, _) -> raise (Unsupported ("no definition for " ^ f))
  | _ -> raise (Unsupported "a term the parity evaluator does not model")

(* A reflected function's value at ground arguments: [None] when the
   arguments are outside its refined domain ([pre_f] false). *)
and apply_template (f : string) (args : lv list) : lv option =
  incr steps;
  if !steps > step_cap then raise (Unsupported "the step cap");
  let tp = Hashtbl.find Refine_reflect.templates f in
  let env = List.mapi (fun i a -> (Refine_reflect.param_const i, a)) args in
  let holds t = match eval env t with LBool b -> b | v -> raise (Unsupported ("a guard is " ^ show v)) in
  if not (List.for_all holds tp.Refine_reflect.t_pre) then None
  else
    match List.find_opt (fun (conds, _) -> List.for_all holds conds) tp.Refine_reflect.t_cases with
    | Some (_, r) -> Some (eval env r)
    | None -> raise (Unsupported "no case of the definition covers the input")

and call f args =
  match apply_template f args with
  | Some v -> v
  | None -> raise (Unsupported "a reflected callee applied outside its domain")

(* ── Inputs ──────────────────────────────────────────────────────────────── *)

let boundary = [ 0; 1; -1; max_int; min_int; max_int - 1; min_int + 1 ]

(* A data type's constructors (SMT names) with their field sorts at [args],
   or [None] for a record.  (A constructor name another data type also
   declares is fine since 2026-11-02: the registry is keyed by datatype.) *)
let ctors_of (adt : string) (args : Smt.sort list) : (string * Smt.sort list) list option =
  match Hashtbl.find_opt RE.adt_ctors adt with
  | None | Some [] -> None
  | Some cs ->
    if List.exists (fun c -> Hashtbl.mem RE.ctor_field_names c) cs then None
    else
      let fields c =
        match Hashtbl.find_opt RE.ctor_field_sorts_poly c with
        | Some poly -> Some (List.map (Smt.instantiate args) poly)
        | None -> None
      in
      let rec all = function
        | [] -> Some []
        | c :: rest -> (
          match fields c, all rest with Some fs, Some r -> Some ((c, fs) :: r) | _ -> None)
      in
      all cs

let rec small (s : Smt.sort) : lv option =
  match s with
  | Smt.SInt | Smt.SParam _ -> Some (LInt 1)
  | Smt.SBool -> Some (LBool true)
  | Smt.SData (adt, args) -> (
    match ctors_of adt args with
    | None -> None
    | Some cs ->
      (* The first constructor whose fields are not the type itself. *)
      List.find_map
        (fun (c, fs) ->
          if List.exists (function Smt.SData (a, _) -> a = adt | _ -> false) fs then None
          else
            let vs = List.map small fs in
            if List.for_all Option.is_some vs then Some (LCon (c, List.map Option.get vs)) else None)
        cs)
  | _ -> None

let rec random (st : Random.State.t) ~(depth : int) (s : Smt.sort) : lv option =
  match s with
  | Smt.SInt | Smt.SParam _ ->
    Some
      (LInt
         (match Random.State.int st 4 with
          | 0 -> Random.State.int st 2_000_001 - 1_000_000
          | _ -> Random.State.int st 41 - 20))
  | Smt.SBool -> Some (LBool (Random.State.bool st))
  | Smt.SData (adt, args) -> (
    match ctors_of adt args with
    | None -> None
    | Some cs ->
      let leaf (_, fs) = not (List.exists (function Smt.SData (a, _) -> a = adt | _ -> false) fs) in
      let pool = if depth <= 0 then List.filter leaf cs else cs in
      if pool = [] then small s
      else
        let c, fs = List.nth pool (Random.State.int st (List.length pool)) in
        let vs = List.map (random st ~depth:(depth - 1)) fs in
        if List.for_all Option.is_some vs then Some (LCon (c, List.map Option.get vs)) else None)
  | _ -> None

(* The inputs of one function: (boundary?, arguments). *)
let inputs (name : string) (params : Smt.sort list) : (bool * lv list) list option =
  match List.map small params with
  | smalls when List.for_all Option.is_some smalls ->
    let smalls = List.map Option.get smalls in
    let bounds =
      List.concat
        (List.mapi
           (fun i s ->
             match s with
             | Smt.SInt -> List.map (fun b -> (true, List.mapi (fun j v -> if i = j then LInt b else v) smalls)) boundary
             | _ -> [])
           params)
    in
    let st = Random.State.make [| seed; Hashtbl.hash name |] in
    let rand =
      List.filter_map
        (fun _ ->
          let vs = List.map (random st ~depth:3) params in
          if List.for_all Option.is_some vs then Some (false, List.map Option.get vs) else None)
        (List.init draws Fun.id)
    in
    Some (bounds @ rand)
  | _ -> None

(* ── The program side ────────────────────────────────────────────────────── *)

let rec to_value = function
  | LInt n -> V.VInt n
  | LBool b -> V.VBool b
  | LCon (c, xs) -> V.VCon (RE.ctor_display c, List.map to_value xs)

(* A constructor tag the interpreter may qualify ([M.Some]). *)
let bare_tag c = match String.rindex_opt c '.' with Some i -> String.sub c (i + 1) (String.length c - i - 1) | None -> c

let rec same (v : V.value) (l : lv) : bool option =
  match v, l with
  | V.VInt a, LInt b -> Some (a = b)
  | V.VBool a, LBool b -> Some (a = b)
  | V.VCon (c, xs), LCon (d, ys) ->
    if bare_tag c <> RE.ctor_display d || List.length xs <> List.length ys then Some false
    else
      List.fold_left2
        (fun acc x y -> match acc, same x y with Some true, r -> r | a, _ -> a)
        (Some true) xs ys
  | _ -> None

let rec show_value (v : V.value) =
  match v with
  | V.VInt n -> string_of_int n
  | V.VBool b -> string_of_bool b
  | V.VCon (c, []) -> c
  | V.VCon (c, xs) -> c ^ "(" ^ String.concat ", " (List.map show_value xs) ^ ")"
  | _ -> "<value>"

(* ── The net ─────────────────────────────────────────────────────────────── *)

type outcome =
  | Agree
  | Mismatch of string
  | Interp_failure of string
  | Overflow of string
  | Not_compared of string

type result = { p_name : string; p_file : string; p_compared : int; p_outcome : outcome }

let input_str args = "(" ^ String.concat ", " (List.map show args) ^ ")"

(* One function over its inputs; the first RED input decides, then the first
   overflow, else agreement over every compared input. *)
let check_fn ~(sym : string) ~(name : string) ~(file : string) (fs : RS.fsig) : result =
  let mk compared o = { p_name = name; p_file = file; p_compared = compared; p_outcome = o } in
  match inputs name fs.RS.fs_params with
  | None -> mk 0 (Not_compared "a parameter sort has no generator")
  | Some ins ->
    let compared = ref 0 and red = ref None and over = ref None and why_not = ref None in
    List.iter
      (fun (_bound, args) ->
        if !red = None then begin
          steps := 0;
          let logic =
            try `V (apply_template sym args) with
            | Logic_overflow -> `Overflow
            | Unsupported w -> `No w
            | Not_found -> `No "no definition"
          in
          match logic with
          | `V None -> () (* outside pre_f: not an input of the definition *)
          | _ -> (
            match Witness.call_fn_classified ~name ~args:(List.map to_value args) with
            | Witness.C_overflow m ->
              if !over = None then over := Some (Printf.sprintf "%s at %s" m (input_str args))
            | Witness.C_panic m -> red := Some (Interp_failure (Printf.sprintf "panics (%s) at %s" m (input_str args)))
            | Witness.C_match_failure m ->
              red := Some (Interp_failure (Printf.sprintf "match failure (%s) at %s" m (input_str args)))
            | Witness.C_fuel -> red := Some (Interp_failure (Printf.sprintf "runs out of fuel at %s" (input_str args)))
            | Witness.C_not_run w -> if !why_not = None then why_not := Some ("interpreter: " ^ w)
            | Witness.C_ret v -> (
              match logic with
              | `Overflow ->
                (* The program returned, so its arithmetic stayed in range;
                   only this evaluator's own 63-bit intermediates did not
                   (the logic's Int is unbounded: `-(min_int)` is fine
                   there).  Undecided here, never agreement. *)
                if !why_not = None then
                  why_not := Some (Printf.sprintf "logic: an intermediate exceeds 63 bits at %s" (input_str args))
              | `No w -> if !why_not = None then why_not := Some ("logic: " ^ w)
              | `V None -> ()
              | `V (Some l) -> (
                match same v l with
                | Some true -> incr compared
                | Some false ->
                  red :=
                    Some
                      (Mismatch
                         (Printf.sprintf "at %s the interpreter returns %s, the logic %s" (input_str args)
                            (show_value v) (show l)))
                | None -> if !why_not = None then why_not := Some "the interpreter's value has no logic reading")))
        end)
      ins;
    match !red, !over with
    | Some r, _ -> mk !compared r
    | None, Some o when !compared > 0 -> mk !compared (Overflow (Printf.sprintf "%s; %d inputs compared" o !compared))
    | None, Some o ->
      (* Zero inputs compared (review round 1): the logic side decided no
         input, so the overflow is no evidence about the definition. *)
      mk 0
        (Not_compared
           (Printf.sprintf "%s; the interpreter overflows %s"
              (Option.value ~default:"no input inside the domain" !why_not) o))
    | None, None ->
      if !compared > 0 then mk !compared Agree
      else mk 0 (Not_compared (Option.value ~default:"no input inside the domain" !why_not))

(** The net over every reflected function [is_user] accepts (top-level ones:
    a local [f/go] has no name the interpreter binds).  Returns the report
    lines and whether the net is RED. *)
let run ~(is_user : string -> bool) () : string list * bool =
  Witness.wall_budget := max_int / 2;
  let fns =
    Hashtbl.fold
      (fun sym (name, file) acc ->
        if is_user file && not (String.contains name '/') then
          (Some sym, name, file, if Hashtbl.mem Refine_reflect.templates sym then RS.sig_of sym else None) :: acc
        else acc)
      RS.sym_origin []
  in
  (* Reflected by the rules but given no logic symbol (a parameter or result
     sort the logic has no sort for, e.g. Float). *)
  let with_sym = List.map (fun (_, n, f, _) -> (n, f)) fns in
  let fns =
    fns
    @ List.filter_map
        (fun (name, file) ->
          if is_user file && (not (String.contains name '/')) && not (List.mem (name, file) with_sym) then
            Some (None, name, file, None)
          else None)
        (List.sort_uniq compare !Refine_reflect.reflected_fns)
    |> List.sort (fun (_, a, f, _) (_, b, g, _) -> compare (f, a) (g, b))
  in
  (* A reflected function with no template (an uninterpreted logic symbol:
     the encoder declined its body) or no signature is listed, never dropped
     (review round 1): the net covers it with no evidence, and says so. *)
  let results =
    List.map
      (fun (sym, name, file, fs) ->
        match sym, fs with
        | Some sym, Some fs -> check_fn ~sym ~name ~file fs
        | _ ->
          { p_name = name; p_file = file; p_compared = 0;
            p_outcome =
              Not_compared
                (match sym with
                 | None -> "no logic definition (no logic symbol: a parameter or result sort the logic lacks)"
                 | Some sym when Hashtbl.mem Refine_reflect.templates sym -> "no logic signature"
                 | Some _ -> "no logic definition (the encoder declined the body; its symbol is uninterpreted)") })
      fns
  in
  let line r =
    let status, detail =
      match r.p_outcome with
      | Agree -> ("agree", Printf.sprintf "%d inputs" r.p_compared)
      | Mismatch d -> ("MISMATCH", d)
      | Interp_failure d -> ("INTERPRETER-FAILURE", d)
      | Overflow d -> ("overflow?", d)
      | Not_compared d -> ("not-compared", d)
    in
    Printf.sprintf "parity\t%s\t%s\t%s\t%s" (Filename.basename r.p_file) r.p_name status detail
  in
  let count p = List.length (List.filter (fun r -> p r.p_outcome) results) in
  let mism = count (function Mismatch _ -> true | _ -> false)
  and fails = count (function Interp_failure _ -> true | _ -> false)
  and over = count (function Overflow _ -> true | _ -> false)
  and nc = count (function Not_compared _ -> true | _ -> false)
  and agree = count (function Agree -> true | _ -> false) in
  ( List.map line results
    @ [ Printf.sprintf
          "parity: %d functions (seed %d, %d draws + boundary Ints): %d agree, %d mismatch, %d interpreter failure, %d overflow?, %d not compared"
          (List.length results) seed draws agree mism fails over nc ]
    @ (* Review round 2: a run that compared no input (no reflected
         function, or none the net could run) is no evidence; it says so in
         words rather than reading as green.  Not RED: nothing disagreed. *)
    (if List.fold_left (fun a r -> a + r.p_compared) 0 results = 0 && mism + fails = 0 then
       [ "parity: NOTHING COMPARED (no input of any reflected function was compared; the net is no evidence here)" ]
     else []),
    mism + fails > 0 )
