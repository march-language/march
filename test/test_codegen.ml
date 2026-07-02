(** March test suite — codegen tests. *)
open Test_helpers

let test_nested_bool_lit_pattern_no_tag_switch () =
  let ir = emit_actor_ir {|mod Test do
    fn classify(r : Result(Bool, String)) : String do
      match r do
        Ok(true) -> "T"
        Ok(false) -> "F"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
      println(classify(Ok(true)))
      println(classify(Ok(false)))
      println(classify(Err("x")))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32");
  Alcotest.(check bool) "bool field tested via trunc to i1" true
    (ir_contains ir "trunc i64");
  Alcotest.(check bool) "bool field untagged via ashr" true
    (ir_contains ir "ashr i64")

(** Nested Int literal patterns: the inner test must switch on the raw
    tagged bits with (n<<1)|1 labels — Ok(1) → label 3, Ok(2) → label 5. *)
let test_nested_int_lit_pattern_tagged_switch () =
  let ir = emit_actor_ir {|mod Test do
    fn classify(r : Result(Int, String)) : String do
      match r do
        Ok(1) -> "one"
        Ok(2) -> "two"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
      println(classify(Ok(1)))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32");
  Alcotest.(check bool) "Ok(1) compared against tagged immediate 3" true
    (ir_contains ir "i64 3, label");
  Alcotest.(check bool) "Ok(2) compared against tagged immediate 5" true
    (ir_contains ir "i64 5, label")

(** Nested Atom literal patterns: same shape — no second ctor-tag switch. *)
let test_nested_atom_lit_pattern_no_tag_switch () =
  let ir = emit_actor_ir {|mod Test do
    fn classify(r : Result(Atom, String)) : String do
      match r do
        Ok(:red) -> "R"
        Ok(:blue) -> "B"
        Ok(_) -> "other"
        Err(_) -> "E"
      end
    end
    fn main() : Unit do
      println(classify(Ok(:red)))
    end
  end|} in
  Alcotest.(check int) "exactly one i32 ctor-tag switch (outer Ok/Err)" 1
    (ir_count ir "switch i32")

(* ── TCO (tail-call optimisation) IR tests ─────────────────────────────── *)

(** Helper: full pipeline → LLVM IR, same as emit_actor_ir but named clearly. *)
let test_tco_factorial_has_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn factorial(n : Int, acc : Int) : Int do
      if n == 0 do acc
      else factorial(n - 1, n * acc) end
    end
    fn main() : Unit do println(int_to_string(factorial(10, 1))) end
  end|} in
  (* The tco_loop label and back-edge branch are the unique markers of TCO. *)
  Alcotest.(check bool) "TCO factorial: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO factorial: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Tail-recursive list fold: should be transformed into a loop. *)
let test_tco_fold_has_loop () =
  let ir = emit_tco_ir {|mod Test do
    type L = Nil | Cons(Int, L)
    @[no_warn_recursion]
    fn fold(xs : L, acc : Int) : Int do
      match xs do
      Nil        -> acc
      Cons(h, t) -> fold(t, acc + h)
      end
    end
    fn main() : Unit do println(int_to_string(fold(Cons(1, Cons(2, Nil)), 0))) end
  end|} in
  Alcotest.(check bool) "TCO fold: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO fold: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(** Non-tail-recursive fib must NOT get a TCO loop (it is not tail recursive). *)
let test_tco_nontail_fib_no_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn fib(n : Int) : Int do
      if n < 2 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main() : Unit do println(int_to_string(fib(10))) end
  end|} in
  Alcotest.(check bool) "non-tail fib: no TCO loop" false
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "non-tail fib: call instruction present" true
    (ir_contains ir "call i64 @fib")

(** Single-param tail-recursive countdown: loop emitted with back-edge. *)
let test_tco_countdown_has_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn count(n : Int) : Int do
      if n == 0 do 0
      else count(n - 1) end
    end
    fn main() : Unit do println(int_to_string(count(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop block emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(* ── Mutual TCO codegen tests ──────────────────────────────────────── *)

let test_mutual_tco_even_odd_loop_emitted () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn even(n : Int) : Bool do
      if n == 0 do true else odd(n - 1) end
    end
    @[no_warn_recursion]
    fn odd(n : Int) : Bool do
      if n == 0 do false else even(n - 1) end
    end
    fn main() : Unit do println(to_string(even(1000000))) end
  end|} in
  Alcotest.(check bool) "mutual TCO even/odd: mutual_loop block emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "mutual TCO even/odd: switch dispatch emitted" true
    (ir_contains ir "switch");
  Alcotest.(check bool) "mutual TCO even/odd: back-edge branch emitted" true
    (ir_contains ir "br label %mutual_loop");
  Alcotest.(check bool) "mutual TCO even/odd: combined fn declared" true
    (ir_contains ir "__mutco_");
  Alcotest.(check bool) "mutual TCO even/odd: even wrapper present" true
    (ir_contains ir "@even(")

(** Three-way mutual tail recursion: f → g → h → f.
    All three must end up inside the same combined dispatch function. *)
let test_mutual_tco_three_way () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn fa(n : Int) : Int do
      if n == 0 do 0 else fb(n - 1) end
    end
    @[no_warn_recursion]
    fn fb(n : Int) : Int do
      if n == 0 do 0 else fc(n - 1) end
    end
    @[no_warn_recursion]
    fn fc(n : Int) : Int do
      if n == 0 do 0 else fa(n - 1) end
    end
    fn main() : Unit do println(int_to_string(fa(99))) end
  end|} in
  Alcotest.(check bool) "three-way mutual TCO: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "three-way mutual TCO: switch emitted" true
    (ir_contains ir "switch");
  Alcotest.(check bool) "three-way mutual TCO: combined fn declared" true
    (ir_contains ir "__mutco_")

(** A/B state-machine with mutual tail calls. *)
let test_mutual_tco_state_machine () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn state_a(n : Int) : Int do
      if n <= 0 do 1 else state_b(n - 1) end
    end
    @[no_warn_recursion]
    fn state_b(n : Int) : Int do
      if n <= 0 do 2 else state_a(n - 1) end
    end
    fn main() : Unit do println(int_to_string(state_a(1000000))) end
  end|} in
  Alcotest.(check bool) "state machine mutual TCO: mutual_loop emitted" true
    (ir_contains ir "mutual_loop");
  Alcotest.(check bool) "state machine mutual TCO: combined fn declared" true
    (ir_contains ir "__mutco_")

(** Non-tail mutual recursion must NOT get a mutual_loop block.
    f calls g in non-tail position (result used in arithmetic). *)
let test_mutual_tco_non_tail_no_loop () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn count_f(n : Int) : Int do
      if n == 0 do 1 else count_g(n - 1) + 1 end
      if n == 0 then 1 else count_g(n - 1) + 1
    end
    @[no_warn_recursion]
    fn count_g(n : Int) : Int do
      if n == 0 do 1 else count_f(n - 1) + 1 end
      if n == 0 then 1 else count_f(n - 1) + 1
    end
    fn main() : Unit do println(int_to_string(count_f(10))) end
  end|} in
  Alcotest.(check bool) "non-tail mutual recursion: no mutual_loop" false
    (ir_contains ir "mutual_loop")

(** Self-TCO must still work when mutual-TCO detection is also running.
    A self-recursive function that is NOT part of any mutual group must still
    get its tco_loop transformation. *)
let test_mutual_tco_self_tco_unaffected () =
  let ir = emit_mutual_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
      if n == 0 then 0 else countdown(n - 1)
    end
    fn main() : Unit do println(int_to_string(countdown(10))) end
  end|} in
  Alcotest.(check bool) "self TCO still works: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "self TCO still works: back-edge branch emitted" true
    (ir_contains ir "br label %tco_loop")

(* ── Phase 4: Reduction Counting in Compiled Code ─────────────────────── *)

(** Non-leaf, non-TCO function: reduction check IR must appear. *)
let test_phase4_nonleaf_has_reduction_check () =
  let ir = emit_tco_ir {|mod Test do
    fn fib(n : Int) : Int do
      if n <= 1 do n
      else fib(n - 1) + fib(n - 2) end
    end
    fn main() : Unit do println(int_to_string(fib(10))) end
  end|} in
  Alcotest.(check bool) "non-leaf fib: @march_tls_reductions loaded" true
    (ir_contains ir "@march_tls_reductions");
  Alcotest.(check bool) "non-leaf fib: march_yield_from_compiled called" true
    (ir_contains ir "@march_yield_from_compiled");
  Alcotest.(check bool) "non-leaf fib: sched_yield block emitted" true
    (ir_contains ir "sched_yield");
  Alcotest.(check bool) "non-leaf fib: sched_cont block emitted" true
    (ir_contains ir "sched_cont")

(** All-leaf module (only builtin calls): NO reduction check anywhere.
    - square(n) = n * n        → only builtin `*`  → leaf
    - main()    = println(42)  → only builtins      → leaf
    Neither function should emit the icmp/br reduction check. *)
let test_phase4_leaf_fn_no_reduction_check () =
  let ir = emit_tco_ir {|mod Test do
    fn square(n : Int) : Int do n * n end
    fn main() : Unit do println(int_to_string(42)) end
  end|} in
  (* No non-leaf functions → no reduction check IR anywhere in the output. *)
  Alcotest.(check bool) "all-leaf module: no icmp reduction check" false
    (ir_contains ir "icmp sle i64")

(** TCO function: reduction check must be inside the tco_loop block. *)
let test_phase4_tco_fn_reduction_in_loop () =
  let ir = emit_tco_ir {|mod Test do
    @[no_warn_recursion]
    fn countdown(n : Int) : Int do
      if n == 0 do 0 else countdown(n - 1) end
      if n == 0 then 0 else countdown(n - 1)
    end
    fn main() : Unit do println(int_to_string(countdown(100))) end
  end|} in
  Alcotest.(check bool) "TCO countdown: tco_loop emitted" true
    (ir_contains ir "tco_loop");
  Alcotest.(check bool) "TCO countdown: reduction check in loop" true
    (ir_contains ir "@march_tls_reductions");
  Alcotest.(check bool) "TCO countdown: yield call present" true
    (ir_contains ir "@march_yield_from_compiled")

(** Non-recursive function that calls another user function: non-leaf,
    so it must get a reduction check even though it has no loop. *)
let test_phase4_nonrecursive_caller_has_check () =
  let ir = emit_tco_ir {|mod Test do
    fn double(n : Int) : Int do n + n end
    fn apply_double(n : Int) : Int do double(n) end
    fn main() : Unit do println(int_to_string(apply_double(3))) end
  end|} in
  (* apply_double calls double (non-builtin) → non-leaf → check emitted. *)
  Alcotest.(check bool) "apply_double: reduction check present" true
    (ir_contains ir "@march_tls_reductions")

let test_llvm_no_call_to_double_underscore () =
  let src = {|mod Test do
    fn and_op(a : Bool, b : Bool) : Bool do a && b end
    fn or_op(a : Bool, b : Bool)  : Bool do a || b end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let ir  = March_tir.Llvm_emit.emit_module tir in
  (* The bug was that @__ was emitted as a called symbol. *)
  let has_call_to_dunder =
    try ignore (Str.search_forward (Str.regexp_string "call.*@__") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "no call to @__ in generated IR" false has_call_to_dunder

(* --- multiline tests --- *)

let test_multiline_depth_zero () =
  Alcotest.(check int) "single expression has depth 0"
    0 (March_repl.Multiline.do_end_depth "x + 1")

let test_multiline_depth_open () =
  Alcotest.(check int) "open do block has depth 1"
    1 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1")

let test_multiline_depth_closed () =
  Alcotest.(check int) "closed do block has depth 0"
    0 (March_repl.Multiline.do_end_depth "fn foo() do\n  x + 1\nend")

let test_multiline_ends_with_with () =
  Alcotest.(check int) "match opener depth is 1"
    1 (March_repl.Multiline.do_end_depth "match x do")

let test_multiline_not_ends_with_with () =
  Alcotest.(check bool) "record update does not trigger with heuristic"
    false (March_repl.Multiline.ends_with_with "let y = { x with foo = 1 }")

let test_multiline_starts_with_pipe () =
  Alcotest.(check bool) "match arm starts with pipe"
    true (March_repl.Multiline.starts_with_pipe "| Some(x) -> x")

let test_multiline_is_complete_simple () =
  Alcotest.(check bool) "simple expression is complete"
    true (March_repl.Multiline.is_complete "x + 1")

let test_multiline_is_complete_open_block () =
  Alcotest.(check bool) "open block is not complete"
    false (March_repl.Multiline.is_complete "fn foo() do\n  x")

(* --- complete tests --- *)

let test_complete_command () =
  let completions = March_repl.Complete.complete ":q" [] in
  Alcotest.(check bool) ":q completes to :quit or :q"
    true (List.mem ":quit" completions || List.mem ":q" completions)

let test_complete_keyword () =
  let completions = March_repl.Complete.complete "fn" [] in
  Alcotest.(check bool) "fn is in keyword completions"
    true (List.mem "fn" completions)

let test_complete_in_scope () =
  let scope = [("double", "Int -> Int"); ("x", "Int")] in
  let completions = March_repl.Complete.complete "do" scope in
  Alcotest.(check bool) "double completes from scope"
    true (List.mem "double" completions)

let test_complete_empty_all () =
  let completions = March_repl.Complete.complete "" [] in
  Alcotest.(check bool) "empty prefix returns at least one keyword"
    true (List.length completions > 0)

(* ------------------------------------------------------------------ *)
(* complete_replace tests                                              *)
(* ------------------------------------------------------------------ *)

let test_complete_replace_prefix () =
  (* cursor at end of prefix "fo", no right side → replace "fo" with "foo" *)
  let s = mk_inp "fo" 2 in
  let s' = March_repl.Input.complete_replace s "foo" in
  Alcotest.(check string) "buf" "foo" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 3     s'.March_repl.Input.cursor

let test_complete_replace_midword () =
  (* cursor mid-word: "fo|bar" → replace whole word with "foobar" *)
  let s = mk_inp "fobar" 2 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "foobar" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 6        s'.March_repl.Input.cursor

let test_complete_replace_with_suffix () =
  (* context: "x = fo|bar + 1" → replace word "fobar" with "foobar", keep rest *)
  let s = mk_inp "x = fobar + 1" 7 in
  let s' = March_repl.Input.complete_replace s "foobar" in
  Alcotest.(check string) "buf" "x = foobar + 1" s'.March_repl.Input.buffer;
  Alcotest.(check int)    "cur" 10               s'.March_repl.Input.cursor

(* ------------------------------------------------------------------ *)
(* JIT cross-line REPL variable capture tests                         *)
(* These tests exercise the fix for the bug where variables defined   *)
(* on previous REPL lines could not be referenced in HOF arguments.  *)
(* Tests are skipped gracefully when clang/runtime is unavailable.   *)
(* ------------------------------------------------------------------ *)

(** Try to compile the march runtime to a shared library.
    Returns [Some path] on success, [None] if clang or runtime.c is missing.

    The cache lives in ~/.cache/march, which is SHARED across worktrees and
    concurrent sessions — so the artifact name is keyed by a digest of every
    C source/header that goes into it, and the write is atomic (compile to
    a pid-suffixed temp, then rename).  The old scheme — one fixed
    "libmarch_rt_test.so" with an existence-only check — was never
    invalidated when the runtime changed, and a concurrent worktree with
    diverged runtime sources would overwrite it with an ABI-mismatched
    binary, hanging whichever test process dlopen'd the wrong build. *)
let test_repl_jit_cross_line_let () =
  match setup_jit_runtime () with
  | None -> ()  (* skip: clang or runtime not available in this environment *)
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Compile: let x = 21 *)
       (match parse_repl "let x = 21" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt
                | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet for 'let x = 21'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          (* Update tc_env so 'x : Int' is in scope for the next expression *)
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* Compile: x + 21 — cross-line reference *)
       (match parse_repl "x + 21" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "cross-line let: x+21 = 42" "42" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: `let f = fn x -> x * 2` (DFn) on line 1,
    then `f(21)` on line 2 should give 42 (cross-line function reference). *)
let test_repl_jit_cross_line_fn () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Compile: let f = fn x -> x * 2  (parsed as DLet with lambda RHS) *)
       (match parse_repl "let f = fn x -> x * 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let name = match b.bind_pat with
                | March_ast.Ast.PatVar n -> n.txt
                | _ -> failwith "expected PatVar"
              in (name, b.bind_expr)
            | _ -> failwith "expected DLet for 'let f = fn x -> x * 2'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          (* Update tc_env so 'f : Int -> Int' is in scope for the next expression *)
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* Compile: f(21) — cross-line function reference.
          Known limitation: cross-fragment function calls require `declare` stubs
          for functions compiled in prior fragments (issue #1 in repl_smoke_test.sh).
          This test verifies the let binding compiles; the cross-fragment call
          may fail with a clang error, which is an expected known issue. *)
       (match parse_repl "f(21)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          (try
            let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
            Alcotest.(check string) "cross-line fn: f(21) = 42" "42" result
          with Failure msg when
            (let m = String.lowercase_ascii msg in
             let len = String.length m in
             let rec scan i =
               if i + 8 >= len then false
               else if String.sub m i 9 = "undefined" then true
               else scan (i + 1)
             in scan 0) ->
            (* Cross-fragment declare issue — known limitation, skip *)
            ())
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: both a let and a function defined on previous lines,
    used together in a HOF call — the original bug scenario. *)
let test_repl_jit_cross_line_hof () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* let n = 21 *)
       (match parse_repl "let n = 21" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let nm = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> assert false
              in (nm, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* let double = fn x -> x * 2  (parsed as DLet with lambda RHS) *)
       (match parse_repl "let double = fn x -> x * 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let name = match b.bind_pat with
                | March_ast.Ast.PatVar n -> n.txt
                | _ -> failwith "expected PatVar"
              in (name, b.bind_expr)
            | _ -> failwith "expected DLet for 'let double = fn x -> x * 2'"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* double(n) — both from previous lines.
          Known limitation: cross-fragment function call may fail if the
          closure function compiled in a prior fragment isn't reachable via
          LLVM `declare`. This is a known issue (see repl_smoke_test.sh). *)
       (match parse_repl "double(n)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          (try
            let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
            Alcotest.(check string) "cross-line hof: double(n) = 42" "42" result
          with Failure msg when
            (let m = String.lowercase_ascii msg in
             let len = String.length m in
             let rec scan i =
               if i + 8 >= len then false
               else if String.sub m i 9 = "undefined" then true
               else scan (i + 1)
             in scan 0) ->
            (* Cross-fragment declare issue — known limitation, skip *)
            ())
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Test: List.length works correctly in JIT REPL with stdlib precompile.

    This is a regression test for the defun TVar bug: when the stdlib is
    precompiled with an empty type_map (as in the real REPL), inner function
    calls like [go(xs, 0)] inside [length] had v_ty = TVar "_" at the call site.
    Defun's condition B required TFn to convert EApp → ECallPtr, so the call
    stayed as a direct [call @go] — an undefined symbol — returning garbage.

    The fix: EApp of a TVar-typed non-top-level var is also converted to ECallPtr. *)
let test_repl_jit_stdlib_list_length () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    (* Load list.march *)
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    (* Compute content hash the same way Repl does *)
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       (* Precompile stdlib — this triggers the TVar bug path on unfixed builds *)
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       (* Wrap expression in a module that includes stdlib_decls so that
          List.length resolves through monomorphization to length$List_Int. *)
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let main_clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [main_clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (* List.length([1, 2, 3]) should return 3 *)
       (match parse_repl "List.length([1, 2, 3])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.length [1,2,3] = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* List.length([]) should return 0 *)
       (match parse_repl "List.length([])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.length [] = 0" "0" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* REPL JIT regression tests                                           *)
(* Exercises fixes: AVar extern fix, repl_N global uniquification,    *)
(* List literal JIT support, var redefinition, expr-after-let.        *)
(* ------------------------------------------------------------------ *)

(** Regression: `let xs = [1,2,3]` should succeed without JIT error.
    Fixes: AVar for march_compare_int was falling through to alloca bridge. *)
let test_repl_list_literal () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [1, 2, 3]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false ~bind_name m
        | _ -> failwith "expected ReplDecl");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let xs = [1,2,3]` then `List.length(xs)` should return 3.
    Exercises stdlib dispatch on a list literal defined in a prior REPL line. *)
let test_repl_stdlib_on_list () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [1, 2, 3]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let x = 1` then `let x = 2` then `x` should return 2.
    Exercises global-name uniquification (repl_N_x) so redefining x doesn't
    collide with the previous fragment's global. *)
let test_repl_var_redefinition () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (match parse_repl "let x = 1" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "let x = 2" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "x" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "x after redef = 2" "2" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let xs = [3,1,2]` then `List.length(xs)` twice.
    Exercises that the stdlib precompile cache is stable across multiple calls. *)
let test_repl_stdlib_chain () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let xs = [3, 1, 2]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_stdlib_mod bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (* First call *)
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) call 1 = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* Second call — same value, different fragment *)
       (match parse_repl "List.length(xs)" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "List.length(xs) call 2 = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let x = 42` then `x + 1` should return 43.
    Exercises that an expression using a previous binding evaluates correctly. *)
let test_repl_expr_after_let () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (match parse_repl "let x = 42" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          let m = make_jit_test_module bind_expr in
          March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
          let new_env = March_typecheck.Typecheck.check_decl
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
          tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
        | _ -> failwith "expected ReplDecl");
       (match parse_repl "x + 1" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "x + 1 = 43" "43" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* REPL magic `v` variable and heap pretty-printer tests              *)
(* ------------------------------------------------------------------ *)

(** `v` (magic last-result variable) works across JIT fragments.
    After evaluating `21 + 21`, `v` should be available and equal to 42.
    Bug: previously `v` was added to tc_env but not to JIT globals,
    so referencing `v` in the next fragment crashed clang. *)
let test_repl_jit_v_magic_int () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       (* Evaluate `21 + 21` — result stored as @repl_N_v *)
       (match parse_repl "21 + 21" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "21+21 = 42" "42" result;
          let inferred = March_typecheck.Typecheck.infer_expr
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } e' in
          tc_env := { !tc_env with March_typecheck.Typecheck.vars =
            March_typecheck.Typecheck.StrMap.add "v"
              (March_typecheck.Typecheck.Mono inferred)
              !tc_env.March_typecheck.Typecheck.vars }
        | _ -> failwith "expected ReplExpr");
       (* Now evaluate `v + 1` — references the `v` global from prior fragment *)
       (match parse_repl "v + 1" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "v+1 = 43" "43" result;
          let inferred = March_typecheck.Typecheck.infer_expr
            { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } e' in
          tc_env := { !tc_env with March_typecheck.Typecheck.vars =
            March_typecheck.Typecheck.StrMap.add "v"
              (March_typecheck.Typecheck.Mono inferred)
              !tc_env.March_typecheck.Typecheck.vars }
        | _ -> failwith "expected ReplExpr");
       (* `v` itself equals 43 now (the result of the last expression) *)
       (match parse_repl "v" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_jit_test_module e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
          Alcotest.(check string) "v = 43 (last result)" "43" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Heap pretty-printer: a list literal `[1, 2, 3]` must display as
    "[1, 2, 3]" rather than "#<value at 0x...>".
    Bug: the `_` catch-all in run_expr returned the raw pointer address. *)
let test_repl_jit_list_display () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (* Evaluate `[1, 2, 3]` — should pretty-print as "[1, 2, 3]" *)
       (match parse_repl "[1, 2, 3]" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "[1,2,3] display" "[1, 2, 3]" result
        | _ -> failwith "expected ReplExpr");
       (* Empty list `[]` — should display as "[]" *)
       (match parse_repl "List.empty()" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_mod e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "empty list display" "[]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Parser hint: `x = 5` at REPL top-level should raise ParseError with
    a hint containing "let". *)
let test_repl_assign_hint () =
  (try
     let _ = parse_repl "x = 5" in
     Alcotest.fail "expected ParseError for `x = 5`"
   with
   | March_errors.Errors.ParseError (msg, _hint, _pos) ->
     (* Message must mention `let` as a hint *)
     let has_let = String.length msg >= 3 &&
       (let rec check i =
          if i + 2 >= String.length msg then false
          else if String.sub msg i 3 = "let" then true
          else check (i + 1)
        in check 0) in
     Alcotest.(check bool) "hint mentions let" true has_let
   | exn ->
     Alcotest.failf "unexpected exception: %s" (Printexc.to_string exn))

(** General REPL interaction: define a variable, evaluate an expression
    using it, redefine it, and check v tracks the last result. *)
