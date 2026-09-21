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

(* The stdlib here has no `SessionNode`, so the generated `<P>_Run` (whose
   every function calls `SessionNode.run`) cannot typecheck against it: turn
   its emission off for these cases.  Its shape is asserted below with it on,
   and the native/two-node fixtures typecheck and run it for real. *)
let without_runner f =
  let r = March_desugar.Desugar_endpoints.emit_runner in
  let saved = !r in
  r := false;
  Fun.protect ~finally:(fun () -> r := saved) f

let typecheck_with_stdlib src =
  let m = without_runner (fun () -> parse_and_desugar src) in
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
       Alcotest.(check (list string)) "modules, generated first"
         [ "Stream_Msg"; "Stream_Prod"; "Stream_Cons"; "Stream_Run" ] names;
       List.iter
         (fun (m, f) -> Alcotest.(check bool) (m ^ "." ^ f) true (has_fn mods m f))
         [ ("Stream_Msg", "encode"); ("Stream_Msg", "decode"); ("Stream_Msg", "try_decode");
           ("Stream_Msg", "role_Prod"); ("Stream_Msg", "role_Cons");
           ("Stream_Prod", "register"); ("Stream_Prod", "send_Msg_Prod_Cons_1");
           ("Stream_Prod", "offer_more_done"); ("Stream_Prod", "close");
           ("Stream_Cons", "register"); ("Stream_Cons", "recv_Msg_Prod_Cons_1");
           ("Stream_Cons", "choose_more"); ("Stream_Cons", "choose_done"); ("Stream_Cons", "close");
           (* the event API, beside the callback one, in the same modules *)
           ("Stream_Prod", "idle"); ("Stream_Prod", "take_idle"); ("Stream_Prod", "await_more_done");
           ("Stream_Prod", "finish"); ("Stream_Prod", "resume");
           ("Stream_Cons", "await_Msg_Prod_Cons_1"); ("Stream_Cons", "finish"); ("Stream_Cons", "resume");
           (* the role runner's typed front, one per role, and its address table *)
           ("Stream_Msg", "role_names");
           ("Stream_Run", "run_Prod"); ("Stream_Run", "run_Cons"); ("Stream_Run", "addrs_from_env");
           ("Stream_Run", "host_Prod"); ("Stream_Run", "host_Cons");
           (* the same roles over a running cluster node *)
           ("Stream_Run", "cluster_Prod"); ("Stream_Run", "cluster_Cons");
           (* access points, and the hosted (actor) forms of both *)
           ("Stream_Run", "offer_Prod"); ("Stream_Run", "initiate_Cons");
           ("Stream_Run", "offer_hosted_Prod"); ("Stream_Run", "offer_hosted_Cons");
           ("Stream_Run", "cluster_hosted_Prod"); ("Stream_Run", "cluster_hosted_Cons") ])

let relay_shape =
  Alcotest.test_case "Relay: three roles, each with exactly its own send/recv" `Quick
    (fun () ->
       let mods = generated (wrap relay) in
       Alcotest.(check (list string)) "modules"
         [ "Relay_Msg"; "Relay_Client"; "Relay_Server"; "Relay_Logger"; "Relay_Run" ] (List.map fst mods);
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

(* ── message labels ─────────────────────────────────────────────────────── *)

(** [stream] with its one plain step labelled `item:`, so every generated name
    that said `Msg_Prod_Cons_1` says `Item`. *)
let stream_labelled = {|
  @[endpoints]
  protocol Stream do
    loop do
      item: Prod -> Cons : Int
      choose by Cons:
        more -> Cons -> Prod : Bool
        done -> Cons -> Prod : Bool
                stop
      end
    end
  end
|}

(** The unlabelled [stream]'s generated function names, pinned: a label must
    change nothing for a protocol that has none, and this list is the oracle
    the labelled twin is compared against (below). *)
let stream_prod_fns =
  [ "register"; "cancelled"; "leave_send_Msg_Prod_Cons_1"; "send_Msg_Prod_Cons_1";
    "leave_offer_more_done"; "offer_more_done"; "offer_more_done_or"; "close";
    "idle"; "take_idle"; "cancel"; "await_more_done"; "finish"; "resume" ]

let stream_cons_fns =
  [ "register"; "cancelled"; "leave_recv_Msg_Prod_Cons_1"; "recv_Msg_Prod_Cons_1";
    "recv_Msg_Prod_Cons_1_or"; "leave_choose_more_done"; "choose_more"; "choose_done"; "close";
    "idle"; "take_idle"; "cancel"; "await_Msg_Prod_Cons_1"; "finish"; "resume" ]

let unlabelled_names_pinned =
  Alcotest.test_case "an unlabelled protocol's generated names are exactly what they were" `Quick
    (fun () ->
       let mods = generated (wrap stream) in
       Alcotest.(check (list string)) "Stream_Prod" stream_prod_fns (List.assoc "Stream_Prod" mods);
       Alcotest.(check (list string)) "Stream_Cons" stream_cons_fns (List.assoc "Stream_Cons" mods))

