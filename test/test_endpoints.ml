(* `@[endpoints]`: the protocol projector (lib/desugar/desugar_endpoints.ml).

   Design record: specs/todos/2026-09-03-protocol-projector-typed-endpoints.md.

   Two layers.  The SHAPE tests look at the desugared module and pin what is
   generated for `Stream` (binary) and `Relay` (three roles): which modules,
   which transitions, which destinations.  A change in emitted shape is then a
   readable test diff rather than a downstream typing failure.  The GUARANTEE
   tests typecheck user code against the generated API and are the load-bearing
   ones: order, replay, abandonment and callback abandonment must each be
   REJECTED -- a generated API whose misuse still compiles is worthless.  The
   reject corpus (specs/lang/types/reject/t186-t189) carries the same four with
   the exact diagnostics; these keep them in the ordinary suite. *)

open Test_helpers
open March_ast.Ast

(* The generated code calls `Session.*`, `Json.*` and `Bytes.*`, so the
   guarantee tests typecheck with those three stdlib modules prepended, the
   way the CLI prepends the stdlib.  Each is self-contained (verified by grep:
   none references another module).  Without them every accept case fails on
   an unknown module and every reject case passes for the wrong reason. *)
let stdlib = lazy
  [ load_stdlib_file_for_test "bytes.march";
    load_stdlib_file_for_test "json.march";
    load_stdlib_file_for_test "session.march" ]

let typecheck_with_stdlib src =
  let m = parse_and_desugar src in
  let m = { m with mod_decls = Lazy.force stdlib @ m.mod_decls } in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
  errors

(* The CLI typechecks the stdlib once, separately, and FILTERS diagnostics
   whose span lies in a stdlib file; prepending the stdlib as nested modules
   here does not get that filter, and the prepended `Session` module then
   reports its own `Cap(Session.Live)` uses against a manifest it cannot see.
   Mirror the CLI: only diagnostics outside stdlib files count. *)
let in_stdlib (d : March_errors.Errors.diagnostic) =
  let f = d.span.file in
  let n = String.length f in
  let rec has i = i + 7 <= n && (String.sub f i 7 = "stdlib/" || has (i + 1)) in
  has 0

let error_messages (ctx : March_errors.Errors.ctx) =
  List.filter_map
    (fun (d : March_errors.Errors.diagnostic) ->
       if d.severity = March_errors.Errors.Error && not (in_stdlib d) then Some d.message else None)
    ctx.diagnostics

let ok name src =
  Alcotest.test_case name `Quick (fun () ->
      let ctx = typecheck_with_stdlib src in
      Alcotest.(check (list string)) (name ^ ": no error") [] (error_messages ctx))

(** [bad name needle src]: rejected, AND an error message contains [needle] --
    so a reject that fails for an unrelated reason does not count. *)
let bad name needle src =
  Alcotest.test_case name `Quick (fun () ->
      let msgs = error_messages (typecheck_with_stdlib src) in
      let contains m =
        let n = String.length needle in
        let rec go i = i + n <= String.length m && (String.sub m i n = needle || go (i + 1)) in
        go 0
      in
      Alcotest.(check bool)
        (name ^ ": an error mentions " ^ needle ^ " (got: " ^ String.concat " | " msgs ^ ")")
        true (List.exists contains msgs))

let stream = {|
  @[endpoints]
  protocol Stream do
    loop do
      Prod -> Cons : Int
      choose by Cons:
        more -> Cons -> Prod : Bool
        done -> Cons -> Prod : Bool
                stop
      end
    end
  end
|}

let relay = {|
  @[endpoints]
  protocol Relay do
    Client -> Server : String
    Server -> Logger : String
    Logger -> Client : String
  end
|}

let wrap body = "mod Main do\n  needs IO\n  needs Session.Live\n" ^ body ^ "\n  fn main(c : Cap(IO)) do () end\nend\n"

(* ── shape ─────────────────────────────────────────────────────────────── *)

(** Generated nested modules, as [(module, [fn names])], in order. *)
let generated src : (string * string list) list =
  let m = parse_and_desugar src in
  List.filter_map
    (function
      | DMod (name, _, decls, _) ->
        let fns = List.filter_map (function DFn (fd, _) -> Some fd.fn_name.txt | _ -> None) decls in
        Some (name.txt, fns)
      | _ -> None)
    m.mod_decls