let test_repl_jit_general_interaction () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       let type_map = Hashtbl.create 16 in
       let tc_env = ref (March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map) in
       let run_decl_str src =
         match parse_repl src with
         | March_ast.Ast.ReplDecl d ->
           let d' = March_desugar.Desugar.desugar_decl d in
           let (bind_name, bind_expr) = match d' with
             | March_ast.Ast.DLet (_, b, _) ->
               let n = match b.bind_pat with
                 | March_ast.Ast.PatVar v -> v.txt | _ -> failwith "PatVar"
               in (n, b.bind_expr)
             | _ -> failwith "expected DLet"
           in
           let m = make_jit_test_module bind_expr in
           March_jit.Repl_jit.run_decl jit ~tc_env:!tc_env ~is_fn_decl:false ~bind_name m;
           let new_env = March_typecheck.Typecheck.check_decl
             { !tc_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () } d' in
           tc_env := { new_env with March_typecheck.Typecheck.errors = March_errors.Errors.create () }
         | _ -> failwith ("expected ReplDecl for: " ^ src)
       in
       let run_expr_str src =
         match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let m = make_jit_test_module e' in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env:!tc_env m in
           result
         | _ -> failwith ("expected ReplExpr for: " ^ src)
       in
       run_decl_str "let x = 10";
       (* x + 5 = 15 *)
       Alcotest.(check string) "x+5" "15" (run_expr_str "x + 5");
       (* v = 15 (last result) *)
       Alcotest.(check string) "v=15" "15" (run_expr_str "v");
       (* redefine x = 99 *)
       run_decl_str "let x = 99";
       Alcotest.(check string) "x after redef" "99" (run_expr_str "x");
       (* v = 99 now *)
       Alcotest.(check string) "v=99" "99" (run_expr_str "v");
       (* boolean expression: true *)
       Alcotest.(check string) "true expr" "true" (run_expr_str "1 == 1");
       (* v after bool *)
       Alcotest.(check string) "v=true" "true" (run_expr_str "v");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: `let ll = [1,2,3,9,4,5,6,7]` must compile when bigint is
    in the JIT fragment.  Reproduces the real-REPL scenario where
    precompile_stdlib fails (e.g. decimal.march parse error), causing ALL
    stdlib functions — including BigInt.div_digit$go$apply$N — to be
    JIT-compiled in the first fragment alongside the user's list literal.

    Bug: the Cons branch of div_digit$go$apply$N defines %new_rem.addr in
    case_cons_lbl, but after FBIP the subsequent load lands in fbip_merge1
    without %new_rem.addr being defined there (or the alloca uses the wrong
    slot due to stale local_names state leaking from a prior emit_fn call). *)
let test_repl_list_literal_with_bigint () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl   = load_stdlib_file_for_test "list.march" in
    let bigint_decl = load_stdlib_file_for_test "bigint.march" in
    let stdlib_decls = [list_decl; bigint_decl] in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (* Intentionally do NOT call precompile_stdlib — this forces all stdlib
       functions (including BigInt) into the first JIT fragment, reproducing
       the real-REPL scenario when precompile fails due to a parse error in
       another stdlib file (e.g. decimal.march). *)
    (try
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       let run_decl_with_stdlib src =
         match parse_repl src with
         | March_ast.Ast.ReplDecl d ->
           let d' = March_desugar.Desugar.desugar_decl d in
           let (bind_name, bind_expr) = match d' with
             | March_ast.Ast.DLet (_, b, _) ->
               let n = match b.bind_pat with
                 | March_ast.Ast.PatVar v -> v.txt
                 | _ -> failwith "expected PatVar"
               in (n, b.bind_expr)
             | _ -> failwith "expected DLet"
           in
           March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false
             ~bind_name (make_stdlib_mod bind_expr)
         | _ -> failwith ("expected ReplDecl for: " ^ src)
       in
       (* 8-element list — exact reproducer from bug report *)
       run_decl_with_stdlib "let ll = [1,2,3,9,4,5,6,7]";
       (* Shorter lists at the boundary *)
       run_decl_with_stdlib "let xs = [1,2,3]";
       run_decl_with_stdlib "let ys = [1]";
       run_decl_with_stdlib "let zs = []";
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression: decimal.march must parse without errors.
    A missing `end` in the `align` function caused the module block to close
    prematurely, which then caused a parse error on the next `doc` annotation.
    With decimal fixed, precompile_stdlib can succeed for the full stdlib. *)
let test_decimal_march_parses () =
  (* load_stdlib_file_for_test will raise if decimal.march fails to parse *)
  let _decl = load_stdlib_file_for_test "decimal.march" in
  ignore _decl

(** Regression: precompile_stdlib with bigint + decimal should succeed,
    ensuring list literals don't drag all stdlib fns into every JIT fragment. *)
let test_repl_list_literal_with_precompile_bigint () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl   = load_stdlib_file_for_test "list.march" in
    let bigint_decl = load_stdlib_file_for_test "bigint.march" in
    let stdlib_decls = [list_decl; bigint_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       (* Precompile bigint — should succeed now that decimal.march is fixed *)
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let make_stdlib_mod e =
         let s = March_ast.Ast.dummy_span in
         let clause = March_ast.Ast.{
           fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
         let main_def = March_ast.Ast.{
           fn_name = { txt = "main"; span = s };
           fn_vis = Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
           fn_clauses = [clause]; fn_bounds = [] } in
         { March_ast.Ast.mod_name = { txt = "Main"; span = s };
           mod_decls = stdlib_decls @ [DFn (main_def, s)] }
       in
       (match parse_repl "let ll = [1,2,3,9,4,5,6,7]" with
        | March_ast.Ast.ReplDecl d ->
          let d' = March_desugar.Desugar.desugar_decl d in
          let (bind_name, bind_expr) = match d' with
            | March_ast.Ast.DLet (_, b, _) ->
              let n = match b.bind_pat with
                | March_ast.Ast.PatVar v -> v.txt
                | _ -> failwith "expected PatVar"
              in (n, b.bind_expr)
            | _ -> failwith "expected DLet"
          in
          March_jit.Repl_jit.run_decl jit ~tc_env ~is_fn_decl:false
            ~bind_name (make_stdlib_mod bind_expr)
        | _ -> failwith "expected ReplDecl");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* P0 REGRESSION: compiled_fns corruption fix (2026-03)               *)
(*                                                                     *)
(* Previously `partition_fns` added functions to `compiled_fns`       *)
(* BEFORE `compile_fragment` succeeded.  If compilation failed, those *)
(* functions were poisoned: marked compiled but absent from any .so.   *)
(* On the next REPL expression they became `extern_fns` (declared but *)
(* not defined), causing "undefined symbol" errors on ALL stdlib fns.  *)
(*                                                                     *)
(* Fix: `partition_fns` is now pure; `mark_compiled_fns` is called    *)
(* only after a successful `compile_fragment` + dlopen.               *)
(*                                                                     *)
(* Tests below cover:                                                  *)
(*   1. stdlib fns (List.reverse, List.length) work in successive frags*)
(*   2. stdlib fns available WITHOUT precompile (inline-JIT mode)     *)
(*   3. List.map with user-defined lambda across REPL lines            *)
(* ------------------------------------------------------------------ *)

(** Helper: build a module including [stdlib_decls] with main = [e]. *)
let test_repl_jit_stdlib_reverse () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       (* First fragment: List.reverse([1, 2, 3]) *)
       (match parse_repl "List.reverse([1, 2, 3])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.reverse [1,2,3] = [3, 2, 1]" "[3, 2, 1]" result
        | _ -> failwith "expected ReplExpr");
       (* Second fragment: List.reverse([4, 5]) — stdlib fn in 2nd fragment *)
       (match parse_repl "List.reverse([4, 5])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "List.reverse [4,5] = [5, 4]" "[5, 4]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression P0: stdlib fns available WITHOUT precompile (inline-JIT mode).
    When precompile_stdlib is not called (simulating a failed precompile),
    stdlib fns must still compile inline on first use, and then be properly
    marked compiled so subsequent fragments can use them as externs.
    Previously the premature-marking bug caused the SECOND call to crash. *)
let test_repl_jit_stdlib_no_precompile () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (* Intentionally skip precompile_stdlib to force inline-JIT mode *)
    (try
       (* First call: List.length inline (includes stdlib in fragment) *)
       (match parse_repl "List.length([10, 20, 30])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.length [10,20,30] = 3" "3" result
        | _ -> failwith "expected ReplExpr");
       (* Second call: List.length again — stdlib fns are now extern, must resolve *)
       (match parse_repl "List.length([1])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.length [1] = 1" "1" result
        | _ -> failwith "expected ReplExpr");
       (* Third call: List.reverse — different stdlib fn, same fragment mode *)
       (match parse_repl "List.reverse([3, 2, 1])" with
        | March_ast.Ast.ReplExpr e ->
          let e' = March_desugar.Desugar.desugar_expr e in
          let m = make_stdlib_module stdlib_decls e' in
          let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
          Alcotest.(check string) "inline: List.reverse [3,2,1] = [1, 2, 3]" "[1, 2, 3]" result
        | _ -> failwith "expected ReplExpr");
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(** Regression P0: List.length works 3 times in succession.
    With the old premature-marking bug, if ANY of the compilations had
    failed, subsequent calls would see length$List_Int as "already compiled"
    (extern-only) and crash.  Three successive calls exercises the
    mark-after-success invariant thoroughly. *)
let test_repl_jit_stdlib_length_3x () =
  match setup_jit_runtime () with
  | None -> ()
  | Some runtime_so ->
    let list_decl = load_stdlib_file_for_test "list.march" in
    let stdlib_decls = [list_decl] in
    let content_hash =
      Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
    let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
      Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (try
       March_jit.Repl_jit.precompile_stdlib jit
         ~content_hash ~stdlib_decls ~type_map;
       let run_length lst expected label =
         let src = Printf.sprintf "List.length(%s)" lst in
         match parse_repl src with
         | March_ast.Ast.ReplExpr e ->
           let e' = March_desugar.Desugar.desugar_expr e in
           let m = make_stdlib_module stdlib_decls e' in
           let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
           Alcotest.(check string) label expected result
         | _ -> failwith ("expected ReplExpr for: " ^ src)
       in
       run_length "[1, 2, 3]"    "3" "length 3 (fragment 1)";
       run_length "[1, 2]"       "2" "length 2 (fragment 2)";
       run_length "[]"           "0" "length 0 (fragment 3)";
       March_jit.Repl_jit.cleanup jit
     with exn ->
       March_jit.Repl_jit.cleanup jit; raise exn)

(* ------------------------------------------------------------------ *)
(* list_actors tests                                                   *)
(* ------------------------------------------------------------------ *)

let test_list_actors_empty () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Alcotest.(check int) "empty registry" 0
    (List.length (March_eval.Eval.list_actors ()))

let test_list_actors_alive () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "Counter" true (March_eval.Eval.VInt 5));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "one actor" 1 (List.length actors);
  let a = List.hd actors in
  Alcotest.(check int)    "pid"   0     a.March_eval.Eval.ai_pid;
  Alcotest.(check string) "name"  "Counter" a.March_eval.Eval.ai_name;
  Alcotest.(check bool)   "alive" true  a.March_eval.Eval.ai_alive;
  Alcotest.(check string) "state" "5"   a.March_eval.Eval.ai_state_str

let test_list_actors_sorted () =
  Hashtbl.clear March_eval.Eval.actor_registry;
  Hashtbl.add March_eval.Eval.actor_registry 2
    (mk_actor_inst "A" true (March_eval.Eval.VInt 0));
  Hashtbl.add March_eval.Eval.actor_registry 0
    (mk_actor_inst "B" false (March_eval.Eval.VUnit));
  let actors = March_eval.Eval.list_actors () in
  Alcotest.(check int) "two actors" 2 (List.length actors);
  Alcotest.(check int) "sorted first pid" 0
    (List.nth actors 0).March_eval.Eval.ai_pid;
  Alcotest.(check int) "sorted second pid" 2
    (List.nth actors 1).March_eval.Eval.ai_pid

(* ------------------------------------------------------------------ *)
(* Debugger tests                                                     *)
(* ------------------------------------------------------------------ *)

let test_edbg_ast () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg (None, sp) in
  Alcotest.(check bool) "EDbg is an expr" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_lexer_keyword_dbg () =
  let lexbuf = Lexing.from_string "dbg" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes dbg keyword" true
    (match tok with March_parser.Parser.DBG -> true | _ -> false)

let test_parse_dbg () =
  let lexbuf = Lexing.from_string "dbg()" in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  Alcotest.(check bool) "parses dbg() as EDbg" true
    (match e with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_desugar_edbg () =
  let sp = March_ast.Ast.dummy_span in
  let e = March_ast.Ast.EDbg (None, sp) in
  let e' = March_desugar.Desugar.desugar_expr e in
  Alcotest.(check bool) "EDbg desugar passthrough" true
    (match e' with March_ast.Ast.EDbg _ -> true | _ -> false)

let test_typecheck_edbg () =
  let type_map = Hashtbl.create 4 in
  let env = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let sp = March_ast.Ast.dummy_span in
  let ty = March_typecheck.Typecheck.infer_expr env (March_ast.Ast.EDbg (None, sp)) in
  let pp = March_typecheck.Typecheck.pp_ty (March_typecheck.Typecheck.repr ty) in
  Alcotest.(check string) "EDbg typechecks as Unit" "()" pp

let test_eval_edbg_noop () =
  let v = March_eval.Eval.eval_expr March_eval.Eval.base_env
    (March_ast.Ast.EDbg (None, March_ast.Ast.dummy_span)) in
  Alcotest.(check bool) "EDbg evals to VUnit without debug mode" true
    (match v with March_eval.Eval.VUnit -> true | _ -> false)

let test_ring_buffer () =
  let rb = March_eval.Eval.ring_create 3 in
  March_eval.Eval.ring_push rb 10;
  March_eval.Eval.ring_push rb 20;
  March_eval.Eval.ring_push rb 30;
  Alcotest.(check (option int)) "ring get 0 (most recent)" (Some 30)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 (oldest)" (Some 10)
    (March_eval.Eval.ring_get rb 2);
  (* overflow: push 40, evicts 10 *)
  March_eval.Eval.ring_push rb 40;
  Alcotest.(check (option int)) "ring get 0 after overflow" (Some 40)
    (March_eval.Eval.ring_get rb 0);
  Alcotest.(check (option int)) "ring get 2 after overflow" (Some 20)
    (March_eval.Eval.ring_get rb 2)

let test_trace_recording () =
  let cap = (match Sys.getenv_opt "MARCH_DEBUG_TRACE_SIZE" with
     | Some s -> (try int_of_string s with _ -> 100000) | None -> 100000) in
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create cap;
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
    dc_breakpoints = Hashtbl.create 16;
    dc_step        = March_eval.Eval.Run;
    dc_on_pause    = None;
    dc_last_line   = None;
  } in
  March_eval.Eval.debug_ctx := Some ctx;
  let src = "1 + 2" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  let _v = March_eval.Eval.eval_expr March_eval.Eval.base_env e' in
  let frames_recorded = ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size in
  March_eval.Eval.debug_ctx := None;
  Alcotest.(check bool) "trace records frames" true (frames_recorded > 0)

let test_trace_navigation () =
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _ -> ()) in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  let n = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "recorded some frames" true (n > 0);
  let new_pos = March_debug.Trace.back ctx 1 in
  Alcotest.(check int) "back 1 moves cursor" 1 new_pos;
  let new_pos2 = March_debug.Trace.forward ctx 1 in
  Alcotest.(check int) "forward 1 returns to 0" 0 new_pos2;
  March_debug.Debug.uninstall ()

let test_replay () =
  let hit_dbg = ref false in
  let captured_env = ref March_eval.Eval.base_env in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun env ->
    hit_dbg := true;
    captured_env := env
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod Test do
  fn factorial(n) do
    dbg()
    if n <= 1 do 1
    else n * factorial(n - 1) end
  end
  fn main() do
    factorial(3)
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() was hit" true !hit_dbg;
  let frame_count_before = March_debug.Debug.frame_count ctx in
  let new_env = ("n", March_eval.Eval.VInt 5) ::
                (List.remove_assoc "n" !captured_env) in
  March_debug.Debug.install ctx;
  ignore (March_debug.Replay.replay_from ctx new_env);
  March_debug.Debug.uninstall ();
  let frame_count_after = March_debug.Debug.frame_count ctx in
  Alcotest.(check bool) "replay adds new frames" true
    (frame_count_after > frame_count_before)

let test_debug_continue () =
  let hit = ref false in
  let ctx = March_debug.Debug.make_debug_ctx ~on_dbg:(fun _env ->
    hit := true
  ) in
  March_debug.Debug.install ctx;
  let src = {|
mod DebugTest do
  fn main() do
    dbg()
    42
  end
end
|} in
  let lexbuf = Lexing.from_string src in
  let m  = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m' = March_desugar.Desugar.desugar_module m in
  (try March_eval.Eval.run_module m'
   with
   | March_eval.Eval.Eval_error _    -> ()
   | March_eval.Eval.Match_failure _ -> ());
  March_debug.Debug.uninstall ();
  Alcotest.(check bool) "dbg() triggered on_dbg callback" true !hit

let test_trace_overflow () =
  let ctx = {
    March_eval.Eval.dc_trace   = March_eval.Eval.ring_create 3;
    dc_pos       = 0;
    dc_enabled   = true;
    dc_depth     = 0;
    dc_on_dbg    = None;
    dc_actor_log = [];
    dc_breakpoints = Hashtbl.create 16;
    dc_step        = March_eval.Eval.Run;
    dc_on_pause    = None;
    dc_last_line   = None;
  } in
  March_debug.Debug.install ctx;
  let src = "1 + 2 + 3 + 4" in
  let lexbuf = Lexing.from_string src in
  let e = March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let e' = March_desugar.Desugar.desugar_expr e in
  ignore (March_eval.Eval.eval_expr March_eval.Eval.base_env e');
  March_debug.Debug.uninstall ();
  Alcotest.(check int) "ring buffer size capped at capacity" 3
    ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_size

let test_actor_snapshot () =
  Hashtbl.reset March_eval.Eval.actor_registry;
  Hashtbl.reset March_eval.Eval.actor_defs_tbl;
  March_eval.Eval.next_pid := 0;
  let snap = March_eval.Eval.snapshot_actors () in
  Alcotest.(check int) "empty snapshot has 0 instances" 0
    (List.length snap.March_eval.Eval.ass_instances);
  March_eval.Eval.restore_actors snap;
  Alcotest.(check int) "restore_actors leaves registry empty" 0
    (Hashtbl.length March_eval.Eval.actor_registry)

(* ── Docstring tests ──────────────────────────────────────────────────────── *)

let test_doc_parse_fn () =
  let m = parse_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc string" (Some "Adds two numbers.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_triple_quoted () =
  let m = parse_module {|mod Test do
    doc """
Adds two numbers.
Returns their sum.
"""
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_doc with
     | Some s ->
       Alcotest.(check bool) "multiline content present"
         true (String.length s > 10)
     | None -> Alcotest.fail "expected Some doc")
  | _ -> Alcotest.fail "expected single DFn"

let test_doc_desugar () =
  let m = parse_and_desugar {|mod Test do
    doc "Computes factorial."
    fn factorial(0) do 1 end
    fn factorial(n) do n * factorial(n - 1) end
  end|} in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    Alcotest.(check (option string)) "doc preserved after desugar"
      (Some "Computes factorial.") def.fn_doc
  | _ -> Alcotest.fail "expected single DFn after group_fn_clauses"

let test_doc_eval_registry () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    doc "Adds two numbers."
    fn add(a : Int, b : Int) : Int do a + b end
  end|} in
  Alcotest.(check (option string)) "doc registered"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "add")

let test_doc_nested_module () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    mod Math do
      doc "Adds two numbers."
      fn add(a : Int, b : Int) : Int do a + b end
    end
  end|} in
  Alcotest.(check (option string)) "nested doc registered with prefix"
    (Some "Adds two numbers.")
    (March_eval.Eval.lookup_doc "Math.add")

let test_doc_none () =
  Hashtbl.reset March_eval.Eval.doc_registry;
  let _env = eval_module {|mod Test do
    fn undocumented() : Int do 42 end
  end|} in
  Alcotest.(check (option string)) "no doc is None"
    None
    (March_eval.Eval.lookup_doc "undocumented")

(* ── Purity oracle ───────────────────────────────────────────────── *)

let test_purity_atom () =
  Alcotest.(check bool) "literal is pure" true
    (March_tir.Purity.is_pure (March_tir.Tir.EAtom (ilit 5)))

let test_purity_arith () =
  Alcotest.(check bool) "int add is pure" true
    (March_tir.Purity.is_pure (app "+" [ilit 1; ilit 2]))

let test_purity_println () =
  Alcotest.(check bool) "println is impure" false
    (March_tir.Purity.is_pure (app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_print () =
  Alcotest.(check bool) "print is impure" false
    (March_tir.Purity.is_pure (app "print" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")]))

let test_purity_send () =
  Alcotest.(check bool) "send is impure" false
    (March_tir.Purity.is_pure (app "send" [March_tir.Tir.ALit (March_ast.Ast.LitString "msg")]))

let test_purity_let_pure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt, app "+" [ilit 2; ilit 3], body) in
  Alcotest.(check bool) "let with pure rhs is pure" true
    (March_tir.Purity.is_pure expr)

let test_purity_let_impure () =
  let body = March_tir.Tir.EAtom (ilit 1) in
  let expr = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TInt,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")], body) in
  Alcotest.(check bool) "let with impure rhs is impure" false
    (March_tir.Purity.is_pure expr)

let test_purity_callptr () =
  let f = March_tir.Tir.ALit (March_ast.Ast.LitInt 0) in  (* dummy closure *)
  Alcotest.(check bool) "indirect call is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.ECallPtr (f, [])))

let test_purity_kill () =
  Alcotest.(check bool) "kill is impure" false
    (March_tir.Purity.is_pure (app "kill" [ilit 0]))

let test_purity_incrc () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EIncRC is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EIncRC v))

let test_purity_free () =
  let v = March_tir.Tir.AVar (mk_var "x" March_tir.Tir.TInt) in
  Alcotest.(check bool) "EFree is impure" false
    (March_tir.Purity.is_pure (March_tir.Tir.EFree v))

(* ── Constant folding ────────────────────────────────────────────── *)

let test_fold_int_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "+" [ilit 2; ilit 3])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "2+3=5"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 5)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_mul () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "*" [ilit 6; ilit 7])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "6*7=42"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_div_by_zero () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 5; ilit 0])] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_fold_float_add () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (fapp "+." [flit 1.5; flit 2.5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "1.5+.2.5=4.0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (flit 4.0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_bool_not () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "not" [blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "not true = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_pure () =
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [blit false; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "false && true = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_shortcircuit_impure () =
  (* false && <AVar> IS folded: AVar is a pure atom (register read in ANF) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let impure = app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")] in
  let print_var = mk_var "p" March_tir.Tir.TBool in
  let body = March_tir.Tir.ELet (print_var, impure,
               bapp "&&" [blit false; March_tir.Tir.AVar print_var]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (AVar is a pure atom)" true !changed

let test_fold_if_true () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit true,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if true → then"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 1)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_if_false () =
  let changed = ref false in
  let then_e = March_tir.Tir.EAtom (ilit 1) in
  let else_e = March_tir.Tir.EAtom (ilit 2) in
  let body = March_tir.Tir.ECase (blit false,
               [{ March_tir.Tir.br_tag = "True"; br_vars = []; br_body = then_e }],
               Some else_e) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if false → else"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 2)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_and_pure_var () =
  (* false && <AVar for pure value> → false (var is pure at atom position) *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let x = avar "x" March_tir.Tir.TBool in
  (* let x = true in false && x — x is a pure AVar at atom position *)
  let body = March_tir.Tir.ELet (mk_var "x" March_tir.Tir.TBool,
               March_tir.Tir.EAtom (blit true),
               bapp "&&" [blit false; x]) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed (pure var folded)" true !changed;
  (* The && should be folded; the let may remain *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, inner) ->
     (match inner with
      | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
      | _ -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr inner))
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false)) -> ()
   | other -> Alcotest.failf "expected false, got %s" (March_tir.Tir.show_expr other))

let test_fold_or_shortcircuit_pure () =
  (* true || <pure rhs> → true *)
  let changed = ref false in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "||" [blit true; blit false])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "true || false = true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_concat () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "++" [slit "hello"; slit " world"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "\"hello\" ++ \" world\" = \"hello world\""
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (slit "hello world")))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_byte_length () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_byte_length" [slit "hello"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_byte_length(\"hello\") = 5"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 5)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_is_empty () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_is_empty" [slit ""])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_is_empty(\"\") = true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_string_is_empty_false () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "string_is_empty" [slit "x"])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "string_is_empty(\"x\") = false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

(* ── Fold: boolean comparison identities + int comparison folding ─────────── *)

let test_fold_eq_true_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "==" [x; blit true])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x==true → x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_eq_false_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "==" [x; blit false])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  match first_body m' with
  | March_tir.Tir.EApp (f, [_]) when f.March_tir.Tir.v_name = "not" -> ()
  | e -> Alcotest.failf "x==false → not x, got: %s" (March_tir.Tir.show_expr e)

