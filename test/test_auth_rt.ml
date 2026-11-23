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

(* Task 4's deferred agreement case, closed by Task 6's per-actor authority:
   an actor spawned only through a function value (a named fn read as a
   value inside a framed fn, called by [List.map]) runs under that fn's
   frame, in the interpreter as compiled.  The JS target has no actors. *)
let test_spawn_via_value_every_runtime () =
  let want =
    "IO.FileRead(\"/etc/x\") refused by function start_all's needs \
     (IO.Console, IO.FileRead(\"/srv/\"), IO.Spawn)\n\
     IO.FileRead(\"/etc/x\") refused by function start_all's needs \
     (IO.Console, IO.FileRead(\"/srv/\"), IO.Spawn)\nok\n" in
  List.iter
    (fun (mode, outs) ->
       if mode <> "js" then
         List.iter (fun out -> Alcotest.(check string) mode want out) outs)
    (Test_authority_differential.run_modes ~envs:[ "" ]
       ~src:({|mod SpawnVal do
  needs IO.Console
  needs IO.FileRead
  needs IO.Spawn
  type ProbeReq = ProbeReq
|} ^ show_fn ^ {|  actor Worker do
    state { n : Int }
    init  { n: 0 }
    on Probe(reply_to) do
      Actor.reply(reply_to, show(Authority.check("IO.FileRead", "/etc/x")))
      state
    end
  end
  fn spawner(_i : Int) do
    spawn(Worker)
  end
  fn start_all(xs : List(Int)) needs IO.Console, IO.FileRead("/srv/"), IO.Spawn do
    List.map(xs, spawner)
  end
  fn ask(p) : String do
    match Actor.call(p, ProbeReq, 5000) do
    Ok(s) -> s
    Err(e) -> "call failed: " ++ e
    end
  end
  fn main() do
    let ws = start_all([1, 2])
    List.each(ws, fn w -> println(ask(w)))
    println(ask(spawner(3)))
  end
end
|}))

(* ── restrict blocks (ocap phase 5, Task 4) ───────────────────────────

   [Lower] lowers a [restrict] to a frame around its body, its layer built
   by [<encl>$restrict<N>$auth_layer]; [Auth_rt.restricts] drops the frame
   where the static check proves the block (a literal, unscoped restrict
   whose block reaches no actor spawn and no call of a function value). *)

let restricts src =
  let tir = Test_helpers.lower_module_typed src in
  let sites = Hashtbl.copy Lower.restrict_sites in
  let out, kept = Auth_rt.restricts tir ~sites in
  (tir, out, kept, sites)

let restrict_fns (m : Tir.tir_module) =
  List.filter_map
    (fun (f : Tir.fn_def) ->
       if Test_helpers.contains "$restrict" f.Tir.fn_name then Some f.Tir.fn_name else None)
    m.Tir.tm_fns

let check_framed what (main : Tir.fn_def) framed =
  let cs = callees main.Tir.fn_body in
  Alcotest.(check bool) (what ^ ": enters a frame") framed (List.mem Tir_names.enter_fn_name cs);
  Alcotest.(check bool) (what ^ ": restores") framed (List.mem "cap_restore" cs)

let test_restrict_none_identity () =
  let tir, out, kept, sites = restricts console_only in
  Alcotest.(check int) "no sites" 0 (Hashtbl.length sites);
  Alcotest.(check bool) "kept" false kept;
  Alcotest.(check bool) "the module is returned physically unchanged" true (out == tir)

let restrict_console = {|mod R1 do
  needs IO.Console
  fn main() do
    restrict IO.Console do
      println("x")
    end
  end
end
|}

let test_restrict_dropped () =
  let tir, out, kept, sites = restricts restrict_console in
  Alcotest.(check (list string)) "lowering made the layer fn" [ "main$restrict0$auth_layer" ]
    (restrict_fns tir);
  (match Hashtbl.find_opt sites "main$restrict0$auth_layer" with
   | Some rs ->
     Alcotest.(check (option string)) "literal text" (Some "IO.Console") rs.Lower_state.rs_text;
     Alcotest.(check bool) "unscoped" false rs.Lower_state.rs_scoped
   | None -> Alcotest.fail "the restrict site was not recorded");
  check_framed "lowered" (fn_exn "main" tir) true;
  Alcotest.(check bool) "kept" false kept;
  Alcotest.(check (list string)) "no layer fn is left" [] (restrict_fns out);
  let main = fn_exn "main" out in
  check_framed "after restricts" main false;
  Alcotest.(check bool) "the body remains" true (List.mem "println" (callees main.Tir.fn_body))

