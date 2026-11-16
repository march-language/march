(* ocap phase 4, Task 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md):
   run-time frames for function `needs` clauses ([March_tir.Auth_rt]).

   A fn with a `needs` clause gets a frame only when the clause carries a
   scope, or the fn reaches an actor spawn or a call of a function value
   (the checker proves only direct calls); everything else the static
   checker already proves.  A framed [f] becomes a wrapper that enters the
   frame (its layer built once by [f$auth_layer]) around [f$auth], the
   original body, whose self calls target [f$auth] so a self tail call stays
   a loop; a lambda it makes keeps calling the wrapper, since it may run
   outside the frame.  No frame for the program entry.

   The first group inspects the lowered TIR; the second runs a framed
   program in every runtime. *)

open March_tir

let lower src =
  let tir = Test_helpers.lower_module_typed src in
  (tir, Hashtbl.copy Lower.fn_needs_tbl)

let frames src =
  let tir, needs = lower src in
  let out, has = Auth_rt.frames tir ~needs in
  (tir, out, has)

let fn_opt name (m : Tir.tir_module) =
  List.find_opt (fun (f : Tir.fn_def) -> f.Tir.fn_name = name) m.Tir.tm_fns

let fn_exn name m =
  match fn_opt name m with
  | Some f -> f
  | None ->
    Alcotest.failf "no fn %s among: %s" name
      (String.concat ", " (List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) m.Tir.tm_fns))

(* Every direct callee in [e], in order. *)
let rec callees (e : Tir.expr) : string list =
  match e with
  | Tir.EApp (f, _) -> [ f.Tir.v_name ]
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> callees a @ callees b
  | Tir.ELetRec (fns, b) ->
    List.concat_map (fun (f : Tir.fn_def) -> callees f.Tir.fn_body) fns @ callees b
  | Tir.ECase (_, brs, d) ->
    List.concat_map (fun (b : Tir.branch) -> callees b.Tir.br_body) brs
    @ (match d with Some d -> callees d | None -> [])
  | _ -> []

(* The callee of every call in tail position of [e]. *)
let rec tail_callees (e : Tir.expr) : string list =
  match e with
  | Tir.EApp (f, _) -> [ f.Tir.v_name ]
  | Tir.ELet (_, _, b) | Tir.ESeq (_, b) | Tir.ELetRec (_, b) -> tail_callees b
  | Tir.ECase (_, brs, d) ->
    List.concat_map (fun (b : Tir.branch) -> tail_callees b.Tir.br_body) brs
    @ (match d with Some d -> tail_callees d | None -> [])
  | _ -> []

let console_only = {|mod A do
  needs IO.Console
  fn greet(s : String) : Unit needs IO.Console do
    println(s)
  end
  fn main() do
    greet("hi")
  end
end
|}

let test_unscoped_not_framed () =
  let tir, out, has = frames console_only in
  Alcotest.(check bool) "the needs clause was recorded" true
    (Hashtbl.mem Lower.fn_needs_tbl "greet");
  Alcotest.(check bool) "has_frames" false has;
  Alcotest.(check bool) "the module is returned physically unchanged" true (out == tir);
  Alcotest.(check bool) "no greet$auth" true (fn_opt "greet$auth" out = None)

let scoped = {|mod B do
  needs IO.Console
  needs IO.FileRead
  fn read_in(p : String) : String needs IO.FileRead("/a/") do
    p
  end
  fn main() needs IO.Console, IO.FileRead("/a/") do
    println(read_in("/a/x"))
  end
end
|}

let test_scoped_framed () =
  let _, out, has = frames scoped in
  Alcotest.(check bool) "has_frames" true has;
  let w = fn_exn "read_in" out in
  Alcotest.(check (list string)) "the wrapper enters the frame around the body"
    [ "read_in$auth_layer"; Tir_names.enter_fn_name; "read_in$auth"; "cap_restore" ]
    (callees w.Tir.fn_body);
  let body = fn_exn "read_in$auth" out in
  Alcotest.(check int) "the body keeps the params" 1 (List.length body.Tir.fn_params);
  let layer = fn_exn "read_in$auth_layer" out in
  Alcotest.(check int) "the layer fn takes nothing" 0 (List.length layer.Tir.fn_params);
  (match layer.Tir.fn_body with
   | Tir.EApp (f, [ Tir.ALit (March_ast.Ast.LitString n); Tir.ALit (March_ast.Ast.LitString t) ]) ->
     Alcotest.(check string) "the layer is parsed by frame_layer" Tir_names.frame_layer_fn_name
       f.Tir.v_name;
     Alcotest.(check string) "the frame's name" "read_in" n;
     Alcotest.(check string) "canonical needs text" "IO.FileRead(\"/a/\")" t
   | _ -> Alcotest.fail "the layer fn is not frame_layer(name, text)");
  Alcotest.(check bool) "no frame for main" true (fn_opt "main$auth" out = None)