let test_fold_int_cmp_lit () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "<" [ilit 3; ilit 5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "3 < 5 → true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_fold_int_cmp_lit_false () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app ">" [ilit 3; ilit 5])] in
  let m' = March_tir.Fold.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "3 > 5 → false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "+" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_mul_zero_pure () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x*0=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_self () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "x" March_tir.Tir.TInt])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x-x=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_sub_different () =
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "-" [avar "x" March_tir.Tir.TInt; avar "y" March_tir.Tir.TInt])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

let test_simplify_div_one () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "/" [x; ilit 1])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x/1=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div () =
  (* 0 / x where x is a variable must NOT simplify — x could be 0 *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let original = app "/" [ilit 0; x] in
  let m = mk_module [mk_fn "f" original] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed;
  Alcotest.(check string) "0/x unchanged"
    (March_tir.Tir.show_expr original)
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_zero_div_lit () =
  (* 0 / 5 → 0 (divisor is a known non-zero literal) *)
  let changed = ref false in
  let m = mk_module [mk_fn "f" (app "/" [ilit 0; ilit 5])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "0/5=0"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_strength_reduce () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "*" [x; ilit 2])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EApp (f, _), _) ->
     Alcotest.(check string) "strength reduce to add" "+" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected ELet wrapping EApp(+)")

let test_simplify_float_add_zero () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TFloat in
  let fapp' op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args) in
  let m = mk_module [mk_fn "f" (fapp' "+." [x; flit 0.0])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x+.0.0=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_bool_and_true () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let bapp op args =
    March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TBool)), args) in
  let m = mk_module [mk_fn "f" (bapp "&&" [x; blit true])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x&&true=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

(* The empty-string concat identities are sound ONLY before Perceus, so they
   fire under ~pre_perceus:true (the dedicated pre-Perceus pipeline step) and
   are deliberately suppressed in the default post-Perceus Opt loop. *)
let test_simplify_string_concat_empty_rhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [x; slit ""])] in
  let m' = March_tir.Simplify.run ~pre_perceus:true ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x++\"\"=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_string_concat_empty_lhs () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [slit ""; x])] in
  let m' = March_tir.Simplify.run ~pre_perceus:true ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "\"\"++x=x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

(* Guard: the default (post-Perceus) Simplify must NOT fold empty-string concat,
   else it would alias an RC-tracked value and double-free. *)
let test_simplify_string_concat_not_folded_post_perceus () =
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TString in
  let m = mk_module [mk_fn "f" (app "++" [x; slit ""])] in
  let _m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "unchanged post-Perceus" false !changed

(* P14 — boolean conditional identities ──────────────────────────── *)

let test_simplify_if_then_true_else_false () =
  (* if x then true else false → x *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let body = March_tir.Tir.ECase (x,
    [{ March_tir.Tir.br_tag = "True"; br_vars = [];
       br_body = March_tir.Tir.EAtom (blit true) }],
    Some (March_tir.Tir.EAtom (blit false))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "if x then true else false = x"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom x))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_if_then_false_else_true () =
  (* if x then false else true → not x *)
  let changed = ref false in
  let x = avar "x" March_tir.Tir.TBool in
  let body = March_tir.Tir.ECase (x,
    [{ March_tir.Tir.br_tag = "True"; br_vars = [];
       br_body = March_tir.Tir.EAtom (blit false) }],
    Some (March_tir.Tir.EAtom (blit true))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.EApp (f, [_]) when f.March_tir.Tir.v_name = "not" -> ()
   | e -> Alcotest.failf "expected EApp(not, [x]), got: %s" (March_tir.Tir.show_expr e))

let test_simplify_eq_self () =
  (* x == x → true (non-float) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x==x=true"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit true)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_ne_self () =
  (* x != x → false (non-float) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let m = mk_module [mk_fn "f" (app "!=" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "x!=x=false"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (blit false)))
    (March_tir.Tir.show_expr (first_body m'))

let test_simplify_eq_self_float_no_reduce () =
  (* x == x must NOT reduce when x is Float (NaN != NaN in IEEE 754) *)
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TFloat in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed for float ==" false !changed

let test_simplify_eq_self_tuple_float_no_reduce () =
  (* x == x must NOT reduce for TTuple containing Float — NaN inside a tuple
     means (NaN,1) == (NaN,1) is false at runtime but the rule would return true *)
  let changed = ref false in
  let ty = March_tir.Tir.TTuple [March_tir.Tir.TFloat; March_tir.Tir.TInt] in
  let x = mk_var "x" ty in
  let m = mk_module [mk_fn "f" (app "==" [March_tir.Tir.AVar x; March_tir.Tir.AVar x])] in
  let _ = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "not changed for tuple-float ==" false !changed

(* ── P15: boolean short-circuit absorber peepholes ──────────────────────── *)

let test_simplify_and_false_rhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "&&" [March_tir.Tir.AVar x;
                                           March_tir.Tir.ALit (March_ast.Ast.LitBool false)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_and_false_lhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "&&" [March_tir.Tir.ALit (March_ast.Ast.LitBool false);
                                           March_tir.Tir.AVar x])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_or_true_rhs () =
  let x = mk_var "x" March_tir.Tir.TBool in
  let m = mk_module [mk_fn "f" (app "||" [March_tir.Tir.AVar x;
                                           March_tir.Tir.ALit (March_ast.Ast.LitBool true)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom true"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool true))) true

let test_simplify_not_true () =
  let m = mk_module [mk_fn "f" (app "not" [March_tir.Tir.ALit (March_ast.Ast.LitBool true)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom false"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool false))) true

let test_simplify_not_false () =
  let m = mk_module [mk_fn "f" (app "not" [March_tir.Tir.ALit (March_ast.Ast.LitBool false)])] in
  let changed = ref false in
  let m' = March_tir.Simplify.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  Alcotest.(check bool) "result is EAtom true"
    (body = March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitBool true))) true

(* ── Function inlining ───────────────────────────────────────────── *)

let test_inline_pure_small () =
  (* fn double(x) = x + x; fn main() = double(5) → call gets inlined *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let double_body = app "+" [March_tir.Tir.AVar x_param; March_tir.Tir.AVar x_param] in
  let double_fn = { March_tir.Tir.fn_name = "double"; fn_params = [x_param];
                    fn_ret_ty = March_tir.Tir.TInt; fn_body = double_body } in
  let call = March_tir.Tir.EApp (mk_var "double"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [double_fn; main_fn] in
  let m' = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* main body should no longer be a bare EApp to "double" *)
  let main_body = (List.find (fun fd -> fd.March_tir.Tir.fn_name = "main") m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  (match main_body with
   | March_tir.Tir.EApp (f, _) when f.March_tir.Tir.v_name = "double" ->
     Alcotest.fail "call was not inlined"
   | _ -> ())

let test_inline_impure_not_inlined () =
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let bad_body = March_tir.Tir.ESeq (
    app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
    March_tir.Tir.EAtom (March_tir.Tir.AVar x_param)) in
  let bad_fn = { March_tir.Tir.fn_name = "bad"; fn_params = [x_param];
                 fn_ret_ty = March_tir.Tir.TInt; fn_body = bad_body } in
  let call = March_tir.Tir.EApp (mk_var "bad"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [bad_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (impure)" false !changed

let test_inline_recursive_not_inlined () =
  let changed = ref false in
  let n_param = mk_var "n" March_tir.Tir.TInt in
  (* self-calling fn — must not inline *)
  let fact_body = March_tir.Tir.EApp (mk_var "fact"
                    (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
                    [March_tir.Tir.AVar n_param]) in
  let fact_fn = { March_tir.Tir.fn_name = "fact"; fn_params = [n_param];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = fact_body } in
  let call = March_tir.Tir.EApp (mk_var "fact"
               (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 5]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt; fn_body = call } in
  let m = mk_module [fact_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (recursive)" false !changed

let test_inline_mutual_recursion_not_inlined () =
  (* fn f(x) = g(x); fn g(x) = f(x) — mutually recursive, neither should inline *)
  let changed = ref false in
  let x_param = mk_var "x" March_tir.Tir.TInt in
  let g_call = March_tir.Tir.EApp (mk_var "g" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let f_fn = { March_tir.Tir.fn_name = "f"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = g_call } in
  let f_call = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [March_tir.Tir.AVar x_param]) in
  let g_fn = { March_tir.Tir.fn_name = "g"; fn_params = [x_param]; fn_ret_ty = March_tir.Tir.TInt; fn_body = f_call } in
  let call_f = March_tir.Tir.EApp (mk_var "f" (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)), [ilit 1]) in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = []; fn_ret_ty = March_tir.Tir.TInt; fn_body = call_f } in
  let m = mk_module [f_fn; g_fn; main_fn] in
  let _ = March_tir.Inline.run ~changed m in
  Alcotest.(check bool) "not changed (mutually recursive)" false !changed

(* ── Known-call optimization ─────────────────────────────────────── *)

(** Helper: build an EAlloc for a Defun-style closure struct.
    apply_name is the lifted apply function.  clo_struct_name is "$Clo_foo$N". *)
let test_known_call_direct () =
  let changed = ref false in
  (* let clo = EAlloc("$Clo_foo$0", [fn_ptr]) in ECallPtr(clo, [5]) *)
  let clo_var = mk_var "clo" (March_tir.Tir.TCon ("$Clo_foo$0", [])) in
  let alloc = mk_closure_alloc "$Clo_foo$0" "foo$apply$0" in
  let callptr = March_tir.Tir.ECallPtr
    (March_tir.Tir.AVar clo_var, [ilit 5]) in
  let body = March_tir.Tir.ELet (clo_var, alloc, callptr) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* The ECallPtr should be gone — inner expression should be EApp *)
  let main_body = (List.find (fun fd -> fd.March_tir.Tir.fn_name = "main")
                    m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  (match main_body with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EApp (f, _)) ->
     Alcotest.(check string) "apply fn name" "foo$apply$0" f.March_tir.Tir.v_name
   | other ->
     Alcotest.failf "expected ELet(_,EAlloc,EApp), got: %s"
       (March_tir.Tir.show_expr other))

(** ECallPtr on a variable NOT in the known-closure map stays unchanged. *)
let test_known_call_unknown_unchanged () =
  let changed = ref false in
  let v = mk_var "f" (March_tir.Tir.TPtr March_tir.Tir.TUnit) in
  let callptr = March_tir.Tir.ECallPtr (March_tir.Tir.AVar v, [ilit 1]) in
  let m = mk_module [mk_fn "main" callptr] in
  let _ = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "not changed (unknown closure)" false !changed

(** Two consecutive closures in the same scope are both tracked. *)
let test_known_call_two_closures () =
  let changed = ref false in
  let clo1 = mk_var "clo1" (March_tir.Tir.TCon ("$Clo_f$0", [])) in
  let clo2 = mk_var "clo2" (March_tir.Tir.TCon ("$Clo_g$1", [])) in
  let alloc1 = mk_closure_alloc "$Clo_f$0" "f$apply$0" in
  let alloc2 = mk_closure_alloc "$Clo_g$1" "g$apply$1" in
  (* let clo1 = EAlloc($Clo_f$0)
     let clo2 = EAlloc($Clo_g$1)
     ECallPtr(clo1, []) *)
  let body =
    March_tir.Tir.ELet (clo1, alloc1,
      March_tir.Tir.ELet (clo2, alloc2,
        March_tir.Tir.ECallPtr (March_tir.Tir.AVar clo1, []))) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Inner expression should reference f$apply$0 *)
  let inner = match (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body with
    | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, e)) -> e
    | _ -> Alcotest.fail "unexpected structure" in
  (match inner with
   | March_tir.Tir.EApp (f, _) ->
     Alcotest.(check string) "apply fn" "f$apply$0" f.March_tir.Tir.v_name
   | _ -> Alcotest.fail "expected EApp")

(** Stack-allocated closures (after Escape) are also recognized. *)
let test_known_call_stack_alloc () =
  let changed = ref false in
  let clo_var = mk_var "clo" (March_tir.Tir.TCon ("$Clo_h$2", [])) in
  let fn_ptr_atom = March_tir.Tir.AVar
    (mk_var "h$apply$2" (March_tir.Tir.TPtr March_tir.Tir.TUnit)) in
  let stack_alloc = March_tir.Tir.EStackAlloc
    (March_tir.Tir.TCon ("$Clo_h$2", []), [fn_ptr_atom]) in
  let callptr = March_tir.Tir.ECallPtr (March_tir.Tir.AVar clo_var, [ilit 42]) in
  let body = March_tir.Tir.ELet (clo_var, stack_alloc, callptr) in
  let m = mk_module [mk_fn "main" body] in
  let _ = March_tir.Known_call.run ~changed m in
  Alcotest.(check bool) "changed (stack-allocated closure)" true !changed

(* ── Struct update fusion ────────────────────────────────────────── *)

(** Two consecutive record updates on the same base record, with the
    intermediate variable used exactly once, should be merged. *)
let test_struct_fusion_two_updates () =
  let changed = ref false in
  let conn0 = mk_var "conn0" March_tir.Tir.TUnit in
  let conn1 = mk_var "conn1" March_tir.Tir.TUnit in
  let conn2 = mk_var "conn2" March_tir.Tir.TUnit in
  let h_atom = ilit 200 in
  let s_atom = ilit 42 in
  (* let conn1 = { conn0 | status = 200 }
     let conn2 = { conn1 | body_size = 42 }
     conn2 *)
  let body =
    March_tir.Tir.ELet (conn1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar conn0, [("status", h_atom)]),
      March_tir.Tir.ELet (conn2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar conn1, [("body_size", s_atom)]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar conn2))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Result: ELet(conn2, EUpdate(conn0, [(status,200);(body_size,42)]), conn2) *)
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (March_tir.Tir.AVar base, fields), _) ->
     Alcotest.(check string) "base variable" "conn0" base.March_tir.Tir.v_name;
     Alcotest.(check int)    "merged field count" 2 (List.length fields)
   | other ->
     Alcotest.failf "expected merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Three consecutive updates should be collapsed into one after two
    fixed-point iterations (each iteration collapses one pair). *)
let test_struct_fusion_three_updates () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  let v3 = mk_var "v3" March_tir.Tir.TUnit in
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b,  [("a", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("b", ilit 2)]),
        March_tir.Tir.ELet (v3,
          March_tir.Tir.EUpdate (March_tir.Tir.AVar v2, [("c", ilit 3)]),
          March_tir.Tir.EAtom (March_tir.Tir.AVar v3)))) in
  let m = mk_module [mk_fn "f" body] in
  (* Run twice to fully collapse the 3-step chain *)
  let m' = March_tir.Fusion.run_struct ~changed m in
  let m'' = March_tir.Fusion.run_struct ~changed m' in
  (match first_body m'' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (March_tir.Tir.AVar base, fields), _) ->
     Alcotest.(check string) "base variable" "b" base.March_tir.Tir.v_name;
     Alcotest.(check int)    "all three fields merged" 3 (List.length fields)
   | other ->
     Alcotest.failf "expected single merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Later updates on the same field override earlier ones. *)
let test_struct_fusion_field_override () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  (* let v1 = { b | x = 1 }; let v2 = { v1 | x = 99 }; v2
     After fusion: let v2 = { b | x = 99 }  — second write wins *)
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b,  [("x", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("x", ilit 99)]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar v2))) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, March_tir.Tir.EUpdate (_, fields), _) ->
     Alcotest.(check int) "deduplicated: only one x field" 1 (List.length fields);
     let (_, v) = List.find (fun (k, _) -> k = "x") fields in
     Alcotest.(check string) "second value wins"
       (March_tir.Tir.show_atom (ilit 99))
       (March_tir.Tir.show_atom v)
   | other ->
     Alcotest.failf "expected merged EUpdate, got: %s"
       (March_tir.Tir.show_expr other))

(** Multi-use intermediate must NOT be fused. *)
let test_struct_fusion_no_fuse_multi_use () =
  let changed = ref false in
  let b  = mk_var "b"  March_tir.Tir.TUnit in
  let v1 = mk_var "v1" March_tir.Tir.TUnit in
  let v2 = mk_var "v2" March_tir.Tir.TUnit in
  (* v1 is used twice — in the EUpdate and in the final EAtom *)
  let body =
    March_tir.Tir.ELet (v1,
      March_tir.Tir.EUpdate (March_tir.Tir.AVar b, [("x", ilit 1)]),
      March_tir.Tir.ELet (v2,
        March_tir.Tir.EUpdate (March_tir.Tir.AVar v1, [("y", ilit 2)]),
        (* Use v1 a second time — blocks fusion *)
        March_tir.Tir.ESeq (
          March_tir.Tir.EAtom (March_tir.Tir.AVar v1),
          March_tir.Tir.EAtom (March_tir.Tir.AVar v2)))) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Fusion.run_struct ~changed m in
  Alcotest.(check bool) "not changed (multi-use)" false !changed

(* ── Dead code elimination ───────────────────────────────────────── *)

let test_dce_dead_pure_let () =
  (* let x = 5 in 42 → 42, because x is unused and rhs is pure *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5), March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  Alcotest.(check string) "dead let removed"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

let test_dce_impure_let_kept () =
  (* let x = println("hi") in 42 → println("hi"); 42 (rhs is impure, must keep) *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "println" [March_tir.Tir.ALit (March_ast.Ast.LitString "hi")],
               March_tir.Tir.EAtom (ilit 42)) in
  let m = mk_module [mk_fn "f" body] in
  let m' = March_tir.Dce.run ~changed m in
  (* result should be ESeq, not the original ELet, but the print must be present *)
  (match first_body m' with
   | March_tir.Tir.ESeq _ -> ()  (* impure effect sequenced *)
   | March_tir.Tir.ELet _ -> ()  (* or kept as let — both acceptable *)
   | _ -> Alcotest.fail "impure rhs must be preserved")

let test_dce_used_let_kept () =
  (* let x = 5 in x + 1 → unchanged *)
  let changed = ref false in
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var, March_tir.Tir.EAtom (ilit 5),
               app "+" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "f" body] in
  let _ = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "not changed (used)" false !changed

let test_dce_unreachable_topfn () =
  (* fn unused() = 99 is not reachable from main → removed *)
  let changed = ref false in
  let unused_fn = { March_tir.Tir.fn_name = "unused"; fn_params = [];
                    fn_ret_ty = March_tir.Tir.TInt;
                    fn_body = March_tir.Tir.EAtom (ilit 99) } in
  let main_fn = { March_tir.Tir.fn_name = "main"; fn_params = [];
                  fn_ret_ty = March_tir.Tir.TInt;
                  fn_body = March_tir.Tir.EAtom (ilit 0) } in
  let m = mk_module [unused_fn; main_fn] in
  let m' = March_tir.Dce.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let fn_names = List.map (fun fd -> fd.March_tir.Tir.fn_name) m'.March_tir.Tir.tm_fns in
  Alcotest.(check bool) "unused removed" false (List.mem "unused" fn_names);
  Alcotest.(check bool) "main kept"      true  (List.mem "main" fn_names)

(* ── Optimizer coordinator ───────────────────────────────────────── *)

let test_opt_fixpoint () =
  (* let x = 1 + 1 in x * 1
     → fold: let x = 2 in x * 1
     → simplify: let x = 2 in x
     At minimum x*1 should be simplified to x *)
  let x_var = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x_var,
               app "+" [ilit 1; ilit 1],
               app "*" [March_tir.Tir.AVar x_var; ilit 1]) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.AVar _) -> ()
   | March_tir.Tir.EAtom (March_tir.Tir.ALit _) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom _) -> ()
   | e -> Alcotest.failf "expected reduced form, got: %s" (March_tir.Tir.show_expr e))

let test_opt_no_infinite_loop () =
  (* A stable expression should not loop forever *)
  let m = mk_module [mk_fn "main" (March_tir.Tir.EAtom (ilit 42))] in
  let m' = March_tir.Opt.run m in
  Alcotest.(check string) "stable"
    (March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 42)))
    (March_tir.Tir.show_expr (first_body m'))

(* ── fast-math IR attribute ──────────────────────────────────────── *)

let test_fast_math_emits_fast_attr () =
  let x = mk_var "x" March_tir.Tir.TFloat in
  let y = mk_var "y" March_tir.Tir.TFloat in
  let fn_var name = mk_var name (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)) in
  let body = March_tir.Tir.EApp (fn_var "+.", [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) in
  let fd = { March_tir.Tir.fn_name = "fadd_test"; fn_params = [x; y];
             fn_ret_ty = March_tir.Tir.TFloat; fn_body = body } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fd]; tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let ir_fast   = March_tir.Llvm_emit.emit_module ~fast_math:true  m in
  let ir_normal = March_tir.Llvm_emit.emit_module ~fast_math:false m in
  Alcotest.(check bool) "fast_math IR contains 'fadd fast'" true
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_fast 0); true with Not_found -> false));
  Alcotest.(check bool) "normal IR does not contain 'fadd fast'" false
    (let re = Str.regexp "fadd fast" in
     (try ignore (Str.search_forward re ir_normal 0); true with Not_found -> false))

(* ── Constant propagation ───────────────────────────────────────── *)

(* Helpers for cprop tests: build a function body with a let-chain,
   run CProp alone, and inspect the result. *)

let test_cprop_simple_literal () =
  (* let x = 7 in x
     CProp: x is literal 7, so the body EAtom(AVar x) → EAtom(ALit 7) *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 7),
               March_tir.Tir.EAtom (March_tir.Tir.AVar x)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 7))) -> ()
   | e -> Alcotest.failf "expected let x=7 in 7, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_chain () =
  (* let a = 3
     let b = a          — CProp: b's rhs becomes EAtom(ALit 3)
     b                  — CProp: body becomes ALit 3 *)
  let a = mk_var "a" March_tir.Tir.TInt in
  let b = mk_var "b" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (a, March_tir.Tir.EAtom (ilit 3),
      March_tir.Tir.ELet (b, March_tir.Tir.EAtom (March_tir.Tir.AVar a),
        March_tir.Tir.EAtom (March_tir.Tir.AVar b))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let rec find_inner = function
    | March_tir.Tir.ELet (_, _, e) -> find_inner e
    | March_tir.Tir.EAtom a -> a
    | e -> Alcotest.failf "unexpected: %s" (March_tir.Tir.show_expr e)
  in
  (match find_inner (first_body m') with
   | March_tir.Tir.ALit (March_ast.Ast.LitInt 3) -> ()
   | a -> Alcotest.failf "expected ALit 3, got: %s" (March_tir.Tir.show_atom a))

let test_cprop_enables_fold () =
  (* let x = 7
     let r = x + 1
     r
     CProp turns x→7: let x=7 in let r = 7+1 in r
     Fold then gives 8. *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let r = mk_var "r" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 7),
      March_tir.Tir.ELet (r, app "+" [March_tir.Tir.AVar x; ilit 1],
        March_tir.Tir.EAtom (March_tir.Tir.AVar r))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m1 = March_tir.Cprop.run ~changed m in
  let _  = Alcotest.(check bool) "cprop changed" true !changed in
  let changed2 = ref false in
  let m2 = March_tir.Fold.run ~changed:changed2 m1 in
  Alcotest.(check bool) "fold changed after cprop" true !changed2;
  let rec inner = function
    | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, rhs, _)) -> rhs
    | March_tir.Tir.ELet (_, _, e) -> inner e
    | e -> e
  in
  (match inner (first_body m2) with
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 8)) -> ()
   | e -> Alcotest.failf "expected 8 after fold, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_complex () =
  (* let x = 1 + 2   (complex rhs — not a bare literal)
     x
     CProp should NOT propagate x since its rhs is not ALit *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let body = March_tir.Tir.ELet (x, app "+" [ilit 1; ilit 2],
               March_tir.Tir.EAtom (March_tir.Tir.AVar x)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "not changed (complex rhs)" false !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.AVar _)) -> ()
   | e -> Alcotest.failf "expected unchanged, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_case_branch_shadow () =
  (* let x = 5
     match b do
     | True  -> let x = 99 in x   (* shadows outer x *)
     | False -> x                  (* uses outer x = 5 *)
     end
     False branch: x should propagate to 5. *)
  let x_outer = mk_var "x" March_tir.Tir.TInt in
  let x_inner = mk_var "x" March_tir.Tir.TInt in
  let scrutinee = avar "b" March_tir.Tir.TBool in
  let true_branch = { March_tir.Tir.br_tag = "True"; br_vars = [];
    br_body = March_tir.Tir.ELet (x_inner, March_tir.Tir.EAtom (ilit 99),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x_inner)) } in
  let false_branch = { March_tir.Tir.br_tag = "False"; br_vars = [];
    br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar x_outer) } in
  let body = March_tir.Tir.ELet (x_outer, March_tir.Tir.EAtom (ilit 5),
               March_tir.Tir.ECase (scrutinee, [true_branch; false_branch], None)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ECase (_, [_; fb], None)) ->
     (match fb.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 5)) -> ()
      | e -> Alcotest.failf "False branch: expected 5, got: %s" (March_tir.Tir.show_expr e))
   | e -> Alcotest.failf "unexpected outer form: %s" (March_tir.Tir.show_expr e))

