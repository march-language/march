(* Every builtin with a heap parameter has an explicit borrow classification.

   Perceus asks [Borrow.is_borrowed] whether a builtin consumes each argument,
   keyed by the builtin's TIR name, and an unlisted name defaults to OWNED.
   For a builtin whose C implementation only reads the argument that default
   is a leak on every call: `==` on a fresh String leaked one object per
   comparison, `==` on a two-element list six, and `string_length` leaked
   because it was listed under its C name, which the lookup never consults
   (test/native/builtin_borrow_leak_probe.march measures those).

   So the default is not allowed to be silent any more.  Each
   [in_is_builtin] row of [Llvm_builtins.builtins] whose declared signature
   takes a [ptr] must be named, under its TIR name, in exactly one of
   [Borrow.extern_borrow_table], [Borrow.all_args_borrowed_builtins] or
   [Borrow.extern_owned_builtins]. *)

let has_ptr_param (sig_ : string) =
  match String.index_opt sig_ '(' , String.rindex_opt sig_ ')' with
  | Some l, Some r when r > l ->
    String.sub sig_ (l + 1) (r - l - 1)
    |> String.split_on_char ','
    |> List.exists (fun p ->
        let p = String.trim p in
        String.length p >= 3 && String.sub p 0 3 = "ptr")
  | _ -> false

let classifications name =
  List.filter (fun x -> x)
    [ List.mem_assoc name March_tir.Borrow.extern_borrow_table;
      List.mem name March_tir.Borrow.all_args_borrowed_builtins;
      List.mem name March_tir.Borrow.extern_owned_builtins ]
  |> List.length

let heap_param_builtins () =
  List.filter_map
    (fun (b : March_tir.Llvm_builtins.builtin) ->
      match b.March_tir.Llvm_builtins.declare_sig with
      | Some s when b.March_tir.Llvm_builtins.in_is_builtin && has_ptr_param s ->
        Some b.March_tir.Llvm_builtins.march_name
      | _ -> None)
    March_tir.Llvm_builtins.builtins
  |> List.sort_uniq compare

let test_every_heap_builtin_classified () =
  let names = heap_param_builtins () in
  (* Non-vacuity: the table walk must actually find the builtins this guard
     exists for, or a change to the row shape would make it pass trivially. *)
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " is seen by the walk") true (List.mem n names))
    [ "string_length"; "file_exists"; "send" ];
  let unclassified = List.filter (fun n -> classifications n = 0) names in
  if unclassified <> [] then
    Alcotest.failf
      "%d builtin(s) take a heap argument but have no borrow classification: %s\n\
       Add each to Borrow.extern_borrow_table if its C implementation only reads \
       the argument (and nothing passes it an unowned reference), or to \
       Borrow.extern_owned_builtins if it stores or frees it."
      (List.length unclassified) (String.concat ", " unclassified)

let test_no_double_classification () =
  let both = List.filter (fun n -> classifications n > 1) (heap_param_builtins ()) in
  Alcotest.(check (list string)) "no builtin is both borrowed and owned" [] both

let test_comparisons_borrow () =
  List.iter (fun op ->
      Alcotest.(check bool) (op ^ " borrows its left operand") true
        (March_tir.Borrow.is_extern_borrowed op 0);
      Alcotest.(check bool) (op ^ " borrows its right operand") true
        (March_tir.Borrow.is_extern_borrowed op 1))
    [ "=="; "!="; "<"; "<="; ">"; ">=" ];
  Alcotest.(check bool) "string_length is keyed by its TIR name" true
    (March_tir.Borrow.is_extern_borrowed "string_length" 0)

let tests =
  [ Alcotest.test_case "every heap-param builtin is classified" `Quick
      test_every_heap_builtin_classified;
    Alcotest.test_case "no builtin classified twice" `Quick test_no_double_classification;
    Alcotest.test_case "comparison operators borrow" `Quick test_comparisons_borrow ]
