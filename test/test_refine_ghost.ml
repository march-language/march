(* Ghost code (lib/desugar/ghost.ml; specs/lang/lemmas.md, "Ghost code").

   - The worked example, test/refine/ghost/bst.march: every obligation it
     states is proved, and it runs.
   - Erasure: bst.march and its hand-erased twin bst_erased.march (the same
     lines with the ghost code blanked) emit the same LLVM IR and the same
     JavaScript, up to the file name: function signatures, a closure that
     passed ghost arguments (its captures), and RC insertion all match.
     Before erasure ran on the compile path the IR kept `lo`/`hi` as
     parameters of `contains`, and the JS kept `{ };` where lemma calls had
     been; this comparison caught both.
   - Noninterference: each way a ghost value could reach the running program
     is rejected, and the names `ghost` keeps free are still names. *)

module U = Test_refine_unfold

let fixture name =
  let f = Filename.concat (Filename.dirname Sys.executable_name) ("refine/ghost/" ^ name) in
  if Sys.file_exists f then f else "test/refine/ghost/" ^ name

let read f = In_channel.with_open_bin f In_channel.input_all

(* The program ran and printed [want] on a line of its own.  A substring
   would also match source text an error echoes, which always carries a
   line-number gutter. *)
let printed out want =
  List.exists (fun l -> String.trim l = want) (String.split_on_char '\n' out)

let user_rows out =
  String.split_on_char '\n' out |> List.filter (fun l -> U.contains l "\tuser\t")

(* A program that must be refused with [code], whose message names [what]. *)
let rejected name ~code ~what src =
  Alcotest.test_case name `Quick (fun () ->
      let out = U.run ~args:"--check" src in
      if not (U.contains out ("[" ^ code ^ "]") && U.contains out what) then
        Alcotest.failf "expected [%s] naming %S:\n%s" code what out)

(* A program that must check with no ghost diagnostic. *)
let accepted name src =
  Alcotest.test_case name `Quick (fun () ->
      let out = U.run ~args:"--check" src in
      if U.contains out "[ghost_" || U.contains out "[syntax_error]" || U.contains out "[type_mismatch]" then
        Alcotest.failf "expected no ghost diagnostic:\n%s" out)

let first_difference a b =
  let rec go i = function
    | x :: xs, y :: ys -> if x = y then go (i + 1) (xs, ys) else Printf.sprintf "line %d:\n< %s\n> %s" i x y
    | [], [] -> "none"
    | _ -> "lengths differ"
  in
  go 1 (String.split_on_char '\n' a, String.split_on_char '\n' b)

(* [emit dir file] -> the backend's output for [file]; [norm] rewrites the
   twin's file name to the ghost program's. *)
let same_output what ~emit ~norm () =
  let dir = Filename.temp_dir "ghost" "" in
  Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
      List.iter
        (fun n -> Out_channel.with_open_bin (Filename.concat dir n) (fun oc -> output_string oc (read (fixture n))))
        [ "bst.march"; "bst_erased.march" ];
      let ghost = emit dir "bst" and twin = norm (emit dir "bst_erased") in
      if ghost <> twin then
        Alcotest.failf "ghost code changed the emitted %s, first difference at %s" what (first_difference ghost twin))

let emit_llvm dir stem =
  ignore (U.run_in ~dir "--emit-llvm" (stem ^ ".march"));
  let ll = Filename.concat dir (stem ^ ".ll") in
  if not (Sys.file_exists ll) then Alcotest.failf "--emit-llvm %s wrote no IR" stem;
  read ll

let emit_js dir stem =
  ignore (U.run_in ~dir (Printf.sprintf "--target js -o %s.mjs" stem) (stem ^ ".march"));
  let js = Filename.concat dir (stem ^ ".mjs") in
  if not (Sys.file_exists js) then Alcotest.failf "--target js %s wrote no JavaScript" stem;
  read js

let ir_identical =
  same_output "LLVM IR" ~emit:emit_llvm
    ~norm:(Str.global_replace (Str.regexp_string "[17 x i8] c\"bst_erased.march") "[10 x i8] c\"bst.march")

let js_identical =
  same_output "JavaScript" ~emit:emit_js ~norm:(fun s ->
      s
      |> Str.global_replace (Str.regexp_string "bst_erased.march") "bst.march"
      |> Str.global_replace (Str.regexp_string "bst_erased.mjs.map") "bst.mjs.map")