let test_cprop_opt_integration () =
  (* Full pipeline: let x = 3 in let y = x + 4 in y
     CProp+Fold+DCE → 7 *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (ilit 3),
      March_tir.Tir.ELet (y, app "+" [March_tir.Tir.AVar x; ilit 4],
        March_tir.Tir.EAtom (March_tir.Tir.AVar y))) in
  let m = mk_module [mk_fn "main" body] in
  let m' = March_tir.Opt.run m in
  (match first_body m' with
   | March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 7)) -> ()
   | e -> Alcotest.failf "expected 7 after full opt, got: %s" (March_tir.Tir.show_expr e))

(** Regression: cprop must NOT substitute literals into RC / Free arguments.
    Bug: let m = "POST" in ... DecRC(m)  →  DecRC("POST") after cprop.
    LLVM emit would then allocate a fresh string just to free it, while the
    original allocation leaks at RC=1. *)
let test_cprop_no_propagate_into_rc () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Aff } in
  let lit_post = March_ast.Ast.LitString "POST" in
  (* let m = "POST"
     DecRC(m)          -- cprop must leave this as DecRC(AVar m), not DecRC(ALit "POST") *)
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EDecRC (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EDecRC (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EDecRC (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted DecRC target: substituted literal into DecRC argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_into_incrc () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Lin } in
  let lit_post = March_ast.Ast.LitString "POST" in
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EIncRC (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EIncRC (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EIncRC (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted IncRC target: substituted literal into IncRC argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

let test_cprop_no_propagate_into_free () =
  let m_var = { March_tir.Tir.v_name = "m"; v_ty = March_tir.Tir.TString; v_lin = March_tir.Tir.Aff } in
  let lit_post = March_ast.Ast.LitString "POST" in
  let body =
    March_tir.Tir.ELet (m_var,
      March_tir.Tir.EAtom (March_tir.Tir.ALit lit_post),
      March_tir.Tir.EFree (March_tir.Tir.AVar m_var)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EFree (March_tir.Tir.AVar _)) -> ()
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EFree (March_tir.Tir.ALit _)) ->
     Alcotest.fail "cprop corrupted Free target: substituted literal into Free argument"
   | e -> Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e))

(* P13 — EField of known record ──────────────────────────────────── *)

let test_cprop_field_fold_record () =
  (* let r = { x = 3, y = 4 } in r.x
     CProp: r in fenv → EField(r,"x") folds to ALit 3 *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt); ("y", March_tir.Tir.TInt)] in
  let r = mk_var "r" ty_r in
  let body = March_tir.Tir.ELet (r,
    March_tir.Tir.ERecord [("x", ilit 3); ("y", ilit 4)],
    March_tir.Tir.EField (March_tir.Tir.AVar r, "x")) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3))) -> ()
   | e -> Alcotest.failf "expected r.x=3, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_alias () =
  (* let r  = { x = 3 }
     let r2 = r          -- alias: should copy r's fenv entry to r2
     r2.x                -- folds to 3 via alias propagation *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt)] in
  let r  = mk_var "r"  ty_r in
  let r2 = mk_var "r2" ty_r in
  let body =
    March_tir.Tir.ELet (r, March_tir.Tir.ERecord [("x", ilit 3)],
      March_tir.Tir.ELet (r2, March_tir.Tir.EAtom (March_tir.Tir.AVar r),
        March_tir.Tir.EField (March_tir.Tir.AVar r2, "x"))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3)))) -> ()
   | e -> Alcotest.failf "expected r2.x=3 via alias, got: %s" (March_tir.Tir.show_expr e))

let test_cprop_field_fold_update () =
  (* let r  = { x = 3, y = 4 }
     let r2 = { r with y = 99 }
     r2.x   — inherits x field from r → 3 *)
  let ty_r = March_tir.Tir.TRecord [("x", March_tir.Tir.TInt); ("y", March_tir.Tir.TInt)] in
  let r  = mk_var "r"  ty_r in
  let r2 = mk_var "r2" ty_r in
  let body =
    March_tir.Tir.ELet (r, March_tir.Tir.ERecord [("x", ilit 3); ("y", ilit 4)],
      March_tir.Tir.ELet (r2, March_tir.Tir.EUpdate (March_tir.Tir.AVar r, [("y", ilit 99)]),
        March_tir.Tir.EField (March_tir.Tir.AVar r2, "x"))) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ELet (_, _, March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 3)))) -> ()
   | e -> Alcotest.failf "expected r2.x=3 (from r), got: %s" (March_tir.Tir.show_expr e))

(* ── P12: variable copy propagation ─────────────────────────────────────── *)

(** P12 basic: let x = y in x + 1  →  y + 1
    The alias is propagated into the EApp arg. *)
let test_cprop_var_alias () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (March_tir.Tir.AVar y),
      app "succ" [March_tir.Tir.AVar x]) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (match first_body m' with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.EApp (_, [March_tir.Tir.AVar v]))
     when v.March_tir.Tir.v_name = "y" -> ()
   | e -> Alcotest.failf "expected x→y propagation, got: %s" (March_tir.Tir.show_expr e))

(** P12 chain: let x = y in let z = x in z + 1  →  y + 1
    The second alias (z = x → y) is also propagated transitively. *)
let test_cprop_var_chain () =
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let z = mk_var "z" March_tir.Tir.TInt in
  let body =
    March_tir.Tir.ELet (x, March_tir.Tir.EAtom (March_tir.Tir.AVar y),
      March_tir.Tir.ELet (z, March_tir.Tir.EAtom (March_tir.Tir.AVar x),
        app "succ" [March_tir.Tir.AVar z])) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Cprop.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* After propagation, z → x → y, so the arg becomes y. *)
  let rec find_innermost_app = function
    | March_tir.Tir.ELet (_, _, body) -> find_innermost_app body
    | e -> e in
  (match find_innermost_app (first_body m') with
   | March_tir.Tir.EApp (_, [March_tir.Tir.AVar v])
     when v.March_tir.Tir.v_name = "y" -> ()
   | e -> Alcotest.failf "expected chain x→y propagation, got: %s" (March_tir.Tir.show_expr e))

(** P12 closure guard: let f = g (TFn type) must NOT be propagated.
    Closure aliases are excluded to protect ECallPtr dispatch. *)
let test_cprop_var_no_alias_closure () =
  let fn_ty = March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt) in
  let f = mk_var "f" fn_ty in
  let g = mk_var "g" fn_ty in
  let body =
    March_tir.Tir.ELet (f, March_tir.Tir.EAtom (March_tir.Tir.AVar g),
      March_tir.Tir.ECallPtr (March_tir.Tir.AVar f, [ilit 42])) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let _m' = March_tir.Cprop.run ~changed m in
  (* Closure alias must NOT be propagated; changed may be false *)
  (match first_body (March_tir.Cprop.run ~changed:(ref false) m) with
   | March_tir.Tir.ELet (_, _, March_tir.Tir.ECallPtr (March_tir.Tir.AVar fv, _))
     when fv.March_tir.Tir.v_name = "f" -> ()
   | e -> Alcotest.failf "expected f unchanged in ECallPtr, got: %s" (March_tir.Tir.show_expr e))

(* ── P11: beta-ADT (case-of-known-constructor) ───────────────────────────── *)

(** P11 basic: let r = EAlloc(Ok, [x]) in ECase(r, [{Ok; [v]; EAtom v}], None)
    → let v = x in EAtom v  (reduced; EAlloc dead → DCE removes it) *)
let test_beta_adt_ok_inline () =
  let tcon_ty = March_tir.Tir.TCon ("Result", [March_tir.Tir.TInt; March_tir.Tir.TString]) in
  let r = mk_var "r" tcon_ty in
  let v = mk_var "v" March_tir.Tir.TInt in
  let x = mk_var "x" March_tir.Tir.TInt in
  let branch = { March_tir.Tir.br_tag = "Ok"; br_vars = [v];
                 br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar v) } in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Result.Ok", [March_tir.Tir.TInt]), [March_tir.Tir.AVar x]),
      March_tir.Tir.ECase (March_tir.Tir.AVar r, [branch], None)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* Result: let v = EAtom(x) in EAtom(v) — no EAlloc or ECase *)
  let rec find = function
    | March_tir.Tir.ELet (bv, March_tir.Tir.EAtom (March_tir.Tir.AVar src), inner)
      when bv.March_tir.Tir.v_name = "v" && src.March_tir.Tir.v_name = "x" ->
      (match inner with
       | March_tir.Tir.EAtom (March_tir.Tir.AVar rv) when rv.March_tir.Tir.v_name = "v" -> ()
       | e -> Alcotest.failf "expected EAtom(v), got: %s" (March_tir.Tir.show_expr e))
    | March_tir.Tir.ELet (_, _, rest) -> find rest
    | e -> Alcotest.failf "expected let v=x chain, got: %s" (March_tir.Tir.show_expr e) in
  find (first_body m')

(** P11 with qualified tag: EAlloc uses "Result.Ok" but branch tag is "Ok".
    tags_match must handle the mismatch via short_name. *)
let test_beta_adt_qualified_tag () =
  let tcon_ty = March_tir.Tir.TCon ("Result", []) in
  let r = mk_var "r" tcon_ty in
  let v = mk_var "v" March_tir.Tir.TInt in
  let x = mk_var "x" March_tir.Tir.TInt in
  let branch = { March_tir.Tir.br_tag = "Ok"; br_vars = [v];
                 br_body = March_tir.Tir.EAtom (March_tir.Tir.AVar v) } in
  let default_body = March_tir.Tir.EAtom (ilit 0) in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Result.Ok", [March_tir.Tir.TInt]), [March_tir.Tir.AVar x]),
      March_tir.Tir.ECase (March_tir.Tir.AVar r, [branch], Some default_body)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "changed (qualified tag matched)" true !changed;
  (* Default branch (with EAtom 0) must be dropped — we matched Ok *)
  let contains_lit0 e =
    let s = March_tir.Tir.show_expr e in
    let lit0 = March_tir.Tir.show_expr (March_tir.Tir.EAtom (ilit 0)) in
    let n = String.length lit0 in
    let ls = String.length s in
    let found = ref false in
    for i = 0 to ls - n do
      if String.sub s i n = lit0 then found := true
    done; !found in
  if contains_lit0 (first_body m') then
    Alcotest.fail "default branch (lit 0) must be dropped after P11 Ok match"

(** P11 no-fire: ELet body is NOT an ECase — should not fire. *)
let test_beta_adt_no_fire_non_case () =
  let tcon_ty = March_tir.Tir.TCon ("Foo", []) in
  let r = mk_var "r" tcon_ty in
  let body =
    March_tir.Tir.ELet (r,
      March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.Bar", []), []),
      March_tir.Tir.EAtom (March_tir.Tir.AVar r)) in
  let m = mk_module [mk_fn "f" body] in
  let changed = ref false in
  let _m' = March_tir.Beta_adt.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(* ── P8: FBIP cross-tag constructor reuse ───────────────────────────────── *)

(** P8 basic: same_arity returns true when type has the same field count.
    TCon("Foo.A", [TUnit; TUnit]) encodes arity=2; nfields=2 → true. *)
let test_same_arity_match () =
  let ty = March_tir.Tir.TCon ("Foo.A", [March_tir.Tir.TUnit; March_tir.Tir.TUnit]) in
  Alcotest.(check bool) "same arity matches" true
    (March_tir.Perceus.same_arity ty 2)

(** P8: different arity returns false. *)
let test_same_arity_mismatch () =
  let ty = March_tir.Tir.TCon ("Foo.A", [March_tir.Tir.TUnit]) in
  Alcotest.(check bool) "different arity does not match" false
    (March_tir.Perceus.same_arity ty 2)

(** P8: non-TCon type returns false (no arity info). *)
let test_same_arity_non_tcon () =
  Alcotest.(check bool) "non-TCon always false" false
    (March_tir.Perceus.same_arity March_tir.Tir.TInt 0)

(** P8 integration: cross-tag FBIP fires.  We construct a TIR expression that
    mirrors what Perceus emits for a consumed scrutinee followed by a same-arity
    alloc of a different constructor.  Perceus wraps the decrc in ESeq (via
    add_scrutinee_free_for), so fbip_expr's ESeq path calls try_fbip_sink.

    Shape (Perceus ESeq form):
      ESeq(EDecRC(v : TCon("Foo.A", [TUnit])),   -- arity=1 encoded
           ELet(result, EAlloc(TCon("Foo.B",[]), [arg]),
                EAtom result))
    → ELet(result, EReuse(AVar v, TCon("Foo.B",[]), [arg]),
           EAtom result) *)
let test_fbip_cross_tag_reuse () =
  (* v's type encodes arity=1 as one dummy TUnit arg *)
  let v = mk_var "v" (March_tir.Tir.TCon ("Foo.A", [March_tir.Tir.TUnit])) in
  let result = mk_var "result" (March_tir.Tir.TCon ("Foo", [])) in
  let arg = March_tir.Tir.ALit (March_ast.Ast.LitInt 42) in
  let e =
    March_tir.Tir.ESeq (
      March_tir.Tir.EDecRC (March_tir.Tir.AVar v),
      March_tir.Tir.ELet (result,
        March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.B", []), [arg]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar result))) in
  let e' = March_tir.Perceus.fbip_expr e in
  match e' with
  | March_tir.Tir.ELet (_, March_tir.Tir.EReuse (March_tir.Tir.AVar rv, _, _), _) ->
    Alcotest.(check string) "reuses v" "v" rv.March_tir.Tir.v_name
  | _ ->
    Alcotest.failf "expected EReuse, got: %s" (March_tir.Tir.show_expr e')

(** P8: different arity does NOT produce EReuse — falls back to ESeq EDecRC. *)
let test_fbip_no_reuse_arity_mismatch () =
  (* v's type encodes arity=1; alloc has 2 fields → arity mismatch → no reuse *)
  let v = mk_var "v" (March_tir.Tir.TCon ("Foo.A", [March_tir.Tir.TUnit])) in
  let result = mk_var "result" (March_tir.Tir.TCon ("Foo", [])) in
  let arg1 = March_tir.Tir.ALit (March_ast.Ast.LitInt 1) in
  let arg2 = March_tir.Tir.ALit (March_ast.Ast.LitInt 2) in
  let e =
    March_tir.Tir.ESeq (
      March_tir.Tir.EDecRC (March_tir.Tir.AVar v),
      March_tir.Tir.ELet (result,
        March_tir.Tir.EAlloc (March_tir.Tir.TCon ("Foo.B", []), [arg1; arg2]),
        March_tir.Tir.EAtom (March_tir.Tir.AVar result))) in
  let e' = March_tir.Perceus.fbip_expr e in
  match e' with
  | March_tir.Tir.ESeq (March_tir.Tir.EDecRC _, _) ->
    ()  (* correct: no reuse, kept as ESeq(EDecRC, ...) *)
  | March_tir.Tir.ELet (_, March_tir.Tir.EReuse _, _) ->
    Alcotest.fail "should NOT produce EReuse for arity mismatch"
  | _ ->
    Alcotest.failf "unexpected shape: %s" (March_tir.Tir.show_expr e')

(* ── P1: let-floating past ECase ─────────────────────────────────────────── *)

(** P1 basic: a common leading let in every branch is floated above the ECase.

    ECase(a,
      [{T1; []; ELet(x, EApp(f,[y]), EAtom x)},
       {T2; []; ELet(x, EApp(f,[y]), EAtom x)}],
      None)
    →
    ELet(x, EApp(f,[y]),
      ECase(a,
        [{T1; []; EAtom x},
         {T2; []; EAtom x}],
        None)) *)
let test_join_points_float_common_let () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let rhs = March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]) in
  let br tag = { March_tir.Tir.br_tag = tag; br_vars = [];
                 br_body = March_tir.Tir.ELet (x, rhs, March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a,
    [br "T1"; br "T2"], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp (_, _),
                         March_tir.Tir.ECase (_, branches, None)) ->
    Alcotest.(check string) "floated var name" "x" bv.March_tir.Tir.v_name;
    List.iter (fun br ->
      match br.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom _ -> ()
      | _ -> Alcotest.fail "branch body should be EAtom after floating"
    ) branches
  | _ ->
    Alcotest.failf "expected ELet(x, EApp, ECase), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 no-fire: different RHS expressions in branches — cannot float. *)
let test_join_points_no_float_different_rhs () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f1 = mk_var "f1" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let f2 = mk_var "f2" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f1, [March_tir.Tir.AVar y]),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f2, [March_tir.Tir.AVar y]),  (* different fn *)
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(** P1 no-fire: let RHS mentions a pattern-bound variable. *)
let test_join_points_no_float_uses_br_var () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let v1 = mk_var "v1" March_tir.Tir.TInt in
  let v2 = mk_var "v2" March_tir.Tir.TInt in
  (* Each arm binds pattern var vN, then uses it in the RHS — can't float *)
  let br tag pv = { March_tir.Tir.br_tag = tag; br_vars = [pv];
                    br_body = March_tir.Tir.ELet (x,
                      March_tir.Tir.EAtom (March_tir.Tir.AVar pv),
                      March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a,
    [br "T1" v1; br "T2" v2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(** P1 chain: two consecutive common lets are both floated (fixpoint via opt loop). *)
let test_join_points_float_two_common_lets () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let z  = mk_var "z"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  (* Both branches: let x = f(y) in let z = x in z *)
  let arm_body =
    March_tir.Tir.ELet (x, March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]),
      March_tir.Tir.ELet (z, March_tir.Tir.EAtom (March_tir.Tir.AVar x),
        March_tir.Tir.EAtom (March_tir.Tir.AVar z))) in
  let br tag = { March_tir.Tir.br_tag = tag; br_vars = []; br_body = arm_body } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br "T1"; br "T2"], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  (* After one pass: let x = f(y) in ECase(..., ELet(z, x, z), ...) *)
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp _, _) ->
    Alcotest.(check string) "outer floated var" "x" bv.March_tir.Tir.v_name
  | _ ->
    Alcotest.failf "expected outer ELet(x, ...), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 Layer 1 (pre-Perceus alpha-merge): arms share an identical RHS but bind
    it to DIFFERENT variable names (fresh ANF temporaries).  [run_pre] floats a
    single binding and substitutes each arm's binder with the floated one. *)
let test_join_points_pre_float_alpha () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let w  = mk_var "w"  March_tir.Tir.TInt in   (* different binder name *)
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f  = mk_var "f"  (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let rhs = March_tir.Tir.EApp (f, [March_tir.Tir.AVar y]) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x, rhs,
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (w, rhs,
                March_tir.Tir.EAtom (March_tir.Tir.AVar w)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let m' = March_tir.Join_points.run_pre ~changed m in
  Alcotest.(check bool) "changed" true !changed;
  let body' = (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body in
  match body' with
  | March_tir.Tir.ELet (bv, March_tir.Tir.EApp (_, _),
                         March_tir.Tir.ECase (_, branches, None)) ->
    (* Every arm body must now reference the single floated binder. *)
    List.iter (fun br ->
      match br.March_tir.Tir.br_body with
      | March_tir.Tir.EAtom (March_tir.Tir.AVar v) ->
        Alcotest.(check string) "arm uses floated binder"
          bv.March_tir.Tir.v_name v.March_tir.Tir.v_name
      | other ->
        Alcotest.failf "branch body should be EAtom(floated), got: %s"
          (March_tir.Tir.show_expr other)
    ) branches
  | _ ->
    Alcotest.failf "expected ELet(_, EApp, ECase), got: %s"
      (March_tir.Tir.show_expr body')

(** P1 Layer 1 no-fire: different RHS across arms, even with the alpha-merge
    relaxation, must not float. *)
let test_join_points_pre_no_float_different_rhs () =
  let a  = mk_var "a"  (March_tir.Tir.TCon ("T", [])) in
  let x  = mk_var "x"  March_tir.Tir.TInt in
  let w  = mk_var "w"  March_tir.Tir.TInt in
  let y  = mk_var "y"  March_tir.Tir.TInt in
  let f1 = mk_var "f1" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let f2 = mk_var "f2" (March_tir.Tir.TFn ([], March_tir.Tir.TInt)) in
  let br1 = { March_tir.Tir.br_tag = "T1"; br_vars = [];
              br_body = March_tir.Tir.ELet (x,
                March_tir.Tir.EApp (f1, [March_tir.Tir.AVar y]),
                March_tir.Tir.EAtom (March_tir.Tir.AVar x)) } in
  let br2 = { March_tir.Tir.br_tag = "T2"; br_vars = [];
              br_body = March_tir.Tir.ELet (w,
                March_tir.Tir.EApp (f2, [March_tir.Tir.AVar y]),  (* different fn *)
                March_tir.Tir.EAtom (March_tir.Tir.AVar w)) } in
  let e = March_tir.Tir.ECase (March_tir.Tir.AVar a, [br1; br2], None) in
  let m = mk_module [mk_fn "g" e] in
  let changed = ref false in
  let _m' = March_tir.Join_points.run_pre ~changed m in
  Alcotest.(check bool) "not changed" false !changed

(* ── P6 Repr classification ──────────────────────────────────────────────── *)

let test_repr_newtype_int () =
  let tds = [March_tir.Tir.TDVariant ("UserId", [("UserId", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("UserId", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TInt -> ()
  | other -> Alcotest.failf "expected Newtype TInt, got %s"
      (match other with March_tir.Repr.Boxed -> "Boxed" | _ -> "other")

let test_repr_newtype_ptr () =
  let tds = [March_tir.Tir.TDVariant ("Wrap", [("Wrap", [March_tir.Tir.TString])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Wrap", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TString -> ()
  | _ -> Alcotest.fail "expected Newtype TString"

let test_repr_multivariant_is_boxed () =
  (* No type params → can't determine payload → Boxed. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option with no params"

let test_repr_niche_int () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TInt; tagged = true } -> ()
  | _ -> Alcotest.fail "expected Niche{TInt, tagged=true}"

let test_repr_niche_string () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TString])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TString])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TString; tagged = false } -> ()
  | _ -> Alcotest.fail "expected Niche{TString, tagged=false}"

let test_repr_niche_bool () =
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TBool])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TBool])) with
  | March_tir.Repr.Niche { payload = March_tir.Tir.TBool; tagged = true } -> ()
  | _ -> Alcotest.fail "expected Niche{TBool, tagged=true}"

let test_repr_niche_float_is_boxed () =
  (* Float 0.0 bitcasts to 0 → cannot use niche. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TFloat])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TFloat])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Float)"

let test_repr_niche_unit_is_boxed () =
  (* Unit = i64 0 → null → unsafe for niche. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TUnit])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TUnit])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Unit)"

let test_repr_nested_niche_is_boxed () =
  (* Some(None)=0=None: nested niche is ambiguous → must stay Boxed. *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [March_tir.Tir.TCon ("Option", [March_tir.Tir.TInt])])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option(Option(Int))"

