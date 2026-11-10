(* Freshness tests for March_caps.Cap_ops, the ocap phase 1 classification of
   capability builtins into operations, uses and runtime-internal plumbing
   (specs/plans/2026-11-10-ocap-p1-result-plan.md, Task 3).

   Total in both directions: every [builtin_cap_table] name has exactly one
   row, and every row names a capability builtin.  A new capability builtin
   therefore cannot reach the stdlib without someone deciding whether it is
   checked. *)

module Ops = March_caps.Cap_ops

let cap_table = March_typecheck.Typecheck_builtins.builtin_cap_table

let test_every_cap_builtin_classified () =
  let missing =
    List.filter_map (fun (n, _) ->
        match List.filter (fun (m, _) -> m = n) Ops.table with
        | [ _ ] -> None
        | [] -> Some (n ^ ": no row")
        | _ -> Some (n ^ ": more than one row"))
      cap_table in
  Alcotest.(check (list string)) "every builtin_cap_table entry has one row" [] missing

let test_every_row_is_a_cap_builtin () =
  let stray =
    List.filter_map (fun (n, _) ->
        if List.mem_assoc n cap_table
        && List.mem_assoc n March_typecheck.Typecheck_builtins.builtin_bindings
        then None else Some n)
      Ops.table in
  Alcotest.(check (list string)) "every row names a capability builtin" [] stray

let is_checked = function Some (Ops.Checked _) -> true | _ -> false

let test_known_rows () =
  Alcotest.(check bool) "io_read_line is checked" true (is_checked (Ops.classify "io_read_line"));
  Alcotest.(check bool) "io_read_byte is checked" true (is_checked (Ops.classify "io_read_byte"));
  Alcotest.(check bool) "vault_set is a use" true (Ops.classify "vault_set" = Some Ops.Use);
  Alcotest.(check bool) "dist_monitor_ack is internal" true
    (Ops.classify "dist_monitor_ack" = Some Ops.Internal);
  Alcotest.(check bool) "file_open is checked but left to phase 2's gate" true
    (Ops.classify "file_open" = Some (Ops.Checked { entry = [ "File.with_lines"; "File.each_line" ];
                                                    gated = false }));
  Alcotest.(check bool) "unix_time is gated" true (List.mem_assoc "unix_time" Ops.gated)

let test_stdin_reads_charged_to_console () =
  Alcotest.(check (option string)) "io_read_line needs IO.Console" (Some "IO.Console")
    (List.assoc_opt "io_read_line" cap_table);
  Alcotest.(check (option string)) "io_read_byte needs IO.Console" (Some "IO.Console")
    (List.assoc_opt "io_read_byte" cap_table)

let tests =
  [
    Alcotest.test_case "every capability builtin is classified" `Quick
      test_every_cap_builtin_classified;
    Alcotest.test_case "every row is a capability builtin" `Quick
      test_every_row_is_a_cap_builtin;
    Alcotest.test_case "known rows" `Quick test_known_rows;
    Alcotest.test_case "stdin reads are charged to IO.Console" `Quick
      test_stdin_reads_charged_to_console;
  ]