let has_fn mods m f =
  match List.assoc_opt m mods with Some fns -> List.mem f fns | None -> false

let stream_shape =
  Alcotest.test_case "Stream: one Msg module and one module per role, with the transitions" `Quick
    (fun () ->
       let mods = generated (wrap stream) in
       let names = List.map fst mods in
       Alcotest.(check (list string)) "modules, generated first" [ "Stream_Msg"; "Stream_Prod"; "Stream_Cons" ] names;
       List.iter
         (fun (m, f) -> Alcotest.(check bool) (m ^ "." ^ f) true (has_fn mods m f))
         [ ("Stream_Msg", "encode"); ("Stream_Msg", "decode");
           ("Stream_Msg", "role_Prod"); ("Stream_Msg", "role_Cons");
           ("Stream_Prod", "register"); ("Stream_Prod", "send_Msg_Prod_Cons_1");
           ("Stream_Prod", "offer_more_done"); ("Stream_Prod", "close");
           ("Stream_Cons", "register"); ("Stream_Cons", "recv_Msg_Prod_Cons_1");
           ("Stream_Cons", "choose_more"); ("Stream_Cons", "choose_done"); ("Stream_Cons", "close") ])

let relay_shape =
  Alcotest.test_case "Relay: three roles, each with exactly its own send/recv" `Quick
    (fun () ->
       let mods = generated (wrap relay) in
       Alcotest.(check (list string)) "modules"
         [ "Relay_Msg"; "Relay_Client"; "Relay_Server"; "Relay_Logger" ] (List.map fst mods);
       List.iter
         (fun (m, f, expect) -> Alcotest.(check bool) (m ^ "." ^ f) expect (has_fn mods m f))
         [ ("Relay_Client", "send_Msg_Client_Server_1", true);
           ("Relay_Client", "recv_Msg_Logger_Client_1", true);
           ("Relay_Client", "recv_Msg_Server_Logger_1", false);   (* not a party to it *)
           ("Relay_Server", "recv_Msg_Client_Server_1", true);
           ("Relay_Server", "send_Msg_Server_Logger_1", true);
           ("Relay_Logger", "recv_Msg_Server_Logger_1", true);
           ("Relay_Logger", "send_Msg_Logger_Client_1", true) ])

let no_attr_no_generation =
  Alcotest.test_case "a protocol without @[endpoints] generates nothing" `Quick
    (fun () ->
       let src = wrap (String.concat "\n" (List.tl (String.split_on_char '\n' stream))) in
       (* drop the attribute line *)
       let src = Str.global_replace (Str.regexp_string "@[endpoints]") "" src in
       Alcotest.(check int) "no generated modules" 0 (List.length (generated src)))

let bad_branch_head =
  Alcotest.test_case "a choose branch not headed by the chooser's message is a desugar error" `Quick
    (fun () ->
       let src = wrap {|
  @[endpoints]
  protocol P do
    choose by A:
      x -> B -> A : Int
      y -> A -> B : Int
    end
  end
|} in
       Alcotest.(check bool) "reported" true (desugar_has_errors src))

