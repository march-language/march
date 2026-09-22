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

(* The generated code calls `Session.*`, `Json.*` and `Bytes.*`, so those
   stdlib modules are prepended to the guarantee tests, the way the CLI
   prepends the stdlib -- with `String`, which `Session.crash_cause` reads the
   crash marker with, and which `Bytes` and `Json` already need.  Between them
   they reference no module outside this list.  Without them every accept case
   fails on an unknown module and every reject case passes for the wrong
   reason. *)
let stdlib = lazy
  [ load_stdlib_file_for_test "bytes.march";
    load_stdlib_file_for_test "string.march";
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
           ("Stream_Prod", "idle"); ("Stream_Prod", "take_idle"); ("Stream_Prod", "take_closed");
           ("Stream_Prod", "await_more_done");
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
    "idle"; "take_idle"; "take_closed"; "cancel"; "await_more_done"; "finish"; "resume" ]

let stream_cons_fns =
  [ "register"; "cancelled"; "leave_recv_Msg_Prod_Cons_1"; "recv_Msg_Prod_Cons_1";
    "recv_Msg_Prod_Cons_1_or"; "leave_choose_more_done"; "choose_more"; "choose_done"; "close";
    "idle"; "take_idle"; "take_closed"; "cancel"; "await_Msg_Prod_Cons_1"; "finish"; "resume" ]

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

(** The fingerprint of the FIRST `@[endpoints]` protocol in [src], digested
    the way [expand] does it: payload types expanded against the module's own
    type declarations. *)
let fingerprint_of_src ?(proto = "Stream") src =
  let m = parse_module (wrap src) in
  let steps =
    List.find_map (function DProtocol (_, pd, _) -> Some pd.proto_steps | _ -> None) m.mod_decls
    |> Option.get
  in
  let errors = March_errors.Errors.create () in
  let open March_desugar.Desugar_endpoints in
  let annotated = Option.get (annotate errors ~proto ~span:dummy_span steps) in
  fingerprint_of ~proto ~types:(ty_defs_of m.mod_decls) (roles_of annotated) annotated

(** The fingerprint keys on the constructor, so labelling a step changes it:
    two nodes built before and after the rename refuse each other. *)
let label_changes_fingerprint =
  Alcotest.test_case "labelling a step changes the protocol's fingerprint" `Quick
    (fun () ->
       let fingerprint = fingerprint_of_src in
       Alcotest.(check bool) "differs" true (fingerprint stream <> fingerprint stream_labelled);
       Alcotest.(check string) "stable" (fingerprint stream) (fingerprint stream))

(* ── the fingerprint digests what a payload type is MADE OF ─────────────── *)

(* A protocol whose payload is a user type declared alongside it, in four
   versions that differ ONLY below the type's name.  Before
   [2026-09-21-protocol-fingerprint-payload-definitions], all four digested
   to the same `Thing`, so two nodes built from different ones accepted each
   other and the skew surfaced mid-session as an undecodable message. *)
let payload_proto body = {|
  derive Json for Thing
  |} ^ body ^ {|
  @[endpoints]
  protocol Pay do
    A -> B : Thing
    stop
  end
|}

let thing_int    = payload_proto "type Thing = { x : Int }"
let thing_string = payload_proto "type Thing = { x : String }"
let thing_swapped = payload_proto "type Thing = { y : String, x : Int }"
let thing_two    = payload_proto "type Thing = { x : Int, y : String }"
let thing_variant = payload_proto "type Thing = One | Two(Int)"
let thing_variant2 = payload_proto "type Thing = One | Two(String)"

let fp_pay src = fingerprint_of_src ~proto:"Pay" src

let payload_definition_in_fingerprint =
  Alcotest.test_case "a payload type's DEFINITION is part of the fingerprint" `Quick
    (fun () ->
       Alcotest.(check string) "stable" (fp_pay thing_int) (fp_pay thing_int);
       Alcotest.(check bool) "{x:Int} vs {x:String}" true (fp_pay thing_int <> fp_pay thing_string);
       Alcotest.(check bool) "one field vs two" true (fp_pay thing_int <> fp_pay thing_two);
       Alcotest.(check bool) "a variant's payload type" true
         (fp_pay thing_variant <> fp_pay thing_variant2);
       Alcotest.(check bool) "a variant is not a record" true
         (fp_pay thing_variant <> fp_pay thing_int))

(* Field ORDER is part of it: `derive Json` writes the fields in declaration
   order, so a reordering is a wire change even though the type is the same. *)
let payload_field_order_in_fingerprint =
  Alcotest.test_case "reordering a record payload's fields changes the fingerprint" `Quick
    (fun () -> Alcotest.(check bool) "differs" true (fp_pay thing_two <> fp_pay thing_swapped))

(* Hazard 1: a recursive payload type must terminate through a
   back-reference, not expand for ever.  A protocol carrying a tree is
   ordinary, so reaching this test at all is most of the assertion. *)
let recursive_payload_terminates =
  Alcotest.test_case "a recursive payload type terminates (and still digests its shape)" `Quick
    (fun () ->
       let tree a = payload_proto ("type Thing = Leaf | Node(Thing, Thing, " ^ a ^ ")") in
       Alcotest.(check string) "stable" (fp_pay (tree "Int")) (fp_pay (tree "Int"));
       Alcotest.(check bool) "the non-recursive field still counts" true
         (fp_pay (tree "Int") <> fp_pay (tree "String")))

