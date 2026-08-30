(** March LSP tests: find references, rename, signature help, and the code-action families (make-linear, exhaustion, dead code, annotations, naming, De Morgan)

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* 12. Find references                                                 *)
(* ------------------------------------------------------------------ *)

let test_references_empty_for_literal () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  Alcotest.(check int)
    "no refs for literal"
    0
    (List.length (An.references_at a ~include_declaration:false ~line ~character:col))

let test_references_finds_uses () =
  let src = {|
mod M do
  fn double(n: Int): Int do n + n end
  fn main() do
    double(1)
    double(2)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "double(1" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool)
    "at least 2 use refs"
    true
    (List.length refs >= 2)

let test_references_include_declaration () =
  let src = {|
mod M do
  fn sq(n: Int): Int do n * n end
  fn main() do sq(3) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "sq(3" in
  let with_decl    = An.references_at a ~include_declaration:true  ~line ~character:col in
  let without_decl = An.references_at a ~include_declaration:false ~line ~character:col in
  Alcotest.(check bool)
    "include_declaration adds one entry"
    true
    (List.length with_decl = List.length without_decl + 1)

let test_references_local_variable () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    let a = x
    a + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "a = x" in
  let refs = An.references_at a ~include_declaration:false ~line ~character:(col + 4) in
  Alcotest.(check bool) "two uses of x" true (List.length refs >= 2)

let test_references_no_cross_contamination () =
  let src = {|
mod M do
  fn a() do 1 end
  fn b() do 2 end
  fn main() do a() end
end
|} in
  let a_an = analyse src in
  let (line, col) = pos_of src "a()" in
  let refs = An.references_at a_an ~include_declaration:false ~line ~character:col in
  let all_same_name =
    List.for_all (fun (loc : Lsp.Types.Location.t) ->
        loc.range.start.character < loc.range.end_.character
      ) refs
  in
  Alcotest.(check bool) "all refs are real ranges" true all_same_name

(* ------------------------------------------------------------------ *)
(* 13. Rename symbol                                                   *)
(* ------------------------------------------------------------------ *)

let test_rename_no_edits_for_literal () =
  let src = {|mod M do fn f() do 99 end end|} in
  let a = analyse src in
  let (line, col) = pos_of src "99" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"foo" in
  Alcotest.(check int) "no edits for literal" 0 (List.length edits)

let test_rename_produces_edits_for_def_and_uses () =
  let src = {|
mod M do
  fn calc(n: Int): Int do n + 1 end
  fn main() do
    calc(10)
    calc(20)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "calc(10" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"compute" in
  Alcotest.(check bool)
    "at least 3 edits"
    true
    (List.length edits >= 3)

let test_rename_new_name_in_edits () =
  let src = {|
mod M do
  fn old_name(x: Int): Int do x end
  fn main() do old_name(5) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "old_name(5" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"new_name" in
  let all_new_name =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText = "new_name"
      ) edits
  in
  Alcotest.(check bool) "all edits contain new_name" true all_new_name

let test_rename_does_not_rename_other_names () =
  let src = {|
mod M do
  fn alpha() do 1 end
  fn beta()  do 2 end
  fn main()  do alpha() end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "alpha()" in
  let edits = An.rename_at a ~line ~character:col ~new_name:"gamma" in
  let no_beta =
    List.for_all (fun (e : Lsp.Types.TextEdit.t) ->
        e.newText <> "beta"
      ) edits
  in
  Alcotest.(check bool) "beta untouched" true no_beta

(* ------------------------------------------------------------------ *)
(* 14. Signature help                                                  *)
(* ------------------------------------------------------------------ *)

let test_sig_help_none_outside_call () =
  let src = {|mod M do fn f() do 42 end end|} in
  let a = analyse src in
  Alcotest.(check bool)
    "no sig help outside call"
    true
    (An.signature_help_at a ~line:2 ~character:5 = None)

let test_sig_help_single_param () =
  let src = {|
mod M do
  fn negate(n: Int): Int do 0 - n end
  fn main() do negate(10) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "negate(10" in
  let sh = An.signature_help_at a ~line ~character:(col + 7) in
  Alcotest.(check bool) "sig help present" true (sh <> None);
  match sh with
  | None -> ()
  | Some (label, params, active_param) ->
    Alcotest.(check bool) "label non-empty"   true (String.length label > 0);
    Alcotest.(check int)  "one param"         1    (List.length params);
    Alcotest.(check int)  "first param active" 0   active_param

let test_sig_help_active_param_index () =
  let src = {|
mod M do
  fn add3(a: Int, b: Int, c: Int): Int do a + b + c end
  fn main() do add3(1, 2, 3) end
end
|} in
  let a = analyse src in
  let (line, comma_col) = pos_of src ", 3)" in
  (match An.signature_help_at a ~line ~character:(comma_col + 2) with
   | None -> Alcotest.fail "expected signature help"
   | Some (_, _, active) ->
     Alcotest.(check int) "third param active (index 2)" 2 active)

let test_sig_help_param_labels () =
  let src = {|
mod M do
  fn div(numerator: Int, denominator: Int): Int do
    numerator / denominator
  end
  fn main() do div(10, 2) end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "div(10" in
  (match An.signature_help_at a ~line ~character:(col + 4) with
   | None -> Alcotest.fail "expected sig help"
   | Some (_, params, _) ->
     Alcotest.(check int) "two params" 2 (List.length params);
     List.iter (fun p ->
         Alcotest.(check bool)
           "param label non-empty"
           true
           (String.length p > 0)
       ) params)

let test_sig_help_not_a_known_function () =
  let src = {|
mod M do
  fn main() do
    let f = fn x -> x + 1
    f(5)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "f(5" in
  let _ = An.signature_help_at a ~line ~character:(col + 2) in
  Alcotest.(check bool) "no crash" true true

(* ------------------------------------------------------------------ *)
(* 15. Code actions: make-linear                                       *)
(* ------------------------------------------------------------------ *)

let test_make_linear_offered_for_single_use () =
  let src = {|
mod M do
  fn f() do
    let x = 42
    x + 1
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t -> String.length t > 0 &&
               (let low = String.lowercase_ascii t in
                let n = String.length low in
                let sub = "linear" in
                let sn = String.length sub in
                let found = ref false in
                for i = 0 to n - sn do
                  if String.sub low i sn = sub then found := true
                done;
                !found)
      ) acts
  in
  Alcotest.(check bool) "make-linear offered" true has_make_linear

let test_make_linear_not_offered_for_multi_use () =
  let src = {|
mod M do
  fn f() do
    let x = 10
    x + x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_make_linear =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        match ca.title with
        | t ->
          let low = String.lowercase_ascii t in
          let n = String.length low and sn = 6 in
          let found = ref false in
          for i = 0 to n - sn do
            if String.sub low i sn = "linear" then found := true
          done;
          !found
      ) acts
  in
  Alcotest.(check bool) "no make-linear for multi-use" false has_make_linear

let test_make_linear_edit_inserts_keyword () =
  let src = {|
mod M do
  fn f() do
    let value = 5
    value * 2
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let value" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let linear_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      match ca.title with
      | t ->
        let low = String.lowercase_ascii t in
        let n = String.length low and sn = 6 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "linear" then found := true
        done;
        !found
    ) acts
  in
  match linear_act with
  | None -> Alcotest.fail "expected make-linear action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let has_edit =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let t = e.newText in
                   let n = String.length t and sn = 7 in
                   let found = ref false in
                   for i = 0 to n - sn do
                     if String.sub t i sn = "linear " then found := true
                   done;
                   !found
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit inserts 'linear '" true has_edit)

(* ------------------------------------------------------------------ *)
(* 16. Code actions: pattern exhaustion quickfix                       *)
(* ------------------------------------------------------------------ *)

let test_exhaustion_quickfix_absent_for_exhaustive_match () =
  let src = {|
mod M do
  type Hue = Red | Green | Blue

  fn describe(c: Hue): String do
    match c do
    Red   -> "red"
    Green -> "green"
    Blue  -> "blue"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match c" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_exhaustion =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 7 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "missing" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no exhaustion fix for complete match" false has_exhaustion

let test_exhaustion_quickfix_offered_for_incomplete_match () =
  let src = {|
mod M do
  type Shape = Circle | Square | Triangle

  fn area(s: Shape): Int do
    match s do
    Circle -> 1
    Square -> 2
    end
  end
end
|} in
  let a = analyse src in
  let has_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        match d.severity with
        | Some Lsp.Types.DiagnosticSeverity.Warning -> true
        | _ -> false
      ) a.diagnostics
  in
  Alcotest.(check bool) "warning present" true has_warning;
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_quickfix =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
      ) acts
  in
  Alcotest.(check bool) "quickfix offered" true has_quickfix

let test_exhaustion_quickfix_edit_contains_missing_arm () =
  let src = {|
mod M do
  type Dir = North | South | East | West

  fn label(d: Dir): String do
    match d do
    North -> "N"
    South -> "S"
    East  -> "E"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix
    ) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let found_west =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let low = String.lowercase_ascii e.newText in
                   let n = String.length low and sn = 4 in
                   let f = ref false in
                   for i = 0 to n - sn do
                     if String.sub low i sn = "west" then f := true
                   done;
                   !f
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit mentions West" true found_west)

let test_exhaustion_quickfix_edit_inserts_before_end () =
  let src = {|
mod M do
  type Bit = Zero | One

  fn flip(b: Bit): Bit do
    match b do
    Zero -> One
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match b" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let qf = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.kind = Some Lsp.Types.CodeActionKind.QuickFix) acts in
  match qf with
  | None -> Alcotest.fail "expected quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let has_arm =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   (* a generated arm contains an arrow `->` and no leading `|` *)
                   String.contains e.newText '>'
                   && not (String.contains e.newText '|')
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit is a match arm" true has_arm)

(* ------------------------------------------------------------------ *)
(* 17. Phase 2: Enhanced exhaustive match                             *)
(* ------------------------------------------------------------------ *)

let test_exhaustion_all_cases_action_offered () =
  (* Two variants missing → "Add all 2 missing cases" should appear *)
  let src = {|
mod M do
  type Season = Spring | Summer | Autumn | Winter

  fn greet(s: Season): String do
    match s do
    Spring -> "bloom"
    Summer -> "sun"
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_bulk =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 3 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "all" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "bulk 'add all' action offered" true has_bulk

let test_exhaustion_all_cases_edit_covers_all () =
  (* Three variants missing; bulk edit should mention all three *)
  let src = {|
mod M do
  type Dir = North | South | East | West

  fn go(d: Dir): Int do
    match d do
    North -> 0
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match d" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let bulk = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low and sn = 3 in
      let found = ref false in
      for i = 0 to n - sn do
        if String.sub low i sn = "all" then found := true
      done;
      !found
    ) acts in
  match bulk with
  | None -> Alcotest.fail "expected bulk quickfix"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       match edit.changes with
       | None -> Alcotest.fail "expected changes"
       | Some m ->
         let combined = List.concat_map (fun (_, es) ->
             List.map (fun (e : Lsp.Types.TextEdit.t) -> e.newText) es
           ) m |> String.concat "" |> String.lowercase_ascii
         in
         let contains sub str =
           let sn = String.length sub and n = String.length str in
           let found = ref false in
           for i = 0 to n - sn do
             if String.sub str i sn = sub then found := true
           done;
           !found
         in
         Alcotest.(check bool) "south in edit" true (contains "south" combined);
         Alcotest.(check bool) "east in edit"  true (contains "east"  combined);
         Alcotest.(check bool) "west in edit"  true (contains "west"  combined))

let test_exhaustion_single_missing_no_bulk () =
  (* Only one variant missing → no "Add all N missing cases" bulk action *)
  let src = {|
mod M do
  type Bit = Zero | One

  fn inv(b: Bit): Bit do
    match b do
    Zero -> One
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match b" in
  let acts = An.code_actions_at a ~line ~character:col () in
  (* "Add all N missing cases" has the prefix "add all" — not a file-scope fix *)
  let has_add_all =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low and sn = 7 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub low i sn = "add all" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no 'add all' for single missing case" false has_add_all

(* ------------------------------------------------------------------ *)
(* 18. Phase 2: Diagnostics-driven quickfix framework                 *)
(* ------------------------------------------------------------------ *)

let test_fix_registry_has_known_codes () =
  (* The registry should have entries for the standard diagnostic codes *)
  let codes = ["non_exhaustive_match"; "unused_binding";
               "dead-code/unused-private-fn"; "dead-code/unreachable-after-diverge"] in
  List.iter (fun code ->
      let has_entry = Hashtbl.mem An.fix_registry code in
      Alcotest.(check bool) ("registry has " ^ code) true has_entry
    ) codes

let test_apply_fix_registry_empty_for_unknown_code () =
  let src = {|
mod M do
  fn main() do
    println("hi")
  end
end
|} in
  let a = analyse src in
  let fake_diag = Lsp.Types.Diagnostic.create
    ~range:(Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:0 ~character:1))
    ~message:(`String "test") ~source:"march"
    ~code:(`String "no_such_code")
    ()
  in
  let acts = An.apply_fix_registry a [fake_diag] in
  Alcotest.(check int) "no actions for unknown code" 0 (List.length acts)

(* ------------------------------------------------------------------ *)
(* 19. Phase 2: Dead code detection                                   *)
(* ------------------------------------------------------------------ *)

let test_unused_private_fn_warning () =
  let src = {|
mod M do
  pfn helper(): Int do
    42
  end

  fn main() do
    println("hi")
  end
end
|} in
  let a = analyse src in
  let has_unused_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "dead-code/unused-private-fn") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "unused private fn warning" true has_unused_warning

let test_used_private_fn_no_warning () =
  let src = {|
mod M do
  pfn helper(): Int do
    42
  end

  fn main() do
    let x = helper()
    println(int_to_string(x))
  end
end
|} in
  let a = analyse src in
  let has_unused_warning =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "dead-code/unused-private-fn") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "used private fn: no warning" false has_unused_warning

let test_unreachable_code_after_panic_warning () =
  let src = {|
mod M do
  fn bad(x: Int): Int do
    let _ = panic("oops")
    x + 1
  end
end
|} in
  let a = analyse src in
  let has_unreachable =
    List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
        (match d.code with
         | Some (`String "dead-code/unreachable-after-diverge") -> true
         | _ -> false)
      ) a.diagnostics
  in
  Alcotest.(check bool) "unreachable code warning after panic" true has_unreachable

let test_unused_fns_field_populated () =
  let src = {|
mod M do
  pfn dead(): Int do
    99
  end

  fn alive(): Int do
    1
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "dead fn in unused_fns" true
    (List.mem "dead" a.An.unused_fns);
  Alcotest.(check bool) "alive fn not in unused_fns" false
    (List.mem "alive" a.An.unused_fns)

(* ------------------------------------------------------------------ *)
(* 20. P1.8: Assign to `_` (discard result) action                   *)
(* ------------------------------------------------------------------ *)

(* Source that triggers unused_binding via an unused function parameter. *)
let src_unused_param = {|
mod M do
  fn greet(name) do
    "hello"
  end
end
|}

let test_assign_to_underscore_offered () =
  let a = analyse src_unused_param in
  let (line, col) = pos_of src_unused_param "name" in
  (* The unused_binding diagnostic is at the name; pass it as context *)
  let diags = List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.code with Some (`String "unused_binding") -> true | _ -> false
    ) a.diagnostics in
  let acts = An.code_actions_at a ~line ~character:col ~diagnostics:diags () in
  let has_assign_action =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low in
        let found = ref false in
        for i = 0 to n - 7 do
          if String.sub low i 7 = "assign " then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "assign-to-_ offered for unused binding" true has_assign_action

let test_assign_to_underscore_edit_replaces_name () =
  let a = analyse src_unused_param in
  let (line, col) = pos_of src_unused_param "name" in
  let diags = List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.code with Some (`String "unused_binding") -> true | _ -> false
    ) a.diagnostics in
  let acts = An.code_actions_at a ~line ~character:col ~diagnostics:diags () in
  let assign_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low in
      let found = ref false in
      for i = 0 to n - 7 do
        if String.sub low i 7 = "assign " then found := true
      done;
      !found
    ) acts in
  match assign_act with
  | None -> Alcotest.fail "assign-to-_ action not found"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let replaces_with_underscore =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   e.newText = "_"
                 ) edits
             ) m
       in
       Alcotest.(check bool) "assign edit replaces with _" true replaces_with_underscore)

(* ------------------------------------------------------------------ *)
(* 21. P2.10: Remove unused import action                             *)
(* ------------------------------------------------------------------ *)

let test_unused_import_diagnostic_has_code () =
  (* March has a Collections module in the stdlib; using it with .* and then
     not referencing anything should trigger unused_import *)
  let src = {|
mod M do
  fn main() do
    println("hi")
  end
end
|} in
  (* We can't easily test unused_import without a real import that gets unused.
     Instead verify the fix_registry has the code. *)
  let has_entry = Hashtbl.mem An.fix_registry "unused_import" in
  Alcotest.(check bool) "registry has unused_import" true has_entry;
  ignore src

let test_remove_import_action_whole_line () =
  (* We simulate an unused_import diagnostic pointing at line 1 (0-indexed)
     and verify the code action deletes that line. *)
  let src = {|mod M do
  fn main() do
    println("hi")
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  (* Build a synthetic unused_import diagnostic for line 1 (0-indexed) *)
  let fake_range = Lsp.Types.Range.create
    ~start:(Lsp.Types.Position.create ~line:1 ~character:2)
    ~end_:(Lsp.Types.Position.create ~line:1 ~character:10) in
  let fake_diag = Lsp.Types.Diagnostic.create
    ~range:fake_range
    ~message:(`String "Unused import: nothing from `Foo` is used.\nRemove this import.")
    ~source:"march"
    ~code:(`String "unused_import") () in
  let acts = An.code_actions_at a ~line:1 ~character:5 ~diagnostics:[fake_diag] () in
  let has_remove_action =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low in
        let found = ref false in
        for i = 0 to n - 6 do
          if String.sub low i 6 = "remove" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "remove import action offered" true has_remove_action

let test_remove_import_edit_deletes_line () =
  let src = {|mod M do
  fn main() do
    println("hi")
  end
end|} in
  let a = An.analyse ~filename:"test.march" ~src in
  let fake_range = Lsp.Types.Range.create
    ~start:(Lsp.Types.Position.create ~line:1 ~character:2)
    ~end_:(Lsp.Types.Position.create ~line:1 ~character:10) in
  let fake_diag = Lsp.Types.Diagnostic.create
    ~range:fake_range
    ~message:(`String "Unused import: nothing from `Foo` is used.\nRemove this import.")
    ~source:"march"
    ~code:(`String "unused_import") () in
  let acts = An.code_actions_at a ~line:1 ~character:5 ~diagnostics:[fake_diag] () in
  let remove_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low in
      let found = ref false in
      for i = 0 to n - 6 do
        if String.sub low i 6 = "remove" then found := true
      done;
      !found
    ) acts in
  match remove_act with
  | None -> Alcotest.fail "remove import action not found"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let deletes_whole_line =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   e.newText = "" &&
                   e.range.Lsp.Types.Range.start.line = 1 &&
                   e.range.Lsp.Types.Range.end_.line = 2
                 ) edits
             ) m
       in
       Alcotest.(check bool) "edit deletes whole line" true deletes_whole_line)

(* ------------------------------------------------------------------ *)
(* 22. P3.4: Wrap with inspect / Remove inspect                       *)
(* ------------------------------------------------------------------ *)

let test_wrap_with_inspect_offered () =
  let src = {|
mod M do
  fn main() do
    let x = 42
    x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_wrap =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low in
        let found = ref false in
        for i = 0 to n - 4 do
          if String.sub low i 4 = "wrap" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "wrap with inspect offered" true has_wrap

let test_wrap_with_inspect_edit_adds_inspect () =
  let src = {|
mod M do
  fn main() do
    let x = 42
    x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "42" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let wrap_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low in
      let found = ref false in
      for i = 0 to n - 4 do
        if String.sub low i 4 = "wrap" then found := true
      done;
      !found
    ) acts in
  match wrap_act with
  | None -> Alcotest.fail "wrap action not found"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let inserts_inspect =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let t = e.newText in
                   let n = String.length t in
                   let found = ref false in
                   for i = 0 to n - 8 do
                     if String.sub t i 8 = "inspect(" then found := true
                   done;
                   !found
                 ) edits
             ) m
       in
       Alcotest.(check bool) "wrap edit inserts inspect(" true inserts_inspect)

let test_remove_inspect_offered () =
  let src = {|
mod M do
  fn main() do
    let x = inspect(42, "x")
    x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "inspect(" in
  let acts = An.code_actions_at a ~line ~character:(col + 4) () in
  let has_remove =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let low = String.lowercase_ascii ca.title in
        let n = String.length low in
        let found = ref false in
        for i = 0 to n - 6 do
          if String.sub low i 6 = "remove" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "remove inspect offered" true has_remove

let test_remove_inspect_edit_unwraps () =
  let src = {|
mod M do
  fn main() do
    let x = inspect(42, "x")
    x
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "inspect(" in
  let acts = An.code_actions_at a ~line ~character:(col + 4) () in
  let remove_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let low = String.lowercase_ascii ca.title in
      let n = String.length low in
      let found = ref false in
      for i = 0 to n - 6 do
        if String.sub low i 6 = "remove" then found := true
      done;
      !found
    ) acts in
  match remove_act with
  | None -> Alcotest.fail "remove inspect action not found"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected workspace edit"
     | Some edit ->
       let unwraps_to_inner =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   e.newText = "42"
                 ) edits
             ) m
       in
       Alcotest.(check bool) "remove edit unwraps to inner expr" true unwraps_to_inner)

(* ------------------------------------------------------------------ *)
(* 23. P1.1 — Typed match arm stubs                                   *)
(* ------------------------------------------------------------------ *)

(** Typed stubs: ctor with fields should produce Ctor(var) arm, not bare Ctor. *)
let test_typed_match_stub_with_fields () =
  let src = {|
mod M do
  type Shape = Circle(Int) | Square(Int) | Triangle

  fn area(s: Shape): Int do
    match s do
    Circle(r) -> r * r
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  (* Find the "Add missing case: Square" action *)
  let square_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let t = String.lowercase_ascii ca.title in
      let n = String.length t and sn = 6 in
      let found = ref false in
      for i = 0 to n - sn do
        if String.sub t i sn = "square" then found := true
      done;
      !found
    ) acts in
  match square_act with
  | None -> Alcotest.fail "expected Square action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let has_param =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   (* Typed stub should contain "Square(" — param binding *)
                   let t = e.newText in
                   let n = String.length t and sn = 7 in
                   let found = ref false in
                   for i = 0 to n - sn do
                     if String.sub t i sn = "Square(" then found := true
                   done;
                   !found
                 ) edits
             ) m
       in
       Alcotest.(check bool) "typed stub has Square(n)" true has_param)

(** Nullary ctor (no fields) stays as bare name. *)
let test_typed_match_stub_nullary () =
  let src = {|
mod M do
  type Shape = Circle(Int) | Square(Int) | Triangle

  fn area(s: Shape): Int do
    match s do
    Circle(r) -> r * r
    Square(w) -> w * w
    end
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "match s" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let tri_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let t = String.lowercase_ascii ca.title in
      let n = String.length t and sn = 8 in
      let found = ref false in
      for i = 0 to n - sn do
        if String.sub t i sn = "triangle" then found := true
      done;
      !found
    ) acts in
  match tri_act with
  | None -> Alcotest.fail "expected Triangle action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let bare_arm =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) ->
                   let t = e.newText in
                   (* Nullary: should be "Triangle ->" not "Triangle(" *)
                   let n = String.length t in
                   let has_bare = ref false in
                   let sn_bare = 9 in  (* "Triangle " = 9 chars (no leading pipe) *)
                   for i = 0 to n - sn_bare do
                     if String.sub t i sn_bare = "Triangle " then has_bare := true
                   done;
                   let has_params = ref false in
                   let sn_paren = 9 in  (* "Triangle(" = 9 chars *)
                   for i = 0 to n - sn_paren do
                     if String.sub t i sn_paren = "Triangle(" then has_params := true
                   done;
                   !has_bare && not !has_params
                 ) edits
             ) m
       in
       Alcotest.(check bool) "nullary ctor has no params in stub" true bare_arm)

(* ------------------------------------------------------------------ *)
(* 24. P1.7 — Function return type annotation                         *)
(* ------------------------------------------------------------------ *)

(** AnnFnReturn site created for fn without ret_ty. *)
let test_fn_return_annotation_site_created () =
  let src = {|
mod M do
  fn greet(name: String): String do
    name
  end

  fn add(x: Int) do
    x + 1
  end
end
|} in
  let a = analyse src in
  let has_fn_return_site =
    List.exists (fun (site : An.annotation_site) ->
        site.An.as_kind = An.AnnFnReturn
      ) a.An.annotation_sites
  in
  Alcotest.(check bool) "AnnFnReturn site created for unannotated fn" true has_fn_return_site

(** "Add return type annotation" action offered when cursor on fn name. *)
let test_fn_return_annotation_action_offered () =
  let src = {|
mod M do
  fn double(x: Int) do
    x * 2
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "double" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_ret_annot =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let t = String.lowercase_ascii ca.title in
        let n = String.length t and sn = 6 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub t i sn = "return" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "return type annotation action offered" true has_ret_annot

(** Return type annotation edit inserts ": T" before "do" (March return syntax
    is `: T`, not `-> T` which is a parse error). *)
let test_fn_return_annotation_edit_inserts_colon () =
  let src = {|
mod M do
  fn double(x: Int) do
    x * 2
  end
end
|} in
  let has s sub =
    let ls = String.length s and lsub = String.length sub in
    let rec go i = i + lsub <= ls && (String.sub s i lsub = sub || go (i + 1)) in
    go 0 in
  let a = analyse src in
  let (line, col) = pos_of src "double" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let ret_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      has (String.lowercase_ascii ca.title) "return") acts in
  match ret_act with
  | None -> Alcotest.fail "expected return type annotation action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let texts =
         match edit.changes with
         | None -> []
         | Some m -> List.concat_map (fun (_, es) ->
             List.map (fun (e : Lsp.Types.TextEdit.t) -> e.newText) es) m
       in
       let joined = String.concat "|" texts in
       Alcotest.(check bool) "edit uses `: T` colon form" true (has joined ": Int");
       Alcotest.(check bool) "edit does NOT use the invalid `->` form" false
         (has joined "->");
       (* Round-trip: applying the edit must yield source that actually parses
          (the `-> T` form would be a parse error and never reach this). *)
       let te =
         match edit.changes with
         | Some ((_, (te :: _)) :: _) -> te
         | _ -> Alcotest.fail "expected a text edit" in
       let offset_of s ln ch =
         let i = ref 0 and l = ref 0 and n = String.length s in
         while !l < ln && !i < n do (if s.[!i] = '\n' then incr l); incr i done;
         !i + ch in
       let s0 = offset_of src te.range.start.line te.range.start.character in
       let patched =
         String.sub src 0 s0 ^ te.newText
         ^ String.sub src s0 (String.length src - s0) in
       let a2 = analyse patched in
       Alcotest.(check bool) "annotated source parses (fn in def_map)" true
         (Hashtbl.mem a2.An.def_map "double");
       Alcotest.(check int) "annotated source has no error diagnostics" 0
         (List.length (List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
              d.severity = Some Lsp.Types.DiagnosticSeverity.Error) a2.An.diagnostics)))

(* ------------------------------------------------------------------ *)
(* 24b. Named-record nominal-name recovery in rendered types          *)
(* ------------------------------------------------------------------ *)

(** Hover on a fn returning a declared record renders the record's name,
    not the structural `{ … }` form. *)
let test_named_record_hover_shows_name () =
  let src = {|mod Test do
  type R = { a : Int, b : Int }
  fn mk(x : Int) do
    { a: x, b: x }
  end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "mk" in
  let r = Qy.hover a ~line ~utf16_char:col in
  match r.Qy.h_type with
  | None -> Alcotest.fail "expected a hover type for mk"
  | Some s ->
    Alcotest.(check bool) "hover renders record name R" true
      (s = "Int -> R");
    Alcotest.(check bool) "hover has no structural braces" true
      (not (String.contains s '{'))

(** "Add return type annotation" is offered for a fn returning a named
    record, and the inserted annotation uses the record name (no braces),
    so it parses as valid March. *)
let test_named_record_return_annotation_uses_name () =
  let src = {|mod Test do
  type R = { a : Int, b : Int }
  fn mk(x : Int) do
    { a: x, b: x }
  end
end|} in
  let a = analyse src in
  let (line, col) = pos_of src "mk" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let ret_act = List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      let t = String.lowercase_ascii ca.title in
      let n = String.length t and sn = 6 in
      let found = ref false in
      for i = 0 to n - sn do
        if String.sub t i sn = "return" then found := true
      done;
      !found
    ) acts in
  match ret_act with
  | None ->
    Alcotest.fail "expected return type annotation action for named-record return"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected edit"
     | Some edit ->
       let texts =
         match edit.changes with
         | None -> []
         | Some m -> List.concat_map (fun (_, edits) ->
             List.map (fun (e : Lsp.Types.TextEdit.t) -> e.newText) edits) m
       in
       let all = String.concat "" texts in
       let contains hay needle =
         let n = String.length hay and sn = String.length needle in
         let found = ref false in
         for i = 0 to n - sn do
           if String.sub hay i sn = needle then found := true
         done; !found
       in
       Alcotest.(check bool) "annotation uses record name R" true
         (contains all "R");
       Alcotest.(check bool) "annotation has no structural braces" true
         (not (String.contains all '{')))

(* ------------------------------------------------------------------ *)
(* 25. P1.7 — Function parameter type annotation                      *)
(* ------------------------------------------------------------------ *)

(** AnnFnParam site created for bare variable param (no type annotation). *)
let test_fn_param_annotation_site_created () =
  let src = {|
mod M do
  fn negate(x) do
    0 - x
  end
end
|} in
  let a = analyse src in
  let has_fn_param_site =
    List.exists (fun (site : An.annotation_site) ->
        site.An.as_kind = An.AnnFnParam
      ) a.An.annotation_sites
  in
  Alcotest.(check bool) "AnnFnParam site for unannotated param" true has_fn_param_site

(** "Add parameter type annotation" action offered when cursor on param name. *)
let test_fn_param_annotation_action_offered () =
  let src = {|
mod M do
  fn negate(x) do
    0 - x
  end
end
|} in
  let a = analyse src in
  (* "negate(x)" — pos_of gives position of 'n' in "negate".
     The param 'x' is at column of 'x' in "(x)". *)
  let (line, col) = pos_of src "(x)" in
  let col = col + 1 in  (* skip '(' to get to 'x' *)
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_param_annot =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let t = String.lowercase_ascii ca.title in
        let n = String.length t and sn = 9 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub t i sn = "parameter" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "param annotation action offered" true has_param_annot

(* ------------------------------------------------------------------ *)
(* 26. P1.7 — Batch annotation action                                 *)
(* ------------------------------------------------------------------ *)

(** Batch "Annotate all N unannotated bindings" offered when 2+ AnnLet sites. *)
let test_batch_annotation_offered_for_multiple_bindings () =
  let src = {|
mod M do
  fn f() do
    let a = 1
    let b = "hello"
    let c = true
    a
  end
end
|} in
  let a = analyse src in
  (* Cursor must be on the variable name 'a', not on 'let'.
     pos_of finds 'l' in "let a "; add 4 to reach 'a'. *)
  let (line, col) = pos_of src "let a" in
  let col = col + 4 in  (* skip "let " to reach 'a' *)
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_batch =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let t = String.lowercase_ascii ca.title in
        let n = String.length t and sn = 8 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub t i sn = "annotate" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "batch annotation offered" true has_batch

(** No batch action when only one unannotated binding. *)
let test_batch_annotation_not_offered_for_single_binding () =
  let src = {|
mod M do
  fn f() do
    let x = 42
    x + 1
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "let x" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let has_batch =
    List.exists (fun (ca : Lsp.Types.CodeAction.t) ->
        let t = String.lowercase_ascii ca.title in
        let n = String.length t and sn = 8 in
        let found = ref false in
        for i = 0 to n - sn do
          if String.sub t i sn = "annotate" then found := true
        done;
        !found
      ) acts
  in
  Alcotest.(check bool) "no batch action for single binding" false has_batch

(* ------------------------------------------------------------------ *)
(* 24. Code actions: naming convention fix (P2.8)                     *)
(* ------------------------------------------------------------------ *)

let test_naming_violation_camel_fn_detected () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "camelCase fn in naming_violations" true
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "myFunction")
       a.An.naming_violations)

let test_naming_violation_suggested_name () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  match List.find_opt
    (fun (nv : An.naming_violation) -> nv.nv_name = "myFunction")
    a.An.naming_violations
  with
  | None -> Alcotest.fail "expected naming violation for myFunction"
  | Some nv ->
    Alcotest.(check string) "suggested name is my_function" "my_function" nv.nv_suggested

let test_naming_violation_deeply_nested_detected () =
  (* Violations are detected inside nested mod blocks *)
  let src = {|
mod M do
  mod Inner do
    fn outerFn(x: Int): Int do
      x
    end
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "camelCase fn inside nested mod detected" true
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "outerFn")
       a.An.naming_violations)

let test_naming_violation_no_violation_for_snake_fn () =
  let src = {|
mod M do
  fn already_good(x: Int): Int do
    x
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "no naming violation for snake_case fn" false
    (List.exists (fun (nv : An.naming_violation) -> nv.nv_name = "already_good")
       a.An.naming_violations)

let test_naming_action_offered_for_camel_fn () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "myFunction" in
  let acts = An.code_actions_at a ~line ~character:col () in
  Alcotest.(check bool) "rename action offered for camelCase fn" true
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t >= 6 && String.sub t 0 6 = "Rename")
       acts)

let test_naming_action_edit_uses_snake_case () =
  let src = {|
mod M do
  fn myFunction(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "myFunction" in
  let acts = An.code_actions_at a ~line ~character:col () in
  let rename_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t >= 6 && String.sub t 0 6 = "Rename") acts in
  match rename_act with
  | None -> Alcotest.fail "no rename action found"
  | Some act ->
    let has_snake = match act.edit with
      | None -> false
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        List.exists (fun (e : Lsp.Types.TextEdit.t) ->
            e.newText = "my_function") edits
    in
    Alcotest.(check bool) "edit contains my_function" true has_snake

let test_naming_action_absent_for_snake_fn () =
  let src = {|
mod M do
  fn good_name(x: Int): Int do
    x
  end
end
|} in
  let a   = analyse src in
  let (line, col) = pos_of src "good_name" in
  let acts = An.code_actions_at a ~line ~character:col () in
  Alcotest.(check bool) "no rename action for already-snake fn" false
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t >= 6 && String.sub t 0 6 = "Rename")
       acts)

(* ------------------------------------------------------------------ *)
(* 25. Code actions: De Morgan's law (P3.10)                          *)
(* ------------------------------------------------------------------ *)

let test_demorgan_not_and_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!(a && b) detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `NegatedBinop "&&") a.An.demorgan_sites)

let test_demorgan_not_or_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a || b)
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!(a || b) detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `NegatedBinop "||") a.An.demorgan_sites)

let test_demorgan_pair_negs_detected () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !a && !b
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "!a && !b detected as De Morgan site" true
    (List.exists (fun (dm : An.demorgan_site) ->
         dm.dm_form = `PairOfNegs "&&") a.An.demorgan_sites)