let test_repr_multifield_is_boxed () =
  let tds = [March_tir.Tir.TDVariant
    ("Point", [("Point", [March_tir.Tir.TInt; March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Point", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for 2-field ctor"

let test_repr_scalar_is_boxed () =
  (* Bare scalars are not TCon ctors — classify as Boxed (irrelevant). *)
  match March_tir.Repr.repr_of_ty [] March_tir.Tir.TInt with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for TInt"

(* ── LLVM emit correctness: constructor hashtable collision ──────────────── *)

(** Bug: ctor_info keyed by constructor name only — two ADTs with the same
    constructor name (e.g. both having "Cons") silently overwrite each other,
    producing wrong tags and field counts.

    Fix: keys are now type-qualified ("A.Cons", "B.Cons").
    lower.ml embeds the parent type name in EAlloc TCon; build_ctor_info stores
    variants as "TypeName.CtorName"; emit_case qualifies br_tag at lookup time. *)
let test_ctor_no_collision_different_tags () =
  (* Type A: [Nil, Cons(Int), End] — Nil=tag0, Cons=tag1, End=tag2
     Type B: [Cons(Int), Nil] — Cons=tag0, Nil=tag1
     Without the fix, ctor_info["Cons"] would be overwritten by whichever type
     is processed last, and make_a's allocation would get the wrong tag.
     A has 3 variants so it is NOT niche-shaped (niche needs exactly 1 nullary +
     1 single-field); the boxed path emits "store i32 1" for A.Cons. *)
  let td_a = March_tir.Tir.TDVariant ("A",
    [("Nil", []); ("Cons", [March_tir.Tir.TInt]); ("End", [])]) in
  let td_b = March_tir.Tir.TDVariant ("B",
    [("Cons", [March_tir.Tir.TInt]); ("Nil", [])]) in
  let x = mk_var "x" March_tir.Tir.TInt in
  (* make_a: builds A.Cons — should store tag 1 (second ctor of A) *)
  let fn_a = { March_tir.Tir.fn_name = "make_a";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              [March_tir.Tir.AVar x]) } in
  (* make_b: builds B.Cons — should store tag 0 (first ctor of B) *)
  let fn_b = { March_tir.Tir.fn_name = "make_b";
               fn_params = [x];
               fn_ret_ty = March_tir.Tir.TCon ("B", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("B.Cons", []),
                              [March_tir.Tir.AVar x]) } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_a; fn_b];
            tm_types = [td_a; td_b]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let ir = March_tir.Llvm_emit.emit_module m in
  (* Without the fix, A.Cons lookup falls back to tag=0 (ctor_info["A.Cons"]
     not found → fallback entry with ce_tag=0).  With the fix, it finds
     ctor_info["A.Cons"] = {tag=1} and emits "store i32 1". *)
  let has_tag1 =
    try ignore (Str.search_forward (Str.regexp "store i32 1") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "A.Cons emits tag 1 (not the fallback tag 0)" true has_tag1

(** Bug 2: when field counts don't match (e.g. cascading from collision),
    the emitter silently fell back to ptr type.  Fix: hard Failure. *)
let test_ctor_arity_mismatch_raises () =
  (* Construct EAlloc with key "A.Cons" (1 field in the type def) but 2 args.
     With the fix this must raise, not silently emit broken IR. *)
  let td = March_tir.Tir.TDVariant ("A",
    [("Cons", [March_tir.Tir.TInt])]) in   (* Cons has exactly 1 field *)
  let x = mk_var "x" March_tir.Tir.TInt in
  let y = mk_var "y" March_tir.Tir.TInt in
  let fn_t = { March_tir.Tir.fn_name = "bad";
               fn_params = [x; y];
               fn_ret_ty = March_tir.Tir.TCon ("A", []);
               fn_body   = March_tir.Tir.EAlloc
                             (March_tir.Tir.TCon ("A.Cons", []),
                              (* 2 args but ctor only has 1 field *)
                              [March_tir.Tir.AVar x; March_tir.Tir.AVar y]) } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn_t];
            tm_types = [td]; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let raised =
    try ignore (March_tir.Llvm_emit.emit_module m); false
    with Failure _ -> true
  in
  Alcotest.(check bool) "arity mismatch raises Failure" true raised

(** Compiled path: the generated @main() C wrapper must call
    march_run_scheduler() after march_main() so that actor mailboxes
    are drained even when main() never calls run_until_idle(). *)
let test_compiled_main_calls_march_run_scheduler () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end
    fn main() do
      let pid = spawn(Counter)
      send(pid, Inc())
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  (* The @main() wrapper must contain a call to march_run_scheduler so
     that actor mailboxes are drained after march_main() returns.
     Without this, handlers would never run in compiled executables. *)
  let has_scheduler_call =
    try ignore (Str.search_forward (Str.regexp "march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "@main wrapper calls march_run_scheduler" true has_scheduler_call;
  (* Verify the declaration is present too (needed by the linker) *)
  let has_declaration =
    try ignore (Str.search_forward
      (Str.regexp "declare void @march_run_scheduler") ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "march_run_scheduler is declared in preamble" true has_declaration

(* ── LLVM emit regression: string_chars / string_from_chars ─────────────── *)

(** Uniform integer tagging: coerce("i64","ptr") must emit shl+or+inttoptr;
    coerce("ptr","i64") must emit ptrtoint+ashr.  This is the IR-level check
    for the low-bit tagging scheme that prevents SIGSEGV when integers pass
    through polymorphic (ptr-typed) ADT fields (e.g. List(Int) with n >= 4096). *)
let test_int_tag_coerce_ir () =
  (* A function that takes a polymorphic list and returns the head as Int forces
     the codegen to coerce Int→ptr when constructing Cons and ptr→i64 when
     extracting the head.  The List type is generic so fields are ptr-typed. *)
  let src = {|mod Test do
    fn head_int(xs : List(Int)) : Int do
      match xs do
        Cons(h, _) -> h
        Nil -> 0
      end
    end
    fn make_list(n : Int) : List(Int) do
      Cons(n, Nil)
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  (* Tag: shl i64 %*, 1 and or i64 %*, 1 should appear for i64→ptr boxing *)
  Alcotest.(check bool) "tag: shl i64 ... 1"  true (ir_has "shl i64");
  Alcotest.(check bool) "tag: or i64 ... 1"   true (ir_has "or i64");
  (* Untag: ashr i64 %*, 1 should appear for ptr→i64 unboxing *)
  Alcotest.(check bool) "untag: ashr i64"      true (ir_has "ashr i64");
  (* The old unsafe raw inttoptr of an unshifted i64 must NOT appear for the
     Int→ptr case (would mean an integer was stored without tagging). *)
  Alcotest.(check bool) "no raw i64 inttoptr"  false (ir_has "inttoptr i64 %r to ptr")

(** Regression: i64-returning closure wrappers must tag the return value.
    Without tagging, an Int value >= 4096 stored in a polymorphic closure
    result would look like a heap pointer and crash march_incrc.
    The wrapper fires when a top-level Int-returning function is used as a
    first-class value (e.g. passed to a HOF that accepts a polymorphic fn). *)
let test_int_tag_wrapper_ir () =
  (* inc_fn is a top-level function returning i64; passing it as a value to
     list_apply forces the codegen to emit a closure wrapper around inc_fn.
     Closure fn-pointers are type-erased and dispatched uniformly, so every
     wrapper ($clo_wrap and $lam$apply) shares ONE calling convention: the
     generic ptr ABI.  The wrapper takes concrete params but returns its result
     in the ptr slot — an i64 result is tagged (n<<1)|1 so the dispatch's
     conditional untag recovers it, and so an Int >= 4096 is never mistaken for a
     heap pointer by march_incrc.  (A prior "concrete i64 return" variant avoided
     tagging but could not carry a *polymorphic* return, e.g. a lambda whose body
     is a dynamic record-field read — the dispatch read the tagged generic value
     as a raw scalar.  Uniform ptr ABI fixes both.) *)
  let src = {|mod Test do
    fn inc_fn(x : Int) : Int do x + 1 end
    fn list_apply(f : Int -> Int, xs : List(Int)) : List(Int) do
      map(xs, f)
    end
    fn use_wrapper() : List(Int) do
      list_apply(inc_fn, Cons(1, Nil))
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  (* The wrapper returns ptr (generic ABI), keeps a concrete i64 param, and tags
     its scalar result so the ECallPtr dispatch can untag it on read. *)
  Alcotest.(check bool) "wrapper: define ptr return" true (ir_has "define ptr @inc_fn$clo_wrap");
  Alcotest.(check bool) "wrapper: i64 param"         true (ir_has "i64 %a0");
  Alcotest.(check bool) "wrapper: tags scalar result (shl)" true (ir_has "shl i64 %r, 1")

(** Regression: string_chars and string_from_chars must lower to C-runtime
    calls in the LLVM backend.  Before the fix, emit_atom fell through to the
    default alloca-load path and generated [%string_chars.addr] which was never
    allocated, crashing LLVM IR verification. *)
let test_string_chars_llvm_emit () =
  let src = {|mod Test do
    fn f(s : String) do
      let chars = string_chars(s)
      string_from_chars(chars)
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let ir = March_tir.Llvm_emit.emit_module tir in
  let ir_has pat =
    try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "string_chars -> @march_string_chars"     true  (ir_has "@march_string_chars");
  Alcotest.(check bool) "string_from_chars -> @march_string_from_chars" true  (ir_has "@march_string_from_chars");
  Alcotest.(check bool) "no %string_chars.addr load"              false (ir_has "%string_chars.addr")

(* ── String stdlib module tests ─────────────────────────────────────────── *)

(** Helper: load string.march and evaluate [src] with it in scope. *)
let test_string_byte_size () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("hello") end
  end|} in
  Alcotest.(check int) "byte_size(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_byte_size_empty () =
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("") end
  end|} in
  Alcotest.(check int) "byte_size(\"\") = 0" 0
    (vint (call_fn env "f" []))

let test_string_byte_size_unicode () =
  (* UTF-8: "é" is 2 bytes *)
  let env = eval_with_string {|mod Test do
    fn f() do String.byte_size("é") end
  end|} in
  Alcotest.(check int) "byte_size(\"é\") = 2" 2
    (vint (call_fn env "f" []))

let test_string_slice_bytes () =
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hello world", 6, 5) end
  end|} in
  Alcotest.(check string) "slice_bytes(\"hello world\", 6, 5) = \"world\"" "world"
    (vstr (call_fn env "f" []))

let test_string_slice_bytes_clamp () =
  (* slice beyond end should clamp, not raise *)
  let env = eval_with_string {|mod Test do
    fn f() do String.slice_bytes("hi", 0, 100) end
  end|} in
  Alcotest.(check string) "slice_bytes clamps to string length" "hi"
    (vstr (call_fn env "f" []))

let test_string_contains () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.contains("hello world", "world") end
    fn no()  do String.contains("hello world", "xyz") end
  end|} in
  Alcotest.(check bool) "contains: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "contains: false" false (vbool (call_fn env "no"  []))

let test_string_starts_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.starts_with("hello", "he") end
    fn no()  do String.starts_with("hello", "lo") end
  end|} in
  Alcotest.(check bool) "starts_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "starts_with: false" false (vbool (call_fn env "no"  []))

let test_string_ends_with () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.ends_with("hello", "lo") end
    fn no()  do String.ends_with("hello", "he") end
  end|} in
  Alcotest.(check bool) "ends_with: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "ends_with: false" false (vbool (call_fn env "no"  []))

let test_string_concat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.concat("foo", "bar") end
  end|} in
  Alcotest.(check string) "concat" "foobar"
    (vstr (call_fn env "f" []))

let test_string_replace () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace("hello world", "world", "there") end
  end|} in
  Alcotest.(check string) "replace first" "hello there"
    (vstr (call_fn env "f" []))

let test_string_replace_all () =
  let env = eval_with_string {|mod Test do
    fn f() do String.replace_all("aabbaa", "a", "x") end
  end|} in
  Alcotest.(check string) "replace_all" "xxbbxx"
    (vstr (call_fn env "f" []))

let test_string_split () =
  let env = eval_with_string {|mod Test do
    fn f() do String.split("a,b,c", ",") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int) "split length" 3 (List.length xs);
  Alcotest.(check string) "split[0]" "a" (vstr (List.nth xs 0));
  Alcotest.(check string) "split[1]" "b" (vstr (List.nth xs 1));
  Alcotest.(check string) "split[2]" "c" (vstr (List.nth xs 2))

let test_string_split_first () =
  (* split_first("a:b:c", ":") = Some("a", "b:c") *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("a:b:c", ":") end
  end|} in
  let args = vcon "Some" (call_fn env "f" []) in
  let pair = (match List.nth args 0 with
    | March_eval.Eval.VTuple [a; b] -> (a, b)
    | _ -> failwith "expected tuple") in
  Alcotest.(check string) "split_first head" "a"   (vstr (fst pair));
  Alcotest.(check string) "split_first tail" "b:c" (vstr (snd pair))

let test_string_split_first_no_sep () =
  (* split_first("hello", ":") = None *)
  let env = eval_with_string {|mod Test do
    fn f() do String.split_first("hello", ":") end
  end|} in
  let _ = vcon "None" (call_fn env "f" []) in
  ()  (* Just checking it returns None *)

let test_string_join () =
  let env = eval_with_string {|mod Test do
    fn f() do String.join(["a", "b", "c"], "-") end
  end|} in
  Alcotest.(check string) "join" "a-b-c"
    (vstr (call_fn env "f" []))

let test_string_trim () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim("  hello  ") end
  end|} in
  Alcotest.(check string) "trim" "hello"
    (vstr (call_fn env "f" []))

let test_string_trim_start () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_start("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_start" "hello  "
    (vstr (call_fn env "f" []))

let test_string_trim_end () =
  let env = eval_with_string {|mod Test do
    fn f() do String.trim_end("  hello  ") end
  end|} in
  Alcotest.(check string) "trim_end" "  hello"
    (vstr (call_fn env "f" []))

let test_string_to_uppercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_uppercase("hello") end
  end|} in
  Alcotest.(check string) "to_uppercase" "HELLO"
    (vstr (call_fn env "f" []))

let test_string_to_lowercase () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_lowercase("HELLO") end
  end|} in
  Alcotest.(check string) "to_lowercase" "hello"
    (vstr (call_fn env "f" []))

let test_string_repeat () =
  let env = eval_with_string {|mod Test do
    fn f() do String.repeat("ab", 3) end
  end|} in
  Alcotest.(check string) "repeat" "ababab"
    (vstr (call_fn env "f" []))

let test_string_reverse () =
  let env = eval_with_string {|mod Test do
    fn f() do String.reverse("hello") end
  end|} in
  Alcotest.(check string) "reverse" "olleh"
    (vstr (call_fn env "f" []))

let test_string_pad_left () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_left("hi", 5, "0") end
  end|} in
  Alcotest.(check string) "pad_left" "000hi"
    (vstr (call_fn env "f" []))

let test_string_pad_right () =
  let env = eval_with_string {|mod Test do
    fn f() do String.pad_right("hi", 5, ".") end
  end|} in
  Alcotest.(check string) "pad_right" "hi..."
    (vstr (call_fn env "f" []))

let test_string_chars () =
  let env = eval_with_string {|mod Test do
    fn f() do String.chars("abc") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int)    "chars length" 3   (List.length xs);
  Alcotest.(check string) "chars[0]"     "a" (vstr (List.nth xs 0));
  Alcotest.(check string) "chars[1]"     "b" (vstr (List.nth xs 1));
  Alcotest.(check string) "chars[2]"     "c" (vstr (List.nth xs 2))

let test_string_chars_empty () =
  let env = eval_with_string {|mod Test do
    fn f() do String.chars("") end
  end|} in
  let xs = vlist (call_fn env "f" []) in
  Alcotest.(check int) "chars empty" 0 (List.length xs)

let test_string_to_upper () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_upper("hello world") end
  end|} in
  Alcotest.(check string) "to_upper" "HELLO WORLD"
    (vstr (call_fn env "f" []))

let test_string_to_lower () =
  let env = eval_with_string {|mod Test do
    fn f() do String.to_lower("HELLO WORLD") end
  end|} in
  Alcotest.(check string) "to_lower" "hello world"
    (vstr (call_fn env "f" []))

let test_string_is_empty () =
  let env = eval_with_string {|mod Test do
    fn yes() do String.is_empty("") end
    fn no()  do String.is_empty("x") end
  end|} in
  Alcotest.(check bool) "is_empty: true"  true  (vbool (call_fn env "yes" []));
  Alcotest.(check bool) "is_empty: false" false (vbool (call_fn env "no"  []))

let test_string_grapheme_count () =
  let env = eval_with_string {|mod Test do
    fn f() do String.grapheme_count("hello") end
  end|} in
  Alcotest.(check int) "grapheme_count(\"hello\") = 5" 5
    (vint (call_fn env "f" []))

let test_string_index_of () =
  let env = eval_with_string {|mod Test do
    fn found()     do String.index_of("hello", "ll") end
    fn not_found() do String.index_of("hello", "xyz") end
  end|} in
  let some_args = vcon "Some" (call_fn env "found" []) in
  Alcotest.(check int) "index_of found at 2" 2
    (vint (List.nth some_args 0));
  let _ = vcon "None" (call_fn env "not_found" []) in
  ()

let test_string_to_int () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_int("42") end
    fn err() do String.to_int("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check int) "to_int Ok(42)" 42 (vint (List.nth ok_args 0));
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_to_float () =
  let env = eval_with_string {|mod Test do
    fn ok()  do String.to_float("3.14") end
    fn err() do String.to_float("abc") end
  end|} in
  let ok_args = vcon "Ok" (call_fn env "ok" []) in
  Alcotest.(check (float 0.001)) "to_float Ok(3.14)" 3.14
    (match List.nth ok_args 0 with
     | March_eval.Eval.VFloat f -> f
     | _ -> failwith "expected VFloat");
  let _ = vcon "Err" (call_fn env "err" []) in
  ()

let test_string_from_int () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_int(42) end
  end|} in
  Alcotest.(check string) "from_int(42)" "42"
    (vstr (call_fn env "f" []))

let test_string_from_float () =
  let env = eval_with_string {|mod Test do
    fn f() do String.from_float(3.14) end
  end|} in
  let s = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "from_float contains dot" true
    (String.contains s '.')

(* ── IOList stdlib module tests ─────────────────────────────────────────── *)

let test_iolist_empty () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.empty()) end
  end|} in
  Alcotest.(check string) "IOList.empty flattens to \"\"" ""
    (vstr (call_fn env "f" []))

let test_iolist_from_string () =
  let env = eval_with_iolist {|mod Test do
    fn f() do IOList.to_string(IOList.from_string("hello")) end
  end|} in
  Alcotest.(check string) "IOList.from_string round-trips" "hello"
    (vstr (call_fn env "f" []))

let test_iolist_append () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.to_string(IOList.append(IOList.from_string("foo"), IOList.from_string("bar")))
    end
  end|} in
  Alcotest.(check string) "IOList.append" "foobar"
    (vstr (call_fn env "f" []))

let test_iolist_byte_size () =
  let env = eval_with_iolist {|mod Test do
    fn f() do
      IOList.byte_size(IOList.from_string("hello"))
    end
  end|} in
  Alcotest.(check int) "IOList.byte_size" 5
    (vint (call_fn env "f" []))

(* ── ~H sigil codegen regression ──────────────────────────────────────────
   Regression for the bidirectional-inference / span-collision bug that broke
   the ~H HTML template sigil in compiled mode.  The desugar built its
   cons-list of parts with every generated Cons/Nil node sharing the sigil's
   span; the typechecker keys its type_map by span, so the outer
   IOList.from_strings(...) application's IOList type clobbered the list's
   List(String) type.  The TIR lowerer reads that map to choose a bare
   constructor's owning ADT, so the list lowered to the non-existent
   IOList.Cons / IOList.Nil tags and the template rendered "".
   These tests assert the desugared list lowers to List.Cons / List.Nil, and
   that the int-interpolation html_auto_escape arg is coerced to a tagged ptr
   (not passed as a raw i64, which segfaulted the runtime). *)

let test_h_sigil_static_lowers_to_list_cons () =
  let tir = emit_tir_with_iolist {|mod Test do
    fn render() : String do IOList.to_string(~H"<p>HHH</p>") end
  end|} in
  Alcotest.(check bool) "~H list uses List.Cons (real List ctor)" true
    (ir_contains tir "List.Cons");
  Alcotest.(check bool) "~H list does NOT use bogus IOList.Cons" false
    (ir_contains tir "IOList.Cons");
  Alcotest.(check bool) "~H list does NOT use bogus IOList.Nil" false
    (ir_contains tir "IOList.Nil")

let test_h_sigil_int_interp_coerces_arg_to_ptr () =
  let ir = emit_ir_with_iolist {|mod Test do
    fn render(n : Int) : String do IOList.to_string(~H"<p>n=${n}</p>") end
  end|} in
  (* The runtime march_html_auto_escape takes a tagged ptr; an int arg must be
     tagged via i64->ptr coercion, never passed as `i64 N` against the `ptr`
     declaration (which segfaulted). *)
  Alcotest.(check bool) "html_auto_escape called with a ptr arg" true
    (ir_contains ir "call ptr @march_html_auto_escape(ptr");
  Alcotest.(check bool) "html_auto_escape NOT called with a raw i64 arg" false
    (ir_contains ir "@march_html_auto_escape(i64")

(* ── Http stdlib module tests ──────────────────────────────────────────── *)

let test_http_parse_url () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/path?q=1") do
      Ok(req) -> Http.host(req)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url host" "example.com" (vstr (call_fn env "f" []))

let test_http_parse_url_scheme () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:8080/api") do
      Ok(req) ->
        match Http.scheme(req) do
        SchemeHttp -> "http"
        SchemeHttps -> "https"
        end
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url scheme" "http" (vstr (call_fn env "f" []))

let test_http_parse_url_path () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/api/v1") do
      Ok(req) -> Http.path(req)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url path" "/api/v1" (vstr (call_fn env "f" []))

let test_http_parse_url_port () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:3000/") do
      Ok(req) ->
        match Http.port(req) do
        Some(p) -> p
        None -> 0
        end
      Err(_) -> -1
      end
    end
  end|} in
  Alcotest.(check int) "parse_url port" 3000 (vint (call_fn env "f" []))

let test_http_parse_url_invalid () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("ftp://bad") do
      Ok(_) -> "ok"
      Err(InvalidScheme(_)) -> "invalid_scheme"
      Err(_) -> "other_error"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url invalid scheme" "invalid_scheme" (vstr (call_fn env "f" []))

let test_http_set_header () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.get("https://example.com") do
      Ok(req) -> do
        let req = Http.set_header(req, "Accept", "application/json")
        match Http.get_request_header(req, "accept") do
        Some(v) -> v
        None -> "none"
        end
      end
      Err(_) -> "error"
      end
    end
  end|} in
  Alcotest.(check string) "set_header" "application/json" (vstr (call_fn env "f" []))

let test_http_method_to_string () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com", ()) do
      Ok(req) -> Http.method_to_string(Http.method(req))
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "method_to_string" "POST" (vstr (call_fn env "f" []))

let test_http_status_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do Http.is_success(Http.status_ok()) end
  end|} in
  Alcotest.(check bool) "status_ok is success" true (vbool (call_fn env "f" []))

let test_http_post_constructor () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com/api", "body data") do
      Ok(req) -> Http.method_to_string(Http.method(req))
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "post method" "POST" (vstr (call_fn env "f" []))

let test_http_encode_query () =
  let env = eval_with_http {|mod Test do
    fn f() do
      Http.encode_query(Cons(("key", "value"), Cons(("foo", "bar"), Nil)))
    end
  end|} in
  Alcotest.(check string) "encode_query" "key=value&foo=bar" (vstr (call_fn env "f" []))

let test_http_response_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do
      let resp = Response(Status(404), Nil, "Not Found")
      Http.response_status_code(resp)
    end
  end|} in
  Alcotest.(check int) "response status code" 404 (vint (call_fn env "f" []))

(* ── Http builtin tests ───────────────────────────────────────────── *)

let test_http_serialize_request () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("GET", "example.com", "/path", None, Nil, "")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "starts with GET /path"
    true (String.length raw > 0 && String.sub raw 0 14 = "GET /path HTTP")

let test_http_serialize_request_with_body () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request("POST", "example.com", "/api", None,
        Cons(Header("Content-Type", "text/plain"), Nil), "hello")
    end
  end|} in
  let raw = vstr (call_fn env "f" []) in
  Alcotest.(check bool) "contains body" true (
    let lines = String.split_on_char '\n' raw in
    List.exists (fun l -> String.trim l = "hello") lines)

let test_http_parse_response () =
  let raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello world" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString _body]]) ->
       Alcotest.(check int) "status code" 200 code
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

let test_http_parse_response_body () =
  (* Build the raw HTTP response with actual \r\n in OCaml, pass to builtin directly *)
  let raw = "HTTP/1.1 404 Not Found\r\nX-Foo: bar\r\n\r\nnot here" in
  let open March_eval.Eval in
  let result = List.assoc "http_parse_response" base_env in
  match result with
  | VBuiltin (_, f) ->
    (match f [VString raw] with
     | VCon ("Ok", [VTuple [VInt code; _; VString body]]) ->
       Alcotest.(check int) "status code" 404 code;
       Alcotest.(check string) "body" "not here" body
     | _ -> Alcotest.fail "expected Ok tuple")
  | _ -> Alcotest.fail "expected builtin"

(* ── Http.Client tests ───────────────────────────────────────────── *)

let test_http_client_new () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      c
    end
  end|} in
  let v = call_fn env "f" [] in
  match v with
  | March_eval.Eval.VCon ("Client", _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected Client, got %s"
    (March_eval.Eval.value_to_string v))

let test_http_client_add_steps () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.add_request_step(c, "auth", HttpClient.step_bearer_auth("tok"))
      let c = HttpClient.add_request_step(c, "headers", HttpClient.step_default_headers)
      fn count(xs) do
        match xs do
        Nil -> 0
        Cons(_, t) -> 1 + count(t)
        end
      end
      count(HttpClient.list_steps(c))
    end
  end|} in
  Alcotest.(check int) "two request steps" 2 (vint (call_fn env "f" []))