(** Replace every occurrence of [needle] in [s] by [by]. *)
let replace_all ~needle ~by s =
  let n = String.length needle in
  let b = Buffer.create (String.length s) in
  let rec go i =
    if i + n <= String.length s && String.sub s i n = needle then (Buffer.add_string b by; go (i + n))
    else if i < String.length s then (Buffer.add_char b s.[i]; go (i + 1))
  in
  go 0;
  Buffer.contents b

let labelled_shape =
  Alcotest.test_case "a labelled step renames exactly the names that carried the synthesised one" `Quick
    (fun () ->
       let mods = generated (wrap stream_labelled) in
       let rename = List.map (replace_all ~needle:"Msg_Prod_Cons_1" ~by:"Item") in
       Alcotest.(check (list string)) "modules" [ "Stream_Msg"; "Stream_Prod"; "Stream_Cons"; "Stream_Run" ]
         (List.map fst mods);
       Alcotest.(check (list string)) "Stream_Prod" (rename stream_prod_fns) (List.assoc "Stream_Prod" mods);
       Alcotest.(check (list string)) "Stream_Cons" (rename stream_cons_fns) (List.assoc "Stream_Cons" mods);
       List.iter
         (fun (m, f) -> Alcotest.(check bool) (m ^ "." ^ f) true (has_fn mods m f))
         [ ("Stream_Prod", "send_Item"); ("Stream_Cons", "recv_Item"); ("Stream_Cons", "recv_Item_or");
           ("Stream_Cons", "await_Item"); ("Stream_Cons", "leave_recv_Item") ])

(** The fingerprint keys on the constructor, so labelling a step changes it:
    two nodes built before and after the rename refuse each other. *)
let label_changes_fingerprint =
  Alcotest.test_case "labelling a step changes the protocol's fingerprint" `Quick
    (fun () ->
       let fingerprint src =
         let m = parse_module (wrap src) in
         let steps =
           List.find_map (function DProtocol (_, pd, _) -> Some pd.proto_steps | _ -> None) m.mod_decls
           |> Option.get
         in
         let errors = March_errors.Errors.create () in
         let open March_desugar.Desugar_endpoints in
         let annotated = Option.get (annotate errors ~proto:"Stream" ~span:dummy_span steps) in
         fingerprint_of ~proto:"Stream" (roles_of annotated) annotated
       in
       Alcotest.(check bool) "differs" true (fingerprint stream <> fingerprint stream_labelled);
       Alcotest.(check string) "stable" (fingerprint stream) (fingerprint stream))

let labelled_roles_ok = ok "both roles written against the labelled names typecheck" (wrap (stream_labelled ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.S_send_Item, next : Int) : Stream_Prod.Yield do
    let st1 = Stream_Prod.send_Item(s, st, next)
    Stream_Prod.offer_more_done(s, st1,
      fn (_b, st2) -> prod(s, st2, next + 1),
      fn (_b, st2) -> Stream_Prod.close(s, st2))
  end
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.S_recv_Item, budget : Int) : Stream_Cons.Yield do
    Stream_Cons.recv_Item(s, st, fn (_n, st1) ->
      if budget > 1 do
        cons(s, Stream_Cons.choose_more(s, st1, true), budget - 1)
      else
        Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true))
      end)
  end
