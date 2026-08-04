(* Path scope algebra (lib/caps/cap_scope.ml).

   Pure functions, so these are the cheap tests that must catch the subtle
   cases before anything downstream trusts them: a `..` escape, a raw-prefix
   near-miss, and the subsumption direction (which has been gotten backwards
   twice already in the sandbox work). *)

module S = March_caps.Cap_scope

let test_normalize () =
  Alcotest.(check string) "collapses //" "/etc/ssl" (S.normalize "/etc//ssl");
  Alcotest.(check string) "strips trailing /" "/etc/ssl"
    (S.normalize "/etc/ssl/");
  Alcotest.(check string) "resolves ." "/etc/ssl" (S.normalize "/etc/./ssl");
  Alcotest.(check string) "resolves .." "/shadow"
    (S.normalize "/etc/ssl/../../shadow");
  Alcotest.(check string) "root stays root" "/" (S.normalize "/");
  (* ".." at the root drops rather than escaping above it, matching how the
     kernel resolves "/..". *)
  Alcotest.(check string) ".. at root does not escape" "/etc"
    (S.normalize "/../etc")

let test_within_basic () =
  Alcotest.(check bool) "scope contains itself" true
    (S.within ~scope:"/etc/ssl" "/etc/ssl");
  Alcotest.(check bool) "scope contains a descendant" true
    (S.within ~scope:"/etc" "/etc/ssl/cert.pem");
  Alcotest.(check bool) "scope does not contain an ancestor" false
    (S.within ~scope:"/etc/ssl" "/etc");
  Alcotest.(check bool) "unrelated path" false
    (S.within ~scope:"/etc" "/var/log/x")

let test_within_is_segmentwise () =
  (* The near-miss that a raw string-prefix test would wrongly accept, and the
     reason this compares whole segments. *)
  Alcotest.(check bool) "/etcpasswd is NOT within /etc" false
    (S.within ~scope:"/etc" "/etcpasswd");
  Alcotest.(check bool) "/etc-backup is NOT within /etc" false
    (S.within ~scope:"/etc" "/etc-backup")

let test_within_normalizes_first () =
  (* Without normalization this escapes the scope, which is the whole point of
     normalizing before comparing. *)
  Alcotest.(check bool) "..-escape is not within the scope" false
    (S.within ~scope:"/etc/ssl" "/etc/ssl/../shadow");
  Alcotest.(check bool) "..-that-stays-inside is within" true
    (S.within ~scope:"/etc" "/etc/ssl/../hosts");
  Alcotest.(check bool) "redundant separators still match" true
    (S.within ~scope:"/etc" "/etc//ssl/./cert.pem")

let test_absolute_vs_relative () =
  Alcotest.(check bool) "absolute is absolute" true (S.is_absolute "/etc");
  Alcotest.(check bool) "relative is not" false (S.is_absolute "etc");
  (* Mixing them would compare unrelated roots. *)
  Alcotest.(check bool) "relative path not within absolute scope" false
    (S.within ~scope:"/etc" "etc/ssl")

let test_scope_subsumption_both_directions () =
  (* Unscoped permits everything, including other unscoped. *)
  Alcotest.(check bool) "None subsumes a scope" true
    (S.scope_subsumes None (Some "/etc"));
  Alcotest.(check bool) "None subsumes None" true (S.scope_subsumes None None);
  (* And a scope NEVER subsumes unscoped: narrowing grants strictly less.
     Getting this backwards would let a scoped declaration silently satisfy a
     requirement for unrestricted access. *)
  Alcotest.(check bool) "a scope does NOT subsume None" false
    (S.scope_subsumes (Some "/etc") None);
  Alcotest.(check bool) "broader scope subsumes narrower" true
    (S.scope_subsumes (Some "/etc") (Some "/etc/ssl"));
  Alcotest.(check bool) "narrower does NOT subsume broader" false
    (S.scope_subsumes (Some "/etc/ssl") (Some "/etc"));
  Alcotest.(check bool) "siblings do not subsume" false
    (S.scope_subsumes (Some "/etc") (Some "/var"))

let test_is_scopable () =
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is scopable" c)
        true (S.is_scopable c))
    [ "IO.FileRead"; "IO.FileWrite"; "IO.FileSystem" ];
  (* A scope on a non-filesystem capability is rejected by the caller rather
     than ignored — an ignored scope reads as enforcement that is not there. *)
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is NOT scopable" c)
        false (S.is_scopable c))
    [ "IO.Network"; "IO.Console"; "IO.Process"; "IO" ]

