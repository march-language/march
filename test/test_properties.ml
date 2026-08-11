(** Property-based tests for the March compiler using QCheck2.

    Three families of tests:
    1. Source-string generators — generate valid March source code and run it
       through the full pipeline (parse → desugar → typecheck → eval → TIR passes).
    2. TIR AST generators — build [Tir.tir_module] values directly and exercise
       individual passes (lower, mono, defun, perceus) without going through the
       parser.
    3. Oracle properties — compile generated programs with the native backend and
       check that the compiled output matches the interpreter's output.

    The interpreter ([March_eval.Eval]) acts as the reference oracle: any
    algebraic property that holds over the semantics must hold in the evaluation
    results, and every TIR pass must be semantics-preserving (tested here as
    "does not crash + result is structurally well-formed"). *)

open QCheck2

(* ── Pipeline helpers ──────────────────────────────────────────────────── *)

module Ast       = March_ast.Ast
module Tir       = March_tir.Tir
module Errors    = March_errors.Errors
module Typecheck = March_typecheck.Typecheck

(** Parse a March source string into an AST module.
    Raises [March_parser.Parser.Error] on syntax error. *)
let parse_src src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

(* ── Stdlib-loaded typecheck env (Task 6.4) ────────────────────────────────

   [pipeline_up_to_typecheck] used to call [check_module] on the bare parsed
   module with NO stdlib in scope.  That made every well-typed program that
   touches a prelude/stdlib binding — most obviously [println([0])], whose
   Show-based signature lives in prelude.march — report a spurious type error
   in-process, even though `march --check`/`--compile` accept it.  QCheck then
   shrank [prop_generated_programs_are_well_typed] straight to [println([0])].

   Fix: mirror exactly what `march --check`/`--compile` do — typecheck the
   stdlib ONCE into a seed env (bin/main.ml's [get_stdlib_tc_env] builds the
   same [check_module_core]-derived [final_env]) and thread it into each
   program's check as [?seed_env], with a FRESH error context per call so
   diagnostics never accumulate across QCheck iterations. *)

(** The ordered native stdlib file list, verbatim from bin/main.ml's
    [stdlib_file_list].  This is the canonical set `march --check` loads; the
    js-only trio (dom/canvas/audio) and on-demand extras are deliberately
    excluded, matching the native compile path.  A file that fails to open is
    skipped gracefully (see [load_stdlib_file]). *)
let stdlib_file_list = [
  "prelude.march"; "option.march"; "result.march"; "list.march"; "hamt.march";
  "map.march"; "math.march"; "string.march"; "iolist.march"; "html.march";
  "sigil.march"; "http.march"; "http_transport.march"; "http_client.march";
  "seq.march"; "path.march"; "file.march"; "dir.march"; "sort.march";
  "csv.march"; "websocket.march"; "http_server.march"; "iterable.march";
  "set.march"; "hash_map.march"; "array.march"; "bigint.march"; "decimal.march";
  "duration.march"; "bytes.march"; "msgpack.march"; "toml.march"; "xml.march";
  "yaml.march"; "socket.march"; "dns.march"; "process.march"; "io.march";
  "system.march"; "cluster.march"; "cluster_load.march"; "logger.march";
  "actor.march"; "flow.march"; "json.march"; "regex.march"; "datetime.march";
  "queue.march"; "enum.march"; "random.march"; "gen.march"; "check.march";
  "stats.march"; "plot.march"; "dataframe.march"; "tls.march"; "uuid.march";
  "vault.march"; "channel.march"; "pubsub.march"; "channel_server.march";
  "channel_socket.march"; "presence.march"; "env.march"; "config.march";
  "cli.march"; "test.march"; "tuple.march"; "char.march"; "ordered_map.march";
  "sorted_set.march"; "range.march"; "crypto.march"; "base64.march";
  "native_array.march"; "task.march"; "rrb_vec.march"; "parallel.march";
  "uri.march"; "forge_nb.march"; "handle.march"; "vector_clock.march";
  "crdt.march"; "merkle.march"; "net_frame.march"; "cluster_auth.march";
  "node_identity.march"; "handshake.march"; "global_pid.march";
  "remote_call.march"; "node_rpc.march"; "peer_registry.march";
  "net_kernel.march"; "membership.march"; "swim.march"; "swim_driver.march";
  "global_registry.march"; "cluster_conn.march"; "node_call.march";
]

(** Parse + desugar one stdlib file into top-level decls, mirroring
    bin/main.ml's [load_stdlib_file]: prelude.march is unwrapped into global
    scope; every other file keeps its outer [DMod] so members stay qualified
    ([Option.is_some]).  A missing/unparseable file yields [] (skipped). *)