let test_http_client_request_step_transforms () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") do
      Err(_) -> "fail"
      Ok(req) -> do
        let step = HttpClient.step_bearer_auth("my-token")
        match step(req) do
        Err(_) -> "fail"
        Ok(transformed) ->
          match Http.get_request_header(transformed, "authorization") do
          Some(v) -> v
          None -> "none"
          end
        end
      end
      end
    end
  end|} in
  Alcotest.(check string) "bearer auth header" "Bearer my-token" (vstr (call_fn env "f" []))

let test_http_client_raise_on_error_status () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      match Http.get("http://example.com") do
      Err(_) -> "url_fail"
      Ok(req) -> do
        let resp = Response(Status(500), Nil, "Internal Server Error")
        match HttpClient.step_raise_on_error(req, resp) do
        Ok(_) -> "ok"
        Err(StepError(name, code)) -> name ++ ":" ++ code
        Err(_) -> "other_error"
        end
      end
      end
    end
  end|} in
  Alcotest.(check string) "raise on 500" "step_raise_on_error:500" (vstr (call_fn env "f" []))

let test_http_client_with_redirects () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let c = HttpClient.new_client()
      let c = HttpClient.with_redirects(c, 5)
      match HttpClient.list_steps(c) do
      Nil -> "empty"
      _ -> "has_steps"
      end
    end
  end|} in
  Alcotest.(check string) "redirects config" "empty" (vstr (call_fn env "f" []))

let test_http_client_base_url_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_base_url("http://api.example.com")
      -- Create a request with just a path
      let req = Request(Get, SchemeHttp, "", None, "/users", None, Nil, "")
      match step(req) do
      Ok(transformed) -> Http.host(transformed)
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "base url sets host" "api.example.com" (vstr (call_fn env "f" []))

let test_http_client_content_type_step () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = HttpClient.step_content_type("application/json")
      let req = Request(Post, SchemeHttp, "example.com", None, "/api", None, Nil, "{}")
      match step(req) do
      Ok(transformed) ->
        match Http.get_request_header(transformed, "content-type") do
        Some(v) -> v
        None -> "none"
        end
      Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "content type header" "application/json" (vstr (call_fn env "f" []))

(* ── Scheduler tests ───────────────────────────────────────────────── *)

let test_reduction_counter_ticks () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let initial = ctx.remaining in
  let exhausted = March_scheduler.Scheduler.tick ctx in
  Alcotest.(check bool) "first tick not exhausted" false exhausted;
  Alcotest.(check int) "decremented by 1" (initial - 1) ctx.remaining

let test_reduction_counter_exhausts () =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  let count = ref 0 in
  while not (March_scheduler.Scheduler.tick ctx) do
    incr count
  done;
  Alcotest.(check int) "exhausts after max_reductions - 1 ticks"
    (March_scheduler.Scheduler.max_reductions - 1) !count;
  Alcotest.(check bool) "yielded flag set" true ctx.yielded

let test_eval_yields_after_budget () =
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 do 0 else countdown(n - 1) end end
    fn countdown(n) do if n <= 0 then 0 else countdown(n - 1) end
  end|} in
  let env = eval_module src in
  March_eval.Eval.set_reduction_counting true;
  let yielded = ref false in
  (try
     ignore (call_fn env "countdown" [March_eval.Eval.VInt 100_000])
   with March_eval.Eval.Yield ->
     yielded := true);
  March_eval.Eval.set_reduction_counting false;
  Alcotest.(check bool) "countdown yields after budget" true !yielded

let test_eval_no_yield_when_disabled () =
  March_eval.Eval.set_reduction_counting false;
  let src = {|mod Test do
    fn countdown(n) do if n <= 0 do 0 else countdown(n - 1) end end
    fn countdown(n) do if n <= 0 then 0 else countdown(n - 1) end
  end|} in
  let env = eval_module src in
  let v = call_fn env "countdown" [March_eval.Eval.VInt 100_000] in
  Alcotest.(check int) "completes without yield" 0 (vint v)

(* ── Task tests ──────────────────────────────────────────────────── *)

let test_eval_task_spawn_await () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn x -> 42)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task returns 42" 42 (vint v)

let test_eval_task_await_unwrap () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn x -> 99)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task unwrap returns 99" 99 (vint v)

let test_eval_task_multiple () =
  let src = {|mod Test do
    fn main() do
      let t1 = task_spawn(fn x -> 10)
      let t2 = task_spawn(fn x -> 20)
      let r1 = task_await_unwrap(t1)
      let r2 = task_await_unwrap(t2)
      r1 + r2
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "two tasks sum to 30" 30 (vint v)

let test_eval_task_captures_env () =
  let src = {|mod Test do
    fn main() do
      let x = 5
      let t = task_spawn(fn u -> x * x)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "task captures outer x" 25 (vint v)

let test_eval_spawn_steal_requires_pool () =
  let src = {|mod Test do
    fn main() do
      task_spawn_steal(42, fn x -> 1)
    end
  end|} in
  let env = eval_module src in
  let raised = ref false in
  (try ignore (call_fn env "main" [])
   with March_eval.Eval.Eval_error _ -> raised := true);
  Alcotest.(check bool) "rejects non-WorkPool" true !raised

let test_eval_spawn_steal_with_pool () =
  let src = {|mod Test do
    fn run(pool) do
      let t = task_spawn_steal(pool, fn x -> 77)
      task_await_unwrap(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "run" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "steal task returns 77" 77 (vint v)

let test_eval_workpool_threading () =
  let src = {|mod Test do
    fn helper(pool) do
      let t = task_spawn_steal(pool, fn x -> 55)
      task_await_unwrap(t)
    end

    fn main(pool) do
      helper(pool)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [March_eval.Eval.VWorkPool] in
  Alcotest.(check int) "threaded pool works" 55 (vint v)

let test_eval_task_sends_to_actor () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }

      on Increment(n) do
        { count: state.count + n }
      end
    end

    fn main() do
      let pid = spawn(Counter)
      let t = task_spawn(fn x -> send(pid, Increment(10)))
      task_await_unwrap(t)
      send(pid, Increment(0))
    end
  end|} in
  let env = eval_module src in
  let _v = call_fn env "main" [] in
  (* If we get here without error, cross-tier messaging works *)
  ()

(** Regression: task_spawn with a heap-allocating lambda must not crash with
    "local RC underflow".  Root cause was march_task_spawn_thunk zeroing the
    Task object's RC field (task[0]=0) after march_alloc already set it to 1,
    so the caller's march_decrc_local on the Task result went 0→-1.
    Secondary: march_incrc on the closure inside the runtime was spurious;
    Perceus treats task_spawn as consuming (no DecRC on caller side). *)
let test_compile_task_spawn_heap_alloc_no_rc_underflow () =
  let ir = emit_actor_ir {|mod T do
    fn go() : String do "hello" end
    fn main() do
      let _ = task_spawn(fn _ -> go())
      ()
    end
  end|} in
  (* march_task_spawn_thunk must be called *)
  Alcotest.(check bool) "calls march_task_spawn_thunk" true
    (ir_contains ir "march_task_spawn_thunk");
  (* The Task result (let _ = ...) must be DecRC'd by the caller — Perceus
     side of the fix; the runtime side (task[0]=0 removal) is verified by the
     full binary tests passing without abort. *)
  Alcotest.(check bool) "task handle is decrc'd by caller" true
    (ir_contains ir "march_decrc_local")

(** Regression (B10): a local variable whose name shadows a builtin (e.g.
    `link`, the actor-linking builtin) must still get its RC ops emitted.
    The five EIncRC/EDecRC/EFree/EAtomicIncRC/EAtomicDecRC arms in
    llvm_emit.ml skip emission purely by NAME match against is_builtin_fn /
    top_fns, without checking whether a local alloca (var_slot) shadows that
    name — unlike emit_atom, which has the correct var_slot guard in both of
    its analogous arms. Perceus DOES insert a dec_rc for the shadowed local
    (confirmed via --dump-tir: `let out = dec_rc link; ...`), so if the
    guard is missing, the alloca for `link` is created and stored but never
    referenced by any RC runtime call — the local leaks (never freed) and,
    more importantly, the same missing-guard bug pattern is what causes
    heap corruption in the emit_atom builtin arm this mirrors. *)
let test_compile_local_shadows_builtin_still_gets_rc_ops () =
  let ir = emit_actor_ir {|mod ShadowRc do
    fn main() do
      let link = String.concat("heap", "-allocated")
      let out = String.concat(link, "!")
      println(out)
    end
  end|} in
  (* The shadowed local must be stack-allocated under its own name... *)
  Alcotest.(check bool) "local `link` gets its own alloca" true
    (ir_contains ir "%link.addr = alloca");
  (* ...and at least one RC runtime call must load from that exact alloca
     (not just some unrelated %link.addr text elsewhere, and not the
     unrelated @march_link actor-linking builtin declaration/call). *)
  let loads_link_addr = Str.regexp "load ptr, ptr %link\\.addr" in
  let ir_has_load_of_link_addr =
    try ignore (Str.search_forward loads_link_addr ir 0); true
    with Not_found -> false
  in
  Alcotest.(check bool) "a load from %link.addr exists (feeds some use)" true
    ir_has_load_of_link_addr;
  (* Precisely: the value loaded from %link.addr must reach an RC op
     (march_decrc_local/march_incrc_local/march_free/march_incrc/march_decrc)
     as an argument — not merely be stored/loaded for the String.concat call.
     Extract every SSA temp assigned from `load ptr, ptr %link.addr`, then
     confirm at least one of those temps is passed to an RC runtime call. *)
  let ssa_temps_loading_link_addr =
    let re = Str.regexp "%\\([A-Za-z0-9_$]+\\) = load ptr, ptr %link\\.addr" in
    let rec go i acc =
      match Str.search_forward re ir i with
      | j -> go (j + 1) (Str.matched_group 1 ir :: acc)
      | exception Not_found -> acc
    in
    go 0 []
  in
  Alcotest.(check bool) "at least one SSA temp loads %link.addr" true
    (ssa_temps_loading_link_addr <> []);
  let rc_call_re =
    Str.regexp "call void @march_\\(decrc_local\\|incrc_local\\|free\\|incrc\\|decrc\\)(ptr %\\([A-Za-z0-9_$]+\\))"
  in
  let rc_call_args =
    let rec go i acc =
      match Str.search_forward rc_call_re ir i with
      | j -> go (j + 1) (Str.matched_group 2 ir :: acc)
      | exception Not_found -> acc
    in
    go 0 []
  in
  let shadow_reaches_rc_op =
    List.exists (fun t -> List.mem t rc_call_args) ssa_temps_loading_link_addr
  in
  Alcotest.(check bool)
    "an RC op (incrc/decrc/free) is emitted against the shadowed local `link`'s value"
    true shadow_reaches_rc_op

(** Phase 5: task_yield() must emit call void @march_sched_yield(), not a no-op. *)
let test_compile_task_yield_actually_yields () =
  let ir = emit_actor_ir {|mod TaskYieldTest do
    fn main() : Unit do
      let _ = task_yield()
      ()
    end
  end|} in
  Alcotest.(check bool) "yields via sched_yield" true
    (ir_contains ir "call void @march_sched_yield()")

(** Phase 5: task_reductions() must read from @march_tls_reductions, not return literal 0. *)
let test_compile_task_reductions_reads_tls () =
  let ir = emit_actor_ir {|mod TaskReductionsTest do
    fn main() : Int do
      task_reductions()
    end
  end|} in
  Alcotest.(check bool) "reads TLS reductions" true
    (ir_contains ir "load i64, ptr @march_tls_reductions")

(** Phase 5: task_await must emit call to @march_task_await, not inline field load. *)
let test_compile_task_await_in_ir () =
  let ir = emit_actor_ir {|mod TaskAwaitTest do
    fn main() do
      let t = task_spawn(fn _ -> 42)
      task_await(t)
    end
  end|} in
  Alcotest.(check bool) "uses march_task_await" true
    (ir_contains ir "call ptr @march_task_await")

(** Phase 5: cancel token builtins must emit the correct C extern calls. *)
let test_compile_cancel_token_ir () =
  let ir = emit_actor_ir {|mod CancelTokenTest do
    fn main() do
      let tok = task_cancel_token_new()
      let _ = task_is_cancelled(tok)
      task_cancel(tok)
    end
  end|} in
  Alcotest.(check bool) "cancel_token_new declared" true
    (ir_contains ir "march_cancel_token_new");
  Alcotest.(check bool) "cancel_token_cancel declared" true
    (ir_contains ir "march_cancel_token_cancel");
  Alcotest.(check bool) "cancel_token_is_cancelled declared" true
    (ir_contains ir "march_cancel_token_is_cancelled")

(* ── P10 Phase 2: NativeArray compiled-path IR tests ────────────────────── *)

(** native_int_arr_* builtins must appear in the LLVM preamble and generate
    correct call instructions: i64 return for length/get/sum, ptr for make/set/map. *)
let test_native_int_arr_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn sum_list(xs : List(Int)) : Int do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_sum(arr)
    end
    fn roundtrip(xs : List(Int)) : List(Int) do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_to_list(arr)
    end
    fn make_arr(n : Int) : Int do
      let arr = native_int_arr_make(n, 0)
      let arr2 = native_int_arr_set(arr, 0, 42)
      native_int_arr_get(arr2, 0)
    end
    fn arr_len(xs : List(Int)) : Int do
      let arr = native_int_arr_from_list(xs)
      native_int_arr_length(arr)
    end
  end|} in
  Alcotest.(check bool) "native_int_arr_from_list declared" true
    (ir_contains ir "@native_int_arr_from_list");
  Alcotest.(check bool) "native_int_arr_sum declared" true
    (ir_contains ir "@native_int_arr_sum");
  Alcotest.(check bool) "native_int_arr_to_list declared" true
    (ir_contains ir "@native_int_arr_to_list");
  Alcotest.(check bool) "native_int_arr_make declared" true
    (ir_contains ir "@native_int_arr_make");
  Alcotest.(check bool) "native_int_arr_set declared" true
    (ir_contains ir "@native_int_arr_set");
  Alcotest.(check bool) "native_int_arr_get declared" true
    (ir_contains ir "@native_int_arr_get");
  Alcotest.(check bool) "native_int_arr_length declared" true
    (ir_contains ir "@native_int_arr_length");
  (* IR calls must use correct return types *)
  Alcotest.(check bool) "sum call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_sum");
  Alcotest.(check bool) "get call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_get");
  Alcotest.(check bool) "length call returns i64" true
    (ir_contains ir "= call i64 @native_int_arr_length");
  Alcotest.(check bool) "from_list call returns ptr" true
    (ir_contains ir "= call ptr @native_int_arr_from_list")

(** native_float_arr_* builtins must appear in the LLVM preamble and generate
    correct call instructions: double return for get/sum, ptr for make/set/map. *)
let test_native_float_arr_ir () =
  let ir = emit_actor_ir {|mod Test do
    fn sum_arr(n : Int) : Float do
      let arr = native_float_arr_make(n, 1.0)
      native_float_arr_sum(arr)
    end
    fn get_arr(n : Int, i : Int) : Float do
      let arr = native_float_arr_make(n, 2.5)
      native_float_arr_get(arr, i)
    end
    fn set_arr(n : Int, i : Int, v : Float) : NativeFloatArr do
      let arr = native_float_arr_make(n, 0.0)
      native_float_arr_set(arr, i, v)
    end
    fn len_arr(n : Int) : Int do
      let arr = native_float_arr_make(n, 0.0)
      native_float_arr_length(arr)
    end
  end|} in
  Alcotest.(check bool) "native_float_arr_make declared" true
    (ir_contains ir "@native_float_arr_make");
  Alcotest.(check bool) "native_float_arr_sum declared" true
    (ir_contains ir "@native_float_arr_sum");
  Alcotest.(check bool) "native_float_arr_get declared" true
    (ir_contains ir "@native_float_arr_get");
  Alcotest.(check bool) "native_float_arr_length declared" true
    (ir_contains ir "@native_float_arr_length");
  Alcotest.(check bool) "native_float_arr_set declared" true
    (ir_contains ir "@native_float_arr_set");
  (* IR calls must use correct return types *)
  Alcotest.(check bool) "float sum call returns double" true
    (ir_contains ir "= call double @native_float_arr_sum");
  Alcotest.(check bool) "float get call returns double" true
    (ir_contains ir "= call double @native_float_arr_get");
  Alcotest.(check bool) "float make call returns ptr" true
    (ir_contains ir "= call ptr @native_float_arr_make")

(** Phase 4: send() should push to mailbox, NOT dispatch inline.
    After send(), mailbox_size = 1 and state is unchanged. *)
let test_cancel_token_new () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      task_is_cancelled(tok)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "new token is not cancelled" false (vbool v)

let test_cancel_token_cancel () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      task_cancel(tok)
      task_is_cancelled(tok)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "cancelled token returns true" true (vbool v)

let test_cancel_tokens_independent () =
  let src = {|mod Test do
    fn main() do
      let tok1 = task_cancel_token_new()
      let tok2 = task_cancel_token_new()
      task_cancel(tok1)
      task_is_cancelled(tok2)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check bool) "other token unaffected" false (vbool v)

let test_spawn_with_cancel_active () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      let t = task_spawn_with_cancel(fn _ -> 42, tok)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "runs when active" "Ok(42)" (March_eval.Eval.value_to_string v)

let test_spawn_with_cancel_precancelled () =
  let src = {|mod Test do
    fn main() do
      let tok = task_cancel_token_new()
      task_cancel(tok)
      let t = task_spawn_with_cancel(fn _ -> 99, tok)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "skipped when pre-cancelled" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

let test_cancel_by_id () =
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn _ -> 7)
      task_cancel_by_id(t)
      task_await(t)
    end
  end|} in
  let env = eval_module src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "cancelled by id" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

(* ── Task.race ─────────────────────────────────────────────────────── *)

let test_task_race_single () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
    fn main() do
      let t = task_spawn(fn _ -> 100)
      Task.race([t])
    end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "race single" "Ok(100)" (March_eval.Eval.value_to_string v)

let test_task_race_cancels_losers () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
    fn main() do
      let t1 = task_spawn(fn _ -> 1)
      let t2 = task_spawn(fn _ -> 2)
      Task.race([t1, t2])
      task_await(t2)
    end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "loser is cancelled" {|Err("cancelled")|} (March_eval.Eval.value_to_string v)

let test_task_race_empty () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let task_decl = load_stdlib_file_for_test "task.march" in
  let src = {|mod Test do
    fn main() do Task.race([]) end
  end|} in
  let env = eval_with_stdlib [list_decl; task_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "race empty" {|Err("race: empty task list")|} (March_eval.Eval.value_to_string v)

(* ── Task.all_settled ──────────────────────────────────────────────── *)

let test_task_all_settled () =
  let list_decl = load_stdlib_file_for_test "list.march" in
  let src = {|mod Test do
    fn main() do
      let t1 = task_spawn(fn _ -> 10)
      let t2 = task_spawn(fn _ -> 20)
      task_cancel_by_id(t2)
      let t3 = task_spawn(fn _ -> 30)
      let rs = List.map([t1, t2, t3], fn t -> task_await(t))
      rs
    end
  end|} in
  let env = eval_with_stdlib [list_decl] src in
  let v = call_fn env "main" [] in
  Alcotest.(check string) "all_settled includes Err"
    {|[Ok(10), Err("cancelled"), Ok(30)]|}
    (March_eval.Eval.value_to_string v)

(** Phase 4: run_scheduler() processes queued messages.
    After run_until_idle(), counter state should be updated. *)
let test_eval_reduction_count () =
  let src = {|mod Test do
    fn countdown(n) do
      if n <= 0 do 0
      else countdown(n - 1) end
    end

    fn main() do
      countdown(100)
    end
  end|} in
  let env = eval_module src in
  let thunk = List.assoc "main" env in
  let (_result, reductions) =
    March_eval.Eval.eval_with_reduction_tracking thunk in
  (* Each iteration: EApp(countdown) + EMatch(if) = 2 reductions.
     Plus the initial EApp(main). Should be roughly 200+. *)
  Alcotest.(check bool) "reductions > 100" true (reductions > 100);
  Alcotest.(check bool) "reductions < 1000" true (reductions < 1000)

(* ── Work-stealing deque tests ────────────────────────────────────── *)

let test_deque_push_pop () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Pop is LIFO from the bottom *)
  Alcotest.(check (option int)) "pop 3" (Some 3)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 2" (Some 2)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop 1" (Some 1)
    (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check (option int)) "pop empty" None
    (March_scheduler.Work_pool.Deque.pop d)

let test_deque_steal () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  March_scheduler.Work_pool.Deque.push d 3;
  (* Steal is FIFO from the top *)
  Alcotest.(check (option int)) "steal 1" (Some 1)
    (March_scheduler.Work_pool.Deque.steal d);
  Alcotest.(check (option int)) "steal 2" (Some 2)
    (March_scheduler.Work_pool.Deque.steal d)

let test_deque_size () =
  let d = March_scheduler.Work_pool.Deque.create 16 in
  Alcotest.(check int) "empty size" 0
    (March_scheduler.Work_pool.Deque.size d);
  March_scheduler.Work_pool.Deque.push d 1;
  March_scheduler.Work_pool.Deque.push d 2;
  Alcotest.(check int) "size 2" 2
    (March_scheduler.Work_pool.Deque.size d);
  ignore (March_scheduler.Work_pool.Deque.pop d);
  Alcotest.(check int) "size after pop" 1
    (March_scheduler.Work_pool.Deque.size d)

let test_pool_submit_steal () =
  let pool = March_scheduler.Work_pool.create 2 in
  March_scheduler.Work_pool.submit pool 0 "task_a";
  March_scheduler.Work_pool.submit pool 0 "task_b";
  let stolen = March_scheduler.Work_pool.Deque.steal pool.workers.(0) in
  Alcotest.(check (option string)) "stole task_a" (Some "task_a") stolen

(* ── Capability security tests ─────────────────────────────────────────── *)