let worked_example =
  [ U.gated "worked example: every obligation proved" (fun () ->
        let out = U.run (read (fixture "bst.march")) in
        let rows = user_rows out in
        if List.length rows <> 10 || List.exists (fun l -> not (String.starts_with ~prefix:"proved\t" l)) rows
           || U.contains out "[ghost_" || U.contains out "[refinement_unverified]" || U.contains out "[invalid_reflect]"
        then Alcotest.failf "expected 10 proved user obligations:\n%s" out);
    Alcotest.test_case "worked example runs" `Quick (fun () ->
        let out = U.run ~args:"" (read (fixture "bst.march")) in
        if not (printed out "3" && printed out "two") then Alcotest.failf "expected 3 and two:\n%s" out);
    Alcotest.test_case "erasure: same LLVM IR as the hand-erased twin" `Quick ir_identical;
    Alcotest.test_case "erasure: same JavaScript as the hand-erased twin" `Quick js_identical ]

let rejects =
  [ rejected "returned" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn f(x : Int, ghost s : Int) : Int do s end\nend\n";
    rejected "branched on" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn f(x : Int, ghost s : Int) : Int do if s > 0 do 1 else 2 end end\nend\n";
    rejected "matched on" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn f(x : Int, ghost s : Option(Int)) : Int do\n    match s do\n      Some(v) -> v\n      None -> x\n    end\n  end\nend\n";
    rejected "captured by a closure" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn f(x : Int, ghost s : Int) : Int do\n    let g = fn y -> y + s\n    g(x)\n  end\nend\n";
    rejected "passed to a runtime parameter" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn g(x : Int, ghost s : Int) : Int do x end\n  fn f(x : Int, ghost s : Int) : Int do g(s, x) end\nend\n";
    rejected "ghost let used at runtime" ~code:"ghost_in_runtime" ~what:"`s` is ghost"
      "mod R do\n  fn f(x : Int) : Int do\n    ghost let s = x + 1\n    s\n  end\nend\n";
    rejected "ghost fn called at runtime" ~code:"ghost_in_runtime" ~what:"ghost function"
      "mod R do\n  ghost fn h(n : Int) : Int do n end\n  fn f(x : Int) : Int do h(x) end\nend\n";
    rejected "qualified ghost fn called at runtime" ~code:"ghost_in_runtime" ~what:"ghost function"
      "mod R do\n  mod Inner do\n    ghost fn gg(n : Int) : Int do n end\n  end\n  fn a(x : Int) : Int do Inner.gg(x) end\nend\n";
    rejected "function with ghost parameters as a value" ~code:"ghost_misuse" ~what:"can only be called directly"
      "mod R do\n  fn g(x : Int, ghost s : Int) : Int do x end\n  fn k() do g end\nend\n";
    rejected "linear value observed" ~code:"ghost_misuse" ~what:"is linear"
      "mod R do\n  type Res = Res(Int)\n  fn g(x : Int, ghost s : Res) : Int do x end\n  fn f(linear r : Res) : Int do\n    let y = g(1, r)\n    match r do Res(n) -> n + y end\n  end\nend\n";
    rejected "several clauses" ~code:"ghost_misuse" ~what:"single clause"
      "mod R do\n  fn f(0, ghost s : Int) do 0 end\n  fn f(n, ghost s : Int) do n end\nend\n";
    rejected "impl method" ~code:"ghost_misuse" ~what:"impl methods"
      "mod R do\n  type T = T(Int)\n  interface Sz(a) do\n    fn sz : a -> Int\n  end\n  impl Sz(T) do\n    fn sz(t : T, ghost k : Int) : Int do 1 end\n  end\nend\n";
    rejected "name shared with a declaration in the file" ~code:"ghost_misuse" ~what:"also named `pick`"
      "mod R do\n  fn pick(x : Int, ghost s : Int) : Int do x end\n  mod Other do\n    fn pick(x : Int) : Int do x end\n  end\nend\n";
    rejected "name a wildcard import may bring in" ~code:"ghost_misuse" ~what:"also named `map`"
      "mod R do\n  use List.*\n  fn map(x : Int, ghost s : Int) : Int do x end\nend\n";
    (* Review findings, 2026-11-08: places the walks first missed. *)
    rejected "ghost fn in a supervised child's init arguments" ~code:"ghost_in_runtime" ~what:"ghost function"
      "mod R do\n  ghost fn seed_of(n : Int) : Int do n end\n  actor Worker do\n    state { base : Int }\n    init(base : Int) { base: base }\n    on Work() do state end\n  end\n  actor Sup do\n    state { w : Int, seed : Int }\n    init(seed : Int) { w: 0, seed: seed }\n    supervise do\n      strategy one_for_one\n      max_restarts 5 within 60\n      Worker w(seed_of(seed))\n    end\n  end\nend\n";
    rejected "ghost parameter on a local function" ~code:"ghost_misuse" ~what:"local functions"
      "mod R do\n  fn outer(x : Int) : Int do\n    fn helper(ghost t : Int, y : Int) : Int do y end\n    helper(x, x)\n  end\nend\n";
    rejected "ghost parameter on a lemma" ~code:"ghost_misuse" ~what:"proof-only already"
      "mod R do\n  @[lemma]\n  fn l(ghost s : Int, x : Int) : {Unit | x == x} do () end\nend\n";
    U.gated "ghost fn must be reflectable" (fun () ->
        let out = U.run ~args:"--check" "mod R do\n  ghost fn spin(n : Int) : Int do spin(n + 1) end\nend\n" in
        if not (U.contains out "[invalid_reflect]" && U.contains out "ghost function `spin`") then
          Alcotest.failf "expected a non-terminating ghost fn refused:\n%s" out) ]

let accepts =
  [ accepted "`ghost` is still a name"
      "mod R do\n  fn ghost(x : Int) : Int do\n    let ghost = x\n    ghost + 1\n  end\nend\n";
    accepted "ghost arguments from ghost parameters and ghost let"
      "mod R do\n  fn g(x : Int, ghost s : Int) : Int do x end\n  fn f(x : Int, ghost s : Int) : Int do\n    ghost let t = s + 1\n    g(x, t)\n  end\nend\n";
    (* `List.member` is not a global, so a bare `contains` here is the
       ghost one and the qualified call is the stdlib's. *)
    Alcotest.test_case "a user `member` with ghost parameters next to List.member" `Quick (fun () ->
        let out =
          U.run ~args:""
            "mod R do\n  needs IO.Console\n  fn member(x : Int, ghost s : Int) : Int do x end\n  fn main(cap : Cap(IO.Console)) do\n    let a = if List.member([1, 2], 2) do member(7, 0) else 0 end\n    println(int_to_string(a))\n  end\nend\n"
        in
        if not (printed out "7") then Alcotest.failf "expected 7:\n%s" out);
    accepted "a local shadows a ghost fn"
      "mod R do\n  ghost fn h(n : Int) : Int do n end\n  fn f(x : Int) : Int do\n    let h = fn y -> y + 1\n    h(x)\n  end\nend\n";
    Alcotest.test_case "qualified call into a nested module runs" `Quick (fun () ->
        let out =
          U.run ~args:""
            "mod Q do\n  needs IO.Console\n  mod Inner do\n    fn bump(ghost b : Int, x : {Int | _ == b}) : {Int | _ == b + 1} do x + 1 end\n  end\n  fn main(cap : Cap(IO.Console)) do\n    let a = 1\n    println(int_to_string(Inner.bump(a, a)))\n  end\nend\n"
        in
        if not (printed out "2") then Alcotest.failf "expected 2:\n%s" out);
    Alcotest.test_case "formatter keeps the keyword" `Quick (fun () ->
        let src = "mod R do\n  ghost fn h(n : Int) : Int do n end\n  fn f(x : Int, ghost s : Int) : Int do\n    ghost let t = s\n    x\n  end\nend\n" in
        let dir = Filename.temp_dir "ghostfmt" "" in
        let out =
          Fun.protect ~finally:(fun () -> try U.remove_tree dir with _ -> ()) (fun () ->
              let f = Filename.concat dir "m.march" in
              Out_channel.with_open_bin f (fun oc -> output_string oc src);
              ignore (U.run_in ~dir "--fmt --check" "m.march");
              read f)
        in
        List.iter
          (fun frag -> if not (U.contains out frag) then Alcotest.failf "--fmt lost %S:\n%s" frag out)
          [ "ghost fn h("; "ghost s : Int"; "ghost let t = s" ];
        if U.contains out "@[ghost]" then Alcotest.failf "--fmt printed the attribute:\n%s" out) ]

let tests = worked_example @ rejects @ accepts
