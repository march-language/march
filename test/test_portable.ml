(* Portable closures at parallel boundaries
   (specs/2026-10-07-portable-closures-design.md): a closure passed to a
   many-call parallel combinator must not capture a native resource handle.
   End to end through `march --compile`, like test_alloc_contract.ml. *)

let contains (hay : string) (needle : string) : bool =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  n = 0 || go 0

let compile ?(flags = "") src = Test_cap_ceiling.compile_with ~flags src

(* Compiles, runs the binary, and runs the interpreter: compiled parity. *)
let compile_and_run src =
  let exe = Test_cap_ceiling.compiler_exe in
  let f = Filename.temp_file "portable" ".march" in
  let oc = open_out f in
  output_string oc src;
  close_out oc;
  let bin = Filename.temp_file "portable" ".bin" in
  let log = Filename.temp_file "portable" ".log" in
  let read p =
    let ic = open_in p in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic; s
  in
  let rc = Sys.command (Printf.sprintf "%s --compile -o %s %s > %s 2>&1"
                          (Filename.quote exe) (Filename.quote bin)
                          (Filename.quote f) (Filename.quote log)) in
  let compile_out = read log in
  let run_out =
    if rc = 0 then begin
      ignore (Sys.command (Printf.sprintf "%s > %s 2>/dev/null" (Filename.quote bin) (Filename.quote log)));
      read log
    end else "" in
  ignore (Sys.command (Printf.sprintf "%s %s > %s 2>/dev/null"
                         (Filename.quote exe) (Filename.quote f) (Filename.quote log)));
  let interp_out = read log in
  List.iter (fun p -> try Sys.remove p with _ -> ()) [f; bin; log];
  (rc, compile_out, run_out, interp_out)

let accepts name src expected_stdout =
  let (rc, out, run_out, interp_out) = compile_and_run src in
  if rc <> 0 then Alcotest.failf "%s: expected accept, got rc=%d:\n%s" name rc out;
  Alcotest.(check string) (name ^ ": compiled output") expected_stdout run_out;
  Alcotest.(check string) (name ^ ": interpreter parity") expected_stdout interp_out;
  Alcotest.(check bool) (name ^ ": no portability diagnostic") false
    (contains out "portable_capture")

let rejects name src needles =
  let (rc, out) = compile src in
  if rc = 0 then Alcotest.failf "%s: expected reject, compiled fine" name;
  List.iter (fun needle ->
      if not (contains out needle) then Alcotest.failf "%s: missing %S in:\n%s" name needle out)
    needles