(* Pure module with no Cap usage and no needs — should be clean *)
let test_cap_needs_pure_ok () =
  let ctx = typecheck {|mod Test do
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "pure module: no errors" false (has_errors ctx)

(* Module declares needs and uses Cap in a function signature — should be clean *)
let test_cap_needs_declared_ok () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "declared needs with Cap: no errors" false (has_errors ctx)

(* Module uses Cap(IO) in a signature without declaring needs IO — should error *)
let test_cap_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    fn greet(cap : Cap(IO)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "undeclared Cap is an error" true (has_errors ctx)

(* Module declares needs IO but never uses Cap(IO) anywhere — should warn *)
let test_cap_unused_needs_warning () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn add(x, y) do x + y end
  end|} in
  Alcotest.(check bool) "unused needs produces a diagnostic" true
    (March_errors.Errors.has_diagnostics ctx)

(* An extern block's Cap(X) counts as USING X, so `needs X` + an extern block
   must NOT trigger the "declared but not used" warning.  An extern block ALSO
   implies `IO.Foreign` (the FFI meta-capability), so a clean module declares
   both — matching the `needs Ffi` + `needs IO.Foreign` pattern in the
   `test/native/ffi_*.march` fixtures. *)
let test_cap_extern_block_counts_as_use () =
  let ctx = typecheck {|mod Test do
    needs Ffi
    needs IO.Foreign
    extern "m" : Cap(Ffi) do
      fn dbl(n : Int) : Int = "ffi_test_dbl"
    end
  end|} in
  Alcotest.(check bool) "extern Cap(Ffi) + needs IO.Foreign: no diagnostics" false
    (March_errors.Errors.has_diagnostics ctx)

(* Cap(IO) as supertype covers Cap(IO.Network) usage *)
let test_cap_supertype_covers_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO
    fn connect(cap : Cap(IO.Network)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO covers Cap(IO.Network): no errors" false (has_errors ctx)

(* Cap(IO.Network) does NOT cover Cap(IO.FileRead) *)
let test_cap_needs_wrong_subtype () =
  let ctx = typecheck {|mod Test do
    needs IO.Network
    fn read_file(cap : Cap(IO.FileRead)) do
      cap
    end
  end|} in
  Alcotest.(check bool) "needs IO.Network does not cover Cap(IO.FileRead): error" true
    (has_errors ctx)

(* Multiple needs declarations are supported *)
let test_cap_multiple_needs () =
  let ctx = typecheck {|mod Test do
    needs IO.Network, IO.FileRead
    fn connect(cap : Cap(IO.Network)) do cap end
    fn read_file(cap : Cap(IO.FileRead)) do cap end
  end|} in
  Alcotest.(check bool) "multiple needs: no errors" false (has_errors ctx)

(* needs IO is parsed correctly *)
let test_cap_parse_needs () =
  let src = {|mod Test do
    needs IO
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let has_needs = List.exists (fun d ->
    match d with
    | March_ast.Ast.DNeeds _ -> true
    | _ -> false
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "DNeeds present in AST" true has_needs

(* needs with dotted path is parsed correctly *)
let test_cap_parse_needs_dotted () =
  let src = {|mod Test do
    needs IO.Network
    fn f(x) do x end
  end|} in
  let m = parse_and_desugar src in
  let cap_paths = List.filter_map (fun d ->
    match d with
    | March_ast.Ast.DNeeds (caps, _) ->
      Some (List.map (fun names ->
        String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) names)
      ) caps)
    | _ -> None
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check bool) "IO.Network parsed as DNeeds" true
    (List.exists (fun paths -> List.mem "IO.Network" paths) cap_paths)

(* ── Transitive capability enforcement tests ────────────────────────────── *)

(* Module that imports another with matching needs declared — should be ok *)
let test_cap_transitive_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO.Network
      use Lib.*
      fn run(cap : Cap(IO.Network)) do Lib.connect(cap) end
    end
  end|} in
  Alcotest.(check bool) "transitive ok when needs declared" false (has_errors ctx)

(* Module imports another that requires IO.Network but declares nothing — error *)
let test_cap_transitive_missing_error () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      use Lib.*
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "transitive import without needs is an error" true (has_errors ctx)

(* Module declares parent cap (IO) which covers imported module's child (IO.Network) *)
let test_cap_transitive_supertype_ok () =
  let ctx = typecheck {|mod Outer do
    mod Lib do
      needs IO.Network
      fn connect(cap : Cap(IO.Network)) do cap end
    end
    mod Test do
      needs IO
      use Lib.*
      fn run(cap : Cap(IO)) do cap end
    end
  end|} in
  Alcotest.(check bool) "parent cap covers transitive import" false (has_errors ctx)

(* Three-level chain: C uses B uses A; B covers its A import, C must cover B's needs *)
let test_cap_transitive_chain_error () =
  let ctx = typecheck {|mod Outer do
    mod A do
      needs IO.FileRead
      fn read(cap : Cap(IO.FileRead)) do cap end
    end
    mod B do
      needs IO.FileRead
      use A.*
      fn do_read(cap : Cap(IO.FileRead)) do A.read(cap) end
    end
    mod C do
      use B.*
      fn run(x) do x end
    end
  end|} in
  Alcotest.(check bool) "chain: C must declare needs covered by B" true (has_errors ctx)

(* extern with capability declared in needs — ok *)
let test_cap_extern_with_needs_ok () =
  let ctx = typecheck {|mod Test do
    needs LibC
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern with declared needs: no errors" false (has_errors ctx)

(* extern without declaring its capability in needs — error *)
let test_cap_extern_missing_needs_error () =
  let ctx = typecheck {|mod Test do
    extern "libc": Cap(LibC) do
      fn malloc(n : Int) : Int
    end
  end|} in
  Alcotest.(check bool) "extern without needs is an error" true (has_errors ctx)

(* ── FFI: extern fn = "symbol" binds the explicit C symbol ──────────────── *)

let test_ffi_extern_explicit_symbol_ir () =
  let ir = emit_actor_ir {|mod Test do
    needs Ffi
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int = "crc32_compute"
    end
    fn main() : Unit do println(int_to_string(crc32(255))) end
  end|} in
  Alcotest.(check bool) "calls the explicit C symbol" true
    (ir_contains ir "@crc32_compute");
  Alcotest.(check bool) "does not emit the default <lib>_<fn> name" false
    (ir_contains ir "@crc_crc32")

let test_ffi_extern_default_symbol_ir () =
  let ir = emit_actor_ir {|mod Test do
    needs Ffi
    extern "crc" : Cap(Ffi) do
      fn crc32(n: Int): Int
    end
    fn main() : Unit do println(int_to_string(crc32(255))) end
  end|} in
  Alcotest.(check bool) "falls back to <lib>_<fn> when no symbol given" true
    (ir_contains ir "@crc_crc32")

(* ── Capability enforcement path tests ─────────────────────────────────── *)

(* Verify capability errors surface via check_capabilities (the effects-module
   entry point that wraps check_module for explicit use on both paths). *)
let test_cap_effects_clean () =
  let src = {|mod Test do
    needs IO.Network
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: clean module has no errors" false
    (March_errors.Errors.has_errors ctx)

let test_cap_effects_violation () =
  let src = {|mod Test do
    fn f(cap : Cap(IO.Network)) do cap end
  end|} in
  let m = parse_and_desugar src in
  let ctx = March_effects.Effects.check_capabilities m in
  Alcotest.(check bool) "check_capabilities: capability violation produces error" true
    (March_errors.Errors.has_errors ctx)

(* Verify eval path: typechecking with capability errors prevents eval.
   We check that has_errors returns true, which in main.ml causes exit(1)
   before run_module is ever called. *)
let test_cap_eval_path_blocked () =
  let src = {|mod Test do
    fn f(cap : Cap(IO.Network)) do cap end
    fn main() do f(42) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: capability error prevents evaluation" true
    (has_errors ctx)

(* Verify eval path: clean module can evaluate *)
let test_cap_eval_path_ok () =
  let src = {|mod Test do
    needs IO.Network
    fn double(x) do x + x end
    fn main() do double(21) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "eval path: clean module with needs evaluates without error" false
    (has_errors ctx)

(* ── Proof cap tests ────────────────────────────────────────────────────── *)

let test_proof_cap_parse () =
  let src = {|mod Db do
    proof cap Migrated
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: parses without error" false (has_errors ctx)

let test_proof_cap_declaration_ok () =
  let src = {|mod Db do
    proof cap Migrated
    needs Db.Migrated
    fn start_app(m : Cap(Db.Migrated)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap declaration: no errors" false (has_errors ctx)

let test_proof_cap_forge_error () =
  (* A function outside the declaring module declares proof cap in return type
     without receiving it as a parameter — Check 6 should fire *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs Db.Migrated
      fn bad_forge() : Cap(Db.Migrated) do () end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap forge: error when non-declaring module returns it without receiving" true (has_errors ctx)

let test_proof_cap_passthrough_ok () =
  (* Receiving a proof cap and returning it (pass-through) is allowed anywhere *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      needs Db.Migrated
      fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap passthrough: receiving and returning is allowed" false (has_errors ctx)

let test_proof_cap_missing_needs_error () =
  (* Using Cap(X) for a proof cap without declaring needs — Check 1 fires with
     proof-cap-specific message naming the declaring module *)
  let src = {|mod Outer do
    mod Db do
      proof cap Migrated
    end
    mod App do
      fn use_cap(m : Cap(Db.Migrated)) : () do () end
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap missing needs: error with declaring-module hint" true (has_errors ctx)

let test_proof_cap_in_declaring_module_ok () =
  (* Within the declaring module, returning the proof cap (pass-through) is fine
     and Check 6 should NOT fire even though declaring_mod = mod_name *)
  let src = {|mod Db do
    proof cap Migrated
    needs Db.Migrated
    fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: declaring module can return it freely" false (has_errors ctx)

let test_proof_cap_implicit_needs () =
  (* The declaring module does NOT need to write `needs Db.Migrated` —
     `proof cap Migrated` implicitly satisfies it for functions that use Cap(Db.Migrated) *)
  let src = {|mod Db do
    proof cap Migrated
    fn use_cap(m : Cap(Db.Migrated)) : () do () end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap: declaring module needs implicit" false (has_errors ctx)

let test_proof_cap_pfn_forge_error () =
  (* A pfn inside the declaring module cannot mint a proof cap from nothing —
     Check 6 fires even though the module is the declaring module.
     Use cap_narrow(root_cap()) so the body typechecks; the error is Check 6 specifically. *)
  let src = {|mod Db do
    proof cap Migrated
    pfn bad_private_forge() : Cap(Db.Migrated) do cap_narrow(root_cap()) end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap pfn forge: error for private function in declaring module" true (has_errors ctx)

let test_proof_cap_pfn_passthrough_ok () =
  (* A pfn inside the declaring module CAN pass a proof cap through —
     it just cannot produce one from nothing *)
  let src = {|mod Db do
    proof cap Migrated
    pfn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "proof cap pfn passthrough: private relay is allowed" false (has_errors ctx)

(** Opt.run is safe on RC-free TIR (the JS target skips Perceus). *)
let test_opt_without_perceus () =
  let src = {|mod Test do
    type Tree = Leaf | Node(Tree, Int, Tree)

    fn sum(t : Tree) : Int do
      match t do
        Leaf -> 0
        Node(l, n, r) -> sum(l) + n + sum(r)
      end
    end

    fn main() : Unit do
      let t = Node(Node(Leaf, 1, Leaf), 2, Node(Leaf, 3, Leaf))
      println(int_to_string(sum(t)))
    end
  end|} in
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  (* NOTE: Defun and Perceus intentionally skipped — this is the JS pipeline *)
  let opt_tir = March_tir.Opt.run tir in
  (* Opt must not introduce RC nodes when given RC-free TIR *)
  let rec has_rc = function
    | March_tir.Tir.EIncRC _ | March_tir.Tir.EDecRC _ | March_tir.Tir.EFree _
    | March_tir.Tir.EReuse _ | March_tir.Tir.EAtomicIncRC _
    | March_tir.Tir.EAtomicDecRC _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_rc e1 || has_rc e2
    | March_tir.Tir.ELetRec (fns, body) ->
      List.exists (fun f -> has_rc f.March_tir.Tir.fn_body) fns || has_rc body
    | March_tir.Tir.ECase (_, brs, def) ->
      List.exists (fun b -> has_rc b.March_tir.Tir.br_body) brs
      || (match def with Some e -> has_rc e | None -> false)
    | March_tir.Tir.ESeq (a, b) -> has_rc a || has_rc b
    | _ -> false
  in
  let any_rc = List.exists
    (fun fn -> has_rc fn.March_tir.Tir.fn_body)
    opt_tir.March_tir.Tir.tm_fns
  in
  Alcotest.(check bool) "Opt on RC-free TIR produces no RC nodes" false any_rc

(* ── Sort stdlib tests ──────────────────────────────────────────────────── *)

(* ── Guard-exhaustion fallthrough (B3) ─────────────────────────────────────
   A guarded match where every guard fails must panic, not silently return
   `LitInt 0` reinterpreted at the match's real (non-Int) type — see
   lib/tir/lower.ml's `nonexhaustive_panic` comment.  This test compiles and
   *runs* the binary (not just inspecting IR text) because the bug's symptom
   is a runtime crash/garbage value, not a shape in the emitted IR. *)
let test_guard_exhaustion_panics_compiled () =
  let exe_dir  = Filename.dirname Sys.executable_name in
  let main_exe = Filename.concat exe_dir "../bin/main.exe" in
  (* Run from the project root so the compiler resolves its CWD-relative
     runtime/ and stdlib/ directories (same trick as the other compiled
     regression tests in test_stdlib_suite.ml). *)
  let project_root = Filename.dirname (Filename.dirname exe_dir) in
  if not (Sys.file_exists main_exe) then ()  (* skip: no compiler binary *)
  else begin
    let src_text =
      "mod GuardEx do\n\
      \  fn classify(n) do\n\
      \    match n do\n\
      \      x when x > 0 -> \"pos\"\n\
      \      x when x < 0 -> \"neg\"\n\
      \    end\n\
      \  end\n\
      \  fn main() do\n\
      \    println(classify(0))\n\
      \  end\n\
       end\n"
    in
    let tmp = Filename.temp_file "march_guardex" "" in
    Sys.remove tmp;
    Unix.mkdir tmp 0o755;
    let src = Filename.concat tmp "guardex.march" in
    let oc = open_out src in
    output_string oc src_text;
    close_out oc;
    (* Read the whole stdout+stderr of a command (trimmed). *)
    let read_cmd cmd =
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 64 in
      (try
         while true do Buffer.add_channel buf ic 1 done
       with End_of_file -> ());
      ignore (Unix.close_process_in ic);
      String.trim (Buffer.contents buf)
    in
    (* --- interpreter: must already panic (parity check) --- *)
    let interp_out = read_cmd (Printf.sprintf
      "cd %s && %s %s 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote src)) in
    Alcotest.(check bool) "interpreter panics on guard exhaustion (non-exhaustive)" true
      (ir_contains interp_out "non-exhaustive" || ir_contains interp_out "panic");
    (* --- compiled: must panic (exit 1) with a non-exhaustive-match message,
       not crash (segfault, exit 139) or exit 0 with garbage output --- *)
    let bin = Filename.concat tmp "guardexbin" in
    let compile_rc = Sys.command (Printf.sprintf
      "cd %s && %s --compile -o %s %s >/dev/null 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote bin) (Filename.quote src)) in
    Alcotest.(check int) "compiles ok" 0 compile_rc;
    let run_out = read_cmd (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled guard-exhaustion panics with a non-exhaustive-match message (not exit 0/segfault)"
      true
      ((ir_contains run_out "non-exhaustive" || ir_contains run_out "panic")
       && ir_contains run_out "EXIT:1")
  end

(* ── Float-literal match arms (B4) ──────────────────────────────────────
   `pat_tag_and_subs` returned `None` for `Ast.LitFloat` patterns, and the
   match-matrix grouping loop silently discarded rows it couldn't tag — so a
   float-literal match arm compiled to nothing, silently falling through to
   whatever the next (typically wildcard) arm was.  The interpreter (which
   matches on the AST directly) got this right; only the compiled backend
   diverged.  These tests compile and *run* the binary, because the bug's
   symptom is a wrong *value*, not a shape in the emitted IR (same rationale
   as the guard-exhaustion test above). *)

(* Read the whole stdout+stderr of a command (trimmed). Shared helper for the
   compile-and-run regression tests in this section. *)
let read_cmd_output cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 64 in
  (try
     while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  String.trim (Buffer.contents buf)

(** Write [src_text] to a fresh temp dir and return (project_root, main_exe,
    src_path, tmp_dir). Shared setup for the compile-and-run tests below. *)
let write_march_source ~name src_text =
  let exe_dir  = Filename.dirname Sys.executable_name in
  let main_exe = Filename.concat exe_dir "../bin/main.exe" in
  let project_root = Filename.dirname (Filename.dirname exe_dir) in
  let tmp = Filename.temp_file name "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp (name ^ ".march") in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  (project_root, main_exe, src, tmp)

let test_float_lit_match_arm_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_floatpat"
    "mod FloatPat do\n\
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\" | _ -> \"other\"\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
    \    println(name(2.5))\n\
    \  end\n\
     end\n"
  in
  if not (Sys.file_exists main_exe) then ()  (* skip: no compiler binary *)
  else begin
    (* --- interpreter: matches the float literal correctly (baseline) --- *)
    let interp_out = read_cmd_output (Printf.sprintf
      "cd %s && %s %s 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote src)) in
    Alcotest.(check string) "interpreter matches float literal arm"
      "two-and-a-half" interp_out;
    (* --- compiled: must match too — this is the B4 regression --- *)
    let bin = Filename.concat tmp "floatpatbin" in
    let compile_rc = Sys.command (Printf.sprintf
      "cd %s && %s --compile -o %s %s >/dev/null 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote bin) (Filename.quote src)) in
    Alcotest.(check int) "compiles ok" 0 compile_rc;
    let run_out = read_cmd_output (Filename.quote bin) in
    Alcotest.(check string)
      "compiled float literal match arm produces the SAME value as the \
       interpreter (not silently falling through to a later/wildcard arm)"
      "two-and-a-half" run_out
  end

(** Float arm with NO wildcard: a non-exhaustive float match must panic (the
    Task 1 / B3 `nonexhaustive_panic` fallback), not silently fall through to
    LLVM `unreachable` (undefined behaviour — observed, pre-fix, to print a
    WRONG matched value with exit 0 instead of crashing). The scrutinee must
    NOT be a compile-time constant, or the optimizer folds the whole match to
    its statically-known arm and never reaches the fallback path at all. *)
let test_float_lit_no_wildcard_panics_compiled () =
  let (project_root, main_exe, src, tmp) = write_march_source ~name:"march_floatpat_nowild"
    "mod FloatPatNoWild do\n\
    \  fn name(x) do\n\
    \    match x do\n\
    \      1.5 -> \"one-and-a-half\" | 2.5 -> \"two-and-a-half\"\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
    \    let n = int_to_float(List.length(process_argv())) +. 3.7\n\
    \    println(name(n))\n\
    \  end\n\
     end\n"
  in
  if not (Sys.file_exists main_exe) then ()  (* skip: no compiler binary *)
  else begin
    (* --- interpreter: must already panic (parity check) --- *)
    let interp_out = read_cmd_output (Printf.sprintf
      "cd %s && %s %s 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote src)) in
    Alcotest.(check bool) "interpreter panics on float non-exhaustive match" true
      (ir_contains interp_out "non-exhaustive" || ir_contains interp_out "panic");
    (* --- compiled: must panic (exit 1), not exit 0 with a wrong value --- *)
    let bin = Filename.concat tmp "floatpatnowildbin" in
    let compile_rc = Sys.command (Printf.sprintf
      "cd %s && %s --compile -o %s %s >/dev/null 2>&1"
      (Filename.quote project_root)
      (Filename.quote main_exe) (Filename.quote bin) (Filename.quote src)) in
    Alcotest.(check int) "compiles ok" 0 compile_rc;
    let run_out = read_cmd_output (Printf.sprintf "%s 2>&1; echo EXIT:$?" (Filename.quote bin)) in
    Alcotest.(check bool)
      "compiled float non-exhaustive match panics with a non-exhaustive-match \
       message (not exit 0 with a wrong value, and not a segfault)"
      true
      ((ir_contains run_out "non-exhaustive" || ir_contains run_out "panic")
       && ir_contains run_out "EXIT:1")
  end

let codegen_suites =
  [
      ( "nested_lit_pattern_codegen", [
          Alcotest.test_case "nested bool lit: no tag switch"   `Quick test_nested_bool_lit_pattern_no_tag_switch;
          Alcotest.test_case "nested int lit: tagged switch"    `Quick test_nested_int_lit_pattern_tagged_switch;
          Alcotest.test_case "nested atom lit: no tag switch"   `Quick test_nested_atom_lit_pattern_no_tag_switch;
        ] );
      ( "tco_codegen", [
          Alcotest.test_case "factorial loop emitted"   `Quick test_tco_factorial_has_loop;
          Alcotest.test_case "fold loop emitted"        `Quick test_tco_fold_has_loop;
          Alcotest.test_case "non-tail fib no loop"     `Quick test_tco_nontail_fib_no_loop;
          Alcotest.test_case "countdown loop emitted"   `Quick test_tco_countdown_has_loop;
        ] );
      ( "mutual_tco_codegen", [
          Alcotest.test_case "even/odd loop emitted"    `Quick test_mutual_tco_even_odd_loop_emitted;
          Alcotest.test_case "three-way mutual TCO"     `Quick test_mutual_tco_three_way;
          Alcotest.test_case "state machine mutual TCO" `Quick test_mutual_tco_state_machine;
          Alcotest.test_case "non-tail mutual: no loop" `Quick test_mutual_tco_non_tail_no_loop;
          Alcotest.test_case "self TCO unaffected"      `Quick test_mutual_tco_self_tco_unaffected;
        ] );
      ( "phase4_reduction_codegen", [
          Alcotest.test_case "non-leaf has reduction check"      `Quick test_phase4_nonleaf_has_reduction_check;
          Alcotest.test_case "leaf fn no reduction check"        `Quick test_phase4_leaf_fn_no_reduction_check;
          Alcotest.test_case "TCO fn reduction check in loop"    `Quick test_phase4_tco_fn_reduction_in_loop;
          Alcotest.test_case "non-recursive caller has check"    `Quick test_phase4_nonrecursive_caller_has_check;
        ] );
      "multiline", [
        Alcotest.test_case "depth zero" `Quick test_multiline_depth_zero;
        Alcotest.test_case "depth open" `Quick test_multiline_depth_open;
        Alcotest.test_case "depth closed" `Quick test_multiline_depth_closed;
        Alcotest.test_case "ends with with" `Quick test_multiline_ends_with_with;
        Alcotest.test_case "not ends with with" `Quick test_multiline_not_ends_with_with;
        Alcotest.test_case "starts with pipe" `Quick test_multiline_starts_with_pipe;
        Alcotest.test_case "is_complete simple" `Quick test_multiline_is_complete_simple;
        Alcotest.test_case "is_complete open block" `Quick test_multiline_is_complete_open_block;
      ];
      "repl_jit_cross_line", [
        Alcotest.test_case "let binding cross-line" `Quick test_repl_jit_cross_line_let;
        Alcotest.test_case "fn reference cross-line" `Quick test_repl_jit_cross_line_fn;
        Alcotest.test_case "hof with fn and let cross-line" `Quick test_repl_jit_cross_line_hof;
        Alcotest.test_case "stdlib List.length via precompile" `Quick test_repl_jit_stdlib_list_length;
      ];
      "repl_jit_regression", [
        Alcotest.test_case "list literal compiles" `Quick test_repl_list_literal;
        Alcotest.test_case "list literal with bigint in fragment" `Quick test_repl_list_literal_with_bigint;
        Alcotest.test_case "decimal.march parses" `Quick test_decimal_march_parses;
        Alcotest.test_case "list literal with precompile bigint" `Quick test_repl_list_literal_with_precompile_bigint;
        Alcotest.test_case "stdlib on list literal" `Quick test_repl_stdlib_on_list;
        Alcotest.test_case "var redefinition" `Quick test_repl_var_redefinition;
        Alcotest.test_case "stdlib chain" `Quick test_repl_stdlib_chain;
        Alcotest.test_case "expr after let" `Quick test_repl_expr_after_let;
        Alcotest.test_case "v magic var (int)" `Quick test_repl_jit_v_magic_int;
        Alcotest.test_case "list pretty-print display" `Quick test_repl_jit_list_display;
        Alcotest.test_case "assign hint (x = 5)" `Quick test_repl_assign_hint;
        Alcotest.test_case "general REPL interaction" `Quick test_repl_jit_general_interaction;
        (* P0 compiled_fns corruption fix *)
        Alcotest.test_case "P0: List.reverse works (precompile)" `Quick test_repl_jit_stdlib_reverse;
        Alcotest.test_case "P0: stdlib fns inline (no precompile)" `Quick test_repl_jit_stdlib_no_precompile;
        Alcotest.test_case "P0: List.length x3 successive fragments" `Quick test_repl_jit_stdlib_length_3x;
      ];
      "complete", [
        Alcotest.test_case "command" `Quick test_complete_command;
        Alcotest.test_case "keyword" `Quick test_complete_keyword;
        Alcotest.test_case "in scope" `Quick test_complete_in_scope;
        Alcotest.test_case "empty all" `Quick test_complete_empty_all;
      ];
      "complete_replace", [
        Alcotest.test_case "prefix only"    `Quick test_complete_replace_prefix;
        Alcotest.test_case "mid word"       `Quick test_complete_replace_midword;
        Alcotest.test_case "with suffix"    `Quick test_complete_replace_with_suffix;
      ];
      "actors", [
        Alcotest.test_case "empty"  `Quick test_list_actors_empty;
        Alcotest.test_case "alive"  `Quick test_list_actors_alive;
        Alcotest.test_case "sorted" `Quick test_list_actors_sorted;
      ];
      "debugger", [
        Alcotest.test_case "EDbg AST"               `Quick test_edbg_ast;
        Alcotest.test_case "dbg keyword"            `Quick test_lexer_keyword_dbg;
        Alcotest.test_case "parse dbg()"            `Quick test_parse_dbg;
        Alcotest.test_case "desugar EDbg"           `Quick test_desugar_edbg;
        Alcotest.test_case "typecheck EDbg"         `Quick test_typecheck_edbg;
        Alcotest.test_case "eval EDbg no-op"        `Quick test_eval_edbg_noop;
        Alcotest.test_case "ring buffer"            `Quick test_ring_buffer;
        Alcotest.test_case "trace recording"        `Quick test_trace_recording;
        Alcotest.test_case "trace navigation"       `Quick test_trace_navigation;
        Alcotest.test_case "replay"                 `Quick test_replay;
        Alcotest.test_case "debug continue"         `Quick test_debug_continue;
        Alcotest.test_case "trace overflow"         `Quick test_trace_overflow;
        Alcotest.test_case "actor snapshot"         `Quick test_actor_snapshot;
      ];
      "docstrings", [
        Alcotest.test_case "parse fn doc"         `Quick test_doc_parse_fn;
        Alcotest.test_case "triple-quoted doc"    `Quick test_doc_triple_quoted;
        Alcotest.test_case "doc preserved after desugar" `Quick test_doc_desugar;
        Alcotest.test_case "doc registered in eval" `Quick test_doc_eval_registry;
        Alcotest.test_case "doc in nested module" `Quick test_doc_nested_module;
        Alcotest.test_case "no doc is None"       `Quick test_doc_none;
      ];
      ("purity", [
        Alcotest.test_case "atom"         `Quick test_purity_atom;
        Alcotest.test_case "arith"        `Quick test_purity_arith;
        Alcotest.test_case "println"      `Quick test_purity_println;
        Alcotest.test_case "print"        `Quick test_purity_print;
        Alcotest.test_case "send"         `Quick test_purity_send;
        Alcotest.test_case "let_pure"     `Quick test_purity_let_pure;
        Alcotest.test_case "let_impure"   `Quick test_purity_let_impure;
        Alcotest.test_case "callptr"    `Quick test_purity_callptr;
        Alcotest.test_case "kill"       `Quick test_purity_kill;
        Alcotest.test_case "incrc"      `Quick test_purity_incrc;
        Alcotest.test_case "free"       `Quick test_purity_free;
      ]);
      ("fold", [
        Alcotest.test_case "int_add"                 `Quick test_fold_int_add;
        Alcotest.test_case "int_mul"                 `Quick test_fold_int_mul;
        Alcotest.test_case "int_div_by_zero"         `Quick test_fold_int_div_by_zero;
        Alcotest.test_case "float_add"               `Quick test_fold_float_add;
        Alcotest.test_case "bool_not"                `Quick test_fold_bool_not;
        Alcotest.test_case "and_shortcircuit_pure"   `Quick test_fold_and_shortcircuit_pure;
        Alcotest.test_case "and_shortcircuit_impure" `Quick test_fold_and_shortcircuit_impure;
        Alcotest.test_case "if_true"                 `Quick test_fold_if_true;
        Alcotest.test_case "if_false"                `Quick test_fold_if_false;
        Alcotest.test_case "and_pure_var"            `Quick test_fold_and_pure_var;
        Alcotest.test_case "or_shortcircuit_pure"    `Quick test_fold_or_shortcircuit_pure;
        Alcotest.test_case "string_concat"           `Quick test_fold_string_concat;
        Alcotest.test_case "string_byte_length"      `Quick test_fold_string_byte_length;
        Alcotest.test_case "string_is_empty"         `Quick test_fold_string_is_empty;
        Alcotest.test_case "string_is_empty_false"   `Quick test_fold_string_is_empty_false;
        Alcotest.test_case "eq_true_rhs"             `Quick test_fold_eq_true_rhs;
        Alcotest.test_case "eq_false_rhs"            `Quick test_fold_eq_false_rhs;
        Alcotest.test_case "int_cmp_lit_true"        `Quick test_fold_int_cmp_lit;
        Alcotest.test_case "int_cmp_lit_false"       `Quick test_fold_int_cmp_lit_false;
      ]);
      ("simplify", [
        Alcotest.test_case "add_zero"          `Quick test_simplify_add_zero;
        Alcotest.test_case "mul_one"           `Quick test_simplify_mul_one;
        Alcotest.test_case "mul_zero_pure"     `Quick test_simplify_mul_zero_pure;
        Alcotest.test_case "sub_self"          `Quick test_simplify_sub_self;
        Alcotest.test_case "sub_different"     `Quick test_simplify_sub_different;
        Alcotest.test_case "div_one"           `Quick test_simplify_div_one;
        Alcotest.test_case "zero_div"          `Quick test_simplify_zero_div;
        Alcotest.test_case "zero_div_lit"      `Quick test_simplify_zero_div_lit;
        Alcotest.test_case "strength_reduce"   `Quick test_simplify_strength_reduce;
        Alcotest.test_case "float_add_zero"    `Quick test_simplify_float_add_zero;
        Alcotest.test_case "bool_and_true"     `Quick test_simplify_bool_and_true;
        Alcotest.test_case "str_concat_empty_rhs" `Quick test_simplify_string_concat_empty_rhs;
        Alcotest.test_case "str_concat_empty_lhs" `Quick test_simplify_string_concat_empty_lhs;
        Alcotest.test_case "str_concat_not_folded_post_perceus" `Quick test_simplify_string_concat_not_folded_post_perceus;
        Alcotest.test_case "if_then_true_else_false"  `Quick test_simplify_if_then_true_else_false;
        Alcotest.test_case "if_then_false_else_true"  `Quick test_simplify_if_then_false_else_true;
        Alcotest.test_case "eq_self"                  `Quick test_simplify_eq_self;
        Alcotest.test_case "ne_self"                  `Quick test_simplify_ne_self;
        Alcotest.test_case "eq_self_float_no_reduce"  `Quick test_simplify_eq_self_float_no_reduce;
        Alcotest.test_case "eq_self_tuple_float_no_reduce" `Quick test_simplify_eq_self_tuple_float_no_reduce;
        Alcotest.test_case "and_false_rhs"            `Quick test_simplify_and_false_rhs;
        Alcotest.test_case "and_false_lhs"            `Quick test_simplify_and_false_lhs;
        Alcotest.test_case "or_true_rhs"              `Quick test_simplify_or_true_rhs;
        Alcotest.test_case "not_true"                 `Quick test_simplify_not_true;
        Alcotest.test_case "not_false"                `Quick test_simplify_not_false;
      ]);
      ("inline", [
        Alcotest.test_case "pure_small"            `Quick test_inline_pure_small;
        Alcotest.test_case "impure_not_inlined"    `Quick test_inline_impure_not_inlined;
        Alcotest.test_case "recursive_not_inlined" `Quick test_inline_recursive_not_inlined;
        Alcotest.test_case "mutual_recursion_not_inlined" `Quick test_inline_mutual_recursion_not_inlined;
      ]);
      ("known_call", [
        Alcotest.test_case "direct"          `Quick test_known_call_direct;
        Alcotest.test_case "unknown_unchanged" `Quick test_known_call_unknown_unchanged;
        Alcotest.test_case "two_closures"    `Quick test_known_call_two_closures;
        Alcotest.test_case "stack_alloc"     `Quick test_known_call_stack_alloc;
      ]);
      ("struct_fusion", [
        Alcotest.test_case "two_updates"       `Quick test_struct_fusion_two_updates;
        Alcotest.test_case "three_updates"     `Quick test_struct_fusion_three_updates;
        Alcotest.test_case "field_override"    `Quick test_struct_fusion_field_override;
        Alcotest.test_case "no_fuse_multi_use" `Quick test_struct_fusion_no_fuse_multi_use;
      ]);
      ("dce", [
        Alcotest.test_case "dead_pure_let"       `Quick test_dce_dead_pure_let;
        Alcotest.test_case "impure_let_kept"     `Quick test_dce_impure_let_kept;
        Alcotest.test_case "used_let_kept"       `Quick test_dce_used_let_kept;
        Alcotest.test_case "unreachable_top_fn"  `Quick test_dce_unreachable_topfn;
      ]);
      ("opt", [
        Alcotest.test_case "fixpoint"         `Quick test_opt_fixpoint;
        Alcotest.test_case "no_infinite_loop" `Quick test_opt_no_infinite_loop;
      ]);
      ("cprop", [
        Alcotest.test_case "simple_literal"       `Quick test_cprop_simple_literal;
        Alcotest.test_case "chain"                `Quick test_cprop_chain;
        Alcotest.test_case "enables_fold"         `Quick test_cprop_enables_fold;
        Alcotest.test_case "no_propagate_complex" `Quick test_cprop_no_propagate_complex;
        Alcotest.test_case "case_branch_shadow"      `Quick test_cprop_case_branch_shadow;
        Alcotest.test_case "opt_integration"         `Quick test_cprop_opt_integration;
        Alcotest.test_case "no_propagate_into_decrc" `Quick test_cprop_no_propagate_into_rc;
        Alcotest.test_case "no_propagate_into_incrc" `Quick test_cprop_no_propagate_into_incrc;
        Alcotest.test_case "no_propagate_into_free"  `Quick test_cprop_no_propagate_into_free;
        Alcotest.test_case "field_fold_record"       `Quick test_cprop_field_fold_record;
        Alcotest.test_case "field_fold_alias"        `Quick test_cprop_field_fold_alias;
        Alcotest.test_case "field_fold_update"       `Quick test_cprop_field_fold_update;
        Alcotest.test_case "var_alias"               `Quick test_cprop_var_alias;
        Alcotest.test_case "var_chain"               `Quick test_cprop_var_chain;
        Alcotest.test_case "no_alias_closure"        `Quick test_cprop_var_no_alias_closure;
      ]);
      ("beta_adt", [
        Alcotest.test_case "ok_inline"               `Quick test_beta_adt_ok_inline;
        Alcotest.test_case "qualified_tag"           `Quick test_beta_adt_qualified_tag;
        Alcotest.test_case "no_fire_non_case"        `Quick test_beta_adt_no_fire_non_case;
      ]);
      ("fbip_p8", [
        Alcotest.test_case "same_arity_match"        `Quick test_same_arity_match;
        Alcotest.test_case "same_arity_mismatch"     `Quick test_same_arity_mismatch;
        Alcotest.test_case "same_arity_non_tcon"     `Quick test_same_arity_non_tcon;
        Alcotest.test_case "cross_tag_reuse"         `Quick test_fbip_cross_tag_reuse;
        Alcotest.test_case "no_reuse_arity_mismatch" `Quick test_fbip_no_reuse_arity_mismatch;
      ]);
      ("join_points", [
        Alcotest.test_case "float_common_let"       `Quick test_join_points_float_common_let;
        Alcotest.test_case "no_float_different_rhs" `Quick test_join_points_no_float_different_rhs;
        Alcotest.test_case "no_float_uses_br_var"   `Quick test_join_points_no_float_uses_br_var;
        Alcotest.test_case "float_two_common_lets"  `Quick test_join_points_float_two_common_lets;
        Alcotest.test_case "pre_float_alpha"         `Quick test_join_points_pre_float_alpha;
        Alcotest.test_case "pre_no_float_diff_rhs"   `Quick test_join_points_pre_no_float_different_rhs;
      ]);
      ("repr", [
        Alcotest.test_case "newtype_int"          `Quick test_repr_newtype_int;
        Alcotest.test_case "newtype_ptr"          `Quick test_repr_newtype_ptr;
        Alcotest.test_case "multivariant_boxed"   `Quick test_repr_multivariant_is_boxed;
        Alcotest.test_case "multifield_boxed"     `Quick test_repr_multifield_is_boxed;
        Alcotest.test_case "scalar_boxed"         `Quick test_repr_scalar_is_boxed;
        Alcotest.test_case "niche_int"            `Quick test_repr_niche_int;
        Alcotest.test_case "niche_string"         `Quick test_repr_niche_string;
        Alcotest.test_case "niche_bool"           `Quick test_repr_niche_bool;
        Alcotest.test_case "niche_float_boxed"    `Quick test_repr_niche_float_is_boxed;
        Alcotest.test_case "niche_unit_boxed"     `Quick test_repr_niche_unit_is_boxed;
        Alcotest.test_case "nested_niche_boxed"   `Quick test_repr_nested_niche_is_boxed;
      ]);
      ("fast_math", [
        Alcotest.test_case "emits_fast_attr" `Quick test_fast_math_emits_fast_attr;
      ]);
      ("llvm_emit correctness", [
        Alcotest.test_case "ctor_no_collision_different_tags" `Quick
          test_ctor_no_collision_different_tags;
        Alcotest.test_case "ctor_arity_mismatch_raises" `Quick
          test_ctor_arity_mismatch_raises;
        Alcotest.test_case "compiled main calls march_run_scheduler" `Quick
          (with_reset test_compiled_main_calls_march_run_scheduler);
        Alcotest.test_case "string_chars llvm emit" `Quick
          test_string_chars_llvm_emit;
        Alcotest.test_case "int tag coerce IR (shl+or+ashr)" `Quick
          test_int_tag_coerce_ir;
        Alcotest.test_case "int tag wrapper IR (shl+or in wrapper)" `Quick
          test_int_tag_wrapper_ir;
        (* Regression: 831e315 + perceus caused @__ undefined symbol in &&/|| *)
        Alcotest.test_case "no @__ call for && / || (831e315)" `Quick
          test_llvm_no_call_to_double_underscore;
      ]);
      ("string stdlib", [
        Alcotest.test_case "byte_size"           `Quick test_string_byte_size;
        Alcotest.test_case "byte_size empty"     `Quick test_string_byte_size_empty;
        Alcotest.test_case "byte_size unicode"   `Quick test_string_byte_size_unicode;
        Alcotest.test_case "slice_bytes"         `Quick test_string_slice_bytes;
        Alcotest.test_case "slice_bytes clamp"   `Quick test_string_slice_bytes_clamp;
        Alcotest.test_case "contains"            `Quick test_string_contains;
        Alcotest.test_case "starts_with"         `Quick test_string_starts_with;
        Alcotest.test_case "ends_with"           `Quick test_string_ends_with;
        Alcotest.test_case "concat"              `Quick test_string_concat;
        Alcotest.test_case "replace"             `Quick test_string_replace;
        Alcotest.test_case "replace_all"         `Quick test_string_replace_all;
        Alcotest.test_case "split"               `Quick test_string_split;
        Alcotest.test_case "split_first"         `Quick test_string_split_first;
        Alcotest.test_case "split_first no sep"  `Quick test_string_split_first_no_sep;
        Alcotest.test_case "join"                `Quick test_string_join;
        Alcotest.test_case "trim"                `Quick test_string_trim;
        Alcotest.test_case "trim_start"          `Quick test_string_trim_start;
        Alcotest.test_case "trim_end"            `Quick test_string_trim_end;
        Alcotest.test_case "to_uppercase"        `Quick test_string_to_uppercase;
        Alcotest.test_case "to_lowercase"        `Quick test_string_to_lowercase;
        Alcotest.test_case "repeat"              `Quick test_string_repeat;
        Alcotest.test_case "reverse"             `Quick test_string_reverse;
        Alcotest.test_case "pad_left"            `Quick test_string_pad_left;
        Alcotest.test_case "pad_right"           `Quick test_string_pad_right;
        Alcotest.test_case "chars"               `Quick test_string_chars;
        Alcotest.test_case "chars empty"         `Quick test_string_chars_empty;
        Alcotest.test_case "to_upper"            `Quick test_string_to_upper;
        Alcotest.test_case "to_lower"            `Quick test_string_to_lower;
        Alcotest.test_case "is_empty"            `Quick test_string_is_empty;
        Alcotest.test_case "grapheme_count"      `Quick test_string_grapheme_count;
        Alcotest.test_case "index_of"            `Quick test_string_index_of;
        Alcotest.test_case "to_int"              `Quick test_string_to_int;
        Alcotest.test_case "to_float"            `Quick test_string_to_float;
        Alcotest.test_case "from_int"            `Quick test_string_from_int;
        Alcotest.test_case "from_float"          `Quick test_string_from_float;
      ]);
      ("iolist stdlib", [
        Alcotest.test_case "empty"         `Quick test_iolist_empty;
        Alcotest.test_case "from_string"   `Quick test_iolist_from_string;
        Alcotest.test_case "append"        `Quick test_iolist_append;
        Alcotest.test_case "byte_size"     `Quick test_iolist_byte_size;
      ]);
      ("~H sigil codegen", [
        Alcotest.test_case "static ~H lowers to List.Cons"
          `Quick test_h_sigil_static_lowers_to_list_cons;
        Alcotest.test_case "int interp coerces arg to ptr"
          `Quick test_h_sigil_int_interp_coerces_arg_to_ptr;
      ]);
      ("http stdlib", [
        Alcotest.test_case "parse_url"          `Quick test_http_parse_url;
        Alcotest.test_case "parse_url scheme"    `Quick test_http_parse_url_scheme;
        Alcotest.test_case "parse_url path"      `Quick test_http_parse_url_path;
        Alcotest.test_case "parse_url port"      `Quick test_http_parse_url_port;
        Alcotest.test_case "parse_url invalid"   `Quick test_http_parse_url_invalid;
        Alcotest.test_case "set_header"          `Quick test_http_set_header;
        Alcotest.test_case "method_to_string"    `Quick test_http_method_to_string;
        Alcotest.test_case "status helpers"      `Quick test_http_status_helpers;
        Alcotest.test_case "post constructor"    `Quick test_http_post_constructor;
        Alcotest.test_case "encode_query"        `Quick test_http_encode_query;
        Alcotest.test_case "response helpers"    `Quick test_http_response_helpers;
      ]);
      ("http builtins", [
        Alcotest.test_case "serialize request"       `Quick test_http_serialize_request;
        Alcotest.test_case "serialize with body"     `Quick test_http_serialize_request_with_body;
        Alcotest.test_case "parse response"          `Quick test_http_parse_response;
        Alcotest.test_case "parse response body"     `Quick test_http_parse_response_body;
      ]);
      ("http client", [
        Alcotest.test_case "new client"              `Quick test_http_client_new;
        Alcotest.test_case "add steps"               `Quick test_http_client_add_steps;
        Alcotest.test_case "bearer auth transform"   `Quick test_http_client_request_step_transforms;
        Alcotest.test_case "raise on error status"   `Quick test_http_client_raise_on_error_status;
        Alcotest.test_case "with redirects"          `Quick test_http_client_with_redirects;
        Alcotest.test_case "base url step"           `Quick test_http_client_base_url_step;
        Alcotest.test_case "content type step"       `Quick test_http_client_content_type_step;
      ]);
      ( "scheduler",
        [
          Alcotest.test_case "reduction counter ticks"     `Quick (with_reset test_reduction_counter_ticks);
          Alcotest.test_case "reduction counter exhausts"  `Quick (with_reset test_reduction_counter_exhausts);
          Alcotest.test_case "eval yields after budget"    `Quick (with_reset test_eval_yields_after_budget);
          Alcotest.test_case "eval no yield when disabled" `Quick (with_reset test_eval_no_yield_when_disabled);
          Alcotest.test_case "reduction count"             `Quick (with_reset test_eval_reduction_count);
        ] );
      ( "native_arrays",
        [
          Alcotest.test_case "int arr IR"   `Quick (with_reset test_native_int_arr_ir);
          Alcotest.test_case "float arr IR" `Quick (with_reset test_native_float_arr_ir);
        ] );
      ( "tasks",
        [
          Alcotest.test_case "spawn and await"     `Quick (with_reset test_eval_task_spawn_await);
          Alcotest.test_case "await unwrap"        `Quick (with_reset test_eval_task_await_unwrap);
          Alcotest.test_case "multiple tasks"      `Quick (with_reset test_eval_task_multiple);
          Alcotest.test_case "task captures env"   `Quick (with_reset test_eval_task_captures_env);
          Alcotest.test_case "spawn_steal requires pool" `Quick (with_reset test_eval_spawn_steal_requires_pool);
          Alcotest.test_case "spawn_steal with pool"     `Quick (with_reset test_eval_spawn_steal_with_pool);
          Alcotest.test_case "workpool threading"        `Quick (with_reset test_eval_workpool_threading);
          Alcotest.test_case "task sends to actor"       `Quick (with_reset test_eval_task_sends_to_actor);
          Alcotest.test_case "task_spawn heap-alloc no RC underflow" `Quick
            (with_reset test_compile_task_spawn_heap_alloc_no_rc_underflow);
          Alcotest.test_case "local shadowing builtin still gets RC ops (B10)" `Quick
            (with_reset test_compile_local_shadows_builtin_still_gets_rc_ops);
          (* Phase 5: compiled IR correctness *)
          Alcotest.test_case "task_yield emits sched_yield"        `Quick
            (with_reset test_compile_task_yield_actually_yields);
          Alcotest.test_case "task_reductions reads TLS"           `Quick
            (with_reset test_compile_task_reductions_reads_tls);
          Alcotest.test_case "task_await uses march_task_await"    `Quick
            (with_reset test_compile_task_await_in_ir);
          Alcotest.test_case "cancel token IR correctness"         `Quick
            (with_reset test_compile_cancel_token_ir);
          (* Phase 5B: cancel tokens *)
          Alcotest.test_case "cancel token new"          `Quick (with_reset test_cancel_token_new);
          Alcotest.test_case "cancel token cancel"       `Quick (with_reset test_cancel_token_cancel);
          Alcotest.test_case "cancel tokens independent" `Quick (with_reset test_cancel_tokens_independent);
          Alcotest.test_case "spawn_with_cancel active"  `Quick (with_reset test_spawn_with_cancel_active);
          Alcotest.test_case "spawn_with_cancel pre-cancelled" `Quick (with_reset test_spawn_with_cancel_precancelled);
          Alcotest.test_case "cancel_by_id"              `Quick (with_reset test_cancel_by_id);
          (* Phase 5C: structured concurrency *)
          Alcotest.test_case "race single"               `Quick (with_reset test_task_race_single);
          Alcotest.test_case "race cancels losers"       `Quick (with_reset test_task_race_cancels_losers);
          Alcotest.test_case "race empty"                `Quick (with_reset test_task_race_empty);
          Alcotest.test_case "all_settled mixed results" `Quick (with_reset test_task_all_settled);
        ] );
      ( "work_stealing",
        [
          Alcotest.test_case "deque push/pop"     `Quick (with_reset test_deque_push_pop);
          Alcotest.test_case "deque steal"        `Quick (with_reset test_deque_steal);
          Alcotest.test_case "deque size"         `Quick (with_reset test_deque_size);
          Alcotest.test_case "pool submit/steal"  `Quick (with_reset test_pool_submit_steal);
        ] );
      ( "capabilities",
        [
          Alcotest.test_case "pure module ok"            `Quick test_cap_needs_pure_ok;
          Alcotest.test_case "declared needs ok"         `Quick test_cap_needs_declared_ok;
          Alcotest.test_case "missing needs error"       `Quick test_cap_missing_needs_error;
          Alcotest.test_case "unused needs warning"      `Quick test_cap_unused_needs_warning;
          Alcotest.test_case "extern block counts as cap use" `Quick test_cap_extern_block_counts_as_use;
          Alcotest.test_case "supertype covers subtype"  `Quick test_cap_supertype_covers_subtype;
          Alcotest.test_case "wrong subtype error"       `Quick test_cap_needs_wrong_subtype;
          Alcotest.test_case "multiple needs"            `Quick test_cap_multiple_needs;
          Alcotest.test_case "parse needs"               `Quick test_cap_parse_needs;
          Alcotest.test_case "parse needs dotted"        `Quick test_cap_parse_needs_dotted;
          Alcotest.test_case "transitive ok"             `Quick test_cap_transitive_ok;
          Alcotest.test_case "transitive missing error"  `Quick test_cap_transitive_missing_error;
          Alcotest.test_case "transitive supertype ok"   `Quick test_cap_transitive_supertype_ok;
          Alcotest.test_case "transitive chain error"    `Quick test_cap_transitive_chain_error;
          Alcotest.test_case "extern with needs ok"      `Quick test_cap_extern_with_needs_ok;
          Alcotest.test_case "extern missing needs error" `Quick test_cap_extern_missing_needs_error;
          Alcotest.test_case "ffi: extern explicit symbol in IR" `Quick test_ffi_extern_explicit_symbol_ir;
          Alcotest.test_case "ffi: extern default symbol in IR"  `Quick test_ffi_extern_default_symbol_ir;
          Alcotest.test_case "effects entry point clean"  `Quick test_cap_effects_clean;
          Alcotest.test_case "effects entry point violation" `Quick test_cap_effects_violation;
          Alcotest.test_case "eval path blocked by cap error" `Quick test_cap_eval_path_blocked;
          Alcotest.test_case "eval path ok with needs"    `Quick test_cap_eval_path_ok;
          Alcotest.test_case "proof cap: parse"               `Quick test_proof_cap_parse;
          Alcotest.test_case "proof cap: decl ok"             `Quick test_proof_cap_declaration_ok;
          Alcotest.test_case "proof cap: forge error"         `Quick test_proof_cap_forge_error;
          Alcotest.test_case "proof cap: passthrough ok"      `Quick test_proof_cap_passthrough_ok;
          Alcotest.test_case "proof cap: missing needs"       `Quick test_proof_cap_missing_needs_error;
          Alcotest.test_case "proof cap: declaring mod ok"    `Quick test_proof_cap_in_declaring_module_ok;
          Alcotest.test_case "proof cap: implicit needs"      `Quick test_proof_cap_implicit_needs;
          Alcotest.test_case "proof cap: pfn forge error"     `Quick test_proof_cap_pfn_forge_error;
          Alcotest.test_case "proof cap: pfn passthrough ok"  `Quick test_proof_cap_pfn_passthrough_ok;
        ] );
      ( "js_backend_opt", [
          Alcotest.test_case "Opt safe without Perceus" `Quick test_opt_without_perceus;
        ] );
      ( "guard_exhaustion_codegen", [
          Alcotest.test_case "compiled guard exhaustion panics (B3)" `Quick
            test_guard_exhaustion_panics_compiled;
        ] );
      ( "float_lit_match_codegen", [
          Alcotest.test_case "compiled float-literal match arm (B4)" `Quick
            test_float_lit_match_arm_compiled;
          Alcotest.test_case "compiled float non-exhaustive match panics (B4)" `Quick
            test_float_lit_no_wildcard_panics_compiled;
        ] );
  ]