(* A parameterised type's arguments are positional and substituted, not
   spelled: `Box(Int)` and `Box(String)` are different payloads. *)
let payload_type_arguments_substituted =
  Alcotest.test_case "a parameterised payload's arguments are substituted" `Quick
    (fun () ->
       let boxed a = {|
  derive Json for Box
  type Box(a) = { inner : a }
  @[endpoints]
  protocol Pay do
    A -> B : Box(|} ^ a ^ {|)
    stop
  end
|}
       in
       Alcotest.(check bool) "Box(Int) vs Box(String)" true
         (fingerprint_of_src ~proto:"Pay" (boxed "Int") <> fingerprint_of_src ~proto:"Pay" (boxed "String")))

(* Hazard 2: a payload type from ANOTHER module is out of reach at desugar
   time.  It must fall back without crashing, and VISIBLY -- the digest
   records that the definition was not available -- rather than silently to
   the name-only key this change exists to remove. *)
let imported_payload_falls_back =
  Alcotest.test_case "an imported payload type falls back to a marked name-only key" `Quick
    (fun () ->
       let src = {|
  @[endpoints]
  protocol Pay do
    A -> B : Elsewhere.Thing
    stop
  end
|}
       in
       Alcotest.(check string) "stable" (fingerprint_of_src ~proto:"Pay" src) (fingerprint_of_src ~proto:"Pay" src);
       let open March_desugar.Desugar_endpoints in
       Alcotest.(check string) "marked extern" "extern:Elsewhere.Thing"
         (ty_key_deep ~types:[] (TyCon (March_ast.Ast.{ txt = "Elsewhere.Thing"; span = dummy_span }, [])));
       (* A builtin is NOT marked: both nodes agree on what `Int` is. *)
       Alcotest.(check string) "a builtin is plain" "Int"
         (ty_key_deep ~types:[] (TyCon (March_ast.Ast.{ txt = "Int"; span = dummy_span }, []))))

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