let spawner = {|mod C do
  needs IO.Console
  needs IO.Spawn
  actor Counter do
    state { count : Int }
    init  { count: 0 }
    on Inc() do
      { count: state.count + 1 }
    end
  end
  fn start() : Unit needs IO.Spawn do
    let _pid = spawn(Counter)
    ()
  end
  fn go() : Unit needs IO.Console, IO.Spawn do
    start()
  end
  fn quiet() : Unit needs IO.Console do
    println("x")
  end
  fn main() do
    go()
    quiet()
  end
end
|}

let test_spawn_framed () =
  let _, out, has = frames spawner in
  Alcotest.(check bool) "has_frames" true has;
  Alcotest.(check bool) "the spawning fn is framed" true (fn_opt "start$auth" out <> None);
  Alcotest.(check bool) "a fn that calls a spawning fn is framed" true
    (fn_opt "go$auth" out <> None);
  Alcotest.(check bool) "a fn that reaches no spawn is not" true (fn_opt "quiet$auth" out = None)

let self_tail = {|mod D do
  needs IO.Console
  needs IO.FileRead
  fn countdown(n : Int) : Int needs IO.FileRead("/a/") do
    if n == 0 do 0 else countdown(n - 1) end
  end
  fn main() needs IO.Console, IO.FileRead("/a/") do
    println(countdown(3))
  end
end
|}

let test_self_tail_call () =
  let _, out, _ = frames self_tail in
  let body = fn_exn "countdown$auth" out in
  Alcotest.(check bool) "the self tail call targets countdown$auth" true
    (List.mem "countdown$auth" (tail_callees body.Tir.fn_body));
  Alcotest.(check bool) "and never re-enters the wrapper" false
    (List.mem "countdown" (callees body.Tir.fn_body));
  Alcotest.(check bool) "the self call is still in tail position (TCO)" true
    (Llvm_tco.has_self_tail_call "countdown$auth" body.Tir.fn_body)

let scoped_main = {|mod E do
  needs IO.Console
  needs IO.FileRead
  fn main() needs IO.Console, IO.FileRead("/a/") do
    println("x")
  end
end
|}

let test_main_not_framed () =
  let tir, out, has = frames scoped_main in
  Alcotest.(check bool) "main's clause is the launch request, not a frame" false has;
  Alcotest.(check bool) "unchanged" true (out == tir)

let fn_value = {|mod F do
  needs IO.Console
  fn apply_it(h : String -> String, p : String) : String needs IO.Console do
    h(p)
  end
  fn via_helper(p : String) : String needs IO.Console do
    apply_it(fn s -> s, p)
  end
  fn local_fn(p : String) : String needs IO.Console do
    let twice = fn s -> s ++ s
    p
  end
  fn main() do
    println(via_helper("a"))
    println(local_fn("b"))
  end
end
|}

let test_fn_value_framed () =
  let _, out, has = frames fn_value in
  Alcotest.(check bool) "has_frames" true has;
  Alcotest.(check bool) "a fn that calls a function value is framed" true
    (fn_opt "apply_it$auth" out <> None);
  Alcotest.(check bool) "a fn that reaches one through a direct call is framed" true
    (fn_opt "via_helper$auth" out <> None);
  Alcotest.(check bool) "making a lambda without calling a value is not" true
    (fn_opt "local_fn$auth" out = None)

let spawn_via_value = {|mod G do
  needs IO.Console
  needs IO.Spawn
  actor Worker do
    state { n : Int }
    init  { n: 0 }
    on Go() do
      state
    end
  end
  fn spawner(_i : Int) : Unit do
    let _pid = spawn(Worker)
    ()
  end
  fn each(xs : List(Int), f : Int -> Unit) : Unit do
    match xs do
    Nil -> ()
    Cons(x, rest) ->
      f(x)
      each(rest, f)
    end
  end
  fn start_all(xs : List(Int)) : Unit needs IO.Console, IO.Spawn do
    each(xs, spawner)
  end
  fn main() do
    start_all([1, 2])
  end
end
|}