let test_demorgan_action_offered_for_not_and () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!(a && b)" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  Alcotest.(check bool) "De Morgan action offered for !(a && b)" true
    (List.exists (fun (act : Lsp.Types.CodeAction.t) ->
         let t = act.title in
         String.length t > 10 && String.sub t 0 5 = "Apply")
       acts)

let test_demorgan_action_rewrite_not_and () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !(a && b)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!(a && b)" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  let dm_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t > 10 && String.sub t 0 5 = "Apply") acts in
  match dm_act with
  | None -> Alcotest.fail "no De Morgan action found"
  | Some act ->
    let new_text = match act.edit with
      | None -> ""
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        (match edits with e :: _ -> e.newText | [] -> "")
    in
    let contains_or =
      let n = String.length new_text in
      let found = ref false in
      for i = 0 to n - 2 do
        if new_text.[i] = '|' && new_text.[i + 1] = '|' then found := true
      done;
      !found
    in
    Alcotest.(check bool) "rewrite contains '||'" true
      (String.length new_text > 0 && contains_or)

let test_demorgan_action_rewrite_pair_negs () =
  let src = {|
mod M do
  fn check(a: Bool, b: Bool): Bool do
    !a && !b
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "!a && !b" in
  let acts = An.code_actions_at a ~line ~character:(col + 1) () in
  let dm_act = List.find_opt (fun (act : Lsp.Types.CodeAction.t) ->
      let t = act.title in
      String.length t > 10 && String.sub t 0 5 = "Apply") acts in
  match dm_act with
  | None -> Alcotest.fail "no De Morgan action found for !a && !b"
  | Some act ->
    let new_text = match act.edit with
      | None -> ""
      | Some we ->
        let edits = match we.changes with
          | None -> []
          | Some changes -> List.concat_map snd changes
        in
        (match edits with e :: _ -> e.newText | [] -> "")
    in
    Alcotest.(check bool) "rewrite is !(... || ...)" true
      (String.length new_text > 2 && new_text.[0] = '!')

