(* ocap phase 8a (specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md, Tasks
   2 to 5): capture inference, through `march --dump-captures`.

   Each case writes a program, runs the real compiler on it and reads the
   report: one line per function value (`L:C  lambda in `f`  needs S`), one
   per binding that holds a set (`L:C  let x : T`), one per function
   (`fn f : T`).  Positions are found from a needle in the source, so a case
   names the code it is about. *)

let exe_dir = Filename.dirname Sys.executable_name
let compiler_exe = Filename.concat exe_dir "../bin/main.exe"

let work_dir =
  lazy
    (let d = Filename.temp_file "march_captures" "" in
     Sys.remove d;
     Sys.mkdir d 0o755;
     Sys.mkdir (Filename.concat d "home") 0o755;
     d)

let counter = ref 0

(* The report for [src] (the body of a module), and the source as written. *)
let dump ?(needs = "IO") ?(flags = "") (body : string) : string * string list =
  let d = Lazy.force work_dir in
  incr counter;
  let src = Printf.sprintf "mod T%d do\n  needs %s\n%s\nend\n" !counter needs body in
  let file = Filename.concat d (Printf.sprintf "t%d.march" !counter) in
  Out_channel.with_open_bin file (fun oc -> output_string oc src);
  let out = file ^ ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "cd %s && HOME=%s %s --dump-captures %s %s > %s 2>&1" (Filename.quote d)
         (Filename.quote (Filename.concat d "home")) (Filename.quote compiler_exe) flags (Filename.quote file)
         (Filename.quote out))
  in
  let text = In_channel.with_open_bin out In_channel.input_all in
  if rc <> 0 then Alcotest.failf "the program was rejected (exit %d):\n%s\n-- source --\n%s" rc text src;
  (src, String.split_on_char '\n' text)

(* Run the compiler with [flags] on [body] (a module body); exit code and output. *)
let march ?(needs = "IO") ?(flags = "--check") ?(env = "") (body : string) : int * string =
  let d = Lazy.force work_dir in
  incr counter;
  let src = Printf.sprintf "mod T%d do\n  needs %s\n%s\nend\n" !counter needs body in
  let file = Filename.concat d (Printf.sprintf "t%d.march" !counter) in
  Out_channel.with_open_bin file (fun oc -> output_string oc src);
  let out = file ^ ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "cd %s && HOME=%s %s %s %s %s > %s 2>&1" (Filename.quote d)
         (Filename.quote (Filename.concat d "home")) env (Filename.quote compiler_exe) flags (Filename.quote file)
         (Filename.quote out))
  in
  (rc, In_channel.with_open_bin out In_channel.input_all)

(* "L:C" of the first occurrence of [needle] in [src], as the report prints
   it (1-based line, 0-based column). *)
let pos_of (src : string) (needle : string) : string =
  let n = String.length needle in
  let rec find i =
    if i + n > String.length src then Alcotest.failf "needle %S is not in the source" needle
    else if String.sub src i n = needle then i
    else find (i + 1)
  in
  let off = find 0 in
  let line = ref 1 and col = ref 0 in
  String.iteri (fun i ch -> if i < off then if ch = '\n' then (incr line; col := 0) else incr col) src;
  Printf.sprintf "%d:%d" !line !col

let starts_with ~prefix s = String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let after (line : string) (marker : string) : string option =
  let n = String.length marker in
  let rec go i =
    if i + n > String.length line then None
    else if String.sub line i n = marker then Some (String.sub line (i + n) (String.length line - i - n))
    else go (i + 1)
  in
  go 0

(* The set of the function value that starts at [needle]: "" for one that
   captures nothing. *)
let set_at ((src, lines) : string * string list) (needle : string) : string =
  let p = pos_of src needle ^ " " in
  match
    List.find_opt
      (fun l -> starts_with ~prefix:p l && after l " let " = None)
      lines
  with
  | None -> Alcotest.failf "no function value at %s (%S) in:\n%s" p needle (String.concat "\n" lines)
  | Some l -> (
    match after l "  needs " with
    | Some s -> s
    | None -> if after l "captures nothing" <> None then "" else Alcotest.failf "unreadable line %S" l)

(* The annotated type of the binding [name]. *)
let let_ty ((_, lines) : string * string list) (name : string) : string =
  match List.find_map (fun l -> after l (Printf.sprintf " let %s : " name)) lines with
  | Some t -> t
  | None -> "<plain>"

let fn_ty ((_, lines) : string * string list) (name : string) : string =
  match List.find_map (fun l -> if starts_with ~prefix:(Printf.sprintf "fn %s : " name) l then after l " : " else None) lines with
  | Some t -> t
  | None -> Alcotest.failf "no `fn %s` line in:\n%s" name (String.concat "\n" lines)