let test_spawn_via_value_framed () =
  let _, out, _ = frames spawn_via_value in
  Alcotest.(check bool) "a spawn reached only through a function value is framed" true
    (fn_opt "start_all$auth" out <> None)

let escaping_lambda = {|mod H do
  needs IO.Console
  needs IO.FileRead
  fn mk(p : String) : String -> String needs IO.FileRead("/a/") do
    if p == "self" do
      fn q ->
        let h = mk(q)
        h(q)
    else
      fn _ -> p
    end
  end
  fn main() needs IO.Console, IO.FileRead("/a/") do
    let g = mk("self")
    println(g("/a/x"))
  end
end
|}

let test_lambda_calls_wrapper () =
  let _, out, _ = frames escaping_lambda in
  let body = fn_exn "mk$auth" out in
  Alcotest.(check bool) "a lambda's self call stays on the wrapper" true
    (List.mem "mk" (callees body.Tir.fn_body));
  Alcotest.(check bool) "and never targets the unframed body" false
    (List.mem "mk$auth" (callees body.Tir.fn_body))

(* ── Task 5: function values capture the authority they were made under ── *)

let captures ?(repl = false) src =
  let tir, needs = lower src in
  let framed, has_frames = Auth_rt.frames tir ~needs in
  (framed, Auth_rt.captures framed ~has_frames ~repl, has_frames)

