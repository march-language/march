(* `needs` as a hard ceiling (lib/caps/cap_ceiling.ml + --cap-strict).

   The unit tests pin the rule; the end-to-end tests pin the ROUTES, which is
   the part that actually matters — the source-level checks this replaces were
   measured to disagree with each other about which routes they cover. *)

module C = March_caps.Cap_ceiling

let violations_pp = Alcotest.list Alcotest.string
let describe l = List.map C.describe l

let test_covered_by_exact_declaration () =
  Alcotest.check violations_pp "no violation" []
    (describe
       (C.check
          ~module_caps:[ ("M", [ "IO.FileRead" ]) ]
          ~attribution:[ ("IO.FileRead", "M") ]
          ~caps:[ "IO.FileRead" ]))

let test_covered_by_a_broader_declaration () =
  (* The ceiling is a lattice test, not string equality: IO.FileSystem
     subsumes IO.FileRead, so declaring the parent covers the child. *)
  Alcotest.check violations_pp "parent covers child" []
    (describe
       (C.check
          ~module_caps:[ ("M", [ "IO.FileSystem" ]) ]
          ~attribution:[ ("IO.FileRead", "M") ]
          ~caps:[ "IO.FileRead" ]))

let test_narrower_declaration_does_not_cover () =
  (* And not the other way around — declaring IO.FileRead must NOT license a
     write.  Getting the subsumption direction backwards here would make the
     ceiling admit strictly more than it claims. *)
  Alcotest.(check int) "one violation" 1
    (List.length
       (C.check
          ~module_caps:[ ("M", [ "IO.FileRead" ]) ]
          ~attribution:[ ("IO.FileWrite", "M") ]
          ~caps:[ "IO.FileWrite" ]))

let test_undeclared_module_is_a_violation () =
  Alcotest.(check int) "module with no needs at all" 1
    (List.length
       (C.check ~module_caps:[] ~attribution:[ ("IO.FileRead", "M") ]
          ~caps:[ "IO.FileRead" ]))

let test_each_module_is_judged_on_its_own_needs () =
  (* The whole point: A's declaration must not license B's use.  A check that
     unioned the program's needs would pass this and report nothing, which is
     exactly the whole-program-union blindness this replaces. *)
  let vs =
    C.check
      ~module_caps:[ ("A", [ "IO.FileRead" ]); ("B", [ "IO.Console" ]) ]
      ~attribution:[ ("IO.FileRead", "A"); ("IO.FileRead", "B") ]
      ~caps:[ "IO.FileRead" ]
  in
  Alcotest.(check int) "only B violates" 1 (List.length vs);
  Alcotest.(check bool) "and B is named" true
    (List.exists
       (fun v ->
         match v with C.Undeclared { owner; _ } -> owner = "B" | _ -> false)
       vs)

let test_unattributed_capability_fails_closed () =
  (* A capability nobody can be held responsible for must NOT certify.  It is
     precisely the one an attacker would route through. *)
  Alcotest.(check int) "unattributed is a violation" 1
    (List.length
       (C.check ~module_caps:[] ~attribution:[] ~caps:[ "IO.FileRead" ]))

let test_foreign_is_excluded () =
  (* IO.Foreign comes from the presence of extern blocks, not an attributed
     call site, so it has no owner by construction; Typecheck's Check 5
     already errors when an extern's cap is undeclared.  Treating it as
     unattributed would fire on every FFI-using program. *)
  Alcotest.check violations_pp "no violation for foreign" []
    (describe
       (C.check ~module_caps:[] ~attribution:[]
          ~caps:[ "IO.Foreign"; "IO.Foreign.Blocking" ]))