|}))

(** [bad_desugar name needle src]: like [bad], for an error the GENERATOR
    reports at desugar time -- [typecheck_with_stdlib] discards those (see
    Test_helpers.desugar_has_errors). *)
let bad_desugar name needle src =
  Alcotest.test_case name `Quick (fun () ->
      let errors = March_errors.Errors.create () in
      ignore (without_runner (fun () -> March_desugar.Desugar.desugar_module ~errors (parse_module src)));
      let msgs = error_messages errors in
      let contains m =
        let n = String.length needle in
        let rec go i = i + n <= String.length m && (String.sub m i n = needle || go (i + 1)) in
        go 0
      in
      Alcotest.(check bool)
        (name ^ ": an error mentions " ^ needle ^ " (got: " ^ String.concat " | " msgs ^ ")")
        true (List.exists contains msgs))

let label_on_branch_head = bad_desugar "a label on a choose branch's head message is refused: the branch label names it"
    "already names this message" (wrap {|
  @[endpoints]
  protocol P do
    choose by A:
      go -> item: A -> B : Int
      no -> A -> B : Bool
    end
  end
|})

let label_msg_prefix = bad_desugar "a label spelling a synthesised Msg_ name is refused"
    "could collide" (wrap {|
  @[endpoints]
  protocol P do
    msg_A_B_1: A -> B : Int
    B -> A : Bool
  end
|})

(* One name on two steps: allowed when the payloads agree and no single role
   takes both (one `Ping(Int)` constructor; A sends one and receives the
   other, B and C each take one). *)
let shared_label_ok = ok "two steps may share a label when their payloads agree and no role takes both" (wrap {|
  @[endpoints]
  protocol P do
    ping: A -> B : Int
    ping: C -> A : Int
  end
  pfn a(s : Cap(Session.Live), st : P_A.S_send_Ping) : P_A.Yield do
    let st1 = P_A.send_Ping(s, st, 1)
    P_A.recv_Ping(s, st1, fn (_n, st2) -> P_A.close(s, st2))
  end
  pfn b(s : Cap(Session.Live), st : P_B.S_recv_Ping) : P_B.Yield do
    P_B.recv_Ping(s, st, fn (_n, st1) -> P_B.close(s, st1))
  end
  pfn c(s : Cap(Session.Live), st : P_C.S_send_Ping) : P_C.Yield do
    P_C.close(s, P_C.send_Ping(s, st, 2))
  end
|})

let shared_label_two_payloads = bad_desugar "a shared label with two payload types is the existing label error"
    "used for two messages with different payload" (wrap {|
  @[endpoints]
  protocol P do
    ping: A -> B : Int
    ping: C -> A : String
  end
|})

(* Before this check the role module defined `send_Ping` twice and the second
   silently shadowed the first; two branch heads with one label across two
   `choose`s did the same. *)
let shared_label_one_role = bad_desugar "one role taking two steps of one name is refused, not silently shadowed"
    "would define `send_Ping` twice" (wrap {|
  @[endpoints]
  protocol P do
    ping: A -> B : Int
    ping: A -> C : Int
    C -> A : Bool
  end
|})

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

(* A payload type declared in the module without `derive Json`: the generated
   codec assumes every nested type has one, so this used to pass `--check`,
   fail the compile with codegen's "ambiguous interface-method call", and
   panic the interpreter at the first `encode`. The generator checks up
   front now, names the step and the type, and still generates the modules
   (so no cascade of "Unknown module"). *)
let payload_no_codec = bad_desugar "a payload type without derive Json is refused up front" "has no JSON codec"
  (wrap {|
  type Thing = { x : Int }
  @[endpoints]
  protocol P do
    A -> B : Thing
    B -> A : Int
  end
|})

(* A variant, not a record, for the reason payload_declared_later gives. *)
let payload_with_codec = ok "a payload type with derive Json is fine" (wrap {|
  type Thing = Mark(Int)
  derive Json for Thing
  @[endpoints]
  protocol P do
    A -> B : Thing
    B -> A : List(Thing)
  end
|})

let payload_nested_no_codec = bad_desugar "a payload type nested in a List still needs its codec" "has no JSON codec"
  (wrap {|
  type Thing = { x : Int }
  @[endpoints]
  protocol P do
    A -> B : List(Thing)
    B -> A : Int
  end
|})

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
    let s = Session.attach(c, { register: fn (_a, r) -> r, emit: fn (e, _t, _m) -> e, suspend: fn (e, _f, _h) -> e, close: fn _e -> (), fail: fn (_e, w) -> panic(w), on_cancel: fn (e, _h) -> e, leave: fn (_e, _w) -> () })
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

(* ── the event API: session state in actor state ───────────────────────
   specs/todos/2026-09-13-endpoints-event-api-actor-state.md.  The rejects
   are the record move-out rules (PR #442) applied to the `parked` field; the
   corpus twins are reject/t236-t238 and accept/t239. *)

let cons_actor body = wrap (stream ^ {|
  actor ConsActor do
    state { budget : Int, parked : Stream_Cons.Parked_Cons }
    init  { budget: 2, parked: Stream_Cons.idle() }
|} ^ body ^ {|
  end
|})

let event_ok = ok "an actor holding a Parked endpoint in its state, resuming and re-parking every turn" (cons_actor {|
    on StartC(s : Cap(Session.Live)) do
      Stream_Cons.take_idle(state.parked)
      { state with parked: Stream_Cons.await_Msg_Prod_Cons_1(s, Stream_Cons.register(s, 0)) }
    end
    on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Stream_Cons.resume(state.parked, from, msg, ep) do
        Got_Msg_Prod_Cons_1(_n, st) ->
          if state.budget > 1 do
            { state with budget: state.budget - 1,
                         parked: Stream_Cons.await_Msg_Prod_Cons_1(s, Stream_Cons.choose_more(s, st, true)) }
          else
            { state with parked: Stream_Cons.finish(s, Stream_Cons.choose_done(s, st, true)) }
          end
      end
    end
|})

let event_retained = bad "resuming and then keeping the consumed Parked in the update" "`state.parked` is used more than once" (cons_actor {|
    on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Stream_Cons.resume(state.parked, from, msg, ep) do
        Got_Msg_Prod_Cons_1(n, st) ->
          let _ = Stream_Cons.finish(s, Stream_Cons.choose_done(s, st, true))
          { state with budget: state.budget - n }
      end
    end
|})

let event_not_reparked = bad "resuming and returning the state unchanged" "`state.parked` is used more than once" (cons_actor {|
    on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Stream_Cons.resume(state.parked, from, msg, ep) do
        Got_Msg_Prod_Cons_1(_n, st) ->
          let _ = Stream_Cons.finish(s, Stream_Cons.choose_done(s, st, true))
          state
      end
    end
|})

let event_idle_dropped = bad "a Start that parks without consuming the Idle placeholder" "`state.parked` was never used" (cons_actor {|
    on StartC(s : Cap(Session.Live)) do
      { budget: 2, parked: Stream_Cons.await_Msg_Prod_Cons_1(s, Stream_Cons.register(s, 0)) }
    end
|})

(* `Pid(a)`'s parameter is phantom to the linearity check (typecheck.ml,
   [consumed_var_ids]): a pid of an actor whose state holds a `Parked` can be
   handed to a generic function.  Before that rule, `tag`'s call was refused
   ("is linear, but `tag` is generic in a parameter of that type"), which is
   what made the generated `<P>_Run.host_<Role>(…, host : Pid(a), …)`
   uncallable from exactly the actors it exists for. *)
let event_pid_handle = ok "a pid of an actor holding a Parked can be passed to a generic function" (wrap (stream ^ {|
  actor ConsActor do
    state { budget : Int, parked : Stream_Cons.Parked_Cons }
    init  { budget: 2, parked: Stream_Cons.idle() }
    on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Stream_Cons.resume(state.parked, from, msg, ep) do
        Got_Msg_Prod_Cons_1(_n, st) -> { state with parked: Stream_Cons.finish(s, Stream_Cons.choose_done(s, st, true)) }
      end
    end
  end
  fn tag(p : Pid(a)) : Int do pid_to_int(p) end
  fn tag_cons(p : Pid({ budget : Int, parked : Stream_Cons.Parked_Cons })) : Int do tag(p) end
|}))

(* A builtin given fewer arguments than it takes is an arity error, like a
   module function: `monitor(target)` used to typecheck as a `Pid(a) -> Int`
   VALUE (a partial application March does not have) that `let _ =` then
   discarded, so no monitor was ever set and no Down ever came. *)
(* ── failure handlers (specs/todos/2026-09-18-choreography-failure-handling.md)
   A cancel handler gets the role, the cause and an unforgeable
   [Cancelled_<Role>] token, and no session state: it cannot communicate in
   the failed session (Maty's `end -> end` failure callback).  These pin
   that from both sides. *)

let cancel_handler_ok = ok "a cancel handler that records the failure and ends the endpoint" (wrap (stream ^ {|
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.S_recv_Msg_Prod_Cons_1) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1_or(s, st,
      fn (_n, st1) -> Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true)),
      fn (_role, _cause, c) -> Stream_Cons.cancelled(s, c))
  end
|}))

(* The state a receive consumed is gone for its cancel handler too: reusing
   it there is the linearity error it is anywhere else.  If this were
   accepted, a handler could keep talking in the failed session. *)
let cancel_handler_reuses_state = bad "a cancel handler cannot use the state its receive consumed"
    "`st` is used more than once" (wrap (stream ^ {|
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.S_recv_Msg_Prod_Cons_1) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1_or(s, st,
      fn (_n, st1) -> Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true)),
      fn (_role, _cause, _c) -> Stream_Cons.close(s, Stream_Cons.choose_done(s, st, true)))
  end
|}))

let cancel_handler_must_end = bad "a cancel handler must end the endpoint: it has to return Yield"
    "Yield" (wrap (stream ^ {|
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.S_recv_Msg_Prod_Cons_1) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1_or(s, st,
      fn (_n, st1) -> Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true)),
      fn (_role, _cause, _c) -> ())
  end
|}))

let cancelled_forge = bad "a Cancelled token cannot be forged: its constructor takes the private Secret"
    "Stream_Cons.Secret" (wrap (stream ^ {|
  pfn early(s : Cap(Session.Live)) : Stream_Cons.Yield do
    Stream_Cons.cancelled(s, Stream_Cons.Cancelled_Cons(Stream_Cons.Secret))
  end
|}))

let hosted_cancel_ok = ok "a hosted actor stores the Closed value `cancel` returns" (cons_actor {|
    on CancelC() do
      { state with parked: Stream_Cons.cancel(state.parked) }
    end
|})

let hosted_cancel_retained = bad "a hosted actor cannot cancel its Parked value and keep it too"
    "`state.parked` is used more than once" (cons_actor {|
    on CancelC() do
      let _closed = Stream_Cons.cancel(state.parked)
      state
    end
|})

let builtin_under_application = bad "a builtin given fewer arguments than it takes is an error, not a silent partial application"
    "Function `monitor` expects 2 arguments, but got 1" (wrap {|
  actor W do
    state { n : Int }
    init { n: 0 }
    on Watch(target : Pid({ n : Int })) do
      let _r = monitor(target)
      state
    end
  end
|})

let event_forge = bad "a Parked cannot be forged: its constructors take the private Secret" "Stream_Cons.Secret" (cons_actor {|
    on StartC(s : Cap(Session.Live)) do
      Stream_Cons.take_idle(state.parked)
      { state with parked: Stream_Cons.Awaiting_S_recv_Msg_Prod_Cons_1(7, Stream_Cons.Secret) }
    end
|})

(* ── through the real driver ──────────────────────────────────────────
   These need the CLI: the stdlib as `march` loads it (the bare `Pid` is then
   the Global_pid RECORD, which is what made `Pid(a)` an arity error), and the
   driver's diagnostic filter, which until 2026-09-13 dropped every diagnostic
   raised inside generated code.  Exe-relative like test_cap_ceiling. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let check_cli src_text =
  if not (Sys.file_exists compiler_exe) then Alcotest.failf "compiler not found at %s" compiler_exe;
  let src = Filename.temp_file "endpoints_cli" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  let out = Filename.temp_file "endpoints_cli" ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "%s --check %s > %s 2>&1" (Filename.quote compiler_exe) (Filename.quote src) (Filename.quote out))
  in
  let ic = open_in out in
  let text = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ src; out ];
  (rc, text)

let contains_text hay needle =
  let n = String.length needle in
  let rec go i = i + n <= String.length hay && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let cli_pid_one_arg =
  Alcotest.test_case "CLI: `p : Pid(state)` is accepted; a monitor program has no hidden error" `Quick (fun () ->
      let rc, out = check_cli {|mod Main do
  needs IO.Console
  actor W do
    state { n : Int }
    init { n: 0 }
    on Poke() do panic("bang") end
  end
  actor Watcher do
    state { seen : Int }
    init { seen: 0 }
    on Watch(target : Pid({ n : Int })) do
      let _r = monitor(self, target)
      match receive() do
        Down.Down(_ref, _t, DownReason.Crash(_m)) -> { state with seen: state.seen + 1 }
        _ -> state
      end
    end
  end
  fn main(c : Cap(IO.Console)) do
    let w = spawn(W)
    let v = spawn(Watcher)
    send(v, Watch(w))
    send(w, Poke())
    run_until_idle()
  end
end
|} in
      Alcotest.(check int) ("exit code (output: " ^ out ^ ")") 0 rc;
      Alcotest.(check bool) "no arity error" false (contains_text out "expects 0 type argument"))