let reason_of ((src, lines) : string * string list) (needle : string) : string =
  let p = pos_of src needle ^ " " in
  let rec go = function
    | l :: rest when starts_with ~prefix:p l && after l " let " = None ->
      String.concat "\n" (List.filter (fun x -> starts_with ~prefix:"         " x)
        (let rec take = function x :: xs when starts_with ~prefix:"         " x -> x :: take xs | _ -> [] in take rest))
    | _ :: rest -> go rest
    | [] -> ""
  in
  go lines

let str = Alcotest.(check string)
let contains hay needle = after hay needle <> None

(* ── lambdas (Task 3) ───────────────────────────────────────────────────── *)

let test_lam_pure () =
  let r = dump "  fn main() do\n    let f = fn x -> x + 1\n    f(1)\n  end" in
  str "captures nothing" "" (set_at r "fn x ->");
  str "no annotation on the binding" "<plain>" (let_ty r "f")

let test_lam_own_op () =
  let r = dump "  fn main() do\n    let f = fn s -> println(s)\n    f(\"a\")\n  end" in
  str "kind" "IO.Console" (set_at r "fn s ->");
  Alcotest.(check bool) "reason names the call" true (contains (reason_of r "fn s ->") "calls `println`")

let test_lam_literal_and_computed_path () =
  let r =
    dump
      "  fn main() do\n    let a = fn () -> File.read(\"/srv/data/a.txt\")\n    let b = fn p -> File.read(p)\n    (a, b)\n  end"
  in
  str "literal path" "IO.FileRead(\"/srv/data/a.txt\")" (set_at r "fn () ->");
  str "computed path" "IO.FileRead" (set_at r "fn p ->")

let test_lam_captures_closure () =
  let r =
    dump
      "  fn main() do\n    let g = fn s -> println(s)\n    let w = fn x -> g(x)\n    let u = fn () -> g\n    (w, u)\n  end"
  in
  str "calls what it captured" "IO.Console" (set_at r "fn x ->");
  str "captured but not called" "IO.Console" (set_at r "fn () ->");
  Alcotest.(check bool) "reason" true (contains (reason_of r "fn () ->") "captures `g`")

let test_lam_creates_closure () =
  let r = dump "  fn main() do\n    let mk = fn () -> fn s -> println(s)\n    mk\n  end" in
  str "inner" "IO.Console" (set_at r "fn s ->");
  str "outer" "IO.Console" (set_at r "fn () ->")

let test_lam_calls_param () =
  let r = dump "  fn main() do\n    let hof = fn f -> f()\n    hof\n  end" in
  str "set is the parameter's variable" "c1" (set_at r "fn f ->");
  Alcotest.(check bool) "type" true (contains (let_ty r "hof") "needs c1) -> ");
  Alcotest.(check bool) "reason" true (contains (reason_of r "fn f ->") "calls `f`")

