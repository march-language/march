(** Lemma tests (specs/todos/2026-11-02-lemma-uses-beyond-refinement.md ideas
    1 and 2): a lemma's theorem [P] run on concrete inputs.

    Every function a valid lemma's theorem mentions is reflected (L3), so it
    runs.  [run] evaluates [P] in the interpreter ([Witness.eval_classified]:
    the witness interpreter's fuel and effect veto) on the parity net's inputs
    ([Reflect_parity.inputs]: boundary Ints, then [Reflect_parity.draws]
    random tuples from its fixed, recorded seed).  An input outside a
    parameter's refinement is skipped, not counted.

    - An UNPROVED lemma (z3 did not admit it) becomes a property test: a
      false [P] is a counterexample (RED); otherwise "tested, not proved".
    - An ADMITTED lemma is a miscompile check: [P] was proved, so a false [P]
      in the interpreter, or in the compiled program [harness] builds, is a
      compiler or runtime bug (RED).  The compiled side runs only on inputs
      the interpreter decided, so a crash there is a divergence too.

    An Int overflow is [overflow?] (D8: the logic's Int is unbounded), never
    a counterexample; an input on which [P] cannot be evaluated (a callee
    panics outside its domain, the fuel runs out) is undecided.  Only the
    entry file's lemmas are tested.  Nothing here runs outside
    `--lemma-test`: erasure still removes lemmas from every program. *)

module A = March_ast.Ast
module V = March_eval.Eval_types
module W = Witness
module RP = Reflect_parity
module RE = Refine_encode

(* Test-only: "interp" negates the interpreter's verdict on an admitted
   lemma, "compiled" the compiled program's, so the tests can show a false
   proved law is RED on each side (a real miscompile cannot be summoned). *)
let perturb () = Sys.getenv_opt "MARCH_LEMMA_TEST_PERTURB"

(* How many interpreter-decided inputs per admitted lemma the compiled
   program re-checks. *)
let compiled_inputs = 12

(* Type variables are drawn as Int, as the parity net draws them. *)
let rec int_tyvars (t : A.ty) : A.ty =
  match t with
  | A.TyVar v -> A.TyCon ({ v with A.txt = "Int" }, [])
  | A.TyCon (n, args) -> A.TyCon (n, List.map int_tyvars args)
  | A.TyRefine (b, x, p) -> A.TyRefine (int_tyvars b, x, p)
  | A.TyLinear (l, b) -> A.TyLinear (l, int_tyvars b)
  | t -> t

let rec render (v : V.value) : string =
  match v with
  | V.VInt n -> string_of_int n
  | V.VBool b -> string_of_bool b
  | V.VCon (c, []) -> c
  | V.VCon (c, xs) -> c ^ "(" ^ String.concat ", " (List.map render xs) ^ ")"
  | _ -> "<value>"

(* The same value as March source: a negative Int is written `(0 - n)`. *)
let rec source (v : V.value) : string =
  match v with
  | V.VInt n when n < 0 -> Printf.sprintf "(0 - %d)" (-n)
  | V.VCon (c, []) -> c
  | V.VCon (c, xs) -> c ^ "(" ^ String.concat ", " (List.map source xs) ^ ")"
  | v -> render v

type verdict =
  | Held of int  (** [P] was true on every decided input; how many *)
  | False_at of string  (** the first input on which [P] is false *)
  | Undecided of string  (** no input decided [P]; why *)

type result = {
  l_name : string;
  l_file : string;
  l_admitted : bool;
  l_verdict : verdict;
  l_overflow : string option;  (** the first input whose evaluation overflowed *)
  l_decided : (string * V.value) list list;  (** random inputs on which [P] held *)
  l_fd : A.fn_def;
}

let show_input (bs : (string * V.value) list) =
  String.concat ", " (List.map (fun (n, v) -> n ^ " = " ^ render v) bs)

(* The module-environment bindings of the lemma's own module under their
   bare names: a nested module's members are bound as "M.f", and the
   theorem names them as written inside "M". *)
let aliases (qname : string) : (string * V.value) list =
  match String.rindex_opt qname '.' with
  | None -> []
  | Some i -> (
    let prefix = String.sub qname 0 (i + 1) in
    match W.module_env () with
    | None -> []
    | Some env ->
      List.filter_map
        (fun (k, v) ->
          if String.starts_with ~prefix k && not (String.contains_from k (String.length prefix) '.') then
            Some (String.sub k (String.length prefix) (String.length k - String.length prefix), v)
          else None)
        env)

let test_lemma ~(file : string) (qname, (fd : A.fn_def), admitted) : result =
  let mk ?overflow ?(decided = []) v =
    { l_name = qname; l_file = file; l_admitted = admitted; l_verdict = v; l_overflow = overflow;
      l_decided = decided; l_fd = fd }
  in
  match fd.A.fn_clauses, Refine_check.lemma_post fd with
  | [ c ], Ok (_, p) -> (
    let params = List.map W.clause_param c.A.fc_params in
    if List.exists (fun (n, t) -> n = "_" || t = None) params then mk (Undecided "a parameter has no name or no type")
    else
      let params = List.map (fun (n, t) -> (n, Option.get t)) params in
      let sorts = List.map (fun (_, t) -> RE.instance_sort_of_ty (int_tyvars t)) params in
      match RP.inputs qname sorts with
      | None -> mk (Undecided "a parameter sort has no generator")
      | Some ins ->
        let seen = Hashtbl.create 64 in
        let ins = List.filter (fun (_, a) -> if Hashtbl.mem seen a then false else (Hashtbl.add seen a (); true)) ins in
        let alias = aliases qname in
        let held = ref 0 and false_at = ref None and overflow = ref None and why = ref None and decided = ref [] in
        let note r = if !why = None then why := Some r in
        let flip = admitted && perturb () = Some "interp" in
        List.iter
          (fun (boundary, args) ->
            if !false_at = None then begin
              let bs = List.map2 (fun (n, _) a -> (n, RP.to_value a)) params args in
              let env = bs @ alias in
              (* A refined parameter: an input outside it is no input. *)
              let inside =
                List.for_all
                  (fun ((_, t), (_, v)) ->
                    match t with
                    | A.TyRefine (_, b, pred) -> (
                      let bn = match b with Some b -> b.A.txt | None -> "_" in
                      match W.eval_classified ~bindings:((bn, v) :: env) pred with
                      | W.C_ret (V.VBool true) -> true
                      | _ -> false)
                    | _ -> true)
                  (List.combine params bs)
              in
              if inside then
                match W.eval_classified ~bindings:env p with
                | W.C_ret (V.VBool b) ->
                  if b <> flip then begin
                    incr held;
                    if not boundary then decided := bs :: !decided
                  end
                  else false_at := Some (show_input bs)
                | W.C_ret v -> note ("the theorem's value is " ^ render v)
                | W.C_overflow m -> if !overflow = None then overflow := Some (Printf.sprintf "%s at %s" m (show_input bs))
                | W.C_panic m -> note (Printf.sprintf "a function panics (%s) at %s" m (show_input bs))
                | W.C_match_failure m -> note (Printf.sprintf "a match fails (%s) at %s" m (show_input bs))
                | W.C_fuel -> note ("the fuel runs out at " ^ show_input bs)
                | W.C_not_run w -> note ("the interpreter: " ^ w)
            end)
          ins;
        let overflow = !overflow and decided = List.rev !decided in
        match !false_at with
        | Some at -> mk ?overflow (False_at at)
        | None when !held > 0 -> mk ?overflow ~decided (Held !held)
        | None -> mk ?overflow (Undecided (Option.value ~default:"no input inside the parameters' refinements" !why)))
  | _ -> mk (Undecided "not a single-clause lemma with a theorem")

(* ── The compiled side ───────────────────────────────────────────────────── *)

(** The harness program for the admitted lemmas of [results] (those that held
    on some random input and whose source parts parse), in the module
    [LemmaHarness]: one `pfn` per lemma whose body is the theorem, and a
    `main` that panics with `lemma-law-false <lemma> <input>` at the first
    false one.  [entry_mod] is the entry file's module; the lemma's own
    module is imported with `use`.  Returns the source and the lemmas it
    covers, each with the inputs it runs. *)
(* A type as March source (the shapes a parameter type takes). *)
let rec ty_source (t : A.ty) : string =
  match t with
  | A.TyCon (n, []) -> n.A.txt
  | A.TyCon (n, args) -> n.A.txt ^ "(" ^ String.concat ", " (List.map ty_source args) ^ ")"
  | A.TyVar n -> n.A.txt
  | A.TyTuple ts -> "(" ^ String.concat ", " (List.map ty_source ts) ^ ")"
  | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> ty_source b
  | _ -> "_"

(* An interface law's lemma for one impl ([March_desugar.Interface_laws],
   named `<law>__<Iface>_<Type>`) has no source text of its own.  Its parts
   come from the law as written in the interface (whose method calls then
   dispatch to the impl, in the compiled program, by the parameter types)
   with the generated lemma's parameter types (the impl's type).  Also the
   module to `use` for the interface's methods. *)
let generated_parts (r : result) : (string * string * string option) option =
  match !W.current_module with
  | None -> None
  | Some m -> (
    let bare = match String.rindex_opt r.l_name '.' with Some i -> String.sub r.l_name (i + 1) (String.length r.l_name - i - 1) | None -> r.l_name in
    let law_of_name =
      let n = String.length bare in
      let rec cut i = if i + 1 >= n then None else if bare.[i] = '_' && bare.[i + 1] = '_' then Some (String.sub bare 0 i) else cut (i + 1) in
      cut 0
    in
    let rec find path ds =
      List.find_map
        (function
          | A.DInterface (idef, _) -> (
            match List.find_opt (fun (l : A.fn_def) -> Some l.A.fn_name.A.txt = law_of_name) idef.A.iface_laws with
            | Some l -> Some (path, l)
            | None -> None)
          | A.DMod (n, _, inner, _) -> find (if path = "" then n.A.txt else path ^ "." ^ n.A.txt) inner
          | _ -> None)
        ds
    in
    match find "" m.A.mod_decls, r.l_fd.A.fn_clauses with
    | Some (path, law), [ c ] -> (
      let text = try In_channel.with_open_bin law.A.fn_name.A.span.A.file In_channel.input_all with Sys_error _ -> "" in
      match March_ast.Lemma_source.parts text law with
      | None -> None
      | Some (_, theorem) ->
        let law_names =
          match law.A.fn_clauses with
          | lc :: _ -> List.map (fun fp -> fst (W.clause_param fp)) lc.A.fc_params
          | [] -> []
        in
        let tys = List.map (fun fp -> snd (W.clause_param fp)) c.A.fc_params in
        if List.length law_names <> List.length tys || List.exists Option.is_none tys then None
        else
          let params =
            String.concat ", " (List.map2 (fun n t -> n ^ " : " ^ ty_source (Option.get t)) law_names tys)
          in
          Some (params, theorem, if path = "" then None else Some path))
    | _ -> None)

let harness ~(entry_mod : string) ~(text : string) (results : result list) :
    string * (result * (string * V.value) list list) list =
  let covered =
    List.filter_map
      (fun r ->
        let parts =
          match March_ast.Lemma_source.parts text r.l_fd with
          | Some p -> Some (p, None)
          | None -> Option.map (fun (ps, th, u) -> ((ps, th), u)) (generated_parts r)
        in
        match r.l_verdict, parts with
        | Held _, Some (parts, extra) when r.l_admitted && r.l_decided <> [] ->
          let ins = List.filteri (fun i _ -> i < compiled_inputs) r.l_decided in
          Some (r, parts, ins, extra)
        | _ -> None)
      results
  in
  let modpath r =
    match String.rindex_opt r.l_name '.' with Some i -> entry_mod ^ "." ^ String.sub r.l_name 0 i | None -> entry_mod
  in
  let uses =
    List.sort_uniq compare
      (List.concat_map (fun (r, _, _, extra) -> modpath r :: Option.to_list extra) covered)
  in
  let covered = List.map (fun (r, parts, ins, _) -> (r, parts, ins)) covered in
  let neg = perturb () = Some "compiled" in
  let b = Buffer.create 1024 in
  Buffer.add_string b "mod LemmaHarness do\n";
  List.iter (fun m -> Buffer.add_string b (Printf.sprintf "  use %s.*\n" m)) uses;
  List.iteri
    (fun i (_, (params, theorem), _) ->
      Buffer.add_string b (Printf.sprintf "  pfn lemma_law__%d(%s) : Bool do\n    %s\n  end\n" i params theorem))
    covered;
  Buffer.add_string b "  fn main() do\n";
  List.iteri
    (fun i (_, _, ins) ->
      List.iteri
        (fun j bs ->
          let call = Printf.sprintf "lemma_law__%d(%s)" i (String.concat ", " (List.map (fun (_, v) -> source v) bs)) in
          let fail = Printf.sprintf "panic(\"lemma-law-false %d %d\")" i j in
          Buffer.add_string b
            (if neg then Printf.sprintf "    if %s do %s else () end\n" call fail
             else Printf.sprintf "    if %s do () else %s end\n" call fail))
        ins)
    covered;
  Buffer.add_string b "    ()\n  end\nend\n";
  (Buffer.contents b, List.map (fun (r, _, ins) -> (r, ins)) covered)

(* ── The report ──────────────────────────────────────────────────────────── *)

type compiled =
  | Compiled_held of int
  | Compiled_false of string
  | Compiled_failure of string
  | Compiled_not_run of string

let contains (s : string) (sub : string) =
  let n = String.length sub and h = String.length s in
  let rec go i = i + n <= h && (String.sub s i n = sub || go (i + 1)) in
  go 0

(** The lemma tests of the entry file [filename] (module [entry_mod]).
    [compile_run], when given, compiles and runs a harness source and returns
    [`Ran (exit code, output)] or [`Compile_failed output]: the admitted
    lemmas are then re-checked in the compiled program.  Returns the report lines and whether it is RED. *)
let run ~(filename : string) ~(entry_mod : string) ?compile_run () : string list * bool =
  W.wall_budget := max_int / 2;
  let lemmas =
    List.filter (fun (_, (fd : A.fn_def), _) -> fd.A.fn_name.A.span.A.file = filename) !Refine_check.lemma_defs
    |> List.sort (fun (a, _, _) (b, _, _) -> compare a b)
  in
  let results = List.map (fun l -> RP.steps := 0; test_lemma ~file:filename l) lemmas in
  let compiled : (string * compiled) list =
    match compile_run with
    | None -> []
    | Some cr -> (
      let text = try In_channel.with_open_bin filename In_channel.input_all with Sys_error _ -> "" in
      let src, covered = harness ~entry_mod ~text results in
      let skipped =
        List.filter_map
          (fun r ->
            if r.l_admitted && (match r.l_verdict with Held _ -> true | _ -> false)
               && not (List.exists (fun (c, _) -> c == r) covered)
            then
              Some
                ( r.l_name,
                  Compiled_not_run
                    (if r.l_decided = [] then "no random input was decided in the interpreter"
                     else "its parameters or theorem could not be read from the source") )
            else None)
          results
      in
      if covered = [] then skipped
      else
        let ran = cr src in
        let out = match ran with `Ran (_, o) -> o | `Compile_failed o -> o in
        let failed_at i =
          (* `lemma-law-false <i> <j>` *)
          let marker = Printf.sprintf "lemma-law-false %d " i in
          let k = String.length marker in
          List.find_map
            (fun l ->
              let rec idx p =
                if p + k > String.length l then None else if String.sub l p k = marker then Some (p + k) else idx (p + 1)
              in
              Option.bind (idx 0) (fun p ->
                  let e = ref p in
                  while !e < String.length l && l.[!e] >= '0' && l.[!e] <= '9' do incr e done;
                  int_of_string_opt (String.sub l p (!e - p))))
            (String.split_on_char '\n' out)
        in
        skipped
        @ List.mapi
            (fun i (r, ins) ->
              ( r.l_name,
                match ran with
                | `Compile_failed _ -> Compiled_not_run "the harness did not compile"
                | `Ran (0, _) -> Compiled_held (List.length ins)
                | `Ran (code, _) -> (
                  match failed_at i with
                  | Some j when j < List.length ins ->
                    Compiled_false (show_input (List.nth ins j))
                  | _ when contains out "lemma-law-false" -> Compiled_not_run "an earlier lemma's input failed first"
                  | _ -> Compiled_failure (Printf.sprintf "the compiled harness exited %d" code)) ))
            covered)
  in
  let red = ref 0 in
  let line r =
    let base = Filename.basename r.l_file in
    let ov = match r.l_overflow with Some o -> "; overflow? " ^ o | None -> "" in
    let status, detail =
      match r.l_admitted, r.l_verdict with
      | false, Held n -> ("tested", Printf.sprintf "tested, not proved: %d inputs%s" n ov)
      | false, False_at at ->
        incr red;
        ("COUNTEREXAMPLE", Printf.sprintf "the theorem is false at %s" at)
      | false, Undecided w -> ("not-tested", w ^ ov)
      | true, False_at at ->
        incr red;
        ( "FALSE",
          Printf.sprintf "proved, yet false in the interpreter at %s: a compiler or runtime bug" at )
      | true, Undecided w -> ("not-tested", w ^ ov)
      | true, Held n -> (
        match List.assoc_opt r.l_name compiled with
        | None -> ("holds", Printf.sprintf "%d inputs, interpreter%s" n ov)
        | Some (Compiled_held k) -> ("holds", Printf.sprintf "%d inputs, interpreter; %d compiled%s" n k ov)
        | Some (Compiled_not_run w) ->
          ("holds", Printf.sprintf "%d inputs, interpreter; compiled not run (%s)%s" n w ov)
        | Some (Compiled_false at) ->
          incr red;
          ("COMPILED-FALSE", Printf.sprintf "proved, yet false in the compiled program at %s: a compiler or runtime bug" at)
        | Some (Compiled_failure w) ->
          incr red;
          ("COMPILED-FAILURE", Printf.sprintf "%s on inputs the interpreter decided: a compiler or runtime bug" w))
    in
    Printf.sprintf "lemma-test\t%s\t%s\t%s\t%s" base r.l_name status detail
  in
  let lines = List.map line results in
  let count p = List.length (List.filter p results) in
  let summary =
    Printf.sprintf "lemma-test: %d lemmas (seed %d, %d draws + boundary Ints): %d admitted, %d unproved"
      (List.length results) RP.seed RP.draws
      (count (fun r -> r.l_admitted))
      (count (fun r -> not r.l_admitted))
  in
  ( lines @ [ summary ]
    @ (if !red > 0 then [ Printf.sprintf "lemma-test: RED (%d lemma%s false on a concrete input)" !red (if !red = 1 then "" else "s") ] else []),
    !red > 0 )