let unit_tests =
  [
    Alcotest.test_case "exact declaration covers" `Quick
      test_covered_by_exact_declaration;
    Alcotest.test_case "broader declaration covers" `Quick
      test_covered_by_a_broader_declaration;
    Alcotest.test_case "narrower declaration does NOT cover" `Quick
      test_narrower_declaration_does_not_cover;
    Alcotest.test_case "module with no needs violates" `Quick
      test_undeclared_module_is_a_violation;
    Alcotest.test_case "each module judged on its own needs" `Quick
      test_each_module_is_judged_on_its_own_needs;
    Alcotest.test_case "unattributed fails closed" `Quick
      test_unattributed_capability_fails_closed;
    Alcotest.test_case "IO.Foreign excluded" `Quick test_foreign_is_excluded;
  ]

(* ── End to end: --cap-strict over each ROUTE to a capability ───────────
   Exe-relative for the same reason as test_cap_strip.ml. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let compile_with ~flags src_text =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let src = Filename.temp_file "cap_ceiling" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  let out = Filename.temp_file "cap_ceiling" ".out" in
  let bin = Filename.temp_file "cap_ceiling" ".bin" in
  let rc =
    Sys.command
      (Printf.sprintf "%s %s --compile -o %s %s > %s 2>&1"
         (Filename.quote compiler_exe) flags (Filename.quote bin)
         (Filename.quote src) (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ src; out; bin ];
  (rc, s)

(* DEFAULT flags, deliberately: the ceiling is on by default since 2026-08-07,
   and these tests assert the behavior a user gets without asking for
   anything.  [--cap-strict] is still accepted (a no-op spelling of the
   default); [test_no_cap_strict_opts_out] covers the opt-out. *)
let compile_strict src_text = compile_with ~flags:"" src_text

let rejects name src =
  let rc, out = compile_strict src in
  if rc = 0 then
    Alcotest.failf "%s should have failed --cap-strict but compiled" name;
  if
    not
      (let re = Str.regexp_string "CAPABILITY CEILING" in
       match Str.search_forward re out 0 with
       | _ -> true
       | exception Not_found -> false)
  then Alcotest.failf "%s failed, but not for the ceiling reason:\n%s" name out

(* ── Severity flip, 2026-08-06 ────────────────────────────────────────────
   A DIRECT builtin call in a module body is now a typecheck ERROR, so
   compilation stops before --cap-strict's ceiling pass ever runs.  Those
   routes are therefore caught EARLIER than they used to be, and the ceiling
   never sees them.

   The tests below are re-pointed rather than deleted.  They still assert the
   property that matters — the program is rejected — and they now record WHERE.
   Deleting them would have removed the only regression guard on routes that
   used to be the ceiling's job.

   The ceiling remains load-bearing for the route typecheck CANNOT see: a
   stdlib-mediated call (`File.write(...)` rather than `file_write(...)`),
   which is [test_stdlib_route_was_completely_silent] below and which still
   passes through [rejects] unchanged.  That asymmetry is the point — measured
   2026-08-06, a stdlib-mediated call is still silent under plain `--check`. *)
let rejects_at_typecheck name ~expect src =
  let rc, out = compile_strict src in
  if rc = 0 then
    Alcotest.failf "%s should have been rejected but compiled" name;
  match Str.search_forward (Str.regexp_string expect) out 0 with
  | _ -> ()
  | exception Not_found ->
    Alcotest.failf
      "%s: rejected, but not with the expected typecheck reason %S:\n%s"
      name expect out

let accepts name src =
  let rc, out = compile_strict src in
  if rc <> 0 then Alcotest.failf "%s should compile but did not:\n%s" name out

(* Like [rejects], but pins the TEXT of the ceiling violation.  Needed for the
   nesting cases below: what was wrong there was the module NAME the ceiling
   reported, so a test that only checks "some ceiling violation fired" would
   pass on the buggy spelling too. *)
let rejects_naming name ~expect src =
  let rc, out = compile_strict src in
  if rc = 0 then
    Alcotest.failf "%s should have failed --cap-strict but compiled" name;
  match Str.search_forward (Str.regexp_string expect) out 0 with
  | _ -> ()
  | exception Not_found ->
    Alcotest.failf "%s: expected %S in the output, got:\n%s" name expect out

(* Route 1: a direct builtin call.  Warning-only without --cap-strict. *)
let test_direct_builtin_route () =
  rejects_at_typecheck "direct builtin call"
    ~expect:"declares no matching `needs`"
    {|
mod CeilDirect do
  needs IO.Console
  fn main() : () do
    match file_write("/tmp/x", "d") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

(* Route 2: through a stdlib wrapper.  THE hole this closes — measured, this
   produced NO diagnostic at all before, not even a warning, because
   Typecheck's Check 4 walks `use` declarations and stdlib modules are
   ambiently available without one. *)
let test_stdlib_route_was_completely_silent () =
  rejects "stdlib-mediated call"
    {|
mod CeilStdlib do
  needs IO.Console
  needs IO.FileWrite
  mod Inner do
    needs IO.Console
    fn go() : () do
      match File.write("/tmp/x", "d") do
        Ok(_)  -> println("ok")
        Err(_) -> println("e")
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    Inner.go()
  end
end
|}

(* Route 3: a builtin handed out as a VALUE and invoked indirectly. *)
let test_builtin_as_value_route () =
  rejects "builtin passed as a value"
    {|
mod CeilValue do
  needs IO.Console
  needs IO.FileRead
  mod Inner do
    needs IO.Console
    fn apply1(f : (String) -> a, p : String) : a do
      f(p)
    end
    fn go() : () do
      match apply1(file_read, "/etc/hosts") do
        Ok(_)  -> println("ok")
        Err(_) -> println("e")
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : () do
    Inner.go()
  end
end
|}

(* A DEPENDENCY exceeding its own ceiling, in a program whose entry module is
   itself clean.  This is the supply-chain case, and the reason the check is
   per-module: the whole-program union cannot see it, and the dependency never
   opted in to anything. *)
let test_dependency_exceeding_its_own_ceiling () =
  rejects_at_typecheck "dependency exceeds its declared needs"
    ~expect:"declares no matching `needs`"
    {|
mod CeilApp do
  needs IO.Console
  needs IO.FileRead
  mod Dep do
    needs IO.Console
    fn greet(n : String) : String do
      match file_read("/etc/passwd") do
        Ok(s)  -> s
        Err(_) -> "hello " ++ n
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : () do
    println(Dep.greet("world"))
  end
end
|}

let test_a_correctly_declared_program_compiles () =
  (* The check must be satisfiable.  A test suite of only REJECT cases cannot
     tell a working ceiling from one that rejects everything. *)
  accepts "fully declared program"
    {|
mod CeilOkay do
  needs IO.Console
  needs IO.FileWrite
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    match File.write("/tmp/x", "d") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

let test_parent_declaration_satisfies_the_ceiling () =
  accepts "IO.FileSystem covers a write"
    {|
mod CeilParent do
  needs IO.Console
  needs IO.FileSystem
  fn main(_cap_console : Cap(IO.Console), _cap_filesystem : Cap(IO.FileSystem)) : () do
    match File.write("/tmp/x", "d") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

(* A module nested TWO levels deep that declares exactly what it uses.  This
   was reported as "uses IO.FileWrite but does not declare needs IO.FileWrite"
   even though it plainly declared it: [module_caps] keyed the needs by the
   module's BARE name while TIR attribution names the owner by its qualified
   path, so `Innocent.DeeplyNested` never found its own declaration (and, being
   recorded inside an enclosing DMod's scope, was dropped at that boundary
   before the ceiling ever ran).  At depth 1 the two spellings coincide — hence
   a test at depth >= 2, where they do not. *)
let test_doubly_nested_module_declaring_its_own_needs () =
  accepts "doubly-nested module with its own needs"
    {|
mod CeilDeepOkay do
  needs IO.Console
  needs IO.FileWrite
  mod Innocent do
    mod DeeplyNested do
      needs IO.FileWrite
      fn write_it(data : String) : Bool do
        match file_write("/tmp/ceil_deep_ok", data) do
          Ok(_)  -> true
          Err(_) -> false
        end
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    if Innocent.DeeplyNested.write_it("d") do println("ok") else println("no") end
  end
end
|}

(* And the same shape WITHOUT the declaration must still be caught — reported
   under the qualified name, so the fix above did not buy silence by simply
   dropping deep modules from the ceiling. *)
let test_doubly_nested_module_without_needs_is_still_caught () =
  rejects_at_typecheck "doubly-nested module missing needs"
    ~expect:"declares no matching `needs`"
    {|
mod CeilDeepBad do
  needs IO.Console
  mod Innocent do
    mod DeeplyNested do
      fn write_it(data : String) : Bool do
        match file_write("/tmp/ceil_deep_bad", data) do
          Ok(_)  -> true
          Err(_) -> false
        end
      end
    end
  end
  fn main() : () do
    if Innocent.DeeplyNested.write_it("d") do println("ok") else println("no") end
  end
end
|}

(* A program that uses NO capability at all must compile under --cap-strict.
   It did not: `own_caps_of_this_module` was handed the module AFTER the stdlib
   prepend, so the prelude's own top-level `println`/`debug` counted as
   functions "this file declares" and their IO.Console was credited to the user's
   module — present in the used set, owned by nobody, reported as
   "cannot be attributed to any module".  Every accept test in this file happens
   to call println, which is what hid it: the capability was attributed as soon
   as the program's own code used it. *)
let test_a_program_using_no_capability_compiles () =
  accepts "capability-free program"
    {|
mod CeilNoCaps do
  fn main() : () do
    ()
  end
end
|}

(* The guard on that filter: dropping the prelude's declarations from the OWN
   set must not stop a real console use from being seen.  `println` here is the
   user's own call, so it is attributed to `CeilConsoleUndeclared` and must be
   reported against its (absent) `needs`. *)
let test_console_use_without_needs_is_still_caught () =
  rejects_at_typecheck "undeclared console use"
    ~expect:"declares no matching `needs`"
    {|
mod CeilConsoleUndeclared do
  fn main() : () do
    println("hi")
  end
end
|}

(* ── A module with no entry point must not be charged for the whole stdlib ──

   Measured 2026-08-07, before the fix: this file — which uses no capability
   at all — produced SEVENTEEN ceiling violations, every one of them naming a
   stdlib module (`Check` uses IO.Clock, `Socket` uses IO.NetConnect, `Process`
   uses IO.Process, …).

   The cause is not in the ceiling. [Dce.root_names] fails OPEN: with no
   `main`, no setup/migrate, no exports and no tests, a module has no roots,
   and rather than prune everything it keeps everything. That is the right call
   for DCE — deleting a library's entire body would be absurd — but the ceiling
   reads the pruned TIR to decide what the program USES, so an unpruned stdlib
   made every stdlib module's capability look reachable. Attribution then found
   no non-transparent caller for any of them and named the stdlib module, which
   is [responsible_owners]' documented fallback behaving correctly on input
   that should never have reached it.

   This is the single largest source of ceiling false positives: of 110 failing
   programs in a 312-program sweep, 86 had no `main`.

   The fix supplies the ceiling its own roots (the functions this FILE
   declares) and turns the fail-open off for it alone; codegen's DCE is
   untouched. Two properties have to survive, and each has a test below:

   - A main-less module is NOT capability-free. Its own functions are its API
     surface, so a capability they reach is still charged
     ([..._still_charged_for_its_own_use]). Without this, "prune harder" would
     pass by checking nothing.
   - The roots cannot be recovered from TIR NAMES. [Lower] strips the entry
     module's prefix from its own declarations and the prelude's functions
     (`println`, `panic`, …) are unprefixed too, so "no dot" selects both —
     measured, rooting every unprefixed function charged the entry module
     IO.Console, IO.FileWrite and IO.NetConnect for a file whose only
     declaration was `fn helper(x) = x + 1`. The roots come from the desugared
     AST, where a span still says which file a declaration came from. That is
     what the first test would catch if someone "simplified" it back. *)
let test_no_main_module_is_not_charged_for_the_stdlib () =
  accepts "main-less module using no capability"
    {|
mod CeilNoMain do
  fn helper(x : Int) : Int do
    x + 1
  end
end
|}

let test_no_main_module_still_charged_for_its_own_use () =
  rejects_naming "main-less module using a capability"
    ~expect:"does not declare `needs IO.FileWrite`"
    {|
mod CeilNoMainUses do
  needs IO.Console
  fn save(p : String, d : String) : () do
    match File.write(p, d) do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

(* The degenerate end of the same case: a file with NO declarations at all,
   only a `test` block. `--compile` does not compile test bodies into the
   binary, so it has no roots by any route — not even the file's own
   functions, because it has none. It used to draw the same 17 stdlib
   violations. Reporting nothing is the honest answer for a binary that runs
   no user code; the capability use inside a test body is checked when tests
   are actually built, where [tm_tests] roots them. *)
let test_test_only_file_reports_nothing () =
  accepts "file containing only a test block"
    {|
mod CeilTestOnly do

test "trivial" do
  assert true
end

end
|}

(* ── Default flip, 2026-08-07 ─────────────────────────────────────────────
   The ceiling is the DEFAULT.  Three spellings, three tests:

   - no flag: enforced (every [rejects]-family test above already runs with no
     flag, so the whole file is the witness);
   - [--cap-strict]: still accepted, same behavior — kept so scripts written
     against the opt-in era don't break, and so intent can be stated
     explicitly;
   - [--no-cap-strict]: the opt-out, which must actually disable the check —
     the program below is the stdlib-mediated route the severity flip cannot
     see, so if the opt-out silently stopped working, nothing else in the
     suite would notice. *)
let undeclared_stdlib_write_src =
  {|
mod CeilOptOut do
  needs IO.Console
  needs IO.FileWrite
  mod Inner do
    needs IO.Console
    fn go() : () do
      match File.write("/tmp/cap_ceiling_optout", "d") do
        Ok(_)  -> println("ok")
        Err(_) -> println("e")
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    Inner.go()
  end
end
|}

let test_explicit_cap_strict_still_accepted () =
  let rc, out = compile_with ~flags:"--cap-strict" undeclared_stdlib_write_src in
  if rc = 0 then
    Alcotest.failf "--cap-strict should still enforce the ceiling:\n%s" out

let test_no_cap_strict_opts_out () =
  let rc, out =
    compile_with ~flags:"--no-cap-strict" undeclared_stdlib_write_src
  in
  if rc <> 0 then
    Alcotest.failf "--no-cap-strict should disable the ceiling:\n%s" out

(* ── Actor handlers declared in a NESTED module ─────────────────────────────

   A handler's synthesized TIR fn name is BARE (`Weeble_Zorp`: actor short
   name + `_` + message name) — the HCR manifest format asserts that spelling,
   and `spawn(Weeble)` emits `_Weeble_spawn` from the short name, so the name
   itself cannot be qualified. [Cap_attrib.attribute]'s [owner_of] resolves an
   unprefixed name to the ENTRY module, so a `println` inside a handler
   declared in `Inner` was charged to `Outer`, and `Inner`'s own
   `needs IO.Console` could not satisfy the ceiling
   (specs/todos/2026-08-08-actor-handler-attribution-charges-entry-module.md).

   The fix is a side table ([Handler_owner]) recording each synthesized
   handler name's declaring module at lowering time, consulted before the
   entry fallback.  Both directions are pinned: the declaring module's `needs`
   must satisfy the ceiling (first test — RED before the fix), and a nested
   module WITHOUT the declaration must be named as the violator itself, not
   the entry module (second test — the half that keeps "attribute handlers to
   the entry module and let its needs cover them" from passing). *)
let test_nested_actor_handler_satisfied_by_declaring_module () =
  accepts "nested actor handler covered by Inner's needs"
    {|
mod CeilActorOuter do
  mod Inner do
    needs IO.Console
    actor Weeble do
      state { count : Int }
      init { count: 0 }
      on Zorp(msg : String) do
        println(msg)
        state
      end
    end
    fn run_it() do
      let pid = spawn(Weeble)
      send(pid, Zorp("hi"))
    end
  end
  fn main() do
    Inner.run_it()
  end
end
|}

(* Caught at TYPECHECK, not the ceiling: the handler's `println` is a direct
   builtin call, so Check 1b's body scan (which folds actor handler bodies in)
   rejects it before compilation reaches the ceiling — and names `Inner`,
   which is the property this test pins.  Same re-pointing the severity flip
   applied to the other direct routes; the ceiling half of the fix is
   witnessed by the ACCEPT test above, where the declaration must satisfy
   attribution or the build fails on `CeilActorOuter`. *)
let test_nested_actor_handler_violation_names_inner () =
  rejects_at_typecheck "nested actor handler without needs blames Inner"
    ~expect:"`Inner` declares no matching `needs`"
    {|
mod CeilActorOuter2 do
  mod Inner do
    actor Weeble do
      state { count : Int }
      init { count: 0 }
      on Zorp(msg : String) do
        println(msg)
        state
      end
    end
    fn run_it() do
      let pid = spawn(Weeble)
      send(pid, Zorp("hi"))
    end
  end
  fn main() do
    Inner.run_it()
  end
end
|}

(* ── Impl methods ───────────────────────────────────────────────────────────

   An impl method's TIR name is the iface mangling `Save$Thing.persist`, so
   name-derived ownership produced the SYNTHETIC owner `Save$Thing` — a
   "module" no `needs` line can ever declare for, making a correctly-declared
   program unfixably rejected:

     module `Save$Thing` uses `IO.FileWrite` but does not declare ...

   Found 2026-08-08 while closing the belongs-filter gap
   (2026-08-06-cap-sandbox-belongs-filter-misses-non-dfn-keys.md) — the same
   key-shape blindness, but where the sandbox side merely UNDER-GRANTED
   (denial at runtime), the ceiling side REJECTS, and the ceiling is on by
   default.  The owner of `[Prefix.]Iface$Ty.method` is `Prefix` — the module
   that declared the impl — never the mangled segment. *)
let test_impl_method_covered_by_declaring_module () =
  accepts "impl method covered by the entry module's needs"
    {|
mod CeilImpl do
  needs IO.Console
  needs IO.FileWrite
  type Thing = Thing(Int)
  interface Save(a) do
    fn persist : a -> Unit
  end
  impl Save(Thing) do
    fn persist(_t) do
      match file_write("/tmp/ceil_impl_out", "d") do
        Ok(_) -> ()
        Err(_) -> ()
      end
    end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) do
    persist(Thing(1))
    println("done")
  end
end
|}

let tests =
  unit_tests
  @ [
      Alcotest.test_case "impl method covered by declaring module" `Slow
        test_impl_method_covered_by_declaring_module;
      Alcotest.test_case "nested actor handler covered by declaring module" `Slow
        test_nested_actor_handler_satisfied_by_declaring_module;
      Alcotest.test_case "nested actor handler violation names Inner" `Slow
        test_nested_actor_handler_violation_names_inner;
      Alcotest.test_case "--cap-strict still accepted" `Slow
        test_explicit_cap_strict_still_accepted;
      Alcotest.test_case "--no-cap-strict opts out" `Slow
        test_no_cap_strict_opts_out;
      Alcotest.test_case "main-less module is not charged for the stdlib" `Slow
        test_no_main_module_is_not_charged_for_the_stdlib;
      Alcotest.test_case "test-only file reports nothing" `Slow
        test_test_only_file_reports_nothing;
      Alcotest.test_case "main-less module still charged for its own use" `Slow
        test_no_main_module_still_charged_for_its_own_use;
      Alcotest.test_case "route: direct builtin call" `Slow
        test_direct_builtin_route;
      Alcotest.test_case "route: stdlib wrapper (was silent)" `Slow
        test_stdlib_route_was_completely_silent;
      Alcotest.test_case "route: builtin passed as a value" `Slow
        test_builtin_as_value_route;
      Alcotest.test_case "dependency exceeding its own ceiling" `Slow
        test_dependency_exceeding_its_own_ceiling;
      Alcotest.test_case "correctly declared program compiles" `Slow
        test_a_correctly_declared_program_compiles;
      Alcotest.test_case "parent capability satisfies the ceiling" `Slow
        test_parent_declaration_satisfies_the_ceiling;
      Alcotest.test_case "doubly-nested module declaring its own needs" `Slow
        test_doubly_nested_module_declaring_its_own_needs;
      Alcotest.test_case "doubly-nested module missing needs is caught" `Slow
        test_doubly_nested_module_without_needs_is_still_caught;
      Alcotest.test_case "capability-free program compiles" `Slow
        test_a_program_using_no_capability_compiles;
      Alcotest.test_case "undeclared console use still caught" `Slow
        test_console_use_without_needs_is_still_caught;
    ]