let test_local_let_no_generalise () =
  let r =
    dump
      "  fn main() do\n    let run = fn f -> f(1)\n    let a = run(fn x -> Authority.ignore(println(int_to_string(x))))\n    let b = run(fn y -> ())\n    (a, b)\n  end"
  in
  (* One local value has one set: the union of its uses' (design §5). *)
  str "the local's set" "IO.Console" (set_at r "fn f ->")

let test_data_build_and_read () =
  let r =
    dump
      "  type Client = Client(String -> Result((), CapError))\n  type Job = { name : String, run : () -> Result((), CapError) }\n  fn main() do\n    let c = Client(fn s -> println(s))\n    let j = { name: \"a\", run: fn -> println(\"x\") }\n    let run = j.run\n    (c, run)\n  end"
  in
  Alcotest.(check bool) "the value's type carries the set" true (contains (let_ty r "c") "Client needs IO.Console");
  Alcotest.(check bool) "a field read carries it" true (contains (let_ty r "run") "needs IO.Console")

let test_data_pattern () =
  let r =
    dump
      "  type Client = Client(String -> Result((), CapError))\n  type Pair = Pair(Client, Int)\n  fn main() do\n    let c = Client(fn s -> println(s))\n    let f1 = match c do Client(f) -> f end\n    let f2 = match (c, 1) do (Client(g), _) -> g end\n    let f3 = match Pair(c, 2) do Pair(Client(h), _) -> h end\n    let f4 = match c do Client(_) as whole -> whole end\n    (f1, f2, f3, f4)\n  end"
  in
  List.iter
    (fun n -> Alcotest.(check bool) n true (contains (let_ty r n) "needs IO.Console"))
    [ "f1"; "f2"; "f3"; "f4" ]

let test_data_list_option () =
  let r =
    dump
      "  type Client = Client(String -> Result((), CapError))\n  fn main() do\n    let g = fn s -> println(s)\n    let h = fn s -> File.read(s)\n    let l = [g]\n    let o = Some(Client(g))\n    (l, o, h)\n  end"
  in
  Alcotest.(check bool) "list element type" true (contains (let_ty r "l") "List(");
  Alcotest.(check bool) "list element set" true (contains (let_ty r "l") "needs IO.Console)");
  Alcotest.(check bool) "option of a client" true (contains (let_ty r "o") "Client needs IO.Console)")

let test_branch_union () =
  let r =
    dump
      "  fn pick(b : Bool) do\n    let f = if b do fn s -> Authority.ignore(println(s)) else fn s -> Authority.ignore(File.read(s)) end\n    f\n  end\n  fn main() do pick(true) end"
  in
  Alcotest.(check bool) "union of the branches" true (contains (let_ty r "f") "needs IO.Console, IO.FileRead")

let test_local_fn_site () =
  let r = dump "  fn main() do\n    fn go(n : Int) : Result((), CapError) do println(int_to_string(n)) end\n    go(1)\n  end" in
  str "a local fn is a function value" "IO.Console" (set_at r "go(n")

(* ── named functions (Task 4) ───────────────────────────────────────────── *)

let test_named_as_value () =
  let r = dump "  fn main() do\n    List.map([\"a\"], File.read)\n  end" in
  str "its reach" "IO.FileRead" (set_at r "File.read)")

let test_named_clause_narrows_value () =
  let r =
    dump
      "  fn f(p : String) needs IO.FileRead(\"/srv/\") do File.read(p) end\n  fn main() do\n    let v = f\n    v\n  end"
  in
  str "narrowed by its clause" "IO.FileRead(\"/srv/\")" (set_at r "f\n    v")

let test_hof_polymorphic () =
  let r =
    dump
      "  pfn apply(f, x) do f(x) end\n  fn main() do\n    let a = fn u -> apply(fn s -> println(s), u)\n    let b = fn u -> apply(fn n -> n + 1, u)\n    (a, b)\n  end"
  in
  str "apply's type" "(a -> b needs c1, a) -> b needs c1" (fn_ty r "apply");
  str "with a printing closure" "IO.Console" (set_at r "fn u -> apply(fn s");
  str "with a pure closure" "" (set_at r "fn u -> apply(fn n")

let test_returns_capturing_value () =
  let r =
    dump
      "  type Client = Client(String -> Result(String, String))\n  fn new() do\n    Client(fn city ->\n      match HttpClient.get(HttpClient.new_client(), \"https://api.weather.com/v1/\" ++ city) do\n        Ok(_) -> Ok(\"sunny\")\n        Err(_) -> Err(\"no\")\n      end)\n  end\n  fn main() do\n    let c = new()\n    let d = restrict IO.NetConnect(\"api.weather.com\", methods(get)) do new() end\n    (c, d)\n  end"
  in
  Alcotest.(check bool) "the function's result type" true
    (contains (fn_ty r "new") "Client needs IO.NetConnect(\"api.weather.com/v1/\"))");
  Alcotest.(check bool) "the value" true (contains (let_ty r "c") "Client needs IO.NetConnect(\"api.weather.com/v1/\")");
  (* Design §6.2: a value a call returns is not narrowed at the call site. *)
  str "same type inside a restrict" (let_ty r "c") (let_ty r "d")

let test_launder () =
  let r =
    dump
      "  pfn id(x) do x end\n  fn main() do\n    let g = fn s -> println(s)\n    let a = id(g)\n    let b = g |> id\n    let c = Option.map(Some(g), fn f -> f)\n    let d = List.head([g])\n    let p = (g, 1)\n    let m = match p do (f, _) -> id(f) end\n    (a, b, c, d, m)\n  end"
  in
  List.iter
    (fun n -> Alcotest.(check bool) n true (contains (let_ty r n) "needs IO.Console"))
    [ "a"; "b"; "c"; "d"; "m" ]

let test_recursion () =
  let t0 = Unix.gettimeofday () in
  let r =
    dump
      "  pfn each(xs, f) do\n    match xs do\n      Nil -> ()\n      Cons(h, t) ->\n        f(h)\n        each(t, f)\n    end\n  end\n  mod A do\n    fn ping(n, f) do if n == 0 do f() else T_B.pong(n - 1, f) end end\n  end\n  mod T_B do\n    fn pong(n, f) do A.ping(n, f) end\n  end\n  fn main() do\n    let g = fn s -> println(s)\n    let w = fn () -> each([\"a\"], g)\n    fn go(n : Int) : Result((), CapError) do if n == 0 do g(\"x\") else go(n - 1) end end\n    let v = fn () -> A.ping(3, fn () -> g(\"y\"))\n    (w, go, v)\n  end"
  in
  str "a self-recursive higher-order function" "IO.Console" (set_at r "fn () -> each");
  str "a local recursive fn that captures" "IO.Console" (set_at r "go(n : Int)");
  str "mutual recursion across modules" "IO.Console" (set_at r "fn () -> A.ping");
  Alcotest.(check bool) "terminates quickly" true (Unix.gettimeofday () -. t0 < 20.0)

let test_iface_union () =
  let r =
    dump
      "  type Loud = Loud(Int)\n  interface Speak(a) do\n    fn speak : a -> Result((), CapError)\n  end\n  impl Speak(Loud) do\n    fn speak(x) do println(\"loud\") end\n  end\n  fn main() do\n    let f = fn v -> speak(v)\n    f(Loud(1))\n  end"
  in
  str "any impl may run" "IO.Console" (set_at r "fn v ->")

let test_toplevel_let_closure () =
  let r = dump "  let h = fn s -> println(s)\n  fn main() do\n    let w = fn () -> h(\"a\")\n    w\n  end" in
  str "the module-level closure" "IO.Console" (set_at r "fn s ->");
  str "a closure that calls it" "IO.Console" (set_at r "fn () ->")

let test_vault_invariant () =
  let r =
    dump
      "  fn main() do\n    let v = Authority.must(Vault.new(\"capt_t\"))\n    let g = fn s -> Authority.ignore(println(s))\n    let h = fn s -> Authority.ignore(File.read(s))\n    Vault.set(v, \"a\", g)\n    Vault.set(v, \"b\", h)\n    let back = Vault.get(v, \"a\")\n    back\n  end"
  in
  Alcotest.(check bool) "what is read back has every stored closure's set" true
    (contains (let_ty r "back") "Option((String -> () needs IO.Console, IO.FileRead))")

let test_toplevel_restrict_not_narrowed () =
  (* Found by the soundness oracle (restrict_module_level_closure_captures_nothing):
     a module-level closure captures nothing at run time, so a module-level
     restrict around it bounds nothing. *)
  let r =
    dump
      "  let top = restrict IO.FileRead(\"/srv/\") do\n    fn p -> File.read(p)\n  end\n  let made_later = fn () -> restrict IO.FileRead(\"/srv/\") do fn q -> File.read(q) end\n  fn main() do (top, made_later) end"
  in
  str "made by module-level code" "IO.FileRead" (set_at r "fn p ->");
  str "made when a module-level closure runs" "IO.FileRead(\"/srv/\")" (set_at r "fn q ->")

let test_authority_check_kinds () =
  let r =
    dump
      "  pfn probe(kind : String, target : String) do Authority.check(kind, target) end\n  pfn pick() do \"IO.\" ++ \"Clock\" end\n  fn main() do\n    let lit = fn () -> Authority.check(\"IO.FileRead\", \"/srv/x\")\n    let through = fn () -> probe(\"IO.Console\", \"\")\n    let computed = fn () -> Authority.check(pick(), \"\")\n    (lit, through, computed)\n  end"
  in
  str "a literal kind" "IO.FileRead" (set_at r "fn () -> Authority.check(\"IO.FileRead");
  (* A helper that passes its parameter on as the kind: its callers name it. *)
  str "a kind named by the caller" "IO.Console" (set_at r "fn () -> probe");
  str "a computed kind is not tracked" "?" (set_at r "fn () -> Authority.check(pick");
  let _, lines = r in
  Alcotest.(check bool) "the report says where and why" true
    (List.exists (fun l -> contains l "not tracked: an authority check of a computed kind") lines);
  Alcotest.(check bool) "and counts it" true (List.exists (fun l -> contains l "3 function values, 1 not tracked") lines)

let test_unmodelled_is_unknown_not_smaller () =
  (* A function value read back from a table opened by name: nothing the
     pass can see put it there, so it may do anything. *)
  let r =
    dump
      "  fn main() do\n    let t = Authority.must(Vault.open(\"capt_unknown\"))\n    let stored = Vault.get(t, \"k\")\n    let call = fn () ->\n      match stored do\n        Some(f) -> f(\"x\")\n        None -> ()\n      end\n    call\n  end"
  in
  str "the closure that calls it" "?" (set_at r "fn () ->")

(* ── found by the whole-branch review: each was an inferred set too small ── *)

let test_review_local_fn_recursion () =
  let r =
    dump
      "  fn mk() do fn x -> println(\"hi\") end\n  fn run(n : Int) do\n    fn go(f, k : Int) do\n      if k == 0 do f(1) else go(mk(), k - 1) end\n    end\n    let quiet = fn x -> Ok(())\n    let r = fn () -> go(quiet, n)\n    r\n  end\n  fn main() do run(1) end"
  in
  (* `go` calls itself with a printing closure: whoever calls `go` may print. *)
  str "the closure that starts the recursion" "IO.Console" (set_at r "fn () -> go")

let test_review_mutual_types () =
  let r =
    dump
      "  type A = A(B, Int -> Int)\n  type B = B(A) | BEnd\n  fn aaa(a : A) do\n    match a do\n      A(_, f) -> f(1)\n    end\n  end\n  fn zrunb(b : B) do\n    match b do\n      B(A(_, f)) -> f(1)\n      BEnd -> 0\n    end\n  end\n  fn main() do\n    let w = fn x -> match println(\"x\") do _ -> 1 end\n    let b = B(A(BEnd, w))\n    let r = fn () -> zrunb(b)\n    (r, aaa)\n  end"
  in
  str "through the second of two mutually recursive types" "IO.Console" (set_at r "fn () -> zrunb")

let test_review_or_pattern () =
  let r =
    dump
      "  fn pick(t : (Int -> Int, Int -> Int), k : Int) do\n    match (t, k) do\n      ((f, _), 0) | ((_, f), 1) -> f(1)\n      _ -> 0\n    end\n  end\n  fn mkpair() do (fn x -> x, fn x -> match println(\"x\") do _ -> 1 end) end\n  fn main() do\n    let r = fn () -> pick(mkpair(), 1)\n    r\n  end"
  in
  str "the binder of the second alternative" "IO.Console" (set_at r "fn () -> pick")

let test_review_same_named_types () =
  let r =
    dump
      "  mod M2 do\n    needs IO.Console\n    type T = A(Int -> Int)\n    fn run(t : T) do\n      match t do\n        A(f) -> f(1)\n      end\n    end\n    fn mkp(u : Int) do\n      let l = fn (x : Int) -> match println(\"x\") do _ -> u + x end\n      A(l)\n    end\n  end\n  mod M3 do\n    type T = A(Int)\n    fn m3() do A(2) end\n  end\n  fn main() do\n    let r = fn () -> M2.run(M2.mkp(1))\n    (r, M3.m3())\n  end"
  in
  str "a constructor shared by two types of one name" "IO.Console" (set_at r "fn () -> M2.run")

let test_review_logger_dispatch () =
  (* A callback registered with the logger runs inside whoever logs: the
     pass cannot see which, so the logging closure is not tracked. *)
  let r = dump "  fn main() do\n    let r = fn () -> Logger.info(\"hello\")\n    r\n  end" in
  str "a closure that logs" "?" (set_at r "fn () -> Logger.info")

(* ── static authority (Task 5) ──────────────────────────────────────────── *)

let test_restrict () =
  let r =
    dump
      "  fn main() do\n    let outside = fn s -> println(s)\n    let a = restrict IO.FileRead(\"/srv/data/\") do fn p -> File.read(p) end\n    let b = restrict IO.FileSystem(\"/srv/\") do fn q -> File.read(q) end\n    let sc = IO.FileRead(\"/srv/\" ++ \"x/\")\n    let c = match sc do\n      Ok(sv) -> restrict sv do fn z -> File.read(z) end\n      Err(_) -> fn z -> File.read(z)\n    end\n    let d = restrict IO.FileRead(\"/srv/data/\"), IO.Console do fn m -> outside(m) end\n    let e = restrict IO.FileRead(\"/srv/data/\") do\n      restrict IO.FileRead(\"/srv/data/in/\") do fn n -> File.read(n) end\n    end\n    (a, b, c, d, e)\n  end"
  in
  str "created inside a literal restrict" "IO.FileRead(\"/srv/data/\")" (set_at r "fn p ->");
  str "an ancestor kind's scope" "IO.FileRead(\"/srv/\")" (set_at r "fn q ->");
  str "a computed restrict narrows nothing" "IO.FileRead" (set_at r "fn z -> File.read(z) end\n      Err");
  (* The closure made outside keeps its authority (parent design §5). *)
  str "an outside closure's set arrives whole" "IO.Console" (set_at r "fn m ->");
  str "nested restricts: the innermost" "IO.FileRead(\"/srv/data/in/\")" (set_at r "fn n ->")

let test_clause_narrows_lambda () =
  let r =
    dump
      "  fn f() needs IO.FileRead(\"/srv/\") do\n    let l = fn p -> File.read(p)\n    l\n  end\n  fn main() do f() end"
  in
  str "narrowed by the enclosing clause" "IO.FileRead(\"/srv/\")" (set_at r "fn p ->")

let test_restrict_named_value () =
  let r =
    dump
      "  pfn reader(p) do File.read(p) end\n  fn main() do\n    let v = restrict IO.FileRead(\"/srv/\") do reader end\n    v\n  end"
  in
  str "a named function as a value, inside a restrict" "IO.FileRead(\"/srv/\")" (set_at r "reader end")

let test_spawn_charged () =
  let r =
    dump
      "  actor Logger do\n    state { n : Int }\n    init { n: 0 }\n    on Log(s) do\n      println(s)\n      { state with n: state.n + 1 }\n    end\n  end\n  fn main() do\n    let mk = fn () -> spawn(Logger)\n    let t = fn () -> Task.async(fn () -> println(\"t\"))\n    (mk, t)\n  end"
  in
  str "spawning an actor" "IO.Console" (set_at r "fn () -> spawn");
  Alcotest.(check bool) "spawning a task" true (contains (set_at r "fn () -> Task.async") "IO.Console");
  (* The task holds the function it runs (design §9.2). *)
  Alcotest.(check bool) "the task value carries the set" true (contains (let_ty r "t") "Result((Task(Result((), CapError)) needs IO.Console), CapError)")

(* ocap phase 7: inside a `mock` body an operation may run a handler function
   instead, and a closure created there keeps the mock.  The pass does not
   model the dispatch, so such a closure is "not tracked", never a set that
   leaves the handler out. *)
let test_mock_not_tracked () =
  let r =
    dump ~flags:"--test"
      "  fn main() do\n    mock IO.Console with { print_line: Some(fn s -> Authority.ignore(IO.write(s))) } do\n      let g = fn x -> x + 1\n      g(1)\n    end\n  end"
  in
  str "created inside the mock" "?" (set_at r "fn x ->")

(* ── ocap phase 8b (specs/plans/2026-11-25-ocap-p8b-scoped-escape-plan.md) ── *)

let test_scoped_parses () =
  let rc, out =
    march
      "  fn w(p : String, f : scoped File.Handle -> a) : Result(Result(a, File.FileError), CapError) do\n\
      \    File.with_open(p, f)\n\
      \  end\n\
      \  fn main() do\n\
      \    let _ = w(\"x\", fn h -> File.read_line(h))\n\
      \    ()\n\
      \  end"
  in
  Alcotest.(check int) ("checks clean:\n" ^ out) 0 rc;
  Alcotest.(check bool) "no warning about the marker" false (contains out "scoped")

let test_scoped_is_still_a_name () =
  let rc, out =
    march ~flags:""
      "  fn scoped(scoped : Bool) : Bool do scoped end\n\
      \  fn main() do\n\
      \    let scoped = scoped(true)\n\
      \    println(to_string(scoped))\n\
      \  end"
  in
  Alcotest.(check int) ("runs:\n" ^ out) 0 rc;
  Alcotest.(check string) "prints" "true\n" out

let test_scoped_misplaced () =
  let rc, out = march "  fn bad(x : scoped Int) : Int do x end\n  fn main() do println(to_string(bad(1))) end" in
  Alcotest.(check int) "rejected" 1 rc;
  Alcotest.(check bool) ("names the slug:\n" ^ out) true (contains out "[scoped_misplaced]")

(* A function with a `scoped` callback parameter of the test's own, so these
   cases do not depend on which stdlib functions carry the marker. *)
let opener =
  "  fn opening(p : String, body : scoped File.Handle -> a) : Result(Result(a, File.FileError), CapError) do\n\
  \    File.with_open(p, body)\n\
  \  end\n"

(* [body] is rejected with `capture_escape`, and the message has each of [has]. *)
let escapes ?(flags = "--check") (body : string) (has : string list) () =
  let rc, out = march ~flags (opener ^ body) in
  Alcotest.(check int) ("rejected:\n" ^ out) 1 rc;
  List.iter
    (fun frag -> Alcotest.(check bool) (Printf.sprintf "the message has %S:\n%s" frag out) true (contains out frag))
    ("[capture_escape]" :: "`h` cannot leave the `opening` callback" :: has)

let accepted (body : string) () =
  let rc, out = march (opener ^ body) in
  Alcotest.(check int) ("accepted:\n" ^ out) 0 rc

let main_of (stmts : string) : string = "  fn main() do\n" ^ stmts ^ "\n    ()\n  end"

let escape_cases =
  [ ( "the handle is returned",
      escapes (main_of "    let _ = opening(\"x\", fn h -> h)") [ "but it is returned" ] );
    ( "a closure that captures it is returned",
      escapes
        (main_of "    let _ = opening(\"x\", fn h -> fn () -> File.read_line(h))")
        [ "this function captures it and is returned"; "captures `h`" ] );
    ( "a record that holds it is returned",
      escapes (main_of "    let _ = opening(\"x\", fn h -> { handle: h, n: 1 })") [ "is returned" ] );
    ( "a tuple inside a Result is returned",
      escapes (main_of "    let _ = opening(\"x\", fn h -> Ok((1, h)))") [ "is returned" ] );
    ( "it is stored in a table",
      escapes
        (main_of
           "    let t : Vault(File.Handle) = Authority.must(Vault.new(\"handles\"))\n\
           \    let _ = opening(\"x\", fn h -> Vault.put(t, \"k\", h))")
        [ "is stored in a table" ] );
    ( "it is sent to an actor",
      escapes
        ("  actor Keeper do\n\
         \    state { n : Int }\n\
         \    init { n: 0 }\n\
         \    on Keep(h : File.Handle) do\n\
         \      state\n\
         \    end\n\
         \  end\n"
         ^ main_of "    let k = spawn(Keeper)\n    let _ = opening(\"x\", fn h -> send(k, Keep(h)))")
        [ "is sent to an actor" ] );
    ( "a task that holds it is returned",
      escapes
        (main_of "    let _ = opening(\"x\", fn h -> Task.async(fn () -> File.read_line(h)))")
        [ "is returned" ] );
    ( "it is kept by a registry builtin",
      escapes
        (main_of
           "    let _ = opening(\"x\", fn h ->\n\
           \      Signal.watch(Signal.Term, fn () ->\n\
           \        let _ = File.read_line(h)\n\
           \        ()))")
        [ "this function captures it and is kept by `signal_watch`" ] );
    ( "a helper two calls away stores it",
      escapes
        ("  type Wrapped = Wrapped(File.Handle)\n\
         \  pfn wrap(h : File.Handle) : Wrapped do Wrapped(h) end\n\
         \  pfn keep(t : Vault(Wrapped), w : Wrapped) do Vault.put(t, \"k\", w) end\n"
         ^ main_of
             "    let t : Vault(Wrapped) = Authority.must(Vault.new(\"wrapped\"))\n\
             \    let _ = opening(\"x\", fn h -> keep(t, wrap(h)))")
        [ "is stored in a table" ] );
    ( "it is passed to a function value the compiler cannot follow",
      escapes
        (main_of
           "    let found : Option(Vault(File.Handle -> Int)) = Authority.must(Vault.whereis(\"fns\"))\n\
           \    let _ = opening(\"x\", fn h ->\n\
           \      match found do\n\
           \        Some(t) ->\n\
           \          match Vault.get(t, \"k\") do\n\
           \            Some(f) -> f(h)\n\
           \            None -> 0\n\
           \          end\n\
           \        None -> 0\n\
           \      end)")
        [ "is passed to code the compiler cannot follow" ] );
    ( "the scoped function is used as a value first",
      fun () ->
        let rc, out = march (opener ^ main_of "    let w = opening\n    let _ = w(\"x\", fn h -> h)") in
        Alcotest.(check int) ("rejected:\n" ^ out) 1 rc;
        Alcotest.(check bool) ("the message:\n" ^ out) true
          (contains out "The handle cannot leave the `opening` callback" && contains out "is returned") );
    ( "the callback is a named function",
      fun () ->
        let rc, out =
          march
            (opener ^ "  pfn leak(file : File.Handle) : File.Handle do file end\n"
             ^ main_of "    let _ = opening(\"x\", leak)")
        in
        Alcotest.(check int) ("rejected:\n" ^ out) 1 rc;
        Alcotest.(check bool) ("names the parameter:\n" ^ out) true
          (contains out "`file` cannot leave the `opening` callback") );
    ( "nested: only the inner handle is reported",
      fun () ->
        let rc, out =
          march
            (opener
             ^ main_of
                 "    let _ = opening(\"x\", fn outer ->\n\
                 \      let got = opening(\"y\", fn inner -> inner)\n\
                 \      File.read_line(outer))")
        in
        Alcotest.(check int) ("rejected:\n" ^ out) 1 rc;
        Alcotest.(check bool) ("inner:\n" ^ out) true (contains out "`inner` cannot leave");
        Alcotest.(check bool) ("not outer:\n" ^ out) false (contains out "`outer` cannot leave") ) ]

let accepted_cases =
  [ ("reading inside", accepted (main_of "    let _ = opening(\"x\", fn h -> File.read_line(h))"));
    ( "returning data read from it, in a tuple",
      accepted (main_of "    let _ = opening(\"x\", fn h -> (File.read_line(h), 1))") );
    ( "a local closure over it, called inside",
      accepted
        (main_of
           "    let _ = opening(\"x\", fn h ->\n\
           \      let next = fn () -> File.read_line(h)\n\
           \      let a = next()\n\
           \      next())") );
    ( "a local record around it, used inside",
      accepted
        (main_of
           "    let _ = opening(\"x\", fn h ->\n\
           \      let r = { handle: h, n: 1 }\n\
           \      File.read_line(r.handle))") );
    ( "a task over it, awaited inside",
      accepted
        (main_of
           "    let _ = opening(\"x\", fn h ->\n\
           \      let t = Authority.must(Task.async(fn () -> File.read_line(h)))\n\
           \      Task.await(t))") );
    ( "a helper that only reads",
      accepted
        ("  pfn first(file : File.Handle) : Result(Option(String), File.FileError) do File.read_line(file) end\n"
         ^ main_of "    let _ = opening(\"x\", fn h -> first(h))") );
    ( "a list of handles used inside",
      accepted
        (main_of "    let _ = opening(\"x\", fn h -> List.length(List.map([h, h], fn x -> File.read_line(x))))") );
    ( "an ordinary handle goes anywhere",
      accepted
        (main_of
           "    let t : Vault(File.Handle) = Authority.must(Vault.new(\"handles\"))\n\
           \    let _ = match File.open(\"x\") do\n\
           \      Ok(Ok(h)) -> Vault.put(t, \"k\", h)\n\
           \      _ -> ()\n\
           \    end") ) ]

(* The pass does not run for a program that names no function with a
   `scoped` parameter, and a crash in it is never a silent accept. *)
let test_pass_skipped () =
  let rc, out = march ~flags:"--check --timings" ~env:"MARCH_CAPTURE_FAULT=1" "  fn main() do println(\"hi\") end" in
  Alcotest.(check int) ("checks clean, the pass never started:\n" ^ out) 0 rc

let test_pass_crash_is_an_ice () =
  let rc, out =
    march ~env:"MARCH_CAPTURE_FAULT=1" (main_of "    let _ = File.with_open(\"x\", fn h -> File.read_line(h))")
  in
  Alcotest.(check bool) ("not a clean check:\n" ^ out) true (rc <> 0);
  Alcotest.(check bool) ("an internal compiler error:\n" ^ out) true (contains out "internal compiler error")

(* An impl method is a body like any other. *)
let test_escape_in_impl_method () =
  let rc, out =
    march
      "  type Doc = Doc(String)\n\
      \  interface Opens(a) do\n\
      \    fn grab : a -> Result(Result(File.Handle, File.FileError), CapError)\n\
      \  end\n\
      \  impl Opens(Doc) do\n\
      \    fn grab(d) do\n\
      \      match d do\n\
      \        Doc(p) -> File.with_open(p, fn h -> h)\n\
      \      end\n\
      \    end\n\
      \  end\n\
      \  fn main() do\n\
      \    let _ = grab(Doc(\"x\"))\n\
      \    ()\n\
      \  end"
  in
  Alcotest.(check int) ("rejected:\n" ^ out) 1 rc;
  Alcotest.(check bool) ("with capture_escape:\n" ^ out) true (contains out "[capture_escape]")

let tests =
  [ ( "captures",
      [ Alcotest.test_case "a pure lambda" `Quick test_lam_pure;
        Alcotest.test_case "a lambda's own operation" `Quick test_lam_own_op;
        Alcotest.test_case "literal and computed targets" `Quick test_lam_literal_and_computed_path;
        Alcotest.test_case "a closure that captures a closure" `Quick test_lam_captures_closure;
        Alcotest.test_case "a closure that creates a closure" `Quick test_lam_creates_closure;
        Alcotest.test_case "a lambda that calls its parameter" `Quick test_lam_calls_param;
        Alcotest.test_case "a local let does not generalise" `Quick test_local_let_no_generalise;
        Alcotest.test_case "data built and read" `Quick test_data_build_and_read;
        Alcotest.test_case "a closure taken out by a pattern" `Quick test_data_pattern;
        Alcotest.test_case "lists and options" `Quick test_data_list_option;
        Alcotest.test_case "branches join" `Quick test_branch_union;
        Alcotest.test_case "a local fn is a site" `Quick test_local_fn_site;
        Alcotest.test_case "a named function as a value" `Quick test_named_as_value;
        Alcotest.test_case "a clause narrows the function as a value" `Quick test_named_clause_narrows_value;
        Alcotest.test_case "a private higher-order function generalises" `Quick test_hof_polymorphic;
        Alcotest.test_case "a function that returns a capturing value" `Quick test_returns_capturing_value;
        Alcotest.test_case "laundering through polymorphic code" `Quick test_launder;
        Alcotest.test_case "recursion" `Quick test_recursion;
        Alcotest.test_case "interface methods: any impl" `Quick test_iface_union;
        Alcotest.test_case "a top-level let closure" `Quick test_toplevel_let_closure;
        Alcotest.test_case "a module-level restrict narrows nothing" `Quick test_toplevel_restrict_not_narrowed;
        Alcotest.test_case "a vault is invariant" `Quick test_vault_invariant;
        Alcotest.test_case "authority checks: literal, named by the caller, computed" `Quick test_authority_check_kinds;
        Alcotest.test_case "what is not modelled is not tracked, never smaller" `Quick
          test_unmodelled_is_unknown_not_smaller;
        Alcotest.test_case "review: a local fn that calls itself" `Quick test_review_local_fn_recursion;
        Alcotest.test_case "review: mutually recursive declared types" `Quick test_review_mutual_types;
        Alcotest.test_case "review: an or-pattern binding different parts" `Quick test_review_or_pattern;
        Alcotest.test_case "review: one constructor name in two same-named types" `Quick test_review_same_named_types;
        Alcotest.test_case "review: a builtin that runs registered callbacks" `Quick test_review_logger_dispatch;
        Alcotest.test_case "restrict" `Quick test_restrict;
        Alcotest.test_case "a clause narrows a lambda" `Quick test_clause_narrows_lambda;
        Alcotest.test_case "a named value inside a restrict" `Quick test_restrict_named_value;
        Alcotest.test_case "spawns are charged" `Quick test_spawn_charged;
        Alcotest.test_case "a function value created inside a mock is not tracked" `Quick test_mock_not_tracked ] );
    ( "scoped",
      [ Alcotest.test_case "the marker parses in a callback type" `Quick test_scoped_parses;
        Alcotest.test_case "scoped is still an ordinary name" `Quick test_scoped_is_still_a_name;
        Alcotest.test_case "the marker anywhere else is an error" `Quick test_scoped_misplaced ] );
    ("escape", List.map (fun (n, f) -> Alcotest.test_case n `Quick f) escape_cases);
    ("no escape", List.map (fun (n, f) -> Alcotest.test_case n `Quick f) accepted_cases);
    ( "the escape check",
      [ Alcotest.test_case "does not run when no scoped function is named" `Quick test_pass_skipped;
        Alcotest.test_case "a crash in the pass is an internal compiler error" `Quick test_pass_crash_is_an_ice;
        Alcotest.test_case "an impl method is checked" `Quick test_escape_in_impl_method ] ) ]