let restrict_scoped = {|mod R2 do
  needs IO.FileRead
  fn main() do
    restrict IO.FileRead("/a/") do
      let f = fn p -> File.read(p)
      let _r = f("/a/x")
      ()
    end
  end
end
|}

let test_restrict_scoped_kept () =
  let _, out, kept, _ = restricts restrict_scoped in
  Alcotest.(check bool) "kept" true kept;
  check_framed "scoped" (fn_exn "main" out) true;
  let layer = fn_exn "main$restrict0$auth_layer" out in
  Alcotest.(check int) "the layer fn takes nothing" 0 (List.length layer.Tir.fn_params);
  match layer.Tir.fn_body with
  | Tir.EApp (f, [ Tir.ALit (March_ast.Ast.LitString w); Tir.ALit (March_ast.Ast.LitString t) ]) ->
    Alcotest.(check string) "built by restrict_layer" "Authority.restrict_layer" f.Tir.v_name;
    Alcotest.(check bool) "where is <file>:<line>" true (String.ends_with ~suffix:":4" w);
    Alcotest.(check string) "canonical text" "IO.FileRead(\"/a/\")" t
  | _ -> Alcotest.fail "the layer fn is not restrict_layer(where, text)"

let test_restrict_hof_kept () =
  let _, out, kept, _ = restricts {|mod R3 do
  needs IO.Console
  fn twice(x : Int) : Int do x * 2 end
  fn main() do
    restrict IO.Console do
      let ys = List.map([1, 2], twice)
      println(int_to_string(List.length(ys)))
    end
  end
end
|} in
  Alcotest.(check bool) "kept" true kept;
  check_framed "List.map" (fn_exn "main" out) true;
  Alcotest.(check bool) "the layer fn stays" true (fn_opt "main$restrict0$auth_layer" out <> None)

let test_restrict_spawn_kept () =
  let _, out, kept, _ = restricts {|mod R4 do
  needs IO.Spawn
  actor Counter do
    state { count : Int }
    init  { count: 0 }
    on Inc() do
      { count: state.count + 1 }
    end
  end
  fn main() do
    restrict IO.Spawn do
      let _pid = spawn(Counter)
      ()
    end
  end
end
|} in
  Alcotest.(check bool) "kept" true kept;
  check_framed "spawn" (fn_exn "main" out) true

(* A function value made outside the block: the static check does not judge
   its call, so only the frame can. *)
let test_restrict_fn_value_kept () =
  let _, out, kept, _ = restricts {|mod R6 do
  needs IO.Console
  fn main() do
    let g = fn () -> println("x")
    restrict () do
      g()
    end
  end
end
|} in
  Alcotest.(check bool) "kept" true kept;
  check_framed "g()" (fn_exn "main" out) true

let restrict_computed = {|mod R5 do
  needs IO.FileRead
  fn go(s : Scope) : Unit do
    restrict s do
      ()
    end
  end
  fn main() do
    match IO.FileRead("/a/" ++ "b") do
    Ok(s) -> go(s)
    Err(_) -> ()
    end
  end
end
|}

let test_restrict_computed_kept () =
  let tir, out, kept, sites = restricts restrict_computed in
  Alcotest.(check bool) "kept" true kept;
  Alcotest.(check bool) "nothing dropped, so the module is unchanged" true (out == tir);
  (match Hashtbl.find_opt sites "go$restrict0$auth_layer" with
   | Some rs -> Alcotest.(check (option string)) "computed" None rs.Lower_state.rs_text
   | None -> Alcotest.fail "the computed site was not recorded");
  Alcotest.(check (list string)) "no layer fn" [] (restrict_fns out);
  let go = fn_exn "go" out in
  check_framed "computed" go true;
  let cs = callees go.Tir.fn_body in
  Alcotest.(check bool) "its text is the scope's" true (List.mem "Scope.text" cs);
  Alcotest.(check bool) "its layer is parsed at entry" true (List.mem "Authority.restrict_layer" cs);
  Alcotest.(check bool) "the computed scope expression is built and checked" true
    (List.mem "Scope.build" (callees (fn_exn "main" out).Tir.fn_body))

