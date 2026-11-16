(* ocap phase 4, Task 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md):
   run-time frames for function `needs` clauses ([March_tir.Auth_rt]).

   A fn with a `needs` clause gets a frame only when the clause carries a
   scope or the fn reaches an actor spawn; everything else the static
   checker already proves.  A framed [f] becomes a wrapper that enters the
   frame (its layer built once by [f$auth_layer]) around [f$auth], the
   original body, whose self calls target [f$auth] so a self tail call stays
   a loop.  No frame for the program entry.

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

let tests =
  [ ( "auth_rt",
      [ Alcotest.test_case "an unscoped needs clause that reaches no spawn gets no frame" `Quick
          test_unscoped_not_framed;
        Alcotest.test_case "a scoped needs clause is framed" `Quick test_scoped_framed;
        Alcotest.test_case "a fn that reaches an actor spawn is framed" `Quick test_spawn_framed;
        Alcotest.test_case "a framed fn's self tail call targets its body" `Quick
          test_self_tail_call;
        Alcotest.test_case "main gets no frame" `Quick test_main_not_framed ] );
    ( "auth_rt_runtime",
      [ Alcotest.test_case "frames enforce the clause in every runtime" `Quick
          test_frames_every_runtime ] ) ]