let cli_no_unreachable_catch_all =
  Alcotest.test_case "CLI: a fully covered message type gets no unreachable catch-all arm" `Quick (fun () ->
      (* ONE message: the receiving state's single arm covers the whole
         message type, so a catch-all after it can never be reached. *)
      let rc, out = check_cli (wrap {|
  @[endpoints]
  protocol Ping do
    A -> B : Int
  end
|}) in
      Alcotest.(check int) "exit code" 0 rc;
      Alcotest.(check bool) ("no unreachable-arm warning (output: " ^ out ^ ")") false
        (contains_text out "never be reached"))

let cli_derive_eq_single_ctor =
  Alcotest.test_case "CLI: derive Eq on a single-constructor type emits no unreachable arm" `Quick (fun () ->
      let rc, out = check_cli {|mod Main do
  needs IO.Console
  type V = V(Int, Int)
  derive Eq for V
  fn main(c : Cap(IO.Console)) do println(if V(1, 2) == V(1, 2) do "eq" else "ne" end) end
end
|} in
      Alcotest.(check int) "exit code" 0 rc;
      Alcotest.(check bool) ("no unreachable-arm warning (output: " ^ out ^ ")") false
        (contains_text out "never be reached"))

let tests =
  [ stream_shape; cli_pid_one_arg; cli_no_unreachable_catch_all; cli_derive_eq_single_ctor; relay_shape; no_attr_no_generation; bad_branch_head; same_label_two_payloads;
    unlabelled_names_pinned; labelled_shape; label_changes_fingerprint; labelled_roles_ok;
    label_on_branch_head; label_msg_prefix; shared_label_ok; shared_label_two_payloads; shared_label_one_role;
    prod_ok; wrong_order; replayed; abandoned; callback_forge; relay_ok; payload_declared_later;
    payload_no_codec; payload_with_codec; payload_nested_no_codec;
    event_ok; event_retained; event_not_reparked; event_idle_dropped; event_forge; event_pid_handle; builtin_under_application;
    cancel_handler_ok; cancel_handler_reuses_state; cancel_handler_must_end; cancelled_forge;
    hosted_cancel_ok; hosted_cancel_retained ]