let test_scope_exprs_lowered () =
  let tir, _, _, sites = restricts {|mod R7 do
  needs IO.Console
  needs IO.Clock
  fn join(a : Scope, b : Scope) : Scope do
    a + b
  end
  fn main() do
    let s = IO.Console + IO.Clock
    println(Scope.to_string(join(s, IO.Console)))
    restrict IO.Console + IO.Clock do
      println("x")
    end
  end
end
|} in
  Alcotest.(check bool) "+ on Scope values is Scope.union" true
    (List.mem "Scope.union" (callees (fn_exn "join" tir).Tir.fn_body));
  let lits = ref [] in
  let rec scan (e : Tir.expr) =
    match e with
    | Tir.EApp ({ Tir.v_name = "Scope.literal"; _ }, [ Tir.ALit (March_ast.Ast.LitString t) ]) ->
      lits := t :: !lits
    | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> scan a; scan b
    | Tir.ELetRec (fns, b) -> List.iter (fun (f : Tir.fn_def) -> scan f.Tir.fn_body) fns; scan b
    | Tir.ECase (_, brs, d) ->
      List.iter (fun (br : Tir.branch) -> scan br.Tir.br_body) brs; Option.iter scan d
    | _ -> ()
  in
  scan (fn_exn "main" tir).Tir.fn_body;
  Alcotest.(check (list string)) "a + of literals is one literal" [ "IO.Console, IO.Clock"; "IO.Console" ]
    (List.rev !lits);
  match Hashtbl.find_opt sites "main$restrict0$auth_layer" with
  | Some rs ->
    Alcotest.(check (option string)) "restrict text" (Some "IO.Console, IO.Clock") rs.Lower_state.rs_text
  | None -> Alcotest.fail "no site"

(* restricts, then frames and captures as every pipeline runs them. *)
let restrict_pipeline src =
  let tir = Test_helpers.lower_module_typed src in
  let needs = Hashtbl.copy Lower.fn_needs_tbl in
  let tir, rk = Auth_rt.restricts tir ~sites:(Hashtbl.copy Lower.restrict_sites) in
  let tir, fk = Auth_rt.frames tir ~needs in
  (Auth_rt.captures tir ~has_frames:(rk || fk) ~repl:false, rk || fk)

