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

let compile_strict src_text =
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
      (Printf.sprintf "%s --cap-strict --compile -o %s %s > %s 2>&1"
         (Filename.quote compiler_exe) (Filename.quote bin)
         (Filename.quote src) (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  List.iter (fun f -> try Sys.remove f with Sys_error _ -> ()) [ src; out; bin ];
  (rc, s)

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
  rejects "direct builtin call"
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
  fn main() : () do
    match File.write("/tmp/x", "d") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

(* Route 3: a builtin handed out as a VALUE and invoked indirectly. *)
let test_builtin_as_value_route () =
  rejects "builtin passed as a value"
    {|
mod CeilValue do
  needs IO.Console
  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end
  fn main() : () do
    match apply1(file_read, "/etc/hosts") do
      Ok(_)  -> println("ok")
      Err(_) -> println("e")
    end
  end
end
|}

(* A DEPENDENCY exceeding its own ceiling, in a program whose entry module is
   itself clean.  This is the supply-chain case, and the reason the check is
   per-module: the whole-program union cannot see it, and the dependency never
   opted in to anything. *)
let test_dependency_exceeding_its_own_ceiling () =
  rejects "dependency exceeds its declared needs"
    {|
mod CeilApp do
  needs IO.Console
  mod Dep do
    needs IO.Console
    fn greet(n : String) : String do
      match file_read("/etc/passwd") do
        Ok(s)  -> s
        Err(_) -> "hello " ++ n
      end
    end
  end
  fn main() : () do
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
  fn main() : () do
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
  fn main() : () do
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
  fn main() : () do
    if Innocent.DeeplyNested.write_it("d") do println("ok") else println("no") end
  end
end
|}

(* And the same shape WITHOUT the declaration must still be caught — reported
   under the qualified name, so the fix above did not buy silence by simply
   dropping deep modules from the ceiling. *)
let test_doubly_nested_module_without_needs_is_still_caught () =
  rejects_naming "doubly-nested module missing needs"
    ~expect:
      "module `Innocent.DeeplyNested` uses `IO.FileWrite` but does not declare"
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
  rejects_naming "undeclared console use"
    ~expect:
      "module `CeilConsoleUndeclared` uses `IO.Console` but does not declare"
    {|
mod CeilConsoleUndeclared do
  fn main() : () do
    println("hi")
  end
end
|}

let tests =
  unit_tests
  @ [
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