(* Whether [fd]'s body starts by entering a captured authority. *)
let enters (fd : Tir.fn_def) =
  match fd.Tir.fn_body with
  | Tir.ELet (_, Tir.EApp ({ Tir.v_name = "cap_enter"; _ }, _), _) -> true
  | _ -> false

(* The lambda [e] makes, if it makes one: [Some (fd, captured)]. *)
let lambda_of (e : Tir.expr) : (Tir.fn_def * bool) option =
  match e with
  | Tir.ELetRec ([ fd ], Tir.EAtom (Tir.AVar v)) when v.Tir.v_name = fd.Tir.fn_name ->
    Some (fd, enters fd)
  | _ -> None

(* Whether [f]'s body starts by saving the authority its values capture. *)
let saves (f : Tir.fn_def) =
  match f.Tir.fn_body with
  | Tir.ELet (v, Tir.EApp ({ Tir.v_name = "cap_save"; _ }, []), _) ->
    v.Tir.v_ty = Tir.TCon ("CapAuthRef", [])
  | _ -> false

(* The right-hand side of the first [let name = ...] in [e]. *)
let rec rhs_of name (e : Tir.expr) : Tir.expr option =
  match e with
  | Tir.ELet (v, a, b) ->
    if v.Tir.v_name = name then Some a
    else (match rhs_of name a with Some r -> Some r | None -> rhs_of name b)
  | Tir.ESeq (a, b) -> (match rhs_of name a with Some r -> Some r | None -> rhs_of name b)
  | Tir.ELetRec (fns, b) ->
    (match List.find_map (fun (f : Tir.fn_def) -> rhs_of name f.Tir.fn_body) fns with
     | Some r -> Some r
     | None -> rhs_of name b)
  | Tir.ECase (_, brs, d) ->
    (match List.find_map (fun (br : Tir.branch) -> rhs_of name br.Tir.br_body) brs with
     | Some r -> Some r
     | None -> Option.bind d (rhs_of name))
  | _ -> None

let rhs_exn name (f : Tir.fn_def) =
  match rhs_of name f.Tir.fn_body with
  | Some r -> r
  | None -> Alcotest.failf "no let %s in %s" name f.Tir.fn_name

(* Every lambda [e] makes, anywhere in it. *)
let rec lambdas (e : Tir.expr) : (Tir.fn_def * bool) list =
  let here = match lambda_of e with Some l -> [ l ] | None -> [] in
  here
  @
  match e with
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> lambdas a @ lambdas b
  | Tir.ELetRec (fns, b) ->
    List.concat_map (fun (f : Tir.fn_def) -> lambdas f.Tir.fn_body) fns @ lambdas b
  | Tir.ECase (_, brs, d) ->
    List.concat_map (fun (br : Tir.branch) -> lambdas br.Tir.br_body) brs
    @ (match d with Some d -> lambdas d | None -> [])
  | _ -> []

(* A captured lambda's body enters the saved authority and restores it. *)
let check_enters what (fd : Tir.fn_def) =
  let cs = callees fd.Tir.fn_body in
  Alcotest.(check bool) (what ^ ": the body enters the captured authority") true
    (List.mem "cap_enter" cs && List.mem "cap_restore" cs)

let rec atom_names (e : Tir.expr) : string list =
  let av = List.filter_map (function Tir.AVar v -> Some v.Tir.v_name | _ -> None) in
  match e with
  | Tir.EApp (_, args) -> av args
  | Tir.ECallPtr (f, args) -> av (f :: args)
  | Tir.EAtom a -> av [ a ]
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> atom_names a @ atom_names b
  | Tir.ELetRec (fns, b) ->
    List.concat_map (fun (f : Tir.fn_def) -> atom_names f.Tir.fn_body) fns @ atom_names b
  | _ -> []

let capture_src = {|mod K do
  needs IO.Console
  needs IO.FileRead
  let top = fn x -> println(x)
  let rd = File.read
  fn read_in(p : String) : String needs IO.FileRead("/a/") do
    p
  end
  fn main() needs IO.Console, IO.FileRead("/a/") do
    let xs = ["/a/x"]
    let f = fn x -> println(x)
    let g = fn x -> x + 1
    let ys = List.map(xs, File.read)
    let e = fn p -> File.read(p)
    f(read_in("/a/x"))
    top(int_to_string(g(List.length(ys))))
    let _r = rd("/a/y")
    let _s = e("/a/z")
    ()
  end
end
|}

let no_frames_src = {|mod K0 do
  needs IO.Console
  needs IO.FileRead
  fn main() needs IO.Console, IO.FileRead do
    let f = fn x -> println(x)
    let ys = List.map(["/a"], File.read)
    f(int_to_string(List.length(ys)))
  end
end
|}

let test_capture_no_frames_identity () =
  let framed, out, has = captures no_frames_src in
  Alcotest.(check bool) "has_frames" false has;
  Alcotest.(check bool) "without frames the module is returned physically unchanged" true
    (out == framed)

let test_capture_lambda () =
  let _, out, has = captures capture_src in
  Alcotest.(check bool) "has_frames" true has;
  let main = fn_exn "main" out in
  Alcotest.(check bool) "main saves the authority its values capture, once, on entry" true
    (saves main);
  (match lambda_of (rhs_exn "f" main) with
   | Some (fd, true) -> check_enters "fn x -> println(x)" fd
   | Some (_, false) -> Alcotest.fail "a lambda calling println is not captured"
   | None -> Alcotest.fail "f is not bound to a lambda");
  (match lambda_of (rhs_exn "g" main) with
   | Some (fd, false) ->
     Alcotest.(check bool) "fn x -> x + 1 never enters an authority" false
       (List.mem "cap_enter" (callees fd.Tir.fn_body))
   | Some (_, true) -> Alcotest.fail "fn x -> x + 1 is captured"
   | None -> Alcotest.fail "g is not bound to a lambda")

let test_capture_named_value () =
  let _, out, _ = captures capture_src in
  let rhs = rhs_exn "ys" (fn_exn "main" out) in
  Alcotest.(check bool) "File.read is no longer passed bare" false
    (List.mem "File.read" (atom_names rhs));
  match List.filter (fun (_, c) -> c) (lambdas rhs) with
  | [ (fd, true) ] ->
    check_enters "the eta lambda over File.read" fd;
    Alcotest.(check bool) "the eta lambda calls File.read" true
      (List.mem "File.read" (callees fd.Tir.fn_body))
  | ls -> Alcotest.failf "expected one capturing eta lambda, found %d" (List.length ls)

(* March has no partial application (the typechecker rejects a call that
   supplies too few arguments), so its nearest form, the explicit eta
   lambda [fn p -> File.read(p)], is what must capture. *)
let test_capture_eta_lambda () =
  let _, out, _ = captures capture_src in
  match lambda_of (rhs_exn "e" (fn_exn "main" out)) with
  | Some (fd, true) -> check_enters "fn p -> File.read(p)" fd
  | _ -> Alcotest.fail "fn p -> File.read(p) is not captured"

let test_capture_not_module_level () =
  let _, out, _ = captures capture_src in
  let main = fn_exn "main" out in
  (match lambda_of (rhs_exn "top" main) with
   | Some (_, false) -> ()
   | Some (_, true) -> Alcotest.fail "a lambda in a top-level let is captured"
   | None -> Alcotest.fail "top is not bound to a lambda");
  match rhs_exn "rd" main with
  | Tir.EAtom (Tir.AVar v) ->
    Alcotest.(check string) "a fn named in a top-level let stays bare" "File.read" v.Tir.v_name
  | _ -> Alcotest.fail "a fn named in a top-level let was wrapped"

let test_capture_repl_without_frames () =
  let framed, out, has = captures ~repl:true no_frames_src in
  Alcotest.(check bool) "has_frames" false has;
  Alcotest.(check bool) "the REPL captures even without frames" false (out == framed);
  match lambda_of (rhs_exn "f" (fn_exn "main" out)) with
  | Some (_, true) -> ()
  | _ -> Alcotest.fail "the REPL left fn x -> println(x) uncaptured"

(* ── every runtime ─────────────────────────────────────────────────── *)

let frame_src = {|mod FrameFixture do
  needs IO.Console
  needs IO.FileRead
  fn show(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> Authority.describe(e)
    end
  end
  fn read_in(p : String) : String needs IO.FileRead("/srv/") do
    show(Authority.check("IO.FileRead", p))
  end
  fn nested(p : String) : String needs IO.FileRead("/srv/") do
    read_in(p) ++ " " ++ int_to_string(List.length(cap_layers()))
  end
  fn countdown(n : Int) : Int needs IO.FileRead("/srv/") do
    if n == 0 do List.length(cap_layers()) else countdown(n - 1) end
  end
  fn main() do
    println(read_in("/srv/a"))
    println(read_in("/etc/x"))
    println(nested("/srv/b"))
    println(show(Authority.check("IO.FileRead", "/etc/x")))
    println(int_to_string(List.length(cap_layers())))
    println(int_to_string(countdown(1000000)))
    println(int_to_string(List.length(cap_layers())))
  end
end
|}

let test_frames_every_runtime () =
  let want =
    String.concat "\n"
      [ "ok";
        "IO.FileRead(\"/etc/x\") refused by function read_in's needs (IO.FileRead(\"/srv/\"))";
        "ok 1";
        "ok";
        "0";
        "1";
        "0";
        "" ]
  in
  List.iter
    (fun (mode, outs) ->
       List.iter (fun out -> Alcotest.(check string) mode want out) outs)
    (Test_authority_differential.run_modes ~src:frame_src ~envs:[ "" ])

(* One program, every runtime, the same output. *)
let same_everywhere ~want src =
  List.iter
    (fun (mode, outs) -> List.iter (fun out -> Alcotest.(check string) mode want out) outs)
    (Test_authority_differential.run_modes ~src ~envs:[ "" ])

let show_fn = {|  fn show(r : Result((), CapError)) : String do
    match r do
    Ok(_) -> "ok"
    Err(e) -> Authority.describe(e)
    end
  end
|}

(* A lambda made inside a framed fn that calls it escapes: it must enter the
   frame itself, not run the unframed body. *)
let test_escaping_lambda_every_runtime () =
  same_everywhere
    ~want:
      "IO.FileRead(\"/etc/passwd\") refused by function mk's needs (IO.FileRead(\"/srv/\"))\n\
       IO.FileRead(\"/etc/passwd\") refused by function mk's needs (IO.FileRead(\"/srv/\"))\n"
    ({|mod Esc do
  needs IO.Console
  needs IO.FileRead
|} ^ show_fn ^ {|  fn mk(p : String) : String -> String needs IO.FileRead("/srv/") do
    if p == "self" do
      fn q ->
        let h = mk(q)
        h(q)
    else
      let r = show(Authority.check("IO.FileRead", p))
      fn _ -> r
    end
  end
  fn main() do
    let g = mk("self")
    println(g("/etc/passwd"))
    let d = mk("/etc/passwd")
    println(d("x"))
  end
end
|})

(* A function value made by module-level code captures nothing: called inside
   an unscoped-needs fn, it runs under that fn's authority.  (A named fn
   passed from [main] would instead carry [main]'s authority: Task 5.) *)
let test_fn_value_every_runtime () =
  same_everywhere
    ~want:"IO.FileRead(\"/etc/passwd\") refused by function apply_it's needs (IO.Console)\n\
           IO.FileRead(\"/etc/passwd\") refused by function apply_it's needs (IO.Console)\nok\n"
    ({|mod Hof do
  needs IO.Console
  needs IO.FileRead
|} ^ show_fn ^ {|  fn probe(p : String) : String do
    show(Authority.check("IO.FileRead", p))
  end
  let probe_v = probe
  let probe_l = fn p -> show(Authority.check("IO.FileRead", p))
  fn apply_it(h : String -> String, p : String) : String needs IO.Console do
    h(p)
  end
  fn main() do
    println(apply_it(probe_v, "/etc/passwd"))
    println(apply_it(probe_l, "/etc/passwd"))
    println(probe("/etc/passwd"))
  end
end
|})

(* Task 5: a function value runs under the authority it was made under,
   wherever it is called; the caller's plays no part. *)
let test_capture_every_runtime () =
  same_everywhere
    ~want:
      (String.concat "\n"
         [ "ok";
           "ok";
           "IO.FileRead(\"/etc/x\") refused by function mk's needs (IO.FileRead(\"/srv/\"))";
           "ok";
           "IO.FileRead(\"/etc/x\") refused by function mk_named's needs (IO.FileRead(\"/srv/\"))";
           "IO.FileRead(\"/etc/x\") refused by function apply_it's needs (IO.FileRead(\"/srv/\"))";
           "0";
           "" ])
    ({|mod Capture do
  needs IO.Console
  needs IO.FileRead
|} ^ show_fn ^ {|  fn probe(p : String) : String do
    show(Authority.check("IO.FileRead", p))
  end
  let probe_l = fn p -> show(Authority.check("IO.FileRead", p))
  fn apply_it(h : String -> String, p : String) : String needs IO.FileRead("/srv/") do
    h(p)
  end
  fn mk() : String -> String needs IO.FileRead("/srv/") do
    fn p -> show(Authority.check("IO.FileRead", p))
  end
  fn mk_named() : String -> String needs IO.FileRead("/srv/") do
    probe
  end
  fn main() do
    let mine = fn p -> show(Authority.check("IO.FileRead", p))
    println(apply_it(mine, "/etc/x"))
    println(apply_it(probe, "/etc/x"))
    let m = mk()
    println(m("/etc/x"))
    println(m("/srv/a"))
    let n = mk_named()
    println(n("/etc/x"))
    println(apply_it(probe_l, "/etc/x"))
    println(int_to_string(List.length(cap_layers())))
  end
end
|})

let tests =
  [ ( "auth_rt",
      [ Alcotest.test_case "an unscoped needs clause that reaches no spawn gets no frame" `Quick
          test_unscoped_not_framed;
        Alcotest.test_case "a scoped needs clause is framed" `Quick test_scoped_framed;
        Alcotest.test_case "a fn that reaches an actor spawn is framed" `Quick test_spawn_framed;
        Alcotest.test_case "a framed fn's self tail call targets its body" `Quick
          test_self_tail_call;
        Alcotest.test_case "main gets no frame" `Quick test_main_not_framed;
        Alcotest.test_case "a fn that reaches a call of a function value is framed" `Quick
          test_fn_value_framed;
        Alcotest.test_case "a spawn reached through a function value is framed" `Quick
          test_spawn_via_value_framed;
        Alcotest.test_case "a lambda's self call keeps the frame" `Quick
          test_lambda_calls_wrapper ] );
    ( "auth_rt_capture",
      [ Alcotest.test_case "without frames captures is the identity" `Quick
          test_capture_no_frames_identity;
        Alcotest.test_case "a lambda reaching an op captures; a pure one does not" `Quick
          test_capture_lambda;
        Alcotest.test_case "a named fn passed as a value becomes a capturing eta lambda" `Quick
          test_capture_named_value;
        Alcotest.test_case "an eta lambda over a capability op captures" `Quick
          test_capture_eta_lambda;
        Alcotest.test_case "module-level function values capture nothing" `Quick
          test_capture_not_module_level;
        Alcotest.test_case "the REPL captures without frames" `Quick
          test_capture_repl_without_frames ] );
    ( "auth_rt_runtime",
      [ Alcotest.test_case "frames enforce the clause in every runtime" `Quick
          test_frames_every_runtime;
        Alcotest.test_case "an escaping lambda enters the frame in every runtime" `Quick
          test_escaping_lambda_every_runtime;
        Alcotest.test_case "a function value runs under its caller's frame in every runtime"
          `Quick test_fn_value_every_runtime;
        Alcotest.test_case "a function value runs under the authority it was made under" `Quick
          test_capture_every_runtime ] ) ]
