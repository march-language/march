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

let tests = [
  Alcotest.test_case "triple_ok allowlist" `Quick test_triple_ok;
]
