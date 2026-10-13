(* test/test_shell_triple.ml — the shell client's handling of the node's
   target triple (HELLO `triple:`), which reaches a clang command line.
   [Jit_emit.triple_ok] allowlists it; [Repl_jit.shell_target_flags] fails
   closed on anything the allowlist rejects. *)

module E = March_jit.Jit_emit

let good = [ "arm64-apple-darwin25.6.0"; "x86_64-unknown-linux-gnu";
             "aarch64-unknown-linux-gnu"; "x86_64-pc-linux-gnu"; "unknown" ]

let bad = [ ""; "x86_64-pc-linux-gnu;x"; "x86_64-pc-linux-gnu$(x)";
            "x86_64`x`"; "a|b"; "a&b"; "a{x}"; "a b"; "a\tb"; "a\nb";
            "a'b"; "a\"b"; "a\\b"; "a/b"; "x86_64-pc-linux-gnu${IFS}x" ]

let test_triple_ok () =
  List.iter (fun t -> Alcotest.(check bool) (t ^ " accepted") true (E.triple_ok t)) good;
  List.iter (fun t -> Alcotest.(check bool) (String.escaped t ^ " refused") false (E.triple_ok t)) bad

module R = March_jit.Repl_jit

let starts_with s p = String.length s >= String.length p && String.sub s 0 (String.length p) = p

let contains m sub =
  let n = String.length sub in
  let rec go i = i + n <= String.length m && (String.sub m i n = sub || go (i + 1)) in
  go 0

let test_target_flags_valid () =
  let t = if R.is_macos () then "arm64-apple-darwin25.6.0" else "x86_64-unknown-linux-gnu" in
  let _mac, flags = R.shell_target_flags ~triple:(Some t) in
  Alcotest.(check bool) ("starts with --target=<triple>: " ^ flags) true
    (starts_with flags (" --target=" ^ t) || starts_with flags (" --target=" ^ Filename.quote t))

let test_target_flags_sentinels () =
  Alcotest.(check string) "None -> no flag" "" (snd (R.shell_target_flags ~triple:None));
  Alcotest.(check string) "unknown -> no flag" "" (snd (R.shell_target_flags ~triple:(Some "unknown")));
  Alcotest.(check string) "empty -> no flag" "" (snd (R.shell_target_flags ~triple:(Some "")))

let test_target_flags_refuses_metachars () =
  List.iter (fun t ->
      match R.shell_target_flags ~triple:(Some t) with
      | _ -> Alcotest.failf "%s was accepted" (String.escaped t)
      | exception Failure m ->
        Alcotest.(check bool) ("message names the triple: " ^ m) true (contains m "triple"))
    [ "x86_64-pc-linux-gnu;x"; "x86_64-pc-linux-gnu$(x)"; "arm64-apple-darwin25.6.0|x";
      "x86_64-unknown-linux-gnu${IFS}x"; "a b" ]

let tests = [
  Alcotest.test_case "triple_ok allowlist" `Quick test_triple_ok;
  Alcotest.test_case "shell_target_flags: a real triple" `Quick test_target_flags_valid;
  Alcotest.test_case "shell_target_flags: sentinels give no flag" `Quick test_target_flags_sentinels;
  Alcotest.test_case "shell_target_flags: metacharacters are refused" `Quick test_target_flags_refuses_metachars;
]