let tests =
  [
    Alcotest.test_case "normalize" `Quick test_normalize;
    Alcotest.test_case "within: basic containment" `Quick test_within_basic;
    Alcotest.test_case "within: segment-wise, not raw prefix" `Quick
      test_within_is_segmentwise;
    Alcotest.test_case "within: normalizes before comparing" `Quick
      test_within_normalizes_first;
    Alcotest.test_case "absolute vs relative" `Quick test_absolute_vs_relative;
    Alcotest.test_case "scope subsumption in both directions" `Quick
      test_scope_subsumption_both_directions;
    Alcotest.test_case "only filesystem caps are scopable" `Quick
      test_is_scopable;
  ]

(* ── The static check, end to end through the real compiler ───────────
   A literal path outside every declared scope is a definite violation and an
   error.  Everything else must stay SILENT: false positives here would make
   the feature unusable, and the analysis is deliberately narrow — literals
   only, with computed paths left to runtime enforcement. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let check_src src =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  let f = Filename.temp_file "cap_scope" ".march" in
  let oc = open_out f in
  output_string oc src;
  close_out oc;
  let out = Filename.temp_file "cap_scope" ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "%s --check %s > %s 2>&1" (Filename.quote compiler_exe)
         (Filename.quote f) (Filename.quote out))
  in
  let ic = open_in out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Sys.remove f;
  Sys.remove out;
  (rc, s)

let accepts name src =
  let rc, out = check_src src in
  if rc <> 0 then Alcotest.failf "%s should typecheck but did not:\n%s" name out

let rejects name src =
  let rc, out = check_src src in
  if rc = 0 then Alcotest.failf "%s should have been rejected but was accepted" name;
  let re = Str.regexp_string "outside it" in
  match Str.search_forward re out 0 with
  | _ -> ()
  | exception Not_found ->
    Alcotest.failf "%s was rejected, but not for the scope reason:\n%s" name out

let test_literal_outside_scope_is_rejected () =
  rejects "read outside the declared scope"
    {|
mod ScopeViol do
  needs IO.FileRead("/etc/myapp")
  fn main() : () do
    match file_read("/etc/shadow") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_literal_inside_scope_is_accepted () =
  accepts "read inside the declared scope"
    {|
mod ScopeOkay do
  needs IO.FileRead("/etc/myapp")
  fn main() : () do
    match file_read("/etc/myapp/db.conf") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_dotdot_escape_is_rejected () =
  (* Without normalization this walks straight out of the scope, which is why
     both sides normalize before comparison. *)
  rejects "..-escape from the scope"
    {|
mod ScopeEscape do
  needs IO.FileRead("/etc/myapp")
  fn main() : () do
    match file_read("/etc/myapp/../shadow") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_computed_path_is_silent () =
  (* The analysis reports only DEFINITE violations. A computed path is left to
     runtime enforcement rather than guessed at — guessing would produce false
     positives on the most common real shape. *)
  accepts "computed path is not second-guessed"
    {|
mod ScopeDyn do
  needs IO.FileRead("/etc/myapp")
  fn load(p : String) : String do
    match file_read(p) do
      Ok(s) -> s
      Err(_) -> ""
    end
  end
  fn main() : () do
    println(load("/anything/at/all"))
  end
end
|}

let test_unscoped_declaration_permits_any_path () =
  (* Backward compatibility: every existing `needs IO.FileRead` in the wild
     must keep meaning "any path". *)
  accepts "unscoped needs permits any path"
    {|
mod ScopeUnscoped do
  needs IO.FileRead
  fn main() : () do
    match file_read("/etc/shadow") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_scope_union () =
  accepts "a path in the second of two declared scopes"
    {|
mod ScopeUnion do
  needs IO.FileRead("/etc/app"), IO.FileRead("/usr/share/app")
  fn main() : () do
    match file_read("/usr/share/app/x") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_parent_capability_scope_applies () =
  (* IO.FileSystem subsumes IO.FileRead, so a scope declared on the parent
     scopes the child too. *)
  accepts "scope on IO.FileSystem covers a read beneath it"
    {|
mod ScopeParent do
  needs IO.FileSystem("/srv")
  fn main() : () do
    match file_read("/srv/data/x") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let test_second_path_argument_is_checked () =
  (* file_rename takes TWO paths; checking only the first would let the
     destination escape the scope entirely. *)
  rejects "the destination of a rename is checked"
    {|
mod ScopeTwoPath do
  needs IO.FileWrite("/var/tmp")
  fn main() : () do
    match file_rename("/var/tmp/a", "/etc/passwd") do
      Ok(_) -> println("o")
      Err(_) -> println("e")
    end
  end
end
|}

let tests =
  tests
  @ [
      Alcotest.test_case "literal outside scope is rejected" `Slow
        test_literal_outside_scope_is_rejected;
      Alcotest.test_case "literal inside scope is accepted" `Slow
        test_literal_inside_scope_is_accepted;
      Alcotest.test_case "..-escape is rejected" `Slow
        test_dotdot_escape_is_rejected;
      Alcotest.test_case "computed path is silent" `Slow
        test_computed_path_is_silent;
      Alcotest.test_case "unscoped declaration permits any path" `Slow
        test_unscoped_declaration_permits_any_path;
      Alcotest.test_case "union of declared scopes" `Slow test_scope_union;
      Alcotest.test_case "parent capability scope applies" `Slow
        test_parent_capability_scope_applies;
      Alcotest.test_case "second path argument is checked" `Slow
        test_second_path_argument_is_checked;
    ]