(* A native handle from the runtime's FFI test accumulator (march_ffi.c). *)
let prelude = {|mod Main do
needs IO.Console
needs IO.Spawn
needs Ffi
needs IO.Foreign
resource Acc
extern "rt" : Cap(Ffi) do
  fn acc_new(): Acc = "ffi_acc_new"
  fn acc_push(a: Acc, n: Int): Int = "ffi_acc_push"
  fn finish(consume a: Acc): Int = "ffi_acc_finish"
end
-- Lambdas call the handle through a March function: an extern referenced
-- from inside a lambda does not link today (a separate codegen bug).
fn push(a : Acc, n : Int) : Int do
  acc_push(a, n)
end
fn fresh() : Acc do
  acc_new()
end
fn total(a : Acc) : Int do
  finish(a)
end
|}

let program body main =
  prelude ^ body
  ^ "\nfn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign), _s : Cap(IO.Spawn)) : Unit do\n"
  ^ main ^ "\n  ()\nend\nend\n"

(* ── Rejected ────────────────────────────────────────────────────────── *)

let test_direct_capture () =
  rejects "direct"
    (program {|
fn direct(a : Acc, xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x -> acc_push(a, x))
end|} {|  let a = acc_new()
  println(int_to_string(List.length(direct(a, [1, 2]))))|})
    [ "`direct` passes a closure that captures `a` to `List.pmap`";
      "`a` is a native resource handle (`Acc`)"; "[portable_capture]" ]

let test_through_data () =
  rejects "through data"
    (program {|
type Box = Box(Acc, Int)
fn nested(b : Box, xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x -> match b do Box(a, k) -> acc_push(a, x + k) end)
end|} {|  println(int_to_string(List.length(nested(Box(acc_new(), 1), [1, 2]))))|})
    [ "`b` is a `Box`, which holds a native resource handle (`Acc`)" ]

let test_through_wrapper () =
  rejects "through a wrapper"
    (program {|
fn wrapper(xs : List(Int), f : Int -> Int) : List(Int) do
  List.pmap(xs, f)
end
fn via_wrapper(a : Acc, xs : List(Int)) : List(Int) do
  wrapper(xs, fn x -> acc_push(a, x))
end|} {|  println(int_to_string(List.length(via_wrapper(acc_new(), [1, 2]))))|})
    [ "`via_wrapper` passes a closure that captures `a` to `wrapper`";
      "through `List.pmap`" ]

let test_inside_lambda_reports_named_fn () =
  rejects "inside a lambda"
    (program {|
fn outer(a : Acc, xs : List(Int)) : List(List(Int)) do
  List.map([1, 2], fn _y -> List.pmap(xs, fn x -> acc_push(a, x)))
end|} {|  println(int_to_string(List.length(outer(acc_new(), [1, 2]))))|})
    [ "`outer` passes a closure that captures `a` to `List.pmap`" ]

let test_through_captured_closure () =
  rejects "through a captured closure"
    (program {|
fn twice(a : Acc, xs : List(Int)) : List(Int) do
  let g = fn x -> acc_push(a, x)
  List.pmap(xs, fn x -> g(x) + 1)
end|} {|  println(int_to_string(List.length(twice(acc_new(), [1, 2]))))|})
    [ "captures `a` to `List.pmap`" ]

let test_generic_instantiated_with_resource () =
  (* Generic code is checked after monomorphization: `gen` is fine for an Int,
     rejected for its instance at Acc. *)
  rejects "generic instance"
    (program {|
fn gen(h, xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x -> let _keep = h
                        x)
end|} {|  println(int_to_string(List.length(gen(5, [1]))))
  println(int_to_string(List.length(gen(acc_new(), [1, 2]))))|})
    [ "native resource handle (`Acc`)" ]

let test_task_async_stream () =
  rejects "Task.async_stream"
    (program {|
fn stream(a : Acc, xs : List(Int)) : Int do
  List.length(Authority.must(Task.async_stream(xs, fn x -> acc_push(a, x))))
end|} {|  println(int_to_string(stream(acc_new(), [1, 2])))|})
    [ "to `Task.async_stream`" ]

let test_closure_captured_by_parallel_lambda () =
  (* `h` captures `g` and runs it through List.pmap: after Defun, `g` is a
     free variable of h's apply function ($clo.$fv1), so allocating `h` is
     itself a parallel use of `g`. *)
  rejects "closure captured by a parallel lambda"
    (program {|
fn nest(a : Acc, xs : List(Int)) : List(Int) do
  let g = fn x -> push(a, x)
  let h = fn ys -> List.pmap(ys, g)
  h(xs)
end|} {|  println(int_to_string(List.length(nest(acc_new(), [1]))))|})
    [ "`nest` passes a closure that captures `a` to `List.pmap`" ]

let test_alias () =
  rejects "alias"
    (program {|
fn aliased(a : Acc, xs : List(Int)) : List(Int) do
  let g = fn x -> push(a, x)
  let k = g
  List.pmap(xs, k)
end|} {|  println(int_to_string(List.length(aliased(acc_new(), [1]))))|})
    [ "`aliased` passes a closure that captures `a` to `List.pmap`" ]

let test_param_shadowing_a_top_level_name () =
  (* Top-level names are skipped as captures (they are code), but a parameter
     named like one is a value. *)
  rejects "parameter shadowing a top-level fn"
    (program {|
fn handle() : Acc do
  acc_new()
end
fn shadow(handle : Acc, xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x -> push(handle, x))
end|} {|  println(int_to_string(List.length(shadow(handle(), [1]))))|})
    [ "captures `handle` to `List.pmap`" ]

let test_specialised_over_a_nested_type () =
  (* The combinator call is specialised as List.pmap$<types>, and a nested
     module type puts a dot in that suffix: seeds match on the whole name. *)
  rejects "specialised over a nested-module type"
    (program {|
mod Inner do
  type Rec = Rec(Int)
end
fn dotted(a : Acc, rs : List(Inner.Rec)) : List(Int) do
  List.pmap(rs, fn r -> match r do Inner.Rec(n) -> push(a, n) end)
end|} {|  println(int_to_string(List.length(dotted(acc_new(), [Inner.Rec(1)]))))|})
    [ "`dotted` passes a closure that captures `a` to `List.pmap`" ]

(* ── Accepted ────────────────────────────────────────────────────────── *)

let test_handle_created_inside_closure () =
  (* Also the regression for a false positive: a closure naming a top-level
     function (`push : (Acc, Int) -> Int`, or zero-argument `fresh`, typed
     `Acc` in TIR) holds no Acc. *)
  accepts "handle per task"
    (program {|
fn per_task(xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x ->
    let a = fresh()
    let _ = push(a, x)
    total(a))
end|} {|  println(int_to_string(List.fold_left(per_task([1, 2, 3]), 0, fn (s, v) -> s + v)))|})
    "6\n"

let test_zero_arg_extern_is_not_a_capture () =
  (* A zero-argument extern is typed by its result in TIR (`acc_new : Acc`),
     so the capture check must skip top-level names by name.  This program
     then fails to LINK (an extern referenced from a lambda is never
     defined: a separate codegen bug), so assert on the diagnostics only. *)
  let (_rc, out) = compile (program {|
fn per_task_direct(xs : List(Int)) : List(Int) do
  List.pmap(xs, fn x -> finish(acc_new()) + x)
end|} {|  println(int_to_string(List.length(per_task_direct([1]))))|}) in
  Alcotest.(check bool) "no portability diagnostic" false (contains out "portable_capture")

let test_sequential_map_may_capture () =
  accepts "sequential map"
    (program {|
fn seq(a : Acc, xs : List(Int)) : List(Int) do
  List.map(xs, fn x -> push(a, x))
end|} {|  let a = acc_new()
  let _ = seq(a, [1, 2, 3])
  println(int_to_string(finish(a)))|})
    "6\n"

let test_task_spawn_out_of_scope () =
  (* A task runs its closure once; handing a task a handle is allowed. *)
  accepts "task_spawn"
    (program {|
fn in_task(a : Acc) : Int do
  task_await_unwrap(task_spawn(fn _ -> push(a, 4)))
end|} {|  let a = acc_new()
  let _ = in_task(a)
  println(int_to_string(finish(a)))|})
    "4\n"

let tests = [
  Alcotest.test_case "reject: direct capture"                   `Quick test_direct_capture;
  Alcotest.test_case "reject: through data"                     `Quick test_through_data;
  Alcotest.test_case "reject: through a wrapper (fixpoint)"     `Quick test_through_wrapper;
  Alcotest.test_case "reject: inside a lambda, named fn"        `Quick test_inside_lambda_reports_named_fn;
  Alcotest.test_case "reject: through a captured closure"       `Quick test_through_captured_closure;
  Alcotest.test_case "reject: generic instance at a resource"   `Quick test_generic_instantiated_with_resource;
  Alcotest.test_case "reject: Task.async_stream"                `Quick test_task_async_stream;
  Alcotest.test_case "reject: closure captured by a parallel lambda" `Quick test_closure_captured_by_parallel_lambda;
  Alcotest.test_case "reject: through an alias"                 `Quick test_alias;
  Alcotest.test_case "reject: param shadowing a top-level fn"   `Quick test_param_shadowing_a_top_level_name;
  Alcotest.test_case "reject: specialised over a nested type"   `Quick test_specialised_over_a_nested_type;
  Alcotest.test_case "accept: handle created per task"          `Quick test_handle_created_inside_closure;
  Alcotest.test_case "accept: zero-arg extern is not a capture" `Quick test_zero_arg_extern_is_not_a_capture;
  Alcotest.test_case "accept: sequential map may capture"       `Quick test_sequential_map_may_capture;
  Alcotest.test_case "accept: task_spawn is out of scope"       `Quick test_task_spawn_out_of_scope;
]