let same_label_two_payloads =
  Alcotest.test_case "the same label with two payload types is a desugar error" `Quick
    (fun () ->
       let src = wrap {|
  @[endpoints]
  protocol P do
    choose by A:
      go -> A -> B : Int
      no -> A -> B : Bool
    end
    choose by A:
      go -> A -> B : String
      no -> A -> B : Bool
    end
  end
|} in
       Alcotest.(check bool) "reported" true (desugar_has_errors src))

(* ── guarantees ─────────────────────────────────────────────────────────── *)

let prod_ok = ok "both roles written against the generated API typecheck" (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.S_send_Msg_Prod_Cons_1, next : Int) : Stream_Prod.Yield do
    let st1 = Stream_Prod.send_Msg_Prod_Cons_1(s, st, next)
    Stream_Prod.offer_more_done(s, st1,
      fn (_b, st2) -> prod(s, st2, next + 1),
      fn (_b, st2) -> Stream_Prod.close(s, st2))
  end
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.S_recv_Msg_Prod_Cons_1, budget : Int) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1(s, st, fn (_n, st1) ->
      if budget > 1 do
        cons(s, Stream_Cons.choose_more(s, st1, true), budget - 1)
      else
        Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true))
      end)
  end
|}))

let wrong_order = bad "closing at the loop head is a type error (order)" "expected `S_end` but got `S_send_Msg_Prod_Cons_1`" (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.S_send_Msg_Prod_Cons_1) : Stream_Prod.Yield do
    Stream_Prod.close(s, st)
  end
|}))

let replayed = bad "sending twice on one state is a linearity error (replay)" "is used more than once" (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.S_send_Msg_Prod_Cons_1) : Stream_Prod.Yield do
    let a = Stream_Prod.send_Msg_Prod_Cons_1(s, st, 1)
    let b = Stream_Prod.send_Msg_Prod_Cons_1(s, st, 2)
    let _ = Stream_Prod.offer_more_done(s, a, fn (_x, st2) -> Stream_Prod.close(s, st2), fn (_x, st2) -> Stream_Prod.close(s, st2))
    Stream_Prod.offer_more_done(s, b, fn (_x, st2) -> Stream_Prod.close(s, st2), fn (_x, st2) -> Stream_Prod.close(s, st2))
  end
|}))

let abandoned = bad "registering and never driving the session is a linearity error (abandon)" "was never used" (wrap (stream ^ {|
  fn go(c : Cap(IO)) do
    let s = Session.attach(c, { register: fn (_a, r) -> r, emit: fn (e, _t, _m) -> e, suspend: fn (e, _h) -> e, close: fn _e -> () })
    let st = Stream_Prod.register(s, 0)
    ()
  end
|}))

let callback_forge = bad "a callback cannot abandon its state: the Yield token is unforgeable" "Stream_Prod.Secret" (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.S_send_Msg_Prod_Cons_1) : Stream_Prod.Yield do
    let a = Stream_Prod.send_Msg_Prod_Cons_1(s, st, 1)
    Stream_Prod.offer_more_done(s, a,
      fn (_x, st2) -> Stream_Prod.Yield(Stream_Prod.Secret),
      fn (_x, st2) -> Stream_Prod.close(s, st2))
  end
|}))

let relay_ok = ok "Relay: a client and a server against the multiparty API typecheck" (wrap (relay ^ {|
  pfn client(s : Cap(Session.Live), st : Relay_Client.S_send_Msg_Client_Server_1) : Relay_Client.Yield do
    let st1 = Relay_Client.send_Msg_Client_Server_1(s, st, "hi")
    Relay_Client.recv_Msg_Logger_Client_1(s, st1, fn (_m, st2) -> Relay_Client.close(s, st2))
  end
  pfn server(s : Cap(Session.Live), st : Relay_Server.S_recv_Msg_Client_Server_1) : Relay_Server.Yield do
    Relay_Server.recv_Msg_Client_Server_1(s, st, fn (m, st1) ->
      Relay_Server.close(s, Relay_Server.send_Msg_Server_Logger_1(s, st1, m)))
  end
|}))

let payload_declared_later = ok "a payload type declared after the protocol still resolves" (wrap {|
  @[endpoints]
  protocol Ping do
    A -> B : Marker
  end
  -- A variant, not a record: a record's derived decoder names the Json
  -- module's event constructors unqualified, which resolve only when Json is
  -- loaded as a real stdlib module (the CLI path, exercised by the fixture),
  -- not when it is prepended as a nested module as this harness does.
  type Marker = Mark(Int)
  derive Json for Marker
  pfn a(s : Cap(Session.Live), st : Ping_A.S_send_Msg_A_B_1) : Ping_A.Yield do
    Ping_A.close(s, Ping_A.send_Msg_A_B_1(s, st, Mark(1)))
  end
|})

let tests =
  [ stream_shape; relay_shape; no_attr_no_generation; bad_branch_head; same_label_two_payloads;
    prod_ok; wrong_order; replayed; abandoned; callback_forge; relay_ok; payload_declared_later ]