let test_restrict_lambda_captures () =
  let out, has = restrict_pipeline restrict_scoped in
  Alcotest.(check bool) "has_frames" true has;
  let main = fn_exn "main" out in
  (match lambda_of (rhs_exn "f" main) with
   | Some (fd, true) -> check_enters "fn p -> File.read(p)" fd
   | _ -> Alcotest.fail "a lambda made inside a kept restrict is not captured");
  (* It captures the narrowed authority: saved after the frame's entry. *)
  let cs = callees main.Tir.fn_body in
  let pos name =
    let rec go i = function [] -> -1 | x :: r -> if x = name then i else go (i + 1) r in
    go 0 cs in
  Alcotest.(check bool) "cap_save follows Authority.enter_fn" true
    (pos Tir_names.enter_fn_name >= 0 && pos "cap_save" > pos Tir_names.enter_fn_name)

(* Every runtime: a frame
   kept for a call of a module-level function value (which captures nothing,
   so runs under the restrict), none needed for a closure made outside (it
   keeps its own authority), a dropped frame pushes no layer, and a closure
   made inside a scoped restrict keeps the narrowed authority after the
   block. *)
let test_restrict_every_runtime () =
  let want =
    String.concat "\n"
      [ "IO.FileRead(\"/etc/x\") refused by the restrict at launch.march:13 (IO.Console)";
        "ok";
        "0";
        "IO.FileRead(\"/etc/x\") refused by the restrict at launch.march:25 (IO.FileRead(\"/srv/\"))";
        "ok";
        "0";
        "" ]
  in
  List.iter
    (fun (mode, outs) ->
       (* The interpreter always enters the frame (no drop rule, by design),
          so the third line, the layer count inside a block the compiled
          runtimes drop, is 1 there and 0 elsewhere. *)
       let want =
         if mode = "interp" then
           String.concat "\n"
             (List.mapi (fun i l -> if i = 2 then "1" else l) (String.split_on_char '\n' want))
         else want in
       List.iter (fun out -> Alcotest.(check string) mode want out) outs)
    (Test_authority_differential.run_modes ~envs:[ "" ]
       ~src:({|mod RestrictRt do
  needs IO.Console
  needs IO.FileRead
|} ^ show_fn ^ {|  let probe_l = fn p -> show(Authority.check("IO.FileRead", p))
  fn main() do
    let g = fn p -> show(Authority.check("IO.FileRead", p))
    let a = restrict IO.Console do
      probe_l("/etc/x")
    end
    println(a)
    let b = restrict () do
      g("/etc/x")
    end
    println(b)
    let c = restrict IO.Console do
      int_to_string(List.length(cap_layers()))
    end
    println(c)
    let h = restrict IO.FileRead("/srv/") do
      fn p -> show(Authority.check("IO.FileRead", p))
    end
    println(h("/etc/x"))
    println(h("/srv/a"))
    println(int_to_string(List.length(cap_layers())))
  end
end
|}))

(* ── ocap phase 6, Task 4: dependency grant frames ([Auth_rt.grants]) ──

   The lowered TIR of one module whose nested [Dep] stands for a granted
   package: the grant table is set directly (the lowering fills it from a
   grants file, which a source string has no path for; test_dep_grants.ml
   covers that end to end). *)

let grant_of ?(scoped = false) ?(proven = true) () =
  { Lower_state.fg_pkg = "dep";
    fg_text = (if scoped then "IO.FileRead(\"/srv/\")" else "IO.FileRead");
    fg_scoped = scoped;
    fg_proven = proven }

let grants_of src (entries : (string * Lower_state.fn_grant) list) =
  let tir = Test_helpers.lower_module_typed src in
  let tbl = Hashtbl.create 8 in
  List.iter (fun (n, g) -> Hashtbl.replace tbl n g) entries;
  let out, kept = Auth_rt.grants tir ~tbl in
  (tir, out, kept)

(* The direct callees of [e]'s own code: not a lambda's or local fn's. *)
let rec own_callees (e : Tir.expr) : string list =
  match e with
  | Tir.EApp (f, _) -> [ f.Tir.v_name ]
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> own_callees a @ own_callees b
  | Tir.ELetRec (_, b) -> own_callees b
  | Tir.ECase (_, brs, d) ->
    List.concat_map (fun (b : Tir.branch) -> own_callees b.Tir.br_body) brs
    @ (match d with Some d -> own_callees d | None -> [])
  | _ -> []

(* The direct callees inside the lambdas and local fns [e] makes. *)
let rec lambda_callees (e : Tir.expr) : string list =
  match e with
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> lambda_callees a @ lambda_callees b
  | Tir.ELetRec (fns, b) ->
    List.concat_map (fun (f : Tir.fn_def) -> callees f.Tir.fn_body) fns @ lambda_callees b
  | Tir.ECase (_, brs, d) ->
    List.concat_map (fun (b : Tir.branch) -> lambda_callees b.Tir.br_body) brs
    @ (match d with Some d -> lambda_callees d | None -> [])
  | _ -> []

let grant_layer = "dep$grant$auth_layer"

(* Whether [e] is the grant's frame: the layer, [enter_grant], ... *)
let is_grant_frame (e : Tir.expr) =
  match e with
  | Tir.ELet (_, Tir.EApp (l, []), Tir.ELet (_, Tir.EApp (en, [ _ ]), _)) ->
    l.Tir.v_name = grant_layer && en.Tir.v_name = Tir_names.enter_grant_name
  | _ -> false

let check_wrapped out name =
  let w = fn_exn name out in
  Alcotest.(check bool) (name ^ " enters the grant") true (is_grant_frame w.Tir.fn_body);
  Alcotest.(check bool) (name ^ " calls its body") true
    (List.mem (name ^ "$grant") (callees w.Tir.fn_body))

let check_unwrapped out name =
  ignore (fn_exn name out);
  Alcotest.(check bool) (name ^ " has no grant body") true (fn_opt (name ^ "$grant") out = None)

let grant_src = {|mod A do
  needs IO.Console
  mod Dep do
    fn g(x : Int) : Int do x + 1 end
    fn f(x : Int) : Int do
      let h = fn y -> g(y)
      g(x) + h(x)
    end
  end
  fn main() do
    println(int_to_string(Dep.f(1) + Dep.g(2)))
  end
end
|}

let test_grant_empty_identity () =
  let tir, out, kept = grants_of grant_src [] in
  Alcotest.(check bool) "kept" false kept;
  Alcotest.(check bool) "the module is returned physically unchanged" true (out == tir)

let test_grant_scoped_wraps_and_retargets () =
  let g = grant_of ~scoped:true () in
  let _, out, kept = grants_of grant_src [ ("Dep.f", g); ("Dep.g", g) ] in
  Alcotest.(check bool) "kept" true kept;
  check_wrapped out "Dep.f";
  check_wrapped out "Dep.g";
  let layer = fn_exn grant_layer out in
  Alcotest.(check (list string)) "one layer fn, built by grant_layer"
    [ Tir_names.grant_layer_builtin_name ] (callees layer.Tir.fn_body);
  let body = fn_exn "Dep.f$grant" out in
  Alcotest.(check bool) "an internal call targets the callee's body" true
    (List.mem "Dep.g$grant" (own_callees body.Tir.fn_body));
  Alcotest.(check bool) "and not its wrapper" false (List.mem "Dep.g" (own_callees body.Tir.fn_body));
  Alcotest.(check bool) "a lambda made in a P fn calls the wrapper" true
    (List.mem "Dep.g" (lambda_callees body.Tir.fn_body));
  Alcotest.(check bool) "never the body" false
    (List.mem "Dep.g$grant" (lambda_callees body.Tir.fn_body));
  let main = fn_exn "main" out in
  Alcotest.(check bool) "a call from outside the package keeps the wrapper" true
    (List.mem "Dep.f" (callees main.Tir.fn_body) && List.mem "Dep.g" (callees main.Tir.fn_body));
  Alcotest.(check bool) "and never targets a body" false
    (List.exists (fun n -> String.ends_with ~suffix:"$grant" n) (callees main.Tir.fn_body))

(* Two package fns, no lambda: nothing reaches a function-value call. *)
let pure_src = {|mod A do
  needs IO.Console
  mod Dep do
    fn g(x : Int) : Int do x + 1 end
    fn f(x : Int) : Int do g(x) * 2 end
  end
  fn main() do
    println(int_to_string(Dep.f(1)))
  end
end
|}

(* A dropped caller (unscoped, proven, no spawn or indirect call) keeps its
   callees' wrapper names: the grant is not certainly in force in it. *)
let test_grant_dropped_caller_keeps_wrapper_names () =
  let _, out, kept =
    grants_of pure_src
      [ ("Dep.f", grant_of ()); ("Dep.g", grant_of ~proven:false ()) ] in
  Alcotest.(check bool) "kept" true kept;
  check_unwrapped out "Dep.f";
  check_wrapped out "Dep.g";
  let f = fn_exn "Dep.f" out in
  Alcotest.(check bool) "f calls g's wrapper" true (List.mem "Dep.g" (own_callees f.Tir.fn_body));
  Alcotest.(check bool) "never g's body" false
    (List.mem "Dep.g$grant" (callees f.Tir.fn_body))

let spawn_src = {|mod A do
  needs IO.Console
  needs IO.Spawn
  mod Dep do
    actor W do
      state { n : Int }
      init { n: 0 }
      on Ping() do
        state
      end
    end
    fn g() do spawn(W) end
    fn f() do g() end
    fn pure(x : Int) : Int do x * 2 end
  end
  fn main() do
    let _ = Dep.f()
    println(int_to_string(Dep.pure(2)))
  end
end
|}

(* An unscoped, proven fn that spawns an actor (or calls one that does)
   keeps its frame; a proven, spawn-free one does not. *)
let test_grant_spawn_kept () =
  let g = grant_of () in
  let _, out, _ = grants_of spawn_src [ ("Dep.f", g); ("Dep.g", g); ("Dep.pure", g) ] in
  check_wrapped out "Dep.g";
  check_wrapped out "Dep.f";
  check_unwrapped out "Dep.pure";
  let f = fn_exn "Dep.f$grant" out in
  Alcotest.(check bool) "the kept caller targets the spawner's body" true
    (List.mem "Dep.g$grant" (own_callees f.Tir.fn_body))

let test_grant_proven_not_wrapped () =
  let tir, out, kept = grants_of pure_src [ ("Dep.f", grant_of ()); ("Dep.g", grant_of ()) ] in
  Alcotest.(check bool) "kept" false kept;
  Alcotest.(check bool) "the module is returned physically unchanged" true (out == tir)

let test_grant_unproven_wrapped () =
  let _, out, kept =
    grants_of grant_src
      [ ("Dep.f", grant_of ~proven:false ()); ("Dep.g", grant_of ~proven:false ()) ] in
  Alcotest.(check bool) "kept" true kept;
  check_wrapped out "Dep.f";
  check_wrapped out "Dep.g"

let indirect_src = {|mod A do
  needs IO.Console
  mod Dep do
    fn bump(xs : List(Int)) : List(Int) do List.map(xs, fn x -> x + 1) end
    fn apply(h : Int -> Int, x : Int) : Int do h(x) end
  end
  fn main() do
    println(int_to_string(List.length(Dep.bump([1]))))
    println(int_to_string(Dep.apply(fn x -> x, 1)))
  end
end
|}

(* Proven yet reaching a call of a function value: [List.map(xs, f)], or a
   call of its own parameter (proven by design, the callback being charged
   to the caller), keeps the frame, since a function value runs under its
   caller's authority. *)
let test_grant_indirect_wrapped () =
  let g = grant_of () in
  let _, out, _ = grants_of indirect_src [ ("Dep.bump", g); ("Dep.apply", g) ] in
  check_wrapped out "Dep.bump";
  check_wrapped out "Dep.apply"

let init_src = {|mod A do
  needs IO.Console
  mod Dep do
    let inc = fn x -> x + 1
  end
  fn main() do
    let h = Dep.inc
    println(int_to_string(h(1)))
  end
end
|}

(* A lambda made by a granted package's module-level code captures nothing
   and gets the grant's frame around its own body (decision 9). *)
let test_grant_init_lambda_prologue () =
  let tir, out, kept = grants_of init_src [ ("Dep.inc", grant_of ()) ] in
  Alcotest.(check bool) "kept" true kept;
  Alcotest.(check bool) "the init fn was module-initialiser code" true
    (Lower_state.is_module_init_fn "Dep.inc");
  check_unwrapped out "Dep.inc";
  ignore tir;
  let inc = fn_exn "Dep.inc" out in
  match lambdas inc.Tir.fn_body with
  | [ (fd, _) ] ->
    Alcotest.(check bool) "a module-initialiser lambda" true
      (Lower_state.is_module_init_lambda fd.Tir.fn_name);
    Alcotest.(check bool) "its body is inside the grant's frame" true
      (is_grant_frame fd.Tir.fn_body);
    ignore (fn_exn grant_layer out)
  | ls -> Alcotest.failf "expected one lambda in Dep.inc, got %d" (List.length ls)

let mk_src = {|mod A do
  needs IO.Console
  needs IO.FileRead
  mod Dep do
|} ^ show_fn ^ {|    fn mk() : String -> String do
      fn p -> show(Authority.check("IO.FileRead", p))
    end
  end
  fn main() do
    let m = Dep.mk()
    println(m("/etc/x"))
  end
end
|}

(* A lambda made inside a wrapped fn captures the authority it was made
   under (the grant's): [captures] runs with [has_frames]. *)
let test_grant_lambda_captured () =
  let _, out, kept = grants_of mk_src [ ("Dep.mk", grant_of ~scoped:true ()) ] in
  Alcotest.(check bool) "kept" true kept;
  let cap = Auth_rt.captures out ~has_frames:kept ~repl:false in
  let body = fn_exn "Dep.mk$grant" cap in
  Alcotest.(check bool) "the body saves the authority" true (saves body);
  match lambdas body.Tir.fn_body with
  | (_, captured) :: _ -> Alcotest.(check bool) "the lambda captures" true captured
  | [] -> Alcotest.fail "no lambda in Dep.mk$grant"

(* A granted package's actor: its handler and spawn glue (as the lowering
   tags them) are wrapped, the dispatch glue is not, and the dispatch keeps
   calling the handler's wrapper. *)
let test_grant_actor_handlers () =
  let tir = Test_helpers.lower_module_typed spawn_src in
  let names = List.map (fun (f : Tir.fn_def) -> f.Tir.fn_name) tir.Tir.tm_fns in
  let handler = List.find (fun n -> String.ends_with ~suffix:"W_Ping" n) names in
  let spawner = List.find (fun n -> String.ends_with ~suffix:"W_spawn" n) names in
  let dispatch = List.find (fun n -> String.ends_with ~suffix:"W_dispatch" n) names in
  (* As the lowering tags them: no checker key, never proven. *)
  let g = grant_of ~proven:false () in
  let _, out, kept = grants_of spawn_src [ (handler, g); (spawner, g) ] in
  Alcotest.(check bool) "kept" true kept;
  check_wrapped out handler;
  check_wrapped out spawner;
  check_unwrapped out dispatch;
  let d = fn_exn dispatch out in
  Alcotest.(check bool) "the dispatch calls the handler's wrapper" true
    (List.mem handler (callees d.Tir.fn_body))

(* ── Fix round 1 ── *)

(* I1: the package -> layer name map is injective: [a-b] and [a_b] get two
   layer fns, and each package's wrapper enters its own. *)
let test_grant_layer_names_injective () =
  let la = Tir_names.grant_layer_fn_of "a-b" and lb = Tir_names.grant_layer_fn_of "a_b" in
  Alcotest.(check bool) "distinct names" true (la <> lb);
  Alcotest.(check string) "a-b" "a_2db$grant$auth_layer" la;
  Alcotest.(check string) "a_b" "a_5fb$grant$auth_layer" lb;
  let ga = { (grant_of ~scoped:true ()) with Lower_state.fg_pkg = "a-b" } in
  let gb = { (grant_of ~scoped:true ()) with Lower_state.fg_pkg = "a_b" } in
  let _, out, _ = grants_of pure_src [ ("Dep.f", ga); ("Dep.g", gb) ] in
  let layer_called name = List.hd (callees (fn_exn name out).Tir.fn_body) in
  Alcotest.(check string) "Dep.f enters a-b's layer" la (layer_called "Dep.f");
  Alcotest.(check string) "Dep.g enters a_b's layer" lb (layer_called "Dep.g");
  ignore (fn_exn la out);
  ignore (fn_exn lb out);
  let f = fn_exn "Dep.f$grant" out in
  Alcotest.(check bool) "a call into the other package keeps its wrapper" true
    (List.mem "Dep.g" (own_callees f.Tir.fn_body))

let generic_src = {|mod A do
  needs IO.Console
  type Probe = Probe
  impl Show(Probe) do
    fn show(_p) do "probe" end
  end
  mod Dep do
    fn describe(x) do "<" ++ show(x) ++ ">" end
  end
  fn main() do
    println(Dep.describe(Probe))
  end
end
|}

(* I2: an unscoped, proven fn whose generic interface call mono may resolve
   to an impl outside the package keeps its frame. *)
let test_grant_iface_dispatch_kept () =
  let _, out, _ = grants_of generic_src [ ("Dep.describe", grant_of ()) ] in
  check_wrapped out "Dep.describe"

let interp_src = {|mod A do
  needs IO.Console
  type Probe = Probe
  impl Show(Probe) do
    fn show(_p) do "probe" end
  end
  mod Dep do
    fn bracket(x) do "[${x}]" end
  end
  fn main() do
    println(Dep.bracket(Probe))
  end
end
|}

(* R1: interpolation on a type variable lowers to [to_string(x)], which mono
   resolves to Show impls: the frame is kept, as for [show(x)]. *)
let test_grant_interp_dispatch_kept () =
  let _, out, _ = grants_of interp_src [ ("Dep.bracket", grant_of ()) ] in
  check_wrapped out "Dep.bracket"

let two_pkg_src = {|mod A do
  needs IO.Console
  mod Other do
    fn g(x : Int) : Int do x + 1 end
  end
  mod Dep do
    fn f(x : Int) : Int do Other.g(x) * 2 end
  end
  fn main() do
    println(int_to_string(Dep.f(1)))
  end
end
|}

(* M2 (a): a kept body of P calling a fn of another granted package Q keeps
   Q's wrapper name, so the call enters Q's grant too. *)
let test_grant_cross_package_keeps_wrapper () =
  let gq = { (grant_of ~scoped:true ()) with Lower_state.fg_pkg = "other" } in
  let _, out, _ = grants_of two_pkg_src [ ("Dep.f", grant_of ~scoped:true ()); ("Other.g", gq) ] in
  check_wrapped out "Dep.f";
  let f = fn_exn "Dep.f$grant" out in
  Alcotest.(check bool) "calls Other.g's wrapper" true (List.mem "Other.g" (own_callees f.Tir.fn_body));
  Alcotest.(check bool) "never its body" false (List.mem "Other.g$grant" (callees f.Tir.fn_body))

let needs_src = {|mod A do
  needs IO.Console
  needs IO.FileRead
  mod Dep do
    needs IO.FileRead
    fn f(p : String) : Bool needs IO.FileRead("/srv/") do
      match Authority.check("IO.FileRead", p) do
      Ok(_) -> true
      Err(_) -> false
      end
    end
  end
  fn main() do
    println(Dep.f("/srv/x"))
  end
end
|}

(* M2 (b): a P fn that also has a framed `needs` clause: the grant's
   wrapper [f] (outermost) calls [f$grant], the needs frame's wrapper, which
   enters the fn frame around [f$auth]. *)
let test_grant_around_needs_frame () =
  let tir, needs = lower needs_src in
  let framed, has = Auth_rt.frames tir ~needs in
  Alcotest.(check bool) "the needs clause is framed" true has;
  let tbl = Hashtbl.create 1 in
  Hashtbl.replace tbl "Dep.f" (grant_of ~scoped:true ());
  let out, kept = Auth_rt.grants framed ~tbl in
  Alcotest.(check bool) "kept" true kept;
  check_wrapped out "Dep.f";
  let mid = fn_exn "Dep.f$grant" out in
  Alcotest.(check (list string)) "f$grant enters the fn frame around f$auth"
    [ "Dep.f$auth_layer"; Tir_names.enter_fn_name; "Dep.f$auth"; "cap_restore" ]
    (callees mid.Tir.fn_body);
  Alcotest.(check bool) "f$auth is not wrapped again" true (fn_opt "Dep.f$auth$grant" out = None)

let named_init_src = {|mod A do
  needs IO.Console
  needs IO.FileRead
  mod Dep do
    let named = Authority.check
  end
  fn main() do
    let n = Dep.named
    println(n("IO.FileRead", "/etc/x") == Ok(()))
  end
end
|}

(* C1: a named fn value in a P module-level initialiser becomes an eta
   lambda registered as module-initialiser code, with the grant prologue. *)
let test_grant_init_named_value_eta () =
  let _, out, kept = grants_of named_init_src [ ("Dep.named", grant_of ()) ] in
  Alcotest.(check bool) "kept" true kept;
  let f = fn_exn "Dep.named" out in
  match lambdas f.Tir.fn_body with
  | [ (fd, _) ] ->
    Alcotest.(check bool) "a module-initialiser lambda" true
      (Lower_state.is_module_init_lambda fd.Tir.fn_name);
    Alcotest.(check bool) "inside the grant's frame" true (is_grant_frame fd.Tir.fn_body);
    Alcotest.(check bool) "that calls the named fn" true
      (List.mem "Authority.check" (callees fd.Tir.fn_body))
  | ls -> Alcotest.failf "expected one eta lambda in Dep.named, got %d" (List.length ls)

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
    ( "auth_rt_grants",
      [ Alcotest.test_case "an empty grant table leaves the module unchanged" `Quick
          test_grant_empty_identity;
        Alcotest.test_case "a scoped grant wraps every package fn; internal calls target bodies"
          `Quick test_grant_scoped_wraps_and_retargets;
        Alcotest.test_case "a dropped caller keeps its callees' wrapper names" `Quick
          test_grant_dropped_caller_keeps_wrapper_names;
        Alcotest.test_case "a proven fn that reaches a spawn keeps its frame" `Quick
          test_grant_spawn_kept;
        Alcotest.test_case "unscoped, proven, spawn-free fns get no frame" `Quick
          test_grant_proven_not_wrapped;
        Alcotest.test_case "an unproven fn is wrapped" `Quick test_grant_unproven_wrapped;
        Alcotest.test_case "a proven fn reaching a function-value call is wrapped" `Quick
          test_grant_indirect_wrapped;
        Alcotest.test_case "a module-level lambda gets the grant prologue" `Quick
          test_grant_init_lambda_prologue;
        Alcotest.test_case "a lambda made in a wrapped fn captures" `Quick
          test_grant_lambda_captured;
        Alcotest.test_case "a package actor's handler and spawn are wrapped" `Quick
          test_grant_actor_handlers;
        Alcotest.test_case "two packages get two layers (a-b, a_b)" `Quick
          test_grant_layer_names_injective;
        Alcotest.test_case "a generic interface call keeps the frame" `Quick
          test_grant_iface_dispatch_kept;
        Alcotest.test_case "interpolation of a generic value keeps the frame" `Quick
          test_grant_interp_dispatch_kept;
        Alcotest.test_case "a call into another granted package keeps its wrapper" `Quick
          test_grant_cross_package_keeps_wrapper;
        Alcotest.test_case "the grant wraps a needs frame" `Quick test_grant_around_needs_frame;
        Alcotest.test_case "a module-level named fn value becomes a framed eta lambda" `Quick
          test_grant_init_named_value_eta ] );
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
          test_capture_every_runtime;
        Alcotest.test_case "an actor spawned through a function value runs under the frame, interp = compiled"
          `Quick test_spawn_via_value_every_runtime ] );
    ( "auth_rt_restrict",
      [ Alcotest.test_case "a module with no restrict is unchanged" `Quick
          test_restrict_none_identity;
        Alcotest.test_case "an unscoped literal restrict the checker proves is dropped" `Quick
          test_restrict_dropped;
        Alcotest.test_case "a scoped restrict is kept" `Quick test_restrict_scoped_kept;
        Alcotest.test_case "a restrict calling List.map with a fn is kept" `Quick
          test_restrict_hof_kept;
        Alcotest.test_case "a restrict that spawns an actor is kept" `Quick test_restrict_spawn_kept;
        Alcotest.test_case "a restrict calling a function value is kept" `Quick
          test_restrict_fn_value_kept;
        Alcotest.test_case "a computed restrict is kept" `Quick test_restrict_computed_kept;
        Alcotest.test_case "scope expressions and + lower to Scope calls" `Quick
          test_scope_exprs_lowered;
        Alcotest.test_case "a lambda made in a kept restrict captures the narrowed authority"
          `Quick test_restrict_lambda_captures;
        Alcotest.test_case "restrict frames in every compiled runtime" `Quick
          test_restrict_every_runtime ] ) ]
