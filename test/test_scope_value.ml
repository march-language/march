(* ocap phase 5, Task 2 (specs/plans/2026-11-19-ocap-p5-restrict-plan.md): the
   [Scope] value and the restrict layer's policy hooks, in every runtime.

   The fixture is a stdlib-spanned program (`--stdlib-source`, as
   test_cap_runtime_slot's: [Scope.literal]/[Scope.build] are stdlib-internal)
   run by the real compiler binary interpreted, through the ORC JIT, compiled
   and as JavaScript under node; every run's stdout must equal the same text. *)

let src = {|mod ScopeFixture do
  needs IO.Console
  fn show_build(r : Result(Scope, ScopeError)) do
    println(show(r))
  end
  fn main() needs IO.Console do
    let a = Scope.literal("IO.Console")
    let b = Scope.literal("IO.FileRead(\"/srv/\")")
    let none = Scope.literal("()")
    println(Scope.to_string(Scope.union(a, b)))
    println(Scope.to_string(Scope.union(none, b)))
    println(Scope.to_string(Scope.union(b, none)))
    println(Scope.to_string(Scope.union(none, none)))
    show_build(Scope.build("IO.FileRead", ["/srv/" ++ "x"], []))
    show_build(Scope.build("IO.FileRead", ["../etc"], []))
    show_build(Scope.build("IO.FileRead", ["/srv/" ++ "../etc/"], []))
    show_build(Scope.build("IO.FileRead", ["a\"b"], []))
    show_build(Scope.build("IO.FileRead", ["a;b"], []))
    show_build(Scope.build("IO.FileRead", ["/srv/a\\b"], []))
    show_build(Scope.build("IO.FileRead", [""], []))
    show_build(Scope.build("IO.NetConnect", ["bad host!"], []))
    let l = Authority.restrict_layer("t.march:3", "IO.Console")
    let old = Authority.enter_fn(l)
    let refused = Authority.check("IO.Clock", "")
    match refused do
    Err(e) -> println(Authority.describe(e))
    Ok(_) -> println("admitted")
    end
    let again = Authority.enter_fn(l)
    println(int_to_string(List.length(cap_layers())))
    cap_restore(again)
    cap_restore(old)
    println(int_to_string(List.length(cap_layers())))
  end
end
|}

let expected = String.concat "\n" [
  "IO.Console, IO.FileRead(\"/srv/\")";
  "IO.FileRead(\"/srv/\")";
  "IO.FileRead(\"/srv/\")";
  "()";
  "Ok(IO.FileRead(\"/srv/x\"))";
  "Err(IO.FileRead: the scope `../etc` on `IO.FileRead` is a relative path; give an absolute path, one starting with `/`)";
  "Err(IO.FileRead: the path \"/srv/../etc/\" has a `..` segment)";
  "Err(IO.FileRead: the string \"a\"b\" contains \")";
  "Err(IO.FileRead: the string \"a;b\" contains ;)";
  "Ok(IO.FileRead(\"/srv/a\\\\b\"))";
  "Err(IO.FileRead: the first string is empty)";
  "Err(IO.NetConnect: `bad host!` is not a host name: labels are letters, digits and `-`, separated by single dots)";
  "IO.Clock refused by the restrict at t.march:3 (IO.Console)";
  "1";
  "0"; "" ]

let test_scope_value () =
  Test_cap_runtime_slot.check_all ~name:"scope value" ~src:src [ ("", expected) ]

let tests =
  [ ( "scope_value",
      [ Alcotest.test_case "Scope union/literal/build and restrict layers, every runtime"
          `Quick test_scope_value ] ) ]