let load_stdlib_file path =
  match (try
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic; Some s
  with Sys_error _ -> None) with
  | None | Some "" -> []
  | Some src ->
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    (try
       let m = March_parser.Parser.module_
                 (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let basename = Filename.basename path in
       let m = March_desugar.Desugar.desugar_module
                 ~is_entry:(basename = "prelude.march") m in
       if basename = "prelude.march" then
         (match m.Ast.mod_decls with
          | [Ast.DMod (_, _, inner, _)] -> inner
          | decls -> decls)
       else
         [Ast.DMod (m.Ast.mod_name, Ast.Public, m.Ast.mod_decls, Ast.dummy_span)]
     with _ -> [])

(** The parsed+desugared native stdlib decls, loaded ONCE.  Shared by the
    typecheck seed env (below) and [eval_main] — both must see stdlib for a
    generated program that calls [println]/etc. to behave as it does under
    `march file.march` (which prepends exactly these before typecheck AND
    eval).  Empty if the stdlib dir can't be found (→ bare fallback). *)
let stdlib_decls : Ast.decl list Lazy.t = lazy (
  match March_modules.Module_registry.find_stdlib_dir () with
  | None -> []
  | Some dir ->
    List.concat_map (fun name -> load_stdlib_file (Filename.concat dir name))
      stdlib_file_list
)

(** Typecheck the whole native stdlib ONCE and keep the resulting env, used as
    the [?seed_env] for every generated program's check.  Lazy so the cost is
    paid at most once (and never at all if no property invokes the pipeline).
    [None] if the stdlib is unavailable or checking it raises — the pipeline
    then falls back to the bare (no-stdlib) check. *)
let stdlib_seed_env : Typecheck.env option Lazy.t = lazy (
  match Lazy.force stdlib_decls with
  | [] -> None
  | decls ->
    (try
       let synthetic = Ast.{
         mod_name  = { txt = "StdlibBaseline"; span = dummy_span };
         mod_decls = decls;
       } in
       (* Stdlib-internal diagnostics are discarded (some WIP modules carry
          known errors, exactly as `march --check` tolerates them); we keep
          only the final typing env. *)
       let (_errs, _tm, final_env) =
         Typecheck.check_module_core ~errors:(Errors.create ()) synthetic in
       Some final_env
     with _ -> None)
)

(** Full pipeline through typecheck; returns [None] on parse error.

    When the stdlib seed env is available (the normal case), the generated
    module is checked WITH stdlib in scope — via [check_module_full ~seed_env]
    with a fresh error context — so prelude/stdlib-dispatched calls like
    [println([0])] typecheck exactly as they do under `march --check`. *)
let pipeline_up_to_typecheck src =
  match (try Some (parse_src src) with _ -> None) with
  | None   -> None
  | Some m ->
    let m = March_desugar.Desugar.desugar_module m in
    let (errors, type_map) =
      match Lazy.force stdlib_seed_env with
      | Some base ->
        (* Fresh error ctx per call so diagnostics don't accumulate across
           QCheck iterations; the seed env's [type_map] is shared (mutated in
           place with this module's span→type entries), matching bin/main.ml. *)
        let seed_env = { base with Typecheck.errors = Errors.create () } in
        let (errs, tm, _env) =
          Typecheck.check_module_full ~errors:(Errors.create ()) ~seed_env m in
        (errs, tm)
      | None ->
        (* Stdlib unavailable — fall back to the bare check (historical
           behavior). *)
        Typecheck.check_module m
    in
    Some (m, errors, type_map)

(** Call the reference interpreter and return the value of [main()].
    Resets scheduler/actor state before each call.

    [with_stdlib] (default [false] = the historical fast path): when [true],
    stdlib decls are prepended to the module before eval — exactly as
    `march file.march` does before [Eval.run_module] — so a generated program
    that calls a prelude/stdlib binding ([println], [to_string], …) resolves
    it at eval time.  [Eval.eval_module_env] clears the global module registry
    on entry, so a persistent stdlib env is impossible; prepending is the only
    mechanism and it re-evals stdlib per call (~tens of ms), so callers whose
    generated programs are pure/self-contained (arithmetic, ADTs, tuples,
    closures) leave it [false] to stay fast. *)
let eval_main ?(with_stdlib = false) m =
  March_eval.Eval.reset_scheduler_state ();
  let m =
    if not with_stdlib then m
    else match Lazy.force stdlib_decls with
      | []    -> m
      | decls -> { m with Ast.mod_decls = decls @ m.Ast.mod_decls }
  in
  let env = March_eval.Eval.eval_module_env m in
  match List.assoc_opt "main" env with
  | None    -> None
  | Some fn ->
    (* R1 stage D: the generated `main` declares its grant, so it takes one
       erased capability per parameter — supply them here the way the real
       entry path does (lib/eval/eval.ml, and the LLVM entry thunk on the
       compiled side). Applying [] to a granted `main` raises an arity
       mismatch, which this property would report as "well-typed program
       crashed the interpreter": a true statement about a test-harness bug,
       not about the language. *)
    let arity =
      List.fold_left
        (fun acc d ->
           match d with
           | Ast.DFn (def, _) when def.Ast.fn_name.Ast.txt = "main" -> (
             match def.Ast.fn_clauses with
             | c :: _ -> List.length c.Ast.fc_params
             | [] -> acc)
           | _ -> acc)
        0 m.Ast.mod_decls
    in
    Some (March_eval.Eval.apply fn
            (List.init arity (fun _ -> March_eval.Eval.VUnit)))

(* ── Source string generators ──────────────────────────────────────────── *)

(** Wrap an expression body in a minimal module with a [main] function. *)
let wrap_main body =
  (* [needs IO.Console], not the root [IO].  Measured: the generators in this
     file emit only [println]/[print] — no file, process, clock or spawn
     builtin — so the narrow capability is the correct one, and it is also
     cheaper: [needs IO] costs ~7% more per check, which matters because this
     shard runs 500 cases per property and sat within a minute of its 25-minute
     CI timeout before this change (it then exceeded it).
     If a future generator reaches for another builtin, the flip fails LOUDLY
     with a message naming the missing capability — a visible failure, not a
     silent one, which is why the defensive root declaration is not worth its
     cost here. *)
  "mod Main do\n  needs IO.Console\n  fn main(_cap_console : Cap(IO.Console)) do\n    " ^ body ^ "\n  end\nend"


(** Integer literal in range [-100, 100]. *)
let gen_int_lit : string Gen.t =
  Gen.map string_of_int (Gen.int_range (-100) 100)

(** Positive integer literal (avoids divide-by-zero, negative-mod surprises). *)
let gen_pos_int_lit : string Gen.t =
  Gen.map string_of_int (Gen.int_range 1 100)


(** Int arithmetic expression with no free variables.
    Depth controls maximum nesting. *)
let gen_arith_expr : string Gen.t =
  Gen.fix (fun self depth ->
    if depth = 0 then
      gen_int_lit
    else
      Gen.oneof_weighted [
        4, gen_int_lit;
        2, Gen.map2 (fun a b -> "(" ^ a ^ " + " ^ b ^ ")") (self (depth-1)) (self (depth-1));
        2, Gen.map2 (fun a b -> "(" ^ a ^ " - " ^ b ^ ")") (self (depth-1)) (self (depth-1));
        1, Gen.map2 (fun a b -> "(" ^ a ^ " * " ^ b ^ ")") (self (depth-1)) (self (depth-1));
      ]
  ) 3

(** Boolean comparison expression (always well-typed: Int < Int → Bool). *)
let gen_bool_cmp : string Gen.t =
  Gen.map4
    (fun a op b _ -> a ^ " " ^ op ^ " " ^ b)
    gen_int_lit
    (Gen.oneof_list ["=="; "!="; "<"; ">"; "<="; ">="])
    gen_int_lit
    Gen.unit

(** if/do/else/end with integer branches, condition is a bool comparison. *)
let gen_if_int_expr : string Gen.t =
  Gen.map3
    (fun cond t f -> "if " ^ cond ^ " do " ^ t ^ " else " ^ f ^ " end")
    gen_bool_cmp
    gen_arith_expr
    gen_arith_expr

(** Let-chain: two let bindings then an arithmetic combination. *)
let gen_let_chain : string Gen.t =
  Gen.map2
    (fun e1 e2 ->
       "let a = " ^ e1 ^ "\n    let b = " ^ e2 ^ "\n    a + b")
    gen_arith_expr
    gen_arith_expr

(** Module with just arithmetic in main. *)
let gen_arith_module : string Gen.t =
  Gen.map wrap_main gen_arith_expr

(** Module with an if/do/else/end expression in main. *)
let gen_if_module : string Gen.t =
  Gen.map wrap_main gen_if_int_expr

(** Module with let bindings in main. *)
let gen_let_module : string Gen.t =
  Gen.map wrap_main gen_let_chain

(** Module with a named helper function and a call to it. *)
let gen_fn_module : string Gen.t =
  Gen.map3
    (fun offset arg1 arg2 ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn add_offset(x) do\n\
         \    x + %s\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    add_offset(%s) + add_offset(%s)\n\
         \  end\n\
          end"
         offset arg1 arg2)
    gen_pos_int_lit
    gen_arith_expr
    gen_arith_expr

(** Module with pattern matching on a boolean. *)
let gen_match_bool_module : string Gen.t =
  Gen.map3
    (fun cond t f ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let b = %s\n\
         \    match b do\n\
         \    | true -> %s\n\
         \    | false -> %s\n\
         \    end\n\
         \  end\n\
          end"
         cond t f)
    gen_bool_cmp
    gen_arith_expr
    gen_arith_expr

(* ── New generators: ADTs ───────────────────────────────────────────────── *)

(** Module with a simple two-constructor ADT and pattern matching.
    type Shape = Circle(Int) | Square(Int)
    main returns an Int via pattern match on the constructed value. *)
let gen_adt_module : string Gen.t =
  Gen.map3
    (fun use_circle n1 n2 ->
       let ctor    = if use_circle then Printf.sprintf "Circle(%d)" n1
                                   else Printf.sprintf "Square(%d)" n1 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Shape = Circle(Int) | Square(Int)\n\
         \  fn area(s : Shape) : Int do\n\
         \    match s do\n\
         \    | Circle(r) -> r * r\n\
         \    | Square(n) -> n * %d\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let s = %s\n\
         \    area(s)\n\
         \  end\n\
          end"
         n2 ctor)
    Gen.bool
    (Gen.int_range 1 20)
    (Gen.int_range 1 10)

(** Module with a three-constructor ADT and nested pattern matching.
    Exercises the full match path including a constructor with no fields. *)
let gen_adt3_module : string Gen.t =
  Gen.map4
    (fun pick a b _unit ->
       let ctor = match pick mod 3 with
         | 0 -> Printf.sprintf "Pair(%d, %d)" a b
         | 1 -> Printf.sprintf "Single(%d)" a
         | _ -> "Empty"
       in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type MyData = Empty | Single(Int) | Pair(Int, Int)\n\
         \  fn sum_data(d : MyData) : Int do\n\
         \    match d do\n\
         \    | Empty      -> 0\n\
         \    | Single(x)  -> x\n\
         \    | Pair(x, y) -> x + y\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    sum_data(%s)\n\
         \  end\n\
          end"
         ctor)
    Gen.nat_small
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    Gen.unit

(* ── New generators: Closures and HOFs ─────────────────────────────────── *)

(** Module where main creates a closure that captures a variable and calls it. *)
let gen_closure_module : string Gen.t =
  Gen.map3
    (fun base offset arg ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let base = %d\n\
         \    let adder = fn x -> x + base + %d\n\
         \    adder(%d)\n\
         \  end\n\
          end"
         base offset arg)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(** Module that passes a lambda to a higher-order function.
    apply(f, x) = f(x) *)
let gen_hof_apply_module : string Gen.t =
  Gen.map2
    (fun factor arg ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn apply(f : Int -> Int, x : Int) : Int do\n\
         \    f(x)\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    apply(fn n -> n * %d, %d)\n\
         \  end\n\
          end"
         factor arg)
    (Gen.int_range 1 20)
    (Gen.int_range (-50) 50)

(** Module that uses a higher-order function with two closures.
    compose(f, g)(x) = f(g(x)) *)
let gen_hof_compose_module : string Gen.t =
  Gen.map3
    (fun add_val mul_val arg ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn compose(f : Int -> Int, g : Int -> Int, x : Int) : Int do\n\
         \    f(g(x))\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let add%d = fn n -> n + %d\n\
         \    let mul%d = fn n -> n * %d\n\
         \    compose(add%d, mul%d, %d)\n\
         \  end\n\
          end"
         add_val add_val mul_val mul_val add_val mul_val arg)
    (Gen.int_range 1 10)
    (Gen.int_range 1 10)
    (Gen.int_range (-20) 20)

(** Module with a recursive function (factorial or fibonacci-like). *)
let gen_recursive_module : string Gen.t =
  Gen.map
    (fun n ->
       (* Keep n small to avoid stack overflow / huge outputs *)
       let n' = abs n mod 10 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn fact(n : Int) : Int do\n\
         \    if n <= 1 do 1 else n * fact(n - 1) end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    fact(%d)\n\
         \  end\n\
          end"
         n')
    Gen.nat_small

(** Module with two mutually-calling helper functions. *)
let gen_mutual_fns_module : string Gen.t =
  Gen.map2
    (fun n m ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn double_add(x : Int, y : Int) : Int do\n\
         \    (x * 2) + triple_sub(y, x)\n\
         \  end\n\
         \  fn triple_sub(a : Int, b : Int) : Int do\n\
         \    (a * 3) - b\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    double_add(%d, %d)\n\
         \  end\n\
          end"
         n m)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

(* ── New generators: Tuples ─────────────────────────────────────────────── *)

(** Module with tuple construction and let-destructuring.
    Note: March parser bug — a tuple literal on the line immediately after
    `let (x,y) = expr` gets parsed as calling expr with those args.
    Workaround: bind intermediate tuples to a variable before returning. *)
let gen_tuple_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn swap(t : (Int, Int)) : (Int, Int) do\n\
         \    let (x, y) = t\n\
         \    let result = (y, x)\n\
         \    result\n\
         \  end\n\
         \  fn fst(t : (Int, Int)) : Int do\n\
         \    let (x, _) = t\n\
         \    x\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let t = (%d, %d)\n\
         \    let (a, b) = swap(t)\n\
         \    fst((a, b)) + b\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(** Module returning a 2-tuple from a function. *)
let gen_tuple_return_module : string Gen.t =
  Gen.map3
    (fun a b selector ->
       let extract = if selector then "let (x, _) = r\n    x"
                                 else "let (_, y) = r\n    y" in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn make_pair(x : Int, y : Int) : (Int, Int) do\n\
         \    (x + 1, y - 1)\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let r = make_pair(%d, %d)\n\
         \    %s\n\
         \  end\n\
          end"
         a b extract)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)
    Gen.bool

(* ── New generators: String operations ─────────────────────────────────── *)

(** Module that uses string concatenation and to_string.
    Returns the string length so we get an Int result for oracle comparison. *)
let gen_string_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let s1 = to_string(%d)\n\
         \    let s2 = to_string(%d)\n\
         \    let s3 = s1 ++ \" + \" ++ s2\n\
         \    string_length(s3)\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-9999) 9999)
    (Gen.int_range (-9999) 9999)

(** Module using bool_to_string and string ops. *)
let gen_string_bool_module : string Gen.t =
  Gen.map2
    (fun a b ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let cmp = %d > %d\n\
         \    string_length(bool_to_string(cmp))\n\
         \  end\n\
          end"
         a b)
    (Gen.int_range (-50) 50)
    (Gen.int_range (-50) 50)

(* ── New generators: inline List type + operations ─────────────────────── *)

(** Module that defines its own List and uses map/fold over a small list.
    We define the list ops inline to avoid stdlib dependency in the pipeline. *)
let gen_list_module : string Gen.t =
  Gen.map3
    (fun a b c ->
       (* fold_left (acc, Cons(h, t), f) computing sum *)
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type IntList = Nil | Cons(Int, IntList)\n\
         \  fn sum(lst : IntList) : Int do\n\
         \    match lst do\n\
         \    | Nil        -> 0\n\
         \    | Cons(h, t) -> h + sum(t)\n\
         \    end\n\
         \  end\n\
         \  fn map_add1(lst : IntList) : IntList do\n\
         \    match lst do\n\
         \    | Nil        -> Nil\n\
         \    | Cons(h, t) -> Cons(h + 1, map_add1(t))\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let lst = Cons(%d, Cons(%d, Cons(%d, Nil)))\n\
         \    sum(map_add1(lst))\n\
         \  end\n\
          end"
         a b c)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

(** Module with nested pattern matching: ADT inside ADT. *)
let gen_nested_match_module : string Gen.t =
  Gen.map3
    (fun inner_val outer_tag inner_tag ->
       let ctor = match (outer_tag mod 2, inner_tag mod 2) with
         | (0, _) -> "Nothing"
         | (1, 0) -> Printf.sprintf "Just(Left(%d))" inner_val
         | _      -> Printf.sprintf "Just(Right(%d))" inner_val
       in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Side = Left(Int) | Right(Int)\n\
         \  type Maybe = Nothing | Just(Side)\n\
         \  fn extract(m : Maybe) : Int do\n\
         \    match m do\n\
         \    | Nothing      -> 0\n\
         \    | Just(Left(x))  -> x\n\
         \    | Just(Right(x)) -> x + 100\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    extract(%s)\n\
         \  end\n\
          end"
         ctor)
    (Gen.int_range (-50) 50)
    Gen.nat_small
    Gen.nat_small

(* ── New generators: generic-container println/show output ──────────────
   Guards the `ffe6fba8` bug class: compiled `println([1,2,3])` (and any
   generic container routed through prelude's `impl Show(List(a)) when
   Show(a)` / `impl Show(Option(a)) when Show(a)`) never worked in compiled
   mode — mono enqueued the specialized impl with an empty substitution, so
   the nested element-level `show(x)` call survived to llvm_emit unresolved
   and got silently rebound to the wrong impl (SIGSEGV / panic depending on
   element type).  Fixed in `ffe6fba8`.  These generators are regression
   protection for that whole family, so they must all be fully GREEN.

   IMPORTANT — scope carefully verified by hand (`_build/default/bin/main.exe`
   probes) before writing these, because two ADJACENT shapes are still
   genuinely broken today and must NOT be generated here (that would redden
   an otherwise-green oracle on a real, separate bug rather than the fixed
   one):
     - Tuples have NO `impl Show` in stdlib/prelude.march at all.
       `println((1, 2))` fails to even LINK (`Undefined symbols: _show`) and
       `to_string((1, 2))` compiles but prints garbage `#<tag:N>` (compiled
       `to_string` on any non-primitive type bypasses `show` entirely — see
       `specs/todos.md` "Deferred discoveries" under the `Check.all` fix, and
       `.superpowers/sdd/oracle-task-3-report.md` for the fresh repro this
       task found).  So: no tuple generator here.
     - A bare/unpinned `None` (no `Some` anywhere to pin the element type)
       ALSO fails to link compiled (`println(None)`) even with an explicit
       `Option(Int)` annotation, and `to_string(None : Option(Int))` compiles
       but prints `nil` instead of `None`.  So: every `Option`/`List(Option)`
       generator below guarantees at least one `Some(_)` occurrence and never
       emits a bare `None` on its own.
     - `to_string(container)` (as opposed to `println(container)`, which
       goes through prelude's `show`) is ALSO broken compiled for every
       non-primitive type (confirmed: `to_string([1,2,3])` -> `#<tag:1>`,
       `to_string(Some(9))` -> `9`, both compiled-only divergences from the
       interpreter).  So every generator below prints via `println(<container
       literal>)` directly — never `to_string(<container>)` — matching the
       exact repro shape from `ffe6fba8`'s own regression tests
       (`test/test_codegen.ml`'s `iface_impl_mono_codegen` suite). *)

(** Module that prints a non-empty list of Ints via println/show.
    Guards: println([1,2,3]) — the literal ffe6fba8 repro (was SIGSEGV). *)
let gen_println_int_list_module : string Gen.t =
  Gen.map
    (fun xs ->
       let elems = String.concat ", " (List.map string_of_int xs) in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([%s])\n\
         \  end\n\
          end"
         elems)
    (Gen.list_size (Gen.int_range 1 5) (Gen.int_range (-100) 100))

(** Module that prints a non-empty list of Strings via println/show.
    Guards: println(["a","b"]) — ffe6fba8's non-exhaustive-panic variant.
    Strings are kept to a small safe alphanumeric alphabet: no quotes,
    backslashes, or newlines, so the generated source is always
    well-formed and the printed form is unambiguous. *)
let gen_println_string_list_module : string Gen.t =
  let gen_word : string Gen.t =
    Gen.map
      (fun cs -> String.init (List.length cs) (List.nth cs))
      (Gen.list_size (Gen.int_range 1 4)
         (Gen.map (fun i -> Char.chr (Char.code 'a' + i)) (Gen.int_range 0 25)))
  in
  Gen.map
    (fun words ->
       let elems = String.concat ", " (List.map (Printf.sprintf "%S") words) in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([%s])\n\
         \  end\n\
          end"
         elems)
    (Gen.list_size (Gen.int_range 1 5) gen_word)

(** Module that prints Option(Int) via println/show.  Every value printed
    here is `Some(n)` — never a bare `None` call — because a standalone
    `println(None)` fails to LINK compiled (`Undefined symbols: _show`)
    even when a `Some(...)` of the same element type appears elsewhere in
    the program: verified by hand that mono resolves each `println` call
    site's `Show$Option` specialization independently from its OWN static
    argument, not globally across the module, so an earlier sibling
    `println(Some(n))` does NOT pin the type for a later, separate
    `println(None)` call (an earlier draft of this generator emitted
    exactly that shape and produced real link failures — see
    `.superpowers/sdd/oracle-task-3-report.md`).  `None` IS safely
    exercised elsewhere in this file, but only inside a list literal
    alongside a `Some(_)` in the SAME call site — see
    [gen_println_list_of_options_module] below.
    Guards: println(Some(5)) (ffe6fba8's SIGSEGV/SIGBUS Option variant). *)
let gen_println_option_module : string Gen.t =
  Gen.map2
    (fun n m ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println(Some(%d))\n\
         \    println(Some(%d))\n\
         \  end\n\
          end"
         n m)
    (Gen.int_range (-100) 100)
    (Gen.int_range (-100) 100)

(** Module that prints a nested list of Ints, `List(List(Int))`, via
    println/show — every list at every level is non-empty (an empty list
    literal, e.g. `[]`, fails to link compiled: verified by hand,
    `println([])`/`println([[1],[]])`'s empty-inner-list sibling can still
    compile since the OUTER element type is pinned by a non-empty sibling,
    but to stay safely inside the green subset every inner list generated
    here is non-empty too).
    Guards: println([[1,2],[3]]) — ffe6fba8's nested/recursive-mono-
    termination variant (Show$List specializing Show$List again). *)
let gen_println_nested_list_module : string Gen.t =
  let gen_inner : string Gen.t =
    Gen.map
      (fun xs -> "[" ^ String.concat ", " (List.map string_of_int xs) ^ "]")
      (Gen.list_size (Gen.int_range 1 3) (Gen.int_range (-50) 50))
  in
  Gen.map
    (fun inners ->
       let elems = String.concat ", " inners in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([%s])\n\
         \  end\n\
          end"
         elems)
    (Gen.list_size (Gen.int_range 1 3) gen_inner)

(** Module that prints a non-empty list of Option(Int), `List(Option(Int))`
    — always includes at least one `Some(_)` so the element type is pinned
    (an all-`None` list, e.g. `[None, None]`, fails to link compiled:
    verified by hand — same root cause as the bare-`None` case above).
    Guards: println([Some(1), None, Some(3)]) — the exact ffe6fba8
    regression-test repro for `List(Option(Int))`. *)
let gen_println_list_of_options_module : string Gen.t =
  Gen.map
    (fun opts ->
       (* Force at least one Some by construction: map (bool, int) pairs to
          Some/None, then guarantee element 0 is Some so the list is never
          all-None regardless of what the bools drew. *)
       let rendered =
         List.mapi
           (fun i (is_some, n) ->
              if i = 0 || is_some then Printf.sprintf "Some(%d)" n else "None")
           opts
       in
       let elems = String.concat ", " rendered in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    println([%s])\n\
         \  end\n\
          end"
         elems)
    (Gen.list_size (Gen.int_range 1 5) (Gen.pair Gen.bool (Gen.int_range (-50) 50)))

(* ── Derived-method-call generators (Newtype-derive fix regression guard,
   commit 6cc676fc, 2026-07-04) ────────────────────────────────────────────
   Each generator derives Eq/Ord/Hash for a type, then calls the derived
   method BY NAME (`eq(x,y)`/`compare(x,y)`/`hash(x)`) — the path that used
   to crash compiled on Newtype-repr (single-ctor single-field) variants:
   SIGSEGV for an Int payload, a non-exhaustive-panic for a String payload.
   The `==` OPERATOR path (`ensure_adt_eq_fn`, Repr-aware for the niche/
   Boxed cases) was never affected by 6cc676fc's bug, and each generator
   below also exercises `==` back-to-back with named `eq()` on the SAME
   value — the exact discriminator that isolated "named-method-only" from
   6cc676fc's own regression tests (`test_newtype_derived_eq_operator_vs_
   named_parity` in test_codegen.ml).

   Derived Ord/Hash on VARIANTS intentionally ignore ctor payload — only the
   constructor's declared index matters (`syntax_reference.md` "Derived
   Ord/Hash ignore constructor payloads"), so `compare`'s printed value is a
   payload-independent, stable 0 for any same-constructor pair regardless of
   which random payload the generator drew — deterministic across interp and
   compiled by construction, not by luck. Records are the one case where
   derived Ord/Hash DO look at payload (field-by-field) — see
   [gen_derived_method_record_module] below for why `hash` is excluded there.

   NEWTYPE HEAP-PAYLOAD `==` OPERATOR (real bug found while scoping this
   generator, distinct from 6cc676fc — NOW FIXED): for `type WrapS =
   WrapS(String)` (Newtype repr, String payload), the `==` OPERATOR used to
   give the WRONG answer compiled (`false` for two content-equal strings;
   interp correctly gives `true`) while named `eq()` on the same value was
   correct. Root cause: `ensure_adt_eq_fn` (`lib/tir/llvm_eq.ml`)
   special-cased the Niche (Option-shaped) repr but never consulted
   `Repr.repr_of_ty` for `Newtype` — a String-payload Newtype value is a bare
   heap string pointer with no ctor-tag header, but `ensure_adt_eq_fn`'s
   generic fallback unconditionally read a "ctor tag" at `payload_ptr + 8`
   (inside the string's own heap layout) as if it were a Boxed ADT cell,
   comparing garbage between two distinct string allocations (likewise for any
   heap payload: Boxed ADT / tuple / record). Fixed by adding a
   `Repr.Newtype payload` arm to `ensure_adt_eq_fn` that compares the
   unwrapped operands directly per the payload's repr (march_string_eq for
   String, recursive `ensure_adt_eq_fn` for a nested heap ADT/tuple/record,
   tagged-bits `icmp` for scalars) — no tag/field offset load. The
   String-payload Newtype generator below (Step 1b) now exercises the `==`
   OPERATOR alongside named `eq()`/`compare()`, matching the other shapes; an
   Int-payload Newtype never routed through `ensure_adt_eq_fn` in the first
   place (tagged scalar, `ty_a` is `i64` not `ptr` at the `==`-lowering call
   site, llvm_emit.ml:1051). Compiled regression coverage in test_codegen.ml's
   `newtype_derived_method_crash` suite (String, Int-control, Boxed-ADT). *)

(** (a) Newtype-repr (single-ctor single-field), Int payload — the exact
    shape 6cc676fc fixed for named eq/compare/hash. Exercises `==` AND
    named `eq()` back-to-back on the same values (the discriminator). *)
let gen_derived_method_newtype_int_module : string Gen.t =
  Gen.map3
    (fun n1 n2 same ->
       let n2' = if same then n1 else n2 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Wrap = Wrap(Int)\n\
         \  derive Eq, Ord, Hash for Wrap\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = Wrap(%d)\n\
         \    let b = Wrap(%d)\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(int_to_string(compare(a, b)))\n\
         \  end\n\
          end"
         n1 n2')
    (Gen.int_range (-100) 100)
    (Gen.int_range (-100) 100)
    Gen.bool

(** (b) Newtype-repr, String payload — 6cc676fc's non-exhaustive-panic
    variant for named methods, AND the `==`-operator heap-payload bug (both
    now fixed; see the file-level comment above and specs/todos.md). Exercises
    the `==` OPERATOR alongside named `eq()`/`compare()` — the `==`-vs-`eq`
    discriminator on a heap-payload Newtype, which regressed the operator
    path specifically. *)
let gen_derived_method_newtype_string_module : string Gen.t =
  let gen_word : string Gen.t =
    Gen.map
      (fun cs -> String.init (List.length cs) (List.nth cs))
      (Gen.list_size (Gen.int_range 1 6)
         (Gen.map (fun i -> Char.chr (Char.code 'a' + i)) (Gen.int_range 0 25)))
  in
  Gen.map3
    (fun w1 w2 same ->
       let w2' = if same then w1 else w2 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type WrapS = WrapS(String)\n\
         \  derive Eq, Ord, Hash for WrapS\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = WrapS(%S)\n\
         \    let b = WrapS(%S)\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(int_to_string(compare(a, b)))\n\
         \  end\n\
          end"
         w1 w2')
    gen_word
    gen_word
    Gen.bool

(** (c) Multi-field single-ctor (Boxed repr, NOT Newtype) — negative
    control confirming the Boxed path (always worked) stays correct.
    Exercises `==` and named `eq()`. *)
let gen_derived_method_boxed_module : string Gen.t =
  Gen.map3
    (fun a1 a2 same ->
       let a2' = if same then a1 else a2 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Pair = Pair(Int, Int)\n\
         \  derive Eq, Ord, Hash for Pair\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = Pair(%d, %d)\n\
         \    let b = Pair(%d, %d)\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(int_to_string(compare(a, b)))\n\
         \  end\n\
          end"
         (fst a1) (snd a1) (fst a2') (snd a2'))
    (Gen.pair (Gen.int_range (-50) 50) (Gen.int_range (-50) 50))
    (Gen.pair (Gen.int_range (-50) 50) (Gen.int_range (-50) 50))
    Gen.bool

(** (d) Multi-ctor enum — never Newtype/Niche-shaped with >=3 ctors or two
    non-nullary ctors, so this always took the general Boxed ctor-table
    path. Exercises `==` and named `eq()`; `compare` prints the
    payload-IGNORING ctor-index difference (documented semantics). *)
let gen_derived_method_enum_module : string Gen.t =
  Gen.map3
    (fun pick_a pick_b n ->
       let ctor_of pick = match pick mod 2 with
         | 0 -> Printf.sprintf "Circle(%d)" n
         | _ -> Printf.sprintf "Square(%d)" n
       in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Shape = Circle(Int) | Square(Int)\n\
         \  derive Eq, Ord, Hash for Shape\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = %s\n\
         \    let b = %s\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(int_to_string(compare(a, b)))\n\
         \  end\n\
          end"
         (ctor_of pick_a) (ctor_of pick_b))
    Gen.nat_small
    Gen.nat_small
    (Gen.int_range (-50) 50)

(** (e) Record — derived Ord for records DOES look at payload (field-by-
    field, unlike variants), so `compare` here is genuinely payload-
    sensitive; still deterministic interp-vs-compiled since it's pure Int
    field comparison. `hash` is still NOT printed here, but the reason
    changed (2026-07-13): the primitive `hash()` forms are now cross-backend
    identical (the interpreter reimplements the compiled runtime's
    splitmix64/FNV-1a algorithms bit-for-bit, both masked to 62 bits —
    golden `g51_hash_cross_backend`). What remains non-portable for a RECORD
    is the derived-Hash COMBINE (`hash(field)*prime + …`, generated March
    AST): it can OVERFLOW 63-bit signed, and the interpreter's Int is 63-bit
    while the compiled backend's is 64-bit — the general interpreter-int-
    width limitation, orthogonal to the hash algorithm. This generator's
    fields are unbounded, so the combine could land in the overflow tail;
    printing record `hash` would reintroduce a divergence unrelated to the
    Newtype-derive fix this generator guards. `eq`/`compare`/`==` (its
    actual job) never touch hash. *)
let gen_derived_method_record_module : string Gen.t =
  Gen.map3
    (fun p1 p2 same ->
       let p2' = if same then p1 else p2 in
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Point = { x: Int, y: Int }\n\
         \  derive Eq, Ord, Hash for Point\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let a = { x: %d, y: %d }\n\
         \    let b = { x: %d, y: %d }\n\
         \    println(bool_to_string(a == b))\n\
         \    println(bool_to_string(eq(a, b)))\n\
         \    println(int_to_string(compare(a, b)))\n\
         \  end\n\
          end"
         (fst p1) (snd p1) (fst p2') (snd p2'))
    (Gen.pair (Gen.int_range (-50) 50) (Gen.int_range (-50) 50))
    (Gen.pair (Gen.int_range (-50) 50) (Gen.int_range (-50) 50))
    Gen.bool

(* ── Record-update / dual-position-borrow / FBIP / erased-flow generators
   (Phase 2c, Task 5) ──────────────────────────────────────────────────────
   Four generators guarding four distinct FIXED bug classes:

   (a) [gen_record_update_module] — `{ base with f: v }` functional update on
       a STATICALLY-KNOWN-SHAPE record where the updated field EXISTS.
       Guards the `EUpdate` family fixed in `0d1a829e` (B5: erased-shape
       `EUpdate` wrote past the allocation; `march_record_update_dyn` now
       handles it with one alloc + base-copy + named overwrite). This
       generator deliberately stays on a statically-typed record (`{ x: Int,
       y: Int }` declared as a nominal type), never a `record_from_list` /
       `record_put`-produced erased base — updating a field that does NOT
       exist on an erased base is the OPEN interpreter/compiled divergence
       (`specs/todos.md`: compiled panics via `march_record_update_dyn`,
       interpreter silently fabricates the field). That case is NOT
       generated here; see [test_record_update_missing_field_on_erased_base_
       diverges_documented] below for a targeted, citation-bearing
       documented-skip covering it instead, per this plan's "constrain to
       the currently-working subset" rule.

   (b) [gen_dual_position_borrow_module] — a fn `both(a: String, b: String,
       n: Int)` called as `both(s, s, n)` with `s` dead afterwards: the SAME
       variable flows into what Perceus infers as an OWNED position (`a`,
       returned on one branch) and a BORROWED position (`b`, only read via
       `String.byte_size`) of the same call. Guards the dual-position
       owned+borrowed double-consumption fixed in `a5dad194` (was RC
       underflow, exit 134, compiled-only — interpreter always fine).
       Mirrors `test_compiled_dual_position_owned_borrowed` in
       test_stdlib_suite.ml exactly, with the threshold/length randomized.

   (c) [gen_fbip_same_arity_module] — a dead binding of `Result(Int, String)`
       (a MULTI type-param ADT — two params, `a` and `b`) immediately before
       a same-arity allocation of the SAME type (`Ok(_)`/`Err(_)` are both
       1-field ctors, so the reused cell is genuinely the right size —
       exactly the shape the fix's `$fbip$`-marked arity encoding must get
       right for a 2-type-param TCon). Guards the FBIP `same_arity`
       conflation fixed in `a5dad194` (a TCon's type-PARAMETER count was
       compared against a constructor's FIELD count; a dead binding's raw
       declared type let a narrower cell get reused for a wider constructor,
       overflowing the heap cell — `Result`'s 2 type params vs. `Ok`/`Err`'s
       1 field is precisely the parameter-count/field-count mismatch the
       bug conflated). Mirrors `test_compiled_fbip_arity_no_overflow` in
       test_stdlib_suite.ml (which uses a 5-type-param/1-vs-5-field type),
       parameterized over the churn seed.

   (d) [gen_erased_flow_module] — a value flows through a bare-`TVar`
       generic wrapper (`type Box(a) = Box(a)`, plus a generic `identity`
       function) and is then used CONCRETELY (arithmetic on the unwrapped
       Int). Exercises the erased/type-erased representation path (no
       static shape known inside `unwrap`/`identity`) merging back into a
       concrete numeric use — the general class of erased-repr flow that
       B5's fix and the newtype/niche repr work above both had to get right
       for. All four generators print a single stable Int or String via
       `to_string`/bare `println` — no `==`/`hash`/tuple-or-container
       `to_string` (per this plan's determinism constraints). *)

(** (a) Record update on a statically-known-shape record, updated field
    EXISTS. Guards `0d1a829e` (EUpdate family). *)
let gen_record_update_module : string Gen.t =
  Gen.map3
    (fun x y dx ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Point = { x: Int, y: Int }\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let p = { x: %d, y: %d }\n\
         \    let q = { p with x: p.x + %d }\n\
         \    println(to_string(q.x + q.y))\n\
         \  end\n\
          end"
         x y dx)
    (Gen.int_range (-100) 100)
    (Gen.int_range (-100) 100)
    (Gen.int_range (-50) 50)

(** (b) Dual-position borrow: `both(a: String, b: String, n: Int)` called as
    `both(s, s, n)`, `s` dead afterwards. `a` is used on the owned
    (returned) branch, `b` only via `String.byte_size` (borrowed). The
    string is forced past 15 bytes (inline-string threshold) so it is
    actually heap-allocated and RC-tracked. Guards `a5dad194`. *)
let gen_dual_position_borrow_module : string Gen.t =
  Gen.map2
    (fun tag threshold ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn both(a : String, b : String, n : Int) : String do\n\
         \    if String.byte_size(b) > n do\n\
         \      a\n\
         \    else\n\
         \      \"short\"\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let s = \"hello-world-this-is-a-long-string-\" ++ to_string(%d)\n\
         \    let r = both(s, s, %d)\n\
         \    println(r)\n\
         \  end\n\
          end"
         tag threshold)
    (Gen.int_range 0 999)
    (Gen.int_range 1 5)

(** (c) FBIP same_arity: a dead binding of `Result(Int, String)` — a
    multi-type-param (2) ADT — immediately before a same-arity allocation
    (`mk_result` returns either `Ok(n)` [1 field] or `Err(msg)` [1 field] of
    the SAME 2-type-param `Result`). Mirrors the exact overflow shape from
    `test_compiled_fbip_arity_no_overflow`: a dead `Ok`/`Err` cell followed
    by a live one, matched immediately after. Guards `a5dad194`. *)
let gen_fbip_same_arity_module : string Gen.t =
  Gen.map2
    (fun seed bump ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  pfn churn(n : Int) : Int do\n\
         \    if n > 100 do n else churn(n + 7) end\n\
         \  end\n\
         \  pfn mk_result(n : Int) : Result(Int, String) do\n\
         \    if n > 0 do Ok(n) else Err(\"bad\") end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let n = churn(%d)\n\
         \    let dead = mk_result(n)\n\
         \    let q = mk_result(n + %d)\n\
         \    match q do\n\
         \      Ok(v) -> println(to_string(v))\n\
         \      Err(e) -> println(e)\n\
         \    end\n\
         \  end\n\
          end"
         seed bump)
    (Gen.int_range 1 20)
    (Gen.int_range 1 90)

(** (d) Erased flow: a value passes through a bare-`TVar` generic wrapper
    (`Box(a)`) and a generic `identity` function — both fully type-erased
    inside their own bodies — then is used CONCRETELY (arithmetic) after
    unwrapping. Guards the general erased-representation flow class
    (generic identity/HOF over an unknown-shape payload). *)
let gen_erased_flow_module : string Gen.t =
  Gen.map2
    (fun n delta ->
       Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Box(a) = Box(a)\n\
         \  fn unwrap(b : Box(a)) : a do\n\
         \    match b do\n\
         \      Box(v) -> v\n\
         \    end\n\
         \  end\n\
         \  fn identity(x : a) : a do\n\
         \    x\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let boxed = Box(identity(%d))\n\
         \    let n = unwrap(boxed)\n\
         \    println(to_string(n + %d))\n\
         \  end\n\
          end"
         n delta)
    (Gen.int_range (-100) 100)
    (Gen.int_range (-50) 50)

(** Any of the well-typed module generators (original + new). *)
let gen_well_typed_module : string Gen.t =
  Gen.oneof [
    (* Original generators *)
    gen_arith_module;
    gen_if_module;
    gen_let_module;
    gen_fn_module;
    gen_match_bool_module;
    (* New generators *)
    gen_adt_module;
    gen_adt3_module;
    gen_closure_module;
    gen_hof_apply_module;
    gen_hof_compose_module;
    gen_recursive_module;
    gen_mutual_fns_module;
    gen_tuple_module;
    gen_tuple_return_module;
    gen_string_module;
    gen_string_bool_module;
    gen_list_module;
    gen_nested_match_module;
    (* Generic-container println/show generators (ffe6fba8 regression guard) *)
    gen_println_int_list_module;
    gen_println_string_list_module;
    gen_println_option_module;
    gen_println_nested_list_module;
    gen_println_list_of_options_module;
    (* Derived-method-call generators (Newtype-derive fix regression guard,
       Task 4 / Phase 2b) *)
    gen_derived_method_newtype_int_module;
    gen_derived_method_newtype_string_module;
    gen_derived_method_boxed_module;
    gen_derived_method_enum_module;
    gen_derived_method_record_module;
    (* Record-update / dual-position-borrow / FBIP / erased-flow generators
       (Phase 2c / Task 5) *)
    gen_record_update_module;
    gen_dual_position_borrow_module;
    gen_fbip_same_arity_module;
    gen_erased_flow_module;
  ]

(* ── TIR AST generators ─────────────────────────────────────────────────── *)

(** Generate a [Tir.atom] for a literal integer. *)
let gen_tir_int_atom : Tir.atom Gen.t =
  Gen.map (fun n -> Tir.ALit (Ast.LitInt n)) (Gen.int_range (-50) 50)

(** Generate a [Tir.atom] for a literal bool. *)
let gen_tir_bool_atom : Tir.atom Gen.t =
  Gen.map (fun b -> Tir.ALit (Ast.LitBool b)) Gen.bool

(** Generate a TIR expression that is closed (no free variables) and has
    type Int.  Kept shallow to stay tractable. *)
let gen_tir_int_expr : Tir.expr Gen.t =
  Gen.fix (fun self depth ->
    if depth = 0 then
      Gen.map (fun a -> Tir.EAtom a) gen_tir_int_atom
    else
      Gen.oneof_weighted [
        3, Gen.map (fun a -> Tir.EAtom a) gen_tir_int_atom;
        (* let v : Int = <literal> in <sub-expr> *)
        2, Gen.map2
             (fun n sub ->
                let v = { Tir.v_name = Printf.sprintf "x%d" depth;
                          v_ty = Tir.TInt; v_lin = Tir.Unr } in
                Tir.ELet (v, Tir.EAtom (Tir.ALit (Ast.LitInt n)), sub))
             (Gen.int_range (-50) 50)
             (self (depth-1));
        (* tuple of two ints *)
        1, Gen.map2
             (fun a b -> Tir.ETuple [a; b])
             gen_tir_int_atom
             gen_tir_int_atom;
        (* case b of { true -> n1 | false -> n2 } — exercises perceus branch *)
        1, Gen.map3
             (fun b n1 n2 ->
                let bv = { Tir.v_name = Printf.sprintf "b%d" depth;
                           Tir.v_ty = Tir.TBool; Tir.v_lin = Tir.Unr } in
                let br_true  = { Tir.br_tag = "true";  Tir.br_vars = [];
                                 Tir.br_body = Tir.EAtom (Tir.ALit (Ast.LitInt n1)) } in
                let br_false = { Tir.br_tag = "false"; Tir.br_vars = [];
                                 Tir.br_body = Tir.EAtom (Tir.ALit (Ast.LitInt n2)) } in
                Tir.ELet (bv, Tir.EAtom b,
                  Tir.ECase (Tir.AVar bv, [br_true; br_false], None)))
             gen_tir_bool_atom
             (Gen.int_range (-50) 50)
             (Gen.int_range (-50) 50);
        (* ELetRec: a simple identity lambda called immediately *)
        1, Gen.map
             (fun n ->
                let param = { Tir.v_name = "p"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
                let fn_v   = { Tir.v_name = "id_fn"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
                let fn_def : Tir.fn_def = {
                  fn_name   = "id_fn";
                  fn_params = [param];
                  fn_ret_ty = Tir.TInt;
                  fn_body   = Tir.EAtom (Tir.AVar param);
                  fn_kind   = Tir.FnLambda;
                } in
                (* let $clo = letrec [id_fn] in EAtom(AVar id_fn) in EAtom($clo) *)
                let clo_var = { Tir.v_name = "clo"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
                Tir.ELet (clo_var,
                  Tir.ELetRec ([fn_def], Tir.EAtom (Tir.AVar fn_v)),
                  Tir.ECallPtr (Tir.AVar clo_var, [Tir.ALit (Ast.LitInt n)])))
             (Gen.int_range (-50) 50);
      ]
  ) 3

(** Generate a TIR module with a closure that captures a free variable.
    This exercises defunctionalization's free-variable collection. *)
let gen_tir_closure_module : Tir.tir_module Gen.t =
  Gen.map2
    (fun captured body_add ->
       (* fn main() = let base = captured in
                       let clo = letrec [adder] in EAtom(AVar adder) in
                       ECallPtr(clo, [42]) *)
       let base_var  = { Tir.v_name = "base"; v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let param_var = { Tir.v_name = "x";    v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let adder_v   = { Tir.v_name = "adder"; v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
       let clo_var   = { Tir.v_name = "clo";  v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
       (* adder body: x + base + body_add *)
       let add_var   = { Tir.v_name = "tmp";  v_ty = Tir.TInt; v_lin = Tir.Unr } in
       let adder_body =
         Tir.ELet (add_var,
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr },
                     [Tir.AVar param_var; Tir.AVar base_var]),
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr },
                     [Tir.AVar add_var; Tir.ALit (Ast.LitInt body_add)]))
       in
       let adder_fn : Tir.fn_def = {
         fn_name   = "adder";
         fn_params = [param_var];
         fn_ret_ty = Tir.TInt;
         fn_body   = adder_body;
         fn_kind   = Tir.FnLambda;
       } in
       let main_body =
         Tir.ELet (base_var,
           Tir.EAtom (Tir.ALit (Ast.LitInt captured)),
           Tir.ELet (clo_var,
             Tir.ELetRec ([adder_fn], Tir.EAtom (Tir.AVar adder_v)),
             Tir.ECallPtr (Tir.AVar clo_var, [Tir.ALit (Ast.LitInt 10)])))
       in
       let main_fn : Tir.fn_def = {
         fn_name   = "main";
         fn_params = [];
         fn_ret_ty = Tir.TInt;
         fn_body   = main_body;
         fn_kind   = Tir.FnNormal;
       } in
       { Tir.tm_name    = "Main";
         Tir.tm_fns     = [main_fn];
         Tir.tm_types   = [];
         Tir.tm_externs = [];
         Tir.tm_exports = []; tm_tests = []; tm_io_fns = [] })
    (Gen.int_range (-20) 20)
    (Gen.int_range (-20) 20)

(** Generate a minimal TIR module with a single [main] function whose body
    is a closed integer expression. *)
let gen_tir_module : Tir.tir_module Gen.t =
  Gen.map
    (fun body ->
       let fn : Tir.fn_def = {
         fn_name   = "main";
         fn_params = [];
         fn_ret_ty = Tir.TInt;
         fn_body   = body;
         fn_kind   = Tir.FnNormal;
       } in
       { Tir.tm_name    = "Main";
         Tir.tm_fns     = [fn];
         Tir.tm_types   = [];
         Tir.tm_externs = [];
         Tir.tm_exports = []; tm_tests = []; tm_io_fns = [] })
    gen_tir_int_expr

(* ── TIR walking utilities ──────────────────────────────────────────────── *)

(** Walk a TIR expression and return true if any ELetRec is found. *)
let rec has_letrec : Tir.expr -> bool = function
  | Tir.ELetRec _              -> true
  | Tir.ELet (_, e1, e2)       -> has_letrec e1 || has_letrec e2
  | Tir.ECase (_, brs, def)    ->
    List.exists (fun b -> has_letrec b.Tir.br_body) brs ||
    (match def with Some e -> has_letrec e | None -> false)
  | Tir.ESeq (e1, e2)          -> has_letrec e1 || has_letrec e2
  | _                          -> false

(** Collect all type annotations from a TIR expression. *)
let rec collect_types_expr (acc : Tir.ty list) : Tir.expr -> Tir.ty list = function
  | Tir.EAtom (Tir.AVar v)    -> v.Tir.v_ty :: acc
  | Tir.ELet (v, e1, e2)      ->
    collect_types_expr (collect_types_expr (v.Tir.v_ty :: acc) e1) e2
  | Tir.ELetRec (fns, body)   ->
    let acc' = List.fold_left (fun a fn ->
        fn.Tir.fn_ret_ty ::
        List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params @
        collect_types_expr [] fn.Tir.fn_body @ a) acc fns in
    collect_types_expr acc' body
  | Tir.ECase (_, brs, def)   ->
    let acc' = List.fold_left (fun a b -> collect_types_expr a b.Tir.br_body) acc brs in
    (match def with Some e -> collect_types_expr acc' e | None -> acc')
  | Tir.ESeq (e1, e2)         -> collect_types_expr (collect_types_expr acc e1) e2
  | _                         -> acc

let collect_types_module (m : Tir.tir_module) : Tir.ty list =
  List.fold_left (fun acc fn ->
    fn.Tir.fn_ret_ty ::
    List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params @
    collect_types_expr [] fn.Tir.fn_body @ acc
  ) [] m.Tir.tm_fns

(* ── Helper: extract VInt from a value ─────────────────────────────────── *)

let value_to_int = function
  | March_eval.Eval.VInt n -> Some n
  | _                      -> None

(* ── Oracle helper: run the march binary on source ─────────────────────── *)

(** Find the march binary.  Returns None if not found. *)
let find_march_bin () =
  let candidates = [
    Sys.getenv_opt "MARCH_BIN" |> Option.value ~default:"";
    "_build/default/bin/main.exe";
    "../_build/default/bin/main.exe";
  ] in
  List.find_opt (fun p -> p <> "" && Sys.file_exists p) candidates
  |> Option.map (fun p ->
       if Filename.is_relative p
       then Filename.concat (Sys.getcwd ()) p
       else p)

(** Memoize binary location so we don't stat on every test. *)
let march_bin_opt : string option Lazy.t =
  lazy (find_march_bin ())

(* ── Timeout mechanism detection (P0: the oracle must actually run) ──────── *)

(** The oracle bounds every subprocess so a generated infinite loop can't hang
    the suite.  Historically this used a hardcoded `timeout N sh -c ...`, but
    GNU coreutils `timeout` is NOT present on macOS by default (and CI's macOS
    runner brew-installs blake3/brotli/zstd/llvm — not coreutils), so on those
    hosts every `timeout ...` invocation failed with 127 (command-not-found),
    the interpreter step saw rc<>0, and EVERY oracle check silently skipped —
    the ultimate vacuous-green: the oracle "passed" while testing nothing.

    Detect the mechanism ONCE at module load and build the command prefix from
    whatever exists: prefer `timeout`, then `gtimeout` (Homebrew coreutils),
    then a portable perl fallback that actually bounds runtime.  The perl
    fallback forks the child into its own process group and, on ALARM, kills
    the whole group and exits 124 — preserving the `timeout` convention that
    124 == timed-out.  It also reconstructs the shell's 128+signal convention
    for signal deaths (segfault/abort) so [classify_compile] and the
    `rc_run >= 128` crash check keep working: `$? & 127` is the death signal,
    `$? >> 8` the exit code. *)

(** Is [name] an executable on PATH?  Uses `command -v` (POSIX, always present)
    rather than `which` (not guaranteed).  Silent — output discarded. *)
let on_path name =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" (Filename.quote name)) = 0

(** The perl fallback body (a single -e program).  Args at runtime:
    <seconds> <program> [args...].  Kept as one string constant so the exact
    quoting is auditable in one place. *)
let perl_timeout_prog =
  "my $t=shift @ARGV; my $p=fork; \
   if(!$p){ setpgrp(0,0); exec @ARGV or exit 127 } \
   $SIG{ALRM}=sub{ kill 9,-$p; exit 124 }; \
   alarm $t; waitpid $p,0; my $s=$?; \
   exit($s & 127 ? 128 + ($s & 127) : $s >> 8)"

(** Chosen mechanism, resolved once.  [`Timeout]/[`Gtimeout] use the coreutils
    binary directly; [`Perl] uses the fallback; [`None_avail] means we could
    not bound subprocesses at all (perl absent too) — in that case we still
    run, unbounded, but LOUDLY warn, because an unbounded oracle can hang. *)
let timeout_mechanism : [ `Timeout | `Gtimeout | `Perl | `None_avail ] Lazy.t =
  lazy (
    if on_path "timeout" then `Timeout
    else if on_path "gtimeout" then `Gtimeout
    else if on_path "perl" then `Perl
    else `None_avail
  )

(** Build the command prefix that bounds [cmd] (already a single shell-word,
    typically [Filename.quote]d) to [timeout] seconds.  The caller appends
    redirections; the whole thing runs under the default shell via
    [Sys.command].  For every mechanism the bounded command is executed as
    `sh -c <cmd>`, matching the original semantics exactly. *)
let bounded_command ~timeout ~quoted_cmd =
  match Lazy.force timeout_mechanism with
  | `Timeout  -> Printf.sprintf "timeout %d sh -c %s" timeout quoted_cmd
  | `Gtimeout -> Printf.sprintf "gtimeout %d sh -c %s" timeout quoted_cmd
  | `Perl     ->
    Printf.sprintf "perl -e %s %d /bin/sh -c %s"
      (Filename.quote perl_timeout_prog) timeout quoted_cmd
  | `None_avail ->
    (* No bounding available — run directly.  A generated infinite loop CAN
       hang here; that's why we warn loudly at startup below. *)
    Printf.sprintf "sh -c %s" quoted_cmd

(** Loud one-line note at startup recording which mechanism was chosen — the
    loud-skip doctrine applied to the timeout mechanism itself, so a future
    run's log shows "using gtimeout" / "using perl fallback" instead of the
    silent 100%-skip that hid this bug. *)
let () =
  let note =
    match Lazy.force timeout_mechanism with
    | `Timeout    -> "using `timeout` (GNU coreutils on PATH)"
    | `Gtimeout   -> "using `gtimeout` (Homebrew coreutils on PATH)"
    | `Perl       -> "using perl fallback (no timeout/gtimeout on PATH)"
    | `None_avail -> "WARNING: no timeout/gtimeout/perl — subprocesses run \
                      UNBOUNDED; a generated infinite loop may hang the suite"
  in
  Printf.eprintf "[oracle] subprocess timeout mechanism: %s\n%!" note

(** Run a shell command and capture stdout AND stderr separately, with
    timeout.  Returns (exit_code, stdout_string, stderr_string).

    stderr is captured (not discarded) so callers can distinguish a compiler
    CRASH (OCaml backtrace, "Fatal error: exception", segfault) from a clean
    "unsupported feature" exit — see [classify_compile] below.

    The subprocess is bounded via [bounded_command] (timeout/gtimeout/perl —
    whichever is available), which preserves the shell conventions the
    classifiers rely on: 124 == timed-out, 128+N == killed by signal N. *)
let run_capture3 ?(timeout=15) cmd =
  let tmp     = Filename.temp_file "march_prop_out" ".txt" in
  let tmp_err = Filename.temp_file "march_prop_err" ".txt" in
  let rc  = Sys.command (Printf.sprintf
      "%s > %s 2> %s"
      (bounded_command ~timeout ~quoted_cmd:(Filename.quote cmd)) tmp tmp_err) in
  let read_file path =
    try
      let ic = open_in path in
      let s  = In_channel.input_all ic in
      close_in ic; s
    with _ -> ""
  in
  let out = read_file tmp in
  let err = read_file tmp_err in
  (try Sys.remove tmp with _ -> ());
  (try Sys.remove tmp_err with _ -> ());
  (rc, out, err)

(** Thin wrapper preserving the original (exit_code, stdout) interface for
    callers that don't need stderr. *)
let run_capture ?(timeout=15) cmd =
  let (rc, out, _err) = run_capture3 ~timeout cmd in
  (rc, out)

(** Write [src] to `prog.march` inside a fresh, dedicated temp DIRECTORY and
    return that file's path.

    Why a dedicated dir and not `Filename.temp_file` directly in `TMPDIR`:
    the march compiler auto-discovers *sibling* `.march` files in the entry
    file's own source directory (bin/main.ml — `Filename.dirname filename` is
    added to the module search path).  If the entry lives directly in a shared
    `TMPDIR`, that sibling walk enumerates everything in `TMPDIR` — and on
    macOS `TMPDIR` (`/var/folders/.../T/`) contains a Spotlight-managed
    `TemporaryItems` directory that is permission-denied, so `Sys.readdir`
    inside the compiler's walk throws
    `Sys_error("…/TemporaryItems: Operation not permitted")` and the compiler
    exits 2 on EVERY program — a spurious "compiler crash" that has nothing to
    do with the generated program.  Isolating each generated program in its
    own directory (containing only `prog.march`) means the sibling walk sees
    exactly one file and never touches the poisoned directory. *)
let write_temp_march src =
  let dir = Filename.temp_file "march_prop_dir" "" in
  (* temp_file made a regular file; replace it with a directory of the same
     name so we get a collision-free unique directory. *)
  (try Sys.remove dir with _ -> ());
  Sys.mkdir dir 0o700;
  let path = Filename.concat dir "prog.march" in
  let oc  = open_out path in
  output_string oc src;
  close_out oc;
  path

(** Remove the dedicated temp directory that [write_temp_march] created for a
    program, given the `prog.march` path (or its `.bin` sibling).  Removes the
    whole containing directory and its contents so nothing leaks. *)
let cleanup_temp_march src_file =
  let dir = Filename.dirname src_file in
  (* Only rm dirs we created (name guard), never a shared TMPDIR root. *)
  if
    let base = Filename.basename dir in
    String.length base >= 14 && String.sub base 0 14 = "march_prop_dir"
  then begin
    Array.iter
      (fun e -> try Sys.remove (Filename.concat dir e) with _ -> ())
      (try Sys.readdir dir with _ -> [||]);
    (try Sys.rmdir dir with _ -> ())
  end

(* ── Loud skip accounting (Wave-2 doctrine: no invisible skips) ─────────── *)

(** Every [oracle_check] outcome that is neither a match nor a failure must be
    routed through [record_skip] with a short reason tag.  A per-run summary
    is printed at process exit so a skip can never silently vanish — if the
    oracle's green run is actually "everything got skipped," this makes that
    visible instead of indistinguishable from "everything passed." *)
let oracle_invocations = ref 0
let oracle_matched     = ref 0
let skip_counts : (string, int) Hashtbl.t = Hashtbl.create 16

let record_skip reason =
  let n = try Hashtbl.find skip_counts reason with Not_found -> 0 in
  Hashtbl.replace skip_counts reason (n + 1)

let record_match () =
  incr oracle_matched

let () =
  at_exit (fun () ->
    if !oracle_invocations > 0 then begin
      Printf.eprintf "\n── oracle skip summary ──────────────────────────────\n";
      Printf.eprintf "  total invocations : %d\n" !oracle_invocations;
      Printf.eprintf "  matched (Ok/Fail) : %d\n" !oracle_matched;
      let skipped = Hashtbl.fold (fun _ n acc -> acc + n) skip_counts 0 in
      Printf.eprintf "  skipped           : %d\n" skipped;
      Hashtbl.iter (fun reason n -> Printf.eprintf "    - %-28s %d\n" reason n) skip_counts;
      Printf.eprintf "──────────────────────────────────────────────────────\n%!"
    end)

(* ── Compile-outcome classifier (pure, unit-testable) ────────────────────── *)

(** Markers that indicate the compiler itself crashed (an OCaml exception
    escaped to top level, printing a backtrace) rather than gracefully
    reporting "this program is not supported yet." *)
let internal_error_markers = [
  "Fatal error: exception";
  "Assert_failure";
  "Failure(";
  "Called from";
]

let contains_substring ~needle haystack =
  let nlen = String.length needle in
  let hlen = String.length haystack in
  if nlen = 0 then true
  else
    let rec go i =
      if i + nlen > hlen then false
      else if String.sub haystack i nlen = needle then true
      else go (i + 1)
    in
    go 0

(** Exit code the compiler itself now uses (bin/main.ml,
    [internal_compiler_error_exit_code]) when an OCaml exception escapes the
    compile pipeline (Lower -> Mono -> Perceus -> Opt -> Llvm_emit) uncaught.
    Oracle Task 2's survey of every failwith/assert-false site in lib/tir
    found none of them are a deliberate "typechecked but not lowerable yet"
    marker — all ~33 are internal-invariant checks — so there is no separate
    "unsupported construct" signal to distinguish from this one; exit 3
    always means "compiler bug", full stop. This is now the authoritative,
    positive signal (no stderr text-sniffing needed); the [internal_error_markers]
    heuristic below stays as a fallback for older binaries / paths that don't
    (yet) go through the wrapped pipeline (e.g. a differently-built `march`
    on PATH during a bisect). *)
let internal_compiler_error_exit_code = 3

(** Classify a compiler-step outcome given its exit code and captured stderr.

    - [rc = internal_compiler_error_exit_code]: the compiler's own top-level
      handler caught an escaped exception and reported it as an internal
      error — always [`Fail], no heuristics needed (Oracle Task 2).
    - [rc >= 128]: the compiler was killed by a signal (segfault, abort, …)
      while compiling a well-typed program — always a compiler bug: [`Fail].
    - stderr carries an OCaml internal-error marker (an uncaught exception's
      backtrace, an [Assert_failure], a [Failure(...)], or a "Called from"
      backtrace line) — the compiler's own machinery crashed even though it
      exited "cleanly" (rc in 1..127): [`Fail]. Kept as a fallback for
      binaries built before the exit-3 signal existed.
    - otherwise, a clean nonzero exit with no crash signature is treated as a
      graceful "this construct isn't supported yet": [`Skip].

    [rc = 0] is not a valid input (callers only classify nonzero compiles);
    it is treated as [`Skip "unreachable-rc-zero"] rather than raising, so the
    function stays total. *)
let classify_compile (rc : int) (stderr : string) : [ `Fail of string | `Skip of string ] =
  if rc = 0 then
    `Skip "unreachable-rc-zero"
  else if rc = internal_compiler_error_exit_code then
    `Fail (Printf.sprintf "internal compiler error (exit %d)" rc)
  else if rc >= 128 then
    `Fail (Printf.sprintf "compiler killed by signal %d (exit %d)" (rc - 128) rc)
  else
    match List.find_opt (fun m -> contains_substring ~needle:m stderr) internal_error_markers with
    | Some marker -> `Fail (Printf.sprintf "internal compiler error (stderr marker %S)" marker)
    | None        -> `Skip "unsupported"

(** Run the oracle: compile a March source string and check that
    interpreter output == compiled output.
    Returns Ok () on match, Error msg on mismatch, or None to skip.
    Every [None] result has already been counted via [record_skip]; every
    [Some _] result has been counted via [record_match].

    [tir_opt] controls the March/TIR optimizer passes (the [--no-opt] flag,
    [opt_enabled] in bin/main.ml), which is ORTHOGONAL to [opt] (the clang
    codegen level, [--opt N]).  [tir_opt = true] (default) keeps the passes on
    (historical behavior); [tir_opt = false] adds [--no-opt] so a TIR-level
    optimizer miscompile (the sort_by/cprop class) can be attributed — it
    agrees with the interpreter at [--no-opt] but diverges once the passes run.
    Wave A's [--no-opt --compile] link fix is what lets this axis finally run. *)
let oracle_check ?(opt = None) ?(tir_opt = true) src =
  incr oracle_invocations;
  match Lazy.force march_bin_opt with
  | None ->
    record_skip "no-march-binary";
    None
  | Some bin ->
    let src_file = write_temp_march src in
    let bin_file = src_file ^ ".bin" in
    (* Interpreter mode — the reference oracle. *)
    let interp_cmd = Printf.sprintf "%s %s" (Filename.quote bin) (Filename.quote src_file) in
    let (rc_interp, interp_out) = run_capture ~timeout:10 interp_cmd in
    if rc_interp >= 128 then (
      (* The interpreter itself was killed by a signal.  The interpreter IS the
         oracle; a segfaulting interpreter gives us no ground truth to compare
         against — skip (counted, with a distinct reason so it stays visible in
         the summary and can't masquerade as a match). *)
      cleanup_temp_march src_file;
      record_skip "interp-signal-death";
      None
    ) else begin
      (* Compile mode — stderr captured so we can tell a compiler CRASH
         (segfault, uncaught OCaml exception) from a clean "unsupported
         feature" exit; see [classify_compile].  [opt = None] keeps the
         historical default flags (clang -O2, TIR passes on); [Some n]
         additionally passes [--opt n] (clang -On) so the Phase-3 opt-matrix
         property can diff each optimization level against the interpreter. *)
      let opt_flag = match opt with None -> "" | Some n -> Printf.sprintf " --opt %d" n in
      let tir_flag = if tir_opt then "" else " --no-opt" in
      let compile_cmd =
        Printf.sprintf "%s --compile%s%s %s -o %s"
          (Filename.quote bin) opt_flag tir_flag (Filename.quote src_file) (Filename.quote bin_file)
      in
      let (rc_compile, _compile_out, compile_err) = run_capture3 ~timeout:30 compile_cmd in
      if rc_compile <> 0 then (
        cleanup_temp_march src_file;
        match classify_compile rc_compile compile_err with
        | `Fail reason ->
          record_match ();
          Some (Error (interp_out,
                       Printf.sprintf "<compiler crashed: %s>\nstderr: %s" reason compile_err))
        | `Skip reason ->
          record_skip ("compile-" ^ reason);
          None
      ) else begin
        let (rc_run, compiled_out) = run_capture ~timeout:10 (Filename.quote bin_file) in
        cleanup_temp_march src_file;
        if rc_run >= 128 then begin
          (* Signal-killed binary (sh reports 128+signal: SIGABRT=134,
             SIGSEGV=139, SIGBUS=138…).  The interpreter did NOT signal-die
             (checked above), so whether it exited 0 or clean-nonzero, a
             compiled *signal* death is a divergence — a compiler bug (usually
             an RC miscompile), a FAILURE.  This subsumes the Phase-3
             exit-code-parity case: an interpreter clean-nonzero exit (a clean
             panic) vs a compiled signal-death (segfault/abort) on the same
             program is now a FAILURE rather than a mutual skip. *)
          record_match ();
          Some (Error (
            Printf.sprintf "%s<interpreter exit %d>" interp_out rc_interp,
            Printf.sprintf "<binary killed by signal %d (exit %d)> %s"
              (rc_run - 128) rc_run compiled_out))
        end
        else if rc_interp = 0 && rc_run = 0 then begin
          (* Both sides ran cleanly to completion — the normal output check. *)
          record_match ();
          if interp_out = compiled_out then Some (Ok ())
          else Some (Error (interp_out, compiled_out))
        end
        else if rc_interp = 0 then begin
          (* Interpreter succeeded, compiled exited clean-nonzero (rc in
             1..127).  SKIP (unchanged): the run may have hit a resource/time
             limit (`timeout` reports 124) or a legitimate runtime error the
             interpreter reaches differently — comparing here risks spurious
             diffs. *)
          record_skip "run-nonzero-exit";
          None
        end
        else if rc_run = 0 then begin
          (* Interpreter errored cleanly, compiled succeeded.  A divergence in
             principle, but flagging it risks false positives (the interpreter
             enforces some runtime checks the compiled runtime does not).  Skip
             conservatively, with a distinct reason so the quadrant stays
             visible for later inspection. *)
          record_skip "interp-nonzero-compiled-zero";
          None
        end
        else begin
          (* Both exited clean-nonzero.  Different clean exit codes for the same
             logical runtime error are legitimate across the two backends, so
             (per the Phase-3 scope decision) do NOT require exact-code parity —
             only the clean-vs-signal asymmetry above is a failure.  Skip. *)
          record_skip "both-clean-nonzero";
          None
        end
      end
    end


(* ── End-to-end properties (source string generators) ─────────────────── *)

(** 1. Parse + desugar should never raise unexpected exceptions on any of
       our well-typed source programs (parse errors are ok, panics are not). *)
let prop_parse_no_unexpected_exception =
  Test.make ~name:"parse: no unexpected exceptions on generated programs"
    ~count:500 ~print:(fun s -> s)
    gen_well_typed_module
    (fun src ->
       match parse_src src with
       | _  -> true
       | exception March_parser.Parser.Error -> true
       | exception _ -> false)

(** 2. Typecheck should never raise an exception (only record diagnostics). *)
let prop_typecheck_no_crash =
  Test.make ~name:"typecheck: no crash on generated well-formed programs"
    ~count:500
    gen_well_typed_module
    (fun src ->
       try
         ignore (pipeline_up_to_typecheck src);
         true
       with _ -> false)

(** Returns true if ctx has errors OTHER than tail-call enforcement errors.
    Tail-call enforcement rejects non-tail-recursive code; the generator does
    not produce TCE-compliant programs, so those errors are expected/acceptable. *)
let has_non_tce_errors ctx =
  let is_tce_err (d : Errors.diagnostic) =
    d.Errors.severity = Errors.Error &&
    let msg = d.Errors.message in
    let len = String.length msg in
    let needle = "not in tail position" in
    let nlen = String.length needle in
    let rec check i =
      if i + nlen > len then false
      else if String.sub msg i nlen = needle then true
      else check (i + 1)
    in
    check 0
  in
  List.exists
    (fun d -> d.Errors.severity = Errors.Error && not (is_tce_err d))
    ctx.Errors.diagnostics

(** 3. Well-typed programs should typecheck without errors (modulo tail-call
    enforcement, which the generator does not account for). *)
let prop_generated_programs_are_well_typed =
  Test.make ~name:"generated programs: no type errors"
    ~count:500
    ~print:Fun.id
    gen_well_typed_module
    (fun src ->
       match pipeline_up_to_typecheck src with
       | None -> true  (* parse error counts as skip *)
       | Some (_, errors, _) -> not (has_non_tce_errors errors))

(** 4. Well-typed programs should not crash the interpreter. *)
let prop_type_sound_eval_no_crash =
  Test.make ~name:"type soundness: well-typed → eval does not crash"
    ~count:500
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (* [gen_well_typed_module] includes stdlib-using programs (e.g.
              println of a list), which — now that they typecheck via the
              stdlib seed env — reach eval; eval them WITH stdlib so a
              prelude/stdlib call resolves as it does under `march file.march`
              (bare eval would raise "unbound" and spuriously fail this
              no-crash property). *)
           ignore (eval_main ~with_stdlib:true m);
           true
       with _ -> false)

(** 5. Well-typed programs should survive the lowering pass. *)
let prop_lower_no_crash =
  Test.make ~name:"lowering: no crash on well-typed programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           ignore (March_tir.Lower.lower_module ~type_map m);
           true
       with _ -> false)

(** 6. Monomorphization should not crash on lowered programs. *)
let prop_mono_no_crash =
  Test.make ~name:"mono: no crash on lowered programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir = March_tir.Lower.lower_module ~type_map m in
           ignore (March_tir.Mono.monomorphize tir);
           true
       with _ -> false)

(** 7. Defunctionalization should not crash on monomorphized programs. *)
let prop_defun_no_crash =
  Test.make ~name:"defun: no crash on mono programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir  = March_tir.Lower.lower_module ~type_map m in
           let mono = March_tir.Mono.monomorphize tir in
           ignore (March_tir.Defun.defunctionalize mono);
           true
       with _ -> false)

(** 8. Perceus RC insertion should not crash on the full TIR pipeline. *)
let prop_perceus_no_crash =
  Test.make ~name:"perceus: no crash on defun programs"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir    = March_tir.Lower.lower_module ~type_map m in
           let mono   = March_tir.Mono.monomorphize tir in
           let defun  = March_tir.Defun.defunctionalize mono in
           ignore (March_tir.Perceus.perceus defun);
           true
       with _ -> false)

(* ── Algebraic oracle properties ─────────────────────────────────────────
   The interpreter is the reference oracle.  These properties check that
   the evaluator respects basic arithmetic laws.  If any fail, there's a
   bug in the interpreter semantics. *)

(** Helper: evaluate a program of the form "mod Main do fn main() do <e> end end"
    and return the integer result, or None on any failure. *)
let eval_int_src body =
  try
    match pipeline_up_to_typecheck (wrap_main body) with
    | None -> None
    | Some (_, errors, _) when Errors.has_errors errors -> None
    | Some (m, _, _) ->
      (match eval_main m with
       | Some v -> value_to_int v
       | None   -> None)
  with _ -> None

(** 9. Addition is commutative: eval(a + b) = eval(b + a). *)
let prop_add_commutative =
  Test.make ~name:"oracle: addition is commutative"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (a, b) ->
       let lhs = eval_int_src (Printf.sprintf "(%d + %d)" a b) in
       let rhs = eval_int_src (Printf.sprintf "(%d + %d)" b a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true (* skip if eval failed *))

(** 10. Adding zero is identity: eval(a + 0) = eval(a). *)
let prop_add_zero_identity =
  Test.make ~name:"oracle: a + 0 = a"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       let lhs = eval_int_src (Printf.sprintf "(%d + 0)" a) in
       let rhs = eval_int_src (string_of_int a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true)

(** 11. Multiplying by one is identity: eval(a * 1) = eval(a). *)
let prop_mul_one_identity =
  Test.make ~name:"oracle: a * 1 = a"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       let lhs = eval_int_src (Printf.sprintf "(%d * 1)" a) in
       let rhs = eval_int_src (string_of_int a) in
       match lhs, rhs with
       | Some l, Some r -> l = r
       | _ -> true)

(** 12. Subtraction of self is zero: eval(a - a) = 0. *)
let prop_sub_self_zero =
  Test.make ~name:"oracle: a - a = 0"
    ~count:300
    (Gen.int_range (-100) 100)
    (fun a ->
       match eval_int_src (Printf.sprintf "(%d - %d)" a a) with
       | Some n -> n = 0
       | None   -> true)

(** 13. If expression: when condition is false, the else branch is taken. *)
let prop_if_false_branch =
  Test.make ~name:"oracle: if false do t else f end = f"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (t, f) ->
       let body = Printf.sprintf "if (1 == 2) do %d else %d end" t f in
       match eval_int_src body with
       | Some n -> n = f
       | None   -> true)

(** 14. If expression: when condition is true, the first branch is taken. *)
let prop_if_true_branch =
  Test.make ~name:"oracle: if true do t else f end = t"
    ~count:300
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (t, f) ->
       let body = Printf.sprintf "if (1 == 1) do %d else %d end" t f in
       match eval_int_src body with
       | Some n -> n = t
       | None   -> true)

(* ── ADT semantic properties ─────────────────────────────────────────────── *)

(** 15. Pattern match on a two-constructor ADT is exhaustive and correct. *)
let prop_adt_match_correct =
  Test.make ~name:"oracle: ADT match selects correct branch"
    ~count:300
    Gen.(pair bool (int_range 1 100))
    (fun (use_a, n) ->
       let src = Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type Tag = TagA | TagB(Int)\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let t = %s\n\
         \    match t do\n\
         \    | TagA    -> 0\n\
         \    | TagB(x) -> x\n\
         \    end\n\
         \  end\n\
          end"
         (if use_a then "TagA" else Printf.sprintf "TagB(%d)" n)
       in
       match eval_int_src (String.concat "\n"
           (* We need to embed the full module, not just body *)
           []) with
       | _ ->
         (* Re-implement without eval_int_src which wraps with its own mod *)
         try
           match pipeline_up_to_typecheck src with
           | None -> true
           | Some (_, errors, _) when Errors.has_errors errors -> true
           | Some (m, _, _) ->
             (match eval_main m with
              | Some v ->
                let expected = if use_a then 0 else n in
                (match value_to_int v with
                 | Some result -> result = expected
                 | None -> true)
              | None -> true)
         with _ -> true)

(** 16. Tuple swap is involutory: swap(swap(t)) = t. *)
let prop_tuple_swap_involution =
  Test.make ~name:"oracle: tuple swap is involutory"
    ~count:200
    Gen.(pair (int_range (-100) 100) (int_range (-100) 100))
    (fun (a, b) ->
       let src = Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn swap(t : (Int, Int)) : (Int, Int) do\n\
         \    let (x, y) = t\n\
         \    let result = (y, x)\n\
         \    result\n\
         \  end\n\
         \  fn fst_eq(t1 : (Int, Int), a : Int) : Bool do\n\
         \    let (x, _) = t1\n\
         \    x == a\n\
         \  end\n\
         \  fn snd_eq(t1 : (Int, Int), b : Int) : Bool do\n\
         \    let (_, y) = t1\n\
         \    y == b\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let t = (%d, %d)\n\
         \    let swapped_twice = swap(swap(t))\n\
         \    if fst_eq(swapped_twice, %d) do\n\
         \      if snd_eq(swapped_twice, %d) do 1 else 0 end\n\
         \    else 0 end\n\
         \  end\n\
          end"
         a b a b
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some 1 -> true | Some _ -> false | None -> true)
            | None -> true)
       with _ -> true)

(** 17. Closure captures correct value even after base variable is shadowed. *)
let prop_closure_captures_correct_value =
  Test.make ~name:"oracle: closure captures value at creation time"
    ~count:200
    Gen.(pair (int_range (-50) 50) (int_range (-50) 50))
    (fun (base, arg) ->
       let expected = base + arg in
       let src = Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  fn make_adder(base : Int) : Int -> Int do\n\
         \    fn x -> x + base\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    let f = make_adder(%d)\n\
         \    f(%d)\n\
         \  end\n\
          end"
         base arg
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some r -> r = expected | None -> true)
            | None -> true)
       with _ -> true)

(** 18. List sum: sum of [a, b, c] = a + b + c. *)
let prop_list_sum_correct =
  Test.make ~name:"oracle: inline list sum is correct"
    ~count:200
    Gen.(triple (int_range (-50) 50) (int_range (-50) 50) (int_range (-50) 50))
    (fun (a, b, c) ->
       let expected = a + b + c in
       let src = Printf.sprintf
         "mod Main do\n\
         \  needs IO.Console\n\
         \  type IntList = Nil | Cons(Int, IntList)\n\
         \  fn sum(lst : IntList) : Int do\n\
         \    match lst do\n\
         \    | Nil        -> 0\n\
         \    | Cons(h, t) -> h + sum(t)\n\
         \    end\n\
         \  end\n\
         \  fn main(_cap_console : Cap(IO.Console)) do\n\
         \    sum(Cons(%d, Cons(%d, Cons(%d, Nil))))\n\
         \  end\n\
          end"
         a b c
       in
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, _) ->
           (match eval_main m with
            | Some v -> (match value_to_int v with Some r -> r = expected | None -> true)
            | None -> true)
       with _ -> true)

(* ── TIR-level properties (AST generators) ─────────────────────────────── *)

(** 19. Perceus should not crash on any generated TIR module. *)
let prop_perceus_tir_no_crash =
  Test.make ~name:"perceus (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Perceus.perceus m); true
       with _ -> false)

(** 20. Monomorphize should not crash on generated TIR modules. *)
let prop_mono_tir_no_crash =
  Test.make ~name:"mono (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Mono.monomorphize m); true
       with _ -> false)

(** 21. Defunctionalize should not crash on generated TIR modules. *)
let prop_defun_tir_no_crash =
  Test.make ~name:"defun (TIR gen): no crash on generated TIR modules"
    ~count:500
    gen_tir_module
    (fun m ->
       try ignore (March_tir.Defun.defunctionalize m); true
       with _ -> false)

(** 22. Perceus output has no more functions than input (no fn duplication). *)
let prop_perceus_preserves_fn_count =
  Test.make ~name:"perceus: does not duplicate function definitions"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Perceus.perceus m in
         List.length out.Tir.tm_fns = List.length m.Tir.tm_fns
       with _ -> true (* crash covered by prop_perceus_tir_no_crash *))

(** 23. Mono output preserves the set of function names that are entry points. *)
let prop_mono_preserves_main_fn =
  Test.make ~name:"mono: main function is still present after monomorphization"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Mono.monomorphize m in
         (* mono may specialize or copy fns; main should survive *)
         List.exists (fun (fn : Tir.fn_def) -> fn.fn_name = "main") out.Tir.tm_fns
       with _ -> true)

(** 24. Defun output preserves the total number of definitions (may add
        closure-dispatch helpers, so output count >= input count). *)
let prop_defun_no_fn_loss =
  Test.make ~name:"defun: does not lose function definitions"
    ~count:500
    gen_tir_module
    (fun m ->
       try
         let out = March_tir.Defun.defunctionalize m in
         List.length out.Tir.tm_fns >= List.length m.Tir.tm_fns
       with _ -> true)

(* ── New TIR pass structural invariant properties ──────────────────────── *)

(** 25. After monomorphization, no TVar should remain in type annotations
        of the specialised functions (all polymorphism is resolved). *)
let prop_mono_eliminates_tvars =
  Test.make ~name:"mono: eliminates all TVar type variables"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir  = March_tir.Lower.lower_module ~type_map m in
           let mono = March_tir.Mono.monomorphize tir in
           let tys  = collect_types_module mono in
           (* Allow TVar "_" which is the placeholder for unknown/opaque types *)
           not (List.exists (function Tir.TVar s -> s <> "_" | _ -> false) tys)
       with _ -> true)

(** 26. After defunctionalization, no ELetRec remains in any function body
        (all lambdas have been lifted to top-level closure structs). *)
let prop_defun_eliminates_letrec =
  Test.make ~name:"defun: eliminates all ELetRec in function bodies"
    ~count:300
    gen_well_typed_module
    (fun src ->
       try
         match pipeline_up_to_typecheck src with
         | None -> true
         | Some (_, errors, _) when Errors.has_errors errors -> true
         | Some (m, _, type_map) ->
           let tir   = March_tir.Lower.lower_module ~type_map m in
           let mono  = March_tir.Mono.monomorphize tir in
           let defun = March_tir.Defun.defunctionalize mono in
           not (List.exists (fun fn -> has_letrec fn.Tir.fn_body) defun.Tir.tm_fns)
       with _ -> true)

(** 27. Defun on TIR-generated closures eliminates ELetRec. *)
let prop_defun_tir_eliminates_letrec =
  Test.make ~name:"defun (TIR gen): eliminates ELetRec for closure modules"
    ~count:300
    gen_tir_closure_module
    (fun m ->
       try
         let out = March_tir.Defun.defunctionalize m in
         not (List.exists (fun fn -> has_letrec fn.Tir.fn_body) out.Tir.tm_fns)
       with _ -> true)

(** 28. Perceus idempotency: running Perceus twice produces the same
        function count as running it once (no spurious RC duplication). *)
let prop_perceus_idempotent_fn_count =
  Test.make ~name:"perceus: idempotent (fn count unchanged on second pass)"
    ~count:300
    gen_tir_module
    (fun m ->
       try
         let once  = March_tir.Perceus.perceus m in
         let twice = March_tir.Perceus.perceus once in
         List.length twice.Tir.tm_fns = List.length once.Tir.tm_fns
       with _ -> true)

(** 29. Mono idempotency: running mono twice does not reduce fn count
        (specialization is monotone — it only adds, never removes). *)
let prop_mono_idempotent_fn_count =
  Test.make ~name:"mono: idempotent (fn count non-decreasing on second pass)"
    ~count:300
    gen_tir_module
    (fun m ->
       try
         let once  = March_tir.Mono.monomorphize m in
         let twice = March_tir.Mono.monomorphize once in
         List.length twice.Tir.tm_fns >= List.length once.Tir.tm_fns
       with _ -> true)

(** 30. Defun + Perceus pipeline does not crash on TIR closure modules. *)
let prop_defun_perceus_closure_no_crash =
  Test.make ~name:"defun+perceus (closure TIR gen): pipeline does not crash"
    ~count:300
    gen_tir_closure_module
    (fun m ->
       try
         let defun   = March_tir.Defun.defunctionalize m in
         let _perceus = March_tir.Perceus.perceus defun in
         true
       with _ -> false)

(* ── Oracle property: generated programs match interpreter and compiler ── *)

(** 31. Full pipeline oracle: arith programs with println-wrapped output. *)
let prop_oracle_println_arith =
  Test.make ~name:"oracle (gen): println(arith) — interp = compiled"
    ~count:100
    (Gen.map2
       (fun e1 e2 ->
          Printf.sprintf
            "mod Main do\n\
            \  needs IO.Console\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    println(to_string(%s))\n\
            \    println(to_string(%s))\n\
            \  end\n\
             end" e1 e2)
       gen_arith_expr
       gen_arith_expr)
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         (* Log the mismatch for debugging *)
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 34. Oracle for closure programs with println output. *)
let prop_oracle_println_closure =
  Test.make ~name:"oracle (gen): println(closure) — interp = compiled"
    ~count:50
    (Gen.map3
       (fun base offset arg ->
          Printf.sprintf
            "mod Main do\n\
            \  needs IO.Console\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    let base = %d\n\
            \    let adder = fn x -> x + base + %d\n\
            \    println(to_string(adder(%d)))\n\
            \  end\n\
             end"
            base offset arg)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 35. Oracle for ADT programs with println output. *)
let prop_oracle_println_adt =
  Test.make ~name:"oracle (gen): println(ADT match) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun use_circle n ->
          let ctor = if use_circle then Printf.sprintf "Circle(%d)" (abs n mod 20 + 1)
                                   else Printf.sprintf "Square(%d)" (abs n mod 20 + 1) in
          Printf.sprintf
            (* NOTE: match arms are newline-separated with NO leading `|` —
               March removed the pipe-separated match form.  A leading `|`
               here made EVERY generated program parse-fail, so this oracle
               prop silently skipped 100%% of the time (surfaced by the
               loud skip accounting as `interp-nonzero-exit`).  Fixed so the
               ADT oracle actually exercises programs. *)
            "mod Main do\n\
            \  needs IO.Console\n\
            \  type Shape = Circle(Int) | Square(Int)\n\
            \  fn area(s : Shape) : Int do\n\
            \    match s do\n\
            \      Circle(r) -> r * r\n\
            \      Square(n) -> n * 4\n\
            \    end\n\
            \  end\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    println(to_string(area(%s)))\n\
            \  end\n\
             end"
            ctor)
       Gen.bool
       (Gen.int_range 1 100))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 36. Oracle for HOF programs with println output. *)
let prop_oracle_println_hof =
  Test.make ~name:"oracle (gen): println(HOF apply) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun factor arg ->
          Printf.sprintf
            "mod Main do\n\
            \  needs IO.Console\n\
            \  fn apply(f : Int -> Int, x : Int) : Int do\n\
            \    f(x)\n\
            \  end\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    println(to_string(apply(fn n -> n * %d, %d)))\n\
            \  end\n\
             end"
            (abs factor mod 20 + 1) arg)
       (Gen.int_range 1 20)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 37. Oracle for tuple programs with println output. *)
let prop_oracle_println_tuple =
  Test.make ~name:"oracle (gen): println(tuple) — interp = compiled"
    ~count:50
    (Gen.map2
       (fun a b ->
          Printf.sprintf
            "mod Main do\n\
            \  needs IO.Console\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    let t = (%d, %d)\n\
            \    let (x, y) = t\n\
            \    println(to_string(x + y))\n\
            \  end\n\
             end"
            a b)
       (Gen.int_range (-100) 100)
       (Gen.int_range (-100) 100))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** 38. Oracle for list programs with println output. *)
let prop_oracle_println_list =
  Test.make ~name:"oracle (gen): println(list sum) — interp = compiled"
    ~count:50
    (Gen.map3
       (fun a b c ->
          Printf.sprintf
            (* NOTE: newline-separated match arms, NO leading `|` — see the
               ADT oracle above.  The old leading-`|` form parse-failed on
               every program, making this list oracle prop 100%% vacuous. *)
            "mod Main do\n\
            \  needs IO.Console\n\
            \  type IntList = Nil | Cons(Int, IntList)\n\
            \  fn sum(lst : IntList) : Int do\n\
            \    match lst do\n\
            \      Nil        -> 0\n\
            \      Cons(h, t) -> h + sum(t)\n\
            \    end\n\
            \  end\n\
            \  fn main(_cap_console : Cap(IO.Console)) do\n\
            \    println(to_string(sum(Cons(%d, Cons(%d, Cons(%d, Nil))))))\n\
            \  end\n\
             end"
            a b c)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50)
       (Gen.int_range (-50) 50))
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(* ── Oracle properties: generic-container println/show (ffe6fba8 class) ───
   These five props run the ACTUAL interpreter-vs-compiled diff (via
   [oracle_check]) on the five generic-container generators defined above.
   The generators are ALSO unioned into [gen_well_typed_module] (crash /
   structural coverage), but that pool only feeds the no-crash + TIR-pass
   invariant properties — none of those call [oracle_check], so without
   these dedicated props the diff coverage that is the whole point of the
   ffe6fba8 regression guard would never run in the committed suite.  Each
   mirrors [prop_oracle_println_arith] exactly: Ok -> pass, Error -> fail
   with the interp/compiled diff logged, None -> handled skip. *)

(** Oracle: println(List(Int)) — interp = compiled (ffe6fba8 regression). *)
let prop_oracle_container_int_list =
  Test.make ~name:"oracle (gen): println(List(Int)) — interp = compiled"
    ~count:50
    gen_println_int_list_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle: println(List(String)) — interp = compiled (ffe6fba8 regression). *)
let prop_oracle_container_string_list =
  Test.make ~name:"oracle (gen): println(List(String)) — interp = compiled"
    ~count:50
    gen_println_string_list_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle: println(Option(Int)) — interp = compiled (ffe6fba8 regression). *)
let prop_oracle_container_option =
  Test.make ~name:"oracle (gen): println(Option(Int)) — interp = compiled"
    ~count:50
    gen_println_option_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle: println(List(List(Int))) — interp = compiled (ffe6fba8 regression). *)
let prop_oracle_container_nested_list =
  Test.make ~name:"oracle (gen): println(List(List(Int))) — interp = compiled"
    ~count:50
    gen_println_nested_list_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle: println(List(Option(Int))) — interp = compiled (ffe6fba8 regression). *)
let prop_oracle_container_list_of_options =
  Test.make ~name:"oracle (gen): println(List(Option(Int))) — interp = compiled"
    ~count:50
    gen_println_list_of_options_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(* ── Oracle properties: derived-method calls (Newtype-derive fix class,
   6cc676fc) ────────────────────────────────────────────────────────────
   These five props run the ACTUAL interpreter-vs-compiled diff (via
   [oracle_check]) on the five derived-method generators defined above.
   As with the container props, the generators are ALSO unioned into
   [gen_well_typed_module] for crash/structural coverage, but only these
   dedicated props exercise the diff itself — that's the whole point of
   this regression guard, since the fixed bug was a compiled-only crash
   that a no-crash-only property would never have caught before the fix
   (and wouldn't catch a REGRESSION of the fix after it). *)

(** Oracle (a): derived eq/compare/hash named calls on a Newtype-repr
    (single-ctor single-field) Int-payload type — the exact shape 6cc676fc
    fixed (was SIGSEGV compiled). *)
let prop_oracle_derived_method_newtype_int =
  Test.make ~name:"oracle (gen): derived eq/compare on Newtype(Int) — interp = compiled"
    ~count:50
    gen_derived_method_newtype_int_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (b): derived eq/compare/== on a Newtype-repr String-payload type
    — 6cc676fc's non-exhaustive-panic variant for named methods AND the
    `==`-operator heap-payload wrong-answer bug, both now fixed (see the
    file-level comment above the generator). Exercises the `==` operator
    alongside named `eq()`/`compare()`. *)
let prop_oracle_derived_method_newtype_string =
  Test.make ~name:"oracle (gen): derived eq/compare on Newtype(String) — interp = compiled"
    ~count:50
    gen_derived_method_newtype_string_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (c): derived eq/compare/hash named calls on a Boxed (multi-field
    single-ctor) type — negative control, always worked, must stay green. *)
let prop_oracle_derived_method_boxed =
  Test.make ~name:"oracle (gen): derived eq/compare on Boxed ctor — interp = compiled"
    ~count:50
    gen_derived_method_boxed_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (d): derived eq/compare/hash named calls on a multi-ctor enum —
    negative control, always worked, must stay green. *)
let prop_oracle_derived_method_enum =
  Test.make ~name:"oracle (gen): derived eq/compare on multi-ctor enum — interp = compiled"
    ~count:50
    gen_derived_method_enum_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (e): derived eq/compare named calls on a record (field-by-field
    Ord, unlike variants) — negative control, always worked, must stay
    green. `hash` deliberately excluded (see the generator's doc comment:
    interp/compiled use genuinely different hash algorithms by design). *)
let prop_oracle_derived_method_record =
  Test.make ~name:"oracle (gen): derived eq/compare on record — interp = compiled"
    ~count:50
    gen_derived_method_record_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(* ── Oracle properties: record-update / dual-position-borrow / FBIP /
   erased-flow (Phase 2c, Task 5) ────────────────────────────────────────
   As with the container and derived-method oracle props above, these four
   run the ACTUAL interpreter-vs-compiled diff (via [oracle_check]) on the
   four generators defined above — the generators are ALSO unioned into
   [gen_well_typed_module] for crash/structural coverage, but only these
   dedicated props exercise the diff itself. All four guard bug classes
   that are FIXED (0d1a829e / a5dad194), so all four must stay green; a RED
   here is either a fix regression (report it) or a generator determinism
   bug (fix the generator), never an expected failure. *)

(** Oracle (a): record functional-update on a statically-known-shape record
    where the updated field exists. Guards `0d1a829e` (EUpdate family). *)
let prop_oracle_record_update =
  Test.make ~name:"oracle (gen): record update {base with f: v} — interp = compiled"
    ~count:50
    gen_record_update_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (b): dual-position owned+borrowed argument (`both(s, s, n)`, `s`
    dead afterwards). Guards `a5dad194`'s RC double-consumption fix (was
    exit 134 "RC underflow" compiled-only). *)
let prop_oracle_dual_position_borrow =
  Test.make ~name:"oracle (gen): dual-position owned+borrowed arg — interp = compiled"
    ~count:50
    gen_dual_position_borrow_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (c): FBIP same_arity — dead binding of a multi-type-param
    `Result(Int, String)` immediately before a same-arity allocation.
    Guards `a5dad194`'s arity-encoding fix (was a heap overflow past the
    reused cell, observed as the compiled binary taking the wrong match
    arm). *)
let prop_oracle_fbip_same_arity =
  Test.make ~name:"oracle (gen): FBIP same_arity on Result(a,b) — interp = compiled"
    ~count:50
    gen_fbip_same_arity_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Oracle (d): erased flow through a bare-TVar generic wrapper (`Box(a)`)
    and a generic `identity`, unwrapped and used concretely. Guards the
    general erased-representation flow class exercised by the newtype/niche
    repr and B5 record-update fixes above. *)
let prop_oracle_erased_flow =
  Test.make ~name:"oracle (gen): erased TVar wrapper flow — interp = compiled"
    ~count:50
    gen_erased_flow_module
    (fun src ->
       match oracle_check src with
       | None           -> true
       | Some (Ok ())   -> true
       | Some (Error (interp, compiled)) ->
         Printf.eprintf "MISMATCH:\n  interp:   %S\n  compiled: %S\n%!" interp compiled;
         false)

(** Phase 3 — opt matrix (clang levels + TIR-optimizer axis).  Every other
    [prop_oracle_*] property diffs the interpreter against a SINGLE compiled
    configuration (the [--compile] default = clang -O2, TIR passes on).  This
    one diffs the interpreter against the compiled binary across THREE
    configurations:

      - [--no-opt]  — TIR optimizer passes OFF, clang default level (Task 6.2);
      - [--opt 0]   — TIR passes ON, clang -O0;
      - [--opt 2]   — TIR passes ON, clang -O2.

    The two axes are ORTHOGONAL: [--opt N] is the clang codegen level, while
    the TIR/March optimizer passes (fusion, Opt/cprop, FBIP, …) are gated by
    the separate [--no-opt] flag ([opt_enabled] in bin/main.ml).  Running both
    axes lets a divergence be ATTRIBUTED rather than merely flagged:

      - a config that diverges while another AGREES at the same TIR setting but
        a different clang level → an LLVM-level (clang) optimizer miscompile;
      - the interpreter agreeing with [--no-opt] but diverging once the TIR
        passes run → a TIR-optimizer miscompile (the sort_by/cprop class),
        which the pre-existing default-O2 oracle could flag but never localize.

    Wave A's [--no-opt --compile] LINK fix is what finally lets the [--no-opt]
    axis run at all (it used to fail to link).

    REDUCED COUNT: each draw now runs THREE full compile+run cycles (~3.5s each),
    so this runs at count 20 (was 30 for two configs) to keep the suite within
    its wall-clock budget while still exercising all three configs across a
    spread of generated programs.  Reuses [gen_record_update_module] — a
    generator whose interpreter output is reliably exit-0 and deterministic (a
    single Int sum). *)
let prop_oracle_opt_matrix =
  Test.make
    ~name:"oracle (opt-matrix): interp = compiled at --opt 0, --opt 2, --no-opt"
    ~count:20 ~print:(fun s -> s)
    gen_record_update_module
    (fun src ->
       let check label oc =
         match oc with
         | None           -> `Skip   (* skip — already counted via record_skip *)
         | Some (Ok ())   -> `Ok
         | Some (Error (interp, compiled)) ->
           Printf.eprintf
             "OPT-MATRIX MISMATCH @ %s:\n  interp:   %S\n  compiled: %S\n%!"
             label interp compiled;
           `Diverge
       in
       (* The `--no-opt` (TIR-optimizer-off) axis (Task 6.2) is now ENABLED.
          It was historically disabled on a fear that a compiled binary's
          scheduler worker threads inherit the capture PIPE's write end and
          wedge `run_capture`'s read — but `run_capture`/`run_capture3` capture
          via a `Sys.command` temp-FILE redirect (read only after the bounded
          child is reaped), not a live pipe, so there is no writer-fd to strand.
          The `--opt 0`/`--opt 2` configs already run compiled binaries under
          the same scheduler through the same path without wedging; `--no-opt`
          uses the identical run harness. It buys a real attribution signal: a
          TIR-optimizer miscompile agrees with the interpreter at `--no-opt`
          (passes off) and diverges once the passes run, rather than only
          showing as a flat default-vs-interpreter mismatch. *)
       let r_o0    = check "--opt 0 (TIR passes on)"  (oracle_check ~opt:(Some 0) src) in
       let r_o2    = check "--opt 2 (TIR passes on)"  (oracle_check ~opt:(Some 2) src) in
       let r_noopt = check "--no-opt (TIR passes off)"
                       (oracle_check ~opt:None ~tir_opt:false src) in
       let ok = function `Ok | `Skip -> true | `Diverge -> false in
       ok r_o0 && ok r_o2 && ok r_noopt)

(* ── Converged: record-update on a missing field over an ERASED base
   (formerly an OPEN divergence; RESOLVED by Core March spec Task 3,
   specs/lang/core-march.md §4 ERecordUpdate rule) ─────────────────────────
   Per this plan's "constrain each generator to the currently-working
   subset" rule, [gen_record_update_module] above NEVER generates this
   shape — it only updates fields that exist on a statically-typed record.
   This is a standalone, non-QCheck unit test (using a direct interp-vs-
   compiled comparison on ONE fixed program, not a property) that used to
   pin an OPEN divergence: `{ record_from_list([...]) with z: 99 }` where
   `z` is absent from the base's actual shape. The interpreter's
   [ERecordUpdate] (eval.ml) used to silently fabricate the field
   (`Some(99)`, exit 0) while the compiled backend panicked via
   `march_record_update_dyn` ("no field \"z\" in record", clean exit 1).
   The Core March spec (Task 3) adjudicated the NORMATIVE rule as the
   compiled contract — a functional update of a field absent from the
   record's actual shape is a runtime error — and `eval.ml`'s
   [ERecordUpdate] arm was changed to match (fails loudly via
   [eval_error] instead of appending). Both backends now agree: this test
   confirms CONVERGENCE (both sides exit nonzero, neither is a signal
   death) rather than pinning a divergence. Kept as a standalone unit test
   (not folded into [gen_record_update_module]) because it specifically
   targets the ERASED-base shape the property generator still avoids. *)
let test_record_update_missing_field_on_erased_base_converged () =
  let src =
    "mod Main do\n\
    \  needs IO.Console\n\
    \  fn main(_cap_console : Cap(IO.Console)) do\n\
    \    let base = record_from_list([(\"a\", 1)])\n\
    \    let updated = { base with z: 99 }\n\
    \    println(to_string(record_get(updated, \"z\")))\n\
    \  end\n\
     end\n"
  in
  match Lazy.force march_bin_opt with
  | None ->
    Alcotest.skip ()  (* legitimate, counted skip: no march binary available *)
  | Some bin ->
    let src_file = write_temp_march src in
    let interp_cmd = Printf.sprintf "%s %s" (Filename.quote bin) (Filename.quote src_file) in
    (* [run_capture3], not [run_capture]: eval_error's message is written to
       STDERR, and [run_capture] discards stderr — using it here would leave
       [interp_err] empty and this test would silently stop checking the
       error text. *)
    let (rc_interp, _interp_out, interp_err) = run_capture3 ~timeout:10 interp_cmd in
    let bin_file = src_file ^ ".bin" in
    let compile_cmd =
      Printf.sprintf "%s --compile %s -o %s"
        (Filename.quote bin) (Filename.quote src_file) (Filename.quote bin_file)
    in
    let (rc_compile, _compile_out, _compile_err) = run_capture3 ~timeout:30 compile_cmd in
    if rc_compile <> 0 then begin
      cleanup_temp_march src_file;
      Alcotest.failf
        "expected the missing-field update to COMPILE (and panic at RUNTIME); \
         compile itself failed (rc=%d) — the converged shape may have \
         changed, revisit this test" rc_compile
    end else begin
      let (rc_run, _compiled_out, compiled_err) =
        run_capture3 ~timeout:10 (Filename.quote bin_file) in
      cleanup_temp_march src_file;
      (* Converged: BOTH backends now reject the missing-field update with a
         clean (non-signal) nonzero exit, and both error messages mention the
         missing field. *)
      Alcotest.(check bool) "interpreter exits nonzero (errors loudly), NOT a signal death"
        true (rc_interp <> 0 && rc_interp < 128);
      Alcotest.(check bool) "interpreter stderr mentions the missing field"
        true (contains_substring ~needle:"no field" interp_err);
      Alcotest.(check bool) "compiled binary exits nonzero (panics), NOT a signal death"
        true (rc_run <> 0 && rc_run < 128);
      Alcotest.(check bool) "compiled stderr mentions the record-update panic"
        true (contains_substring ~needle:"no field" compiled_err
              || contains_substring ~needle:"panic" compiled_err)
    end

(* ── Unit tests for classify_compile (RED proof for Task 1) ─────────────── *)

(** Before this change, [oracle_check]'s compile step collapsed ALL nonzero
    compile exits — segfault, uncaught OCaml exception, or genuine
    "unsupported feature" — into an identical, silent [None] (skip).  A
    compiler CRASH on a well-typed program was therefore indistinguishable
    from "the generator hit a construct we don't lower yet."

    These are synthetic (rc, stderr) tuples fed directly to the pure
    [classify_compile] classifier — no compiler invocation needed, so the
    proof is deterministic and instant.  Run against the OLD logic (bare
    [if rc_compile <> 0 then None]), all three cases below would have
    produced the SAME verdict: skip.  Against the NEW classifier:
      - a segfault-shaped rc           -> `Fail
      - a clean rc with backtrace text -> `Fail
      - a clean rc with no backtrace   -> `Skip
    i.e. two of the three flip from "invisible skip" to "loud failure." *)

let test_classify_compile_segfault () =
  (* rc = 139 = 128 + SIGSEGV. No stderr needed — signal death alone is
     conclusive: the compiler was killed compiling a well-typed program. *)
  match classify_compile 139 "" with
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for segfault rc=139, got `Skip %S" r

let test_classify_compile_backtrace () =
  (* rc = 2 (OCaml's default uncaught-exception exit code) with a genuine
     OCaml backtrace on stderr, e.g. from an internal `failwith` /
     `assert false` site reached on a well-typed program. *)
  let stderr =
    "Fatal error: exception Failure(\"lower: unsupported construct XYZ\")\n\
     Raised at Stdlib.failwith in file \"stdlib.ml\", line 29, characters 17-33\n\
     Called from March_tir__Lower.lower_expr in file \"lib/tir/lower.ml\", line 412, characters 4-40\n"
  in
  match classify_compile 2 stderr with
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for backtrace stderr, got `Skip %S" r

let test_classify_compile_clean_unsupported () =
  (* rc = 1, stderr is a normal diagnostic with no OCaml crash signature —
     the genuine "typechecked but not lowerable yet" case, which must stay
     a (counted) skip, not a failure. *)
  let stderr = "march: error: unsupported construct 'foo' in --compile mode\n" in
  match classify_compile 1 stderr with
  | `Skip _ -> ()
  | `Fail r -> Alcotest.failf "expected `Skip for clean unsupported exit, got `Fail %S" r

let test_classify_compile_assert_failure () =
  let stderr = "Fatal error: exception Assert_failure(\"lib/tir/perceus.ml\", 88, 2)\n" in
  match classify_compile 1 stderr with
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for Assert_failure marker, got `Skip %S" r

let test_classify_compile_signal_wins_over_clean_stderr () =
  (* Even if stderr happens to be empty/clean, a signal-death rc alone is
     sufficient to classify as `Fail — rc is checked before stderr content. *)
  match classify_compile 134 "" with (* 128 + SIGABRT *)
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for SIGABRT rc=134, got `Skip %S" r

(** Oracle Task 2 (Phase 1b): bin/main.ml now exits with a dedicated code
    ([internal_compiler_error_exit_code] = 3) whenever its top-level handler
    catches an exception escaping the compile pipeline, and prints
    "march: internal compiler error: ..." (no OCaml backtrace markers
    required for the oracle to recognize it — this is a positive signal, not
    a heuristic). Confirms the fast path fires ahead of, and independent of,
    stderr content. *)
let test_classify_compile_exit_3_is_internal_error () =
  let stderr =
    "march: internal compiler error: Failure(\"some future TIR bug\")\n\
     This is a compiler bug, not a problem with your program. Please file \
     an issue with a minimal reproduction.\n"
  in
  match classify_compile internal_compiler_error_exit_code stderr with
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for exit-3 internal-error signal, got `Skip %S" r

let test_classify_compile_exit_3_wins_with_no_stderr () =
  (* The exit code alone is conclusive — no stderr text needed. *)
  match classify_compile internal_compiler_error_exit_code "" with
  | `Fail _ -> ()
  | `Skip r -> Alcotest.failf "expected `Fail for exit-3 with empty stderr, got `Skip %S" r

let classify_compile_unit_tests = [
  "segfault rc classifies as Fail", `Quick, test_classify_compile_segfault;
  "OCaml backtrace stderr classifies as Fail", `Quick, test_classify_compile_backtrace;
  "Assert_failure marker classifies as Fail", `Quick, test_classify_compile_assert_failure;
  "clean unsupported exit classifies as Skip", `Quick, test_classify_compile_clean_unsupported;
  "signal death wins even with clean stderr", `Quick, test_classify_compile_signal_wins_over_clean_stderr;
  "exit-3 internal-error signal classifies as Fail", `Quick, test_classify_compile_exit_3_is_internal_error;
  "exit-3 wins even with no stderr", `Quick, test_classify_compile_exit_3_wins_with_no_stderr;
]

(** Unit test confirming the CONVERGED record-update-missing-field-on-
    erased-base behavior (Phase 2c, Task 5; converged by Core March spec
    Task 3) — see the doc comment above
    [test_record_update_missing_field_on_erased_base_converged]. *)
let record_update_converged_unit_tests = [
  "record update on missing field over erased base: converged (both backends error)",
  `Quick, test_record_update_missing_field_on_erased_base_converged;
]

(* ── CLI: --timings covers the compiler frontend ─────────────────────────── *)

(** A trivial module that exercises the full compile pipeline (parse through
    llvm-emit) without depending on anything exotic. *)
(* The probe must be CONTENT-UNIQUE per run. `--compile` is content-addressed
   (.march/cas/artifacts-v2): compiling a byte-identical program a second time
   returns the cached artifact and never runs the frontend, so no `[timings]`
   line is emitted and this test fails — on a warm cache only. That made it
   pass locally on a cold cache and fail in CI, which restores one. The nonce
   below gives every run a fresh cache key so the frontend always runs; the
   test is about timing INSTRUMENTATION, not about cache behaviour. *)
let timings_probe_source =
  Printf.sprintf
  "mod TimingsProbe do\n\
  \  needs IO.Console\n\
  \  -- cache-buster %d-%d\n\
  \  fn main(_cap_console : Cap(IO.Console)) do\n\
  \    println(to_string(1 + 1))\n\
  \  end\n\
   end\n" (Unix.getpid ()) (int_of_float (Unix.gettimeofday () *. 1000.))

let test_timings_covers_frontend () =
  match Lazy.force march_bin_opt with
  | None -> ()  (* no binary — skip, consistent with oracle_check *)
  | Some bin ->
    let src_file = write_temp_march timings_probe_source in
    let bin_file = src_file ^ ".bin" in
    let cmd = Printf.sprintf "%s --compile --timings %s -o %s 2>&1 1>/dev/null"
        (Filename.quote bin) (Filename.quote src_file) (Filename.quote bin_file) in
    let tmp = Filename.temp_file "march_timings_out" ".txt" in
    (* No `timeout` wrapper: this is a fixed, non-generated 3-line probe
       compiling, not a fuzzer-generated program that might hang. *)
    let _rc = Sys.command (Printf.sprintf "sh -c %s > %s"
        (Filename.quote cmd) (Filename.quote tmp)) in
    let out =
      let ic = open_in tmp in
      let s = In_channel.input_all ic in
      close_in ic; s
    in
    (try Sys.remove tmp with _ -> ());
    (try Sys.remove src_file with _ -> ());
    (try Sys.remove bin_file with _ -> ());
    let contains s sub =
      let sl = String.length s and bl = String.length sub in
      let rec loop i = i + bl <= sl && (String.sub s i bl = sub || loop (i + 1)) in
      loop 0
    in
    List.iter (fun label ->
        Alcotest.(check bool)
          (Printf.sprintf "[timings] output mentions %S" label) true
          (contains out (Printf.sprintf "  %s\n" label)))
      ["parse"; "desugar"; "resolve-imports"; "stdlib-load"; "typecheck"; "lower"]

let timings_unit_tests = [
  "--timings covers frontend phases (parse/desugar/resolve/stdlib-load)",
  `Quick, test_timings_covers_frontend;
]

(* ── Test suite registration ────────────────────────────────────────────── *)

let () =
  let open Alcotest in
  run "March property tests" [
    "oracle: classify_compile (unit)", classify_compile_unit_tests;
    "oracle: record-update converged (unit)", record_update_converged_unit_tests;
    "cli: timings (unit)", timings_unit_tests;
    "parse+typecheck", List.map QCheck_alcotest.to_alcotest [
      prop_parse_no_unexpected_exception;
      prop_typecheck_no_crash;
      prop_generated_programs_are_well_typed;
    ];
    "type soundness + eval", List.map QCheck_alcotest.to_alcotest [
      prop_type_sound_eval_no_crash;
    ];
    "tir pipeline (source)", List.map QCheck_alcotest.to_alcotest [
      prop_lower_no_crash;
      prop_mono_no_crash;
      prop_defun_no_crash;
      prop_perceus_no_crash;
    ];
    "algebraic oracle", List.map QCheck_alcotest.to_alcotest [
      prop_add_commutative;
      prop_add_zero_identity;
      prop_mul_one_identity;
      prop_sub_self_zero;
      prop_if_true_branch;
      prop_if_false_branch;
    ];
    "semantic properties (source)", List.map QCheck_alcotest.to_alcotest [
      prop_adt_match_correct;
      prop_tuple_swap_involution;
      prop_closure_captures_correct_value;
      prop_list_sum_correct;
    ];
    "tir passes (ast gen)", List.map QCheck_alcotest.to_alcotest [
      prop_perceus_tir_no_crash;
      prop_mono_tir_no_crash;
      prop_defun_tir_no_crash;
      prop_perceus_preserves_fn_count;
      prop_mono_preserves_main_fn;
      prop_defun_no_fn_loss;
    ];
    "tir pass invariants", List.map QCheck_alcotest.to_alcotest [
      prop_mono_eliminates_tvars;
      prop_defun_eliminates_letrec;
      prop_defun_tir_eliminates_letrec;
      prop_perceus_idempotent_fn_count;
      prop_mono_idempotent_fn_count;
      prop_defun_perceus_closure_no_crash;
    ];
    "oracle: interp = compiled", List.map QCheck_alcotest.to_alcotest [
      prop_oracle_println_arith;
      prop_oracle_println_closure;
      prop_oracle_println_adt;
      prop_oracle_println_hof;
      prop_oracle_println_tuple;
      prop_oracle_println_list;
      (* Generic-container diff coverage (ffe6fba8 class) — Task 3 Phase 2a *)
      prop_oracle_container_int_list;
      prop_oracle_container_string_list;
      prop_oracle_container_option;
      prop_oracle_container_nested_list;
      prop_oracle_container_list_of_options;
      (* Derived-method-call diff coverage (Newtype-derive fix class,
         6cc676fc) — Task 4 Phase 2b *)
      prop_oracle_derived_method_newtype_int;
      prop_oracle_derived_method_newtype_string;
      prop_oracle_derived_method_boxed;
      prop_oracle_derived_method_enum;
      prop_oracle_derived_method_record;
      (* Record-update / dual-position-borrow / FBIP / erased-flow diff
         coverage (0d1a829e / a5dad194 classes) — Task 5 Phase 2c *)
      prop_oracle_record_update;
      prop_oracle_dual_position_borrow;
      prop_oracle_fbip_same_arity;
      prop_oracle_erased_flow;
      (* Opt-level matrix (--opt 0 vs --opt 2) + exit-code parity — Phase 3 *)
      prop_oracle_opt_matrix;
    ];
  ]