(* ── `Entry`: the alias for a role's first state ────────────────────────── *)

(** The right-hand side of a generated module's [Entry] alias, if it has one. *)
let entry_alias mods_src m =
  let md = parse_and_desugar mods_src in
  let decls =
    List.find_map (function DMod (name, _, decls, _) when name.txt = m -> Some decls | _ -> None) md.mod_decls
  in
  match decls with
  | None -> None
  | Some decls ->
    List.find_map
      (function
        | DType (_, name, [], TDAlias (TyCon (rhs, [])), _) when name.txt = "Entry" -> Some rhs.txt
        | _ -> None)
      decls

let entry_alias_shape =
  Alcotest.test_case "each role module aliases `Entry` to that role's FIRST state" `Quick
    (fun () ->
       Alcotest.(check (option string)) "Stream_Prod.Entry" (Some "S_send_Msg_Prod_Cons_1")
         (entry_alias (wrap stream) "Stream_Prod");
       Alcotest.(check (option string)) "Stream_Cons.Entry" (Some "S_recv_Msg_Prod_Cons_1")
         (entry_alias (wrap stream) "Stream_Cons");
       (* A role whose first step is a receive from a third party: the alias
          follows the projection, not the protocol's first line. *)
       Alcotest.(check (option string)) "Relay_Logger.Entry" (Some "S_recv_Msg_Server_Logger_1")
         (entry_alias (wrap relay) "Relay_Logger");
       (* `Entry` is not a state name: states are all `S_`-prefixed, so the
          alias cannot shadow one. *)
       Alcotest.(check bool) "no generated fn is called Entry" false
         (has_fn (generated (wrap stream)) "Stream_Prod" "Entry"))

(** A protocol whose ROLE is literally named `Entry`: role names appear only as
    a suffix (`Gate_Entry`, `Parked_Entry`, `Cancelled_Entry`), so the alias
    named `Entry` inside `Gate_Entry` collides with nothing. *)
let role_named_entry = {|
  @[endpoints]
  protocol Gate do
    Entry -> Exit : Int
    Exit -> Entry : Bool
  end
|}

let role_named_entry_shape =
  Alcotest.test_case "a role named `Entry` still gets its own `Entry` alias, with no collision" `Quick
    (fun () ->
       Alcotest.(check (option string)) "Gate_Entry.Entry" (Some "S_send_Msg_Entry_Exit_1")
         (entry_alias (wrap role_named_entry) "Gate_Entry");
       Alcotest.(check (option string)) "Gate_Exit.Entry" (Some "S_recv_Msg_Entry_Exit_1")
         (entry_alias (wrap role_named_entry) "Gate_Exit"))

let role_named_entry_ok =
  ok "a role named `Entry` writes its body against `Gate_Entry.Entry`" (wrap (role_named_entry ^ {|
  pfn ent(s : Cap(Session.Live), st : Gate_Entry.Entry) : Gate_Entry.Yield do
    let st1 = Gate_Entry.send_Msg_Entry_Exit_1(s, st, 1)
    Gate_Entry.recv_Msg_Exit_Entry_1(s, st1, fn (_b, st2) -> Gate_Entry.close(s, st2))
  end
|}))

(* ── alias cycles ─────────────────────────────────────────────────────── *)

(** [surface_ty] expands a transparent alias by resolving its right-hand side,
    so an alias defined in terms of itself would recurse forever.  No source
    syntax builds an alias (the parser reads `type A = B` as a one-constructor
    variant), so these build the [TDAlias] declarations directly and put them in
    front of a module that mentions them.  A module's aliases are registered
    under their qualified name only, so every mention is spelled `Main.X`.  Without the cycle guard the reject
    cases hang the suite instead of failing. *)
let with_aliases aliases body =
  let m = parse_and_desugar ("mod Main do\n" ^ body ^ "\nend\n") in
  let alias (name, rhs) =
    DType (Public, { txt = name; span = dummy_span }, [],
           TDAlias (TyCon ({ txt = "Main." ^ rhs; span = dummy_span }, [])), dummy_span)
  in
  let m = { m with mod_decls = List.map alias aliases @ m.mod_decls } in
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  error_messages errors

let alias_user = "  fn f(x : (Main.A, Main.A)) : Int do 0 end"

let alias_cycles =
  Alcotest.test_case "a cyclic alias is an error, not a hang" `Quick (fun () ->
      Alcotest.(check (list string)) "type A = A"
        [ "`Main.A` is defined in terms of itself (`Main.A` -> `Main.A`)." ]
        (List.sort_uniq compare (with_aliases [ ("A", "A") ] alias_user));
      Alcotest.(check (list string)) "type A = B / type B = A"
        [ "`Main.A` is defined in terms of itself (`Main.A` -> `Main.B` -> `Main.A`)." ]
        (List.sort_uniq compare (with_aliases [ ("A", "B"); ("B", "A") ] alias_user));
      (* Not a false positive: a chain of aliases, and the same alias twice
         side by side in one type, are no cycle. *)
      Alcotest.(check (list string)) "type A = B / type B = Int" []
        (with_aliases [ ("A", "B"); ("B", "C") ]
           (alias_user ^ "\n  type C = C(Int)")))

let entry_roles_ok = ok "both roles written against `Entry` typecheck" (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.Entry, next : Int) : Stream_Prod.Yield do
    let st1 = Stream_Prod.send_Msg_Prod_Cons_1(s, st, next)
    Stream_Prod.offer_more_done(s, st1,
      fn (_b, st2) -> prod(s, st2, next + 1),
      fn (_b, st2) -> Stream_Prod.close(s, st2))
  end
  pfn cons(s : Cap(Session.Live), st : Stream_Cons.Entry, budget : Int) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1(s, st, fn (_n, st1) ->
      if budget > 1 do
        cons(s, Stream_Cons.choose_more(s, st1, true), budget - 1)
      else
        Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true))
      end)
  end
|}))

(** The alias is transparent, so it is the other role's state that a body
    annotated with the wrong role's `Entry` is measured against -- `Entry`
    does not become one nominal type shared by every role. *)
let entry_wrong_role =
  bad "a body annotated with the OTHER role's `Entry` is rejected" "S_send_Msg_Prod_Cons_1"
    (wrap (stream ^ {|
  pfn cons(s : Cap(Session.Live), st : Stream_Prod.Entry, budget : Int) : Stream_Cons.Yield do
    Stream_Cons.recv_Msg_Prod_Cons_1(s, st, fn (_n, st1) ->
      if budget > 1 do
        cons(s, Stream_Cons.choose_more(s, st1, true), budget - 1)
      else
        Stream_Cons.close(s, Stream_Cons.choose_done(s, st1, true))
      end)
  end
|}))

(** The state type is `always_linear`; the alias must not launder that away. *)
let entry_keeps_linearity =
  bad "a state reached through `Entry` is still linear" "used more than once"
    (wrap (stream ^ {|
  pfn prod(s : Cap(Session.Live), st : Stream_Prod.Entry, next : Int) : Stream_Prod.Yield do
    let st1 = Stream_Prod.send_Msg_Prod_Cons_1(s, st, next)
    let _st2 = Stream_Prod.send_Msg_Prod_Cons_1(s, st, next)
    Stream_Prod.offer_more_done(s, st1,
      fn (_b, st2) -> prod(s, st2, next + 1),
      fn (_b, st2) -> Stream_Prod.close(s, st2))
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
    let s = Session.attach(c, { register: fn (_a, r) -> r, emit: fn (e, _t, _m) -> e, suspend: fn (e, _f, _h) -> e, close: fn _e -> (), fail: fn (_e, w) -> panic(w), on_cancel: fn (e, _h) -> e, leave: fn (_e, _w) -> (), on_crash: fn (e, _r, _h) -> e })
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

let event_take_closed = ok "an actor retiring a finished session with the generated take_closed" (cons_actor {|
    on DeliverC(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Stream_Cons.resume(state.parked, from, msg, ep) do
        Got_Msg_Prod_Cons_1(_n, st) ->
          Stream_Cons.take_closed(Stream_Cons.finish(s, Stream_Cons.choose_done(s, st, true)))
          { state with budget: 0, parked: Stream_Cons.idle() }
      end
    end
|})

(* The hole `take_closed` closes: a still-parked endpoint is not retirable.
   The panic is at run time, so what the checker can show here is that the
   call type-checks only against a `Parked`, and that the value it consumes
   cannot be used again. *)
let event_take_closed_consumes = bad "retiring a parked endpoint and then re-parking the same value" "`state.parked` is used more than once" (cons_actor {|
    on DeliverC(_s : Cap(Session.Live), _from : Int, _msg : Bytes, _ep : Int) do
      Stream_Cons.take_closed(state.parked)
      { state with budget: state.budget - 1 }
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

(* ── crash branches (design Part B, 2026-09-20) ───────────────────────────
   The ECOOP logging protocol: C may crash, I detects it at `C -> I`, L is
   told by I's message.  Shape: the detector's receive takes the crash
   callback, the third party offers over the detector's two messages, the
   crashed role's module has no trace of the branch, and every role module
   carries `Crashed_<Role>`.  Then the six well-formedness rules, and the
   `choose` form of a crash branch. *)
let logging = {|
  @[endpoints]
  protocol Logging do
    may crash C
    L -> I : Int
    C -> I : String
      or crash do
        I -> L : String
      end
    I -> L : String
    L -> I : Bool
    I -> C : Bool
  end
|}

let crash_shape =
  Alcotest.test_case "Logging: the detector's recv takes a crash callback; the third party offers; the crashed role has no branch" `Quick
    (fun () ->
       let mods = generated (wrap logging) in
       Alcotest.(check (list string)) "modules"
         [ "Logging_Msg"; "Logging_L"; "Logging_I"; "Logging_C"; "Logging_Run" ] (List.map fst mods);
       List.iter
         (fun (m, f, expect) -> Alcotest.(check bool) (m ^ "." ^ f) expect (has_fn mods m f))
         [ ("Logging_I", "recv_Msg_C_I_1", true);
           ("Logging_I", "recv_Msg_C_I_1_or", false);          (* no cancel form: the sender may crash *)
           ("Logging_I", "send_Msg_I_L_1", true);              (* the crash branch's send *)
           ("Logging_I", "send_Msg_I_L_2", true);
           ("Logging_I", "leave_recv_Msg_C_I_1", true);
           ("Logging_L", "offer_Msg_I_L_2_Msg_I_L_1", true);   (* told apart by I's messages *)
           ("Logging_L", "recv_Msg_I_L_2", false);
           ("Logging_C", "send_Msg_C_I_1", true);
           ("Logging_C", "recv_Msg_I_C_1", true);
           ("Logging_C", "recv_Msg_I_L_1", false) ];
       (* the detector's receive: (s, st, k, on_crash), with `Crashed_I` *)
       let m = parse_and_desugar (wrap logging) in
       let arity =
         List.find_map
           (function
             | DMod (name, _, decls, _) when name.txt = "Logging_I" ->
               List.find_map
                 (function
                   | DFn (fd, _) when fd.fn_name.txt = "recv_Msg_C_I_1" ->
                     Some (List.length (List.hd fd.fn_clauses).fc_params)
                   | _ -> None)
                 decls
             | _ -> None)
           m.mod_decls
       in
       Alcotest.(check (option int)) "recv_Msg_C_I_1 arity" (Some 4) arity;
       let has_type mname tname =
         List.exists
           (function
             | DMod (name, _, decls, _) when name.txt = mname ->
               List.exists (function DType (_, t, _, _, _) | DAlwaysLinearType (_, t, _, _, _) -> t.txt = tname | _ -> false) decls
             | _ -> false)
           m.mod_decls
       in
       Alcotest.(check bool) "Logging_I.Crashed_I" true (has_type "Logging_I" "Crashed_I");
       Alcotest.(check bool) "Logging_I.S_recv_Msg_C_I_1" true (has_type "Logging_I" "S_recv_Msg_C_I_1");
       Alcotest.(check bool) "Logging_I.S_send_Msg_I_L_1 (the crash branch's first state)" true
         (has_type "Logging_I" "S_send_Msg_I_L_1");
       Alcotest.(check bool) "Logging_L.S_offer_Msg_I_L_2_Msg_I_L_1" true (has_type "Logging_L" "S_offer_Msg_I_L_2_Msg_I_L_1"))

let crash_roles_ok = ok "all three roles of Logging typecheck against the generated API" (wrap (logging ^ {|
  pfn role_l(s : Cap(Session.Live), st : Logging_L.S_send_Msg_L_I_1) : Logging_L.Yield do
    let st1 = Logging_L.send_Msg_L_I_1(s, st, 1)
    Logging_L.offer_Msg_I_L_2_Msg_I_L_1(s, st1,
      fn (_read, st2) -> Logging_L.close(s, Logging_L.send_Msg_L_I_2(s, st2, true)),
      fn (_fatal, st2) -> Logging_L.close(s, st2))
  end
  pfn role_i(s : Cap(Session.Live), st : Logging_I.S_recv_Msg_L_I_1) : Logging_I.Yield do
    Logging_I.recv_Msg_L_I_1(s, st, fn (_t, st1) ->
      Logging_I.recv_Msg_C_I_1(s, st1,
        fn (read, st2) ->
          Logging_I.recv_Msg_L_I_2(s, Logging_I.send_Msg_I_L_2(s, st2, read), fn (r, st4) ->
            Logging_I.close(s, Logging_I.send_Msg_I_C_1(s, st4, r))),
        fn (crashed, st2) ->
          Logging_I.close(s, Logging_I.send_Msg_I_L_1(s, st2, crashed.cause ++ int_to_string(crashed.role)))))
  end
  pfn role_c(s : Cap(Session.Live), st : Logging_C.S_send_Msg_C_I_1) : Logging_C.Yield do
    Logging_C.recv_Msg_I_C_1(s, Logging_C.send_Msg_C_I_1(s, st, "x"), fn (_r, st2) -> Logging_C.close(s, st2))
  end
|}))

(* The crash callback's state is the crash branch's, not the normal one's:
   sending the normal `Read` to L from it is a type error. *)
let crash_state_is_the_branch = bad "the crash callback cannot take the normal continuation's step"
    "expected `S_send_Msg_I_L_2` but got `S_send_Msg_I_L_1`" (wrap (logging ^ {|
  pfn role_i(s : Cap(Session.Live), st : Logging_I.S_recv_Msg_C_I_1) : Logging_I.Yield do
    Logging_I.recv_Msg_C_I_1(s, st,
      fn (read, st2) -> Logging_I.recv_Msg_L_I_2(s, Logging_I.send_Msg_I_L_2(s, st2, read), fn (r, st4) ->
                          Logging_I.close(s, Logging_I.send_Msg_I_C_1(s, st4, r))),
      fn (_crashed, st2) -> Logging_I.close(s, Logging_I.send_Msg_I_L_2(s, st2, "no")))
  end
|}))

let crash_rule name needle proto = bad name needle (wrap proto)

let crash_rule_1 = crash_rule "rule 1: a receive from a may-crash role needs a crash branch" "needs `or crash do ... end`" {|
  @[endpoints]
  protocol P do
    may crash C
    L -> I : Int
    C -> I : String
    I -> L : String
  end
|}

let crash_rule_2 = crash_rule "rule 2: a crash branch is only for a may-crash sender" "is not declared `may crash`" {|
  @[endpoints]
  protocol P do
    may crash C
    L -> I : Int
      or crash do
        I -> C : Bool
      end
    C -> I : String
      or crash do
        I -> L : String
      end
    I -> L : String
  end
|}

let crash_rule_3 = crash_rule "rule 3: the crashed role is not in its own crash branch" "has crashed, so it cannot take part" {|
  @[endpoints]
  protocol P do
    may crash C
    L -> I : Int
    C -> I : String
      or crash do
        I -> C : Bool
      end
    I -> L : String
  end
|}

let crash_rule_4 = crash_rule "rule 4: a third party is told by the detector in both continuations" "cannot tell whether `C` crashed" {|
  @[endpoints]
  protocol P do
    may crash C
    L -> I : Int
    C -> I : String
      or crash do
        L -> I : Bool
      end
    I -> L : String
    L -> I : Bool
  end
|}

let crash_rule_5 = crash_rule "rule 5: a choose with a crash branch has one detector" "every other branch must begin with a message to the same role" {|
  @[endpoints]
  protocol P do
    may crash C
    L -> I : Int
    choose by C:
      read -> C -> I : String
              I -> L : String
      done -> C -> L : Bool
      crash -> I -> L : String
    end
  end
|}

let crash_rule_6 = crash_rule "rule 6: may crash names a role of the protocol, once" "names a role that is not in the protocol" {|
  @[endpoints]
  protocol P do
    may crash D
    L -> I : Int
    I -> L : String
  end
|}

let crash_rule_6_twice = crash_rule "rule 6: may crash lists a role once" "lists `C` twice" {|
  @[endpoints]
  protocol P do
    may crash C, C
    C -> I : Int
      or crash do
        I -> L : String
      end
    I -> L : String
  end
|}

(* A `choose by C` with a `crash` branch: I detects, `offer_read_done_crash`
   takes one callback per label and the crash callback; L is told by I's
   messages in every branch. *)
let crash_choose = {|
  @[endpoints]
  protocol Q do
    may crash C
    L -> I : Int
    choose by C:
      read -> C -> I : String
              I -> L : String
      done -> C -> I : Bool
              I -> L : Bool
      crash -> I -> L : Int
    end
  end
|}

let crash_choose_shape =
  Alcotest.test_case "a choose with a crash branch: the detector offers over the labels and crash" `Quick
    (fun () ->
       let mods = generated (wrap crash_choose) in
       List.iter
         (fun (m, f, expect) -> Alcotest.(check bool) (m ^ "." ^ f) expect (has_fn mods m f))
         [ ("Q_I", "offer_read_done_crash", true);
           ("Q_I", "offer_read_done", false);
           ("Q_C", "choose_read", true); ("Q_C", "choose_done", true); ("Q_C", "choose_crash", false);
           ("Q_L", "offer_Msg_I_L_1_Msg_I_L_2_Msg_I_L_3", true) ])

let crash_choose_ok = ok "the detector of a choose with a crash branch, written against the generated API" (wrap (crash_choose ^ {|
  pfn role_i(s : Cap(Session.Live), st : Q_I.S_recv_Msg_L_I_1) : Q_I.Yield do
    Q_I.recv_Msg_L_I_1(s, st, fn (_t, st1) ->
      Q_I.offer_read_done_crash(s, st1,
        fn (r, st2) -> Q_I.close(s, Q_I.send_Msg_I_L_1(s, st2, r)),
        fn (d, st2) -> Q_I.close(s, Q_I.send_Msg_I_L_2(s, st2, d)),
        fn (crashed, st2) -> Q_I.close(s, Q_I.send_Msg_I_L_3(s, st2, crashed.role))))
  end
|}))

(* ── crash branches reaching an ACTOR-HOSTED role (phase B2) ──────────────
   A role hosted in an actor takes its crash branch through the event API:
   `await_<Msg>` of a state with a crash branch installs a crash continuation
   too, the transport forwards the crash on the delivery route, and `resume`
   hands back `Crashed_<Msg>(Crashed_<Role>, S_<branch's first state>)`
   instead of `Got_<Msg>`.  End to end: test/two_node/crash_hosted. *)

(** The constructors of [tname] in module [mname], in order. *)
let variant_ctors src mname tname =
  let m = parse_and_desugar src in
  List.find_map
    (function
      | DMod (name, _, decls, _) when name.txt = mname ->
        List.find_map
          (function
            | DType (_, t, _, TDVariant vs, _) | DAlwaysLinearType (_, t, _, TDVariant vs, _) when t.txt = tname ->
              Some (List.map (fun v -> v.var_name.txt) vs)
            | _ -> None)
          decls
      | _ -> None)
    m.mod_decls

let crash_hosted_shape =
  Alcotest.test_case "Logging: the hosted detector awaits the crash receive and its event API carries Crashed_" `Quick
    (fun () ->
       let src = wrap logging in
       let mods = generated src in
       List.iter
         (fun (m, f, expect) -> Alcotest.(check bool) (m ^ "." ^ f) expect (has_fn mods m f))
         [ ("Logging_I", "await_Msg_L_I_1", true);
           ("Logging_I", "await_Msg_C_I_1", true);     (* the receive with the crash branch *)
           ("Logging_I", "resume", true);
           ("Logging_L", "await_Msg_I_L_2_Msg_I_L_1", true) ];
       (* the detector's events: one `Got_` per message it receives, and the
          crash of C with the branch's first state *)
       Alcotest.(check (option (list string))) "Received_I"
         (Some [ "Got_Msg_L_I_1"; "Got_Msg_C_I_1"; "Got_Msg_L_I_2"; "Crashed_Msg_C_I_1" ])
         (variant_ctors src "Logging_I" "Received_I");
       (* L hears about the crash as one of I's messages: no crash event *)
       Alcotest.(check (option (list string))) "Received_L"
         (Some [ "Got_Msg_I_L_2"; "Got_Msg_I_L_1" ]) (variant_ctors src "Logging_L" "Received_L"))

let crash_choose_hosted_shape =
  Alcotest.test_case "a choose with a crash branch: the hosted detector's await and event carry the labels" `Quick
    (fun () ->
       let src = wrap crash_choose in
       Alcotest.(check bool) "Q_I.await_read_done_crash" true (has_fn (generated src) "Q_I" "await_read_done_crash");
       Alcotest.(check (option (list string))) "Received_I"
         (Some [ "Got_Msg_L_I_1"; "Got_Read"; "Got_Done"; "Crashed_read_done_crash" ])
         (variant_ctors src "Q_I" "Received_I"))

(* The guarantee: an actor that holds I's endpoint takes every step from its
   own handler, the crash branch included, with `state` in scope. *)
let crash_hosted_ok = ok "an actor hosting the detector takes the crash branch from its resume handler"
  (wrap (logging ^ {|
  actor IActor do
    state { parked : Logging_I.Parked_I }
    init  { parked: Logging_I.idle() }
    on StartI(s : Cap(Session.Live)) do
      Logging_I.take_idle(state.parked)
      { state with parked: Logging_I.await_Msg_L_I_1(s, Logging_I.register(s, 0)) }
    end
    on DeliverI(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Logging_I.resume(state.parked, from, msg, ep) do
        Got_Msg_L_I_1(_trigger, st) ->
          { state with parked: Logging_I.await_Msg_C_I_1(s, st) }
        Got_Msg_C_I_1(read, st) ->
          { state with parked: Logging_I.await_Msg_L_I_2(s, Logging_I.send_Msg_I_L_2(s, st, read)) }
        Got_Msg_L_I_2(report, st) ->
          { state with parked: Logging_I.finish(s, Logging_I.send_Msg_I_C_1(s, st, report)) }
        Crashed_Msg_C_I_1(crashed, st) ->
          { state with parked: Logging_I.finish(s, Logging_I.send_Msg_I_L_1(s, st, crashed.cause ++ int_to_string(crashed.role))) }
      end
    end
  end
|}))

(* The crash event's state is the BRANCH's, as the callback's is: the normal
   continuation's step does not typecheck against it. *)
let crash_hosted_state_is_the_branch =
  bad "the crash event's state cannot take the normal continuation's step" "S_send_Msg_I_L_2"
    (wrap (logging ^ {|
  actor IActor do
    state { parked : Logging_I.Parked_I }
    init  { parked: Logging_I.idle() }
    on DeliverI(s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do
      match Logging_I.resume(state.parked, from, msg, ep) do
        Got_Msg_L_I_1(_trigger, st) ->
          { state with parked: Logging_I.await_Msg_C_I_1(s, st) }
        Got_Msg_C_I_1(read, st) ->
          { state with parked: Logging_I.await_Msg_L_I_2(s, Logging_I.send_Msg_I_L_2(s, st, read)) }
        Got_Msg_L_I_2(report, st) ->
          { state with parked: Logging_I.finish(s, Logging_I.send_Msg_I_C_1(s, st, report)) }
        Crashed_Msg_C_I_1(_crashed, st) ->
          { state with parked: Logging_I.finish(s, Logging_I.send_Msg_I_L_2(s, st, "no")) }
      end
    end
  end
|}))

(* The `Chan` API does not run crash branches: the typecheck-side projection
   refuses such a protocol rather than project it without them. *)
let crash_chan_refused = bad "Chan(Role, Proto) refuses a protocol with crash branches" "only supported with `@[endpoints]`" (wrap (logging ^ {|
  pfn as_chan(ch : Chan(L, Logging)) : Int do 0 end
|}))


(* ── two protocols in one module ───────────────────────────────────────── *)

(** The type names each generated nested module declares. *)
let generated_types src : (string * string list) list =
  let m = parse_and_desugar src in
  List.filter_map
    (function
      | DMod (name, _, decls, _) ->
        let tys =
          List.filter_map
            (function
              | DType (_, nm, _, _, _) | DAlwaysLinearType (_, nm, _, _, _) -> Some nm.txt
              | _ -> None)
            decls
        in
        Some (name.txt, tys)
      | _ -> None)
    m.mod_decls

(* The message type is named after its PROTOCOL, not a bare `Msg`.  Impl
   dispatch for the derived `Json` codec keys on the type's SHORT name in both
   backends, so two protocols in one module each declaring a `Msg` made the
   first protocol's sends encode through the second's `to_json`: a match
   failure inside generated code interpreted, and a refused build compiled
   ("ambiguous interface-method call to `JsonFrom$Msg.from_json`").  This is
   the generator-side pin; the runtime one is test/session/in_process.march.
   See the record dated 2026-09-22 under specs/progress/. *)
let msg_type_named_after_protocol =
  Alcotest.test_case "the message type is <P>_Message, not a bare Msg" `Quick
    (fun () ->
       let tys = generated_types (wrap stream) in
       let msg_tys = match List.assoc_opt "Stream_Msg" tys with Some t -> t | None -> [] in
       Alcotest.(check bool) "Stream_Msg declares Stream_Message" true
         (List.mem "Stream_Message" msg_tys);
       Alcotest.(check bool) "Stream_Msg declares no bare `Msg`" false (List.mem "Msg" msg_tys))

let two_protocols = {|
  @[endpoints]
  protocol Other do
    A -> B : Int
    B -> A : String
  end
|}

(* Two protocols in one module generate two DISTINCT message types, so their
   derived codecs cannot collide. *)
let two_protocols_distinct_msg_types =
  Alcotest.test_case "two protocols in one module: distinct message type names" `Quick
    (fun () ->
       let tys = generated_types (wrap (stream ^ two_protocols)) in
       let get m = match List.assoc_opt m tys with Some t -> t | None -> [] in
       Alcotest.(check bool) "Stream_Msg.Stream_Message" true (List.mem "Stream_Message" (get "Stream_Msg"));
       Alcotest.(check bool) "Other_Msg.Other_Message" true (List.mem "Other_Message" (get "Other_Msg"));
       Alcotest.(check bool) "no shared short name" true
         (not (List.exists (fun t -> List.mem t (get "Other_Msg")) (get "Stream_Msg"))))

(* And the pair typechecks: both codecs' `derive Json` coexist. *)
let two_protocols_ok =
  ok "two protocols in one module typecheck together" (wrap (stream ^ two_protocols))

(* ── `role R needs ...`: per-role grants (distributed-deploys step 4) ──── *)

(* [stream] with a grant line per role.  The grant is a claim about the
   role's CODE (checked by [check_role_grants]), not about the wire, so the
   fingerprint must not see it: two nodes built with different grants still
   talk. *)
let stream_granted = {|
  @[endpoints]
  protocol Stream do
    role Prod needs IO.Console
    role Cons needs IO.Console, IO.FileWrite
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

let stream_granted_other = replace_all ~needle:"IO.Console, IO.FileWrite" ~by:"IO.NetConnect" stream_granted

let grants_not_in_fingerprint =
  Alcotest.test_case "two protocols differing only in `role ... needs` fingerprint alike" `Quick
    (fun () ->
       let fp = fingerprint_of_src in
       Alcotest.(check string) "no grants vs grants" (fp stream) (fp stream_granted);
       Alcotest.(check string) "one grant vs another" (fp stream_granted) (fp stream_granted_other))

let role_needs_ok = ok "a protocol with a grant line per role typechecks" (wrap stream_granted)

(* `role` is a soft keyword: the identifier stays available. *)
let role_identifier_ok = ok "`role` is still an ordinary identifier outside a protocol" (wrap {|
  fn pick(role : Int) : Int do
    let role2 = role
    role2
  end
|})

let role_needs_unknown_cap = bad "a grant naming an unknown capability gets `needs`' did-you-mean"
    "`IO.Consol` is not a known capability" (wrap (replace_all ~needle:"role Prod needs IO.Console" ~by:"role Prod needs IO.Consol" stream_granted))

let role_needs_unknown_role = bad "a grant for a role not in the protocol is refused"
    "names a role that is not in the protocol" (wrap (replace_all ~needle:"role Prod needs" ~by:"role Nobody needs" stream_granted))

let role_needs_twice = bad "two grant lines for one role are refused"
    "is declared twice" (wrap (replace_all ~needle:"role Cons needs" ~by:"role Prod needs" stream_granted))

let role_needs_after_message = bad "a grant line after the first message step is refused"
    "must come before the protocol's first message step" (wrap {|
  @[endpoints]
  protocol Stream do
    Prod -> Cons : Int
    role Cons needs IO.Console
    Cons -> Prod : Bool
  end
|})

let role_needs_nested = bad "a grant line inside a loop is refused"
    "must be a top-level step" (wrap {|
  @[endpoints]
  protocol Stream do
    loop do
      role Cons needs IO.Console
      Prod -> Cons : Int
      choose by Cons:
        more -> Cons -> Prod : Bool
        done -> Cons -> Prod : Bool
                stop
      end
    end
  end
|})

let tests =
  [ stream_shape;
    grants_not_in_fingerprint; role_needs_ok; role_identifier_ok; role_needs_unknown_cap;
    role_needs_unknown_role; role_needs_twice; role_needs_after_message; role_needs_nested; msg_type_named_after_protocol; two_protocols_distinct_msg_types; two_protocols_ok;
    cli_pid_one_arg; cli_no_unreachable_catch_all; cli_derive_eq_single_ctor; relay_shape; no_attr_no_generation; bad_branch_head; same_label_two_payloads;
    unlabelled_names_pinned; labelled_shape; label_changes_fingerprint; labelled_roles_ok;
    payload_definition_in_fingerprint; payload_field_order_in_fingerprint;
    recursive_payload_terminates; payload_type_arguments_substituted; imported_payload_falls_back;
    entry_alias_shape; alias_cycles; entry_roles_ok; entry_wrong_role; entry_keeps_linearity;
    role_named_entry_shape; role_named_entry_ok;
    label_on_branch_head; label_msg_prefix; shared_label_ok; shared_label_two_payloads; shared_label_one_role;
    prod_ok; wrong_order; replayed; abandoned; callback_forge; relay_ok; payload_declared_later;
    payload_no_codec; payload_with_codec; payload_nested_no_codec;
    event_ok; event_take_closed; event_take_closed_consumes; event_retained; event_not_reparked; event_idle_dropped; event_forge; event_pid_handle; builtin_under_application;
    cancel_handler_ok; cancel_handler_reuses_state; cancel_handler_must_end; cancelled_forge;
    hosted_cancel_ok; hosted_cancel_retained;
    crash_shape; crash_roles_ok; crash_state_is_the_branch;
    crash_rule_1; crash_rule_2; crash_rule_3; crash_rule_4; crash_rule_5; crash_rule_6; crash_rule_6_twice;
    crash_choose_shape; crash_choose_ok; crash_chan_refused;
    crash_hosted_shape; crash_choose_hosted_shape; crash_hosted_ok; crash_hosted_state_is_the_branch ]
