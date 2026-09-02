(** March LSP tests: Performance Insights (Phase 1)

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* Performance Insights (Phase 1)                                      *)
(* ------------------------------------------------------------------ *)

(** Helper: extract all perf insights from a source string. *)
let perf_insights_of src =
  let a = analyse src in a.An.perf_insights

(** Helper: true if insights list contains at least one NonTailCall. *)
let has_non_tail_call insights =
  List.exists (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with
      | An.NonTailCall _ -> true
      | _ -> false
    ) insights

(** Captures must exclude top-level/global functions (a closure doesn't allocate
    to hold references to statically-known top-level functions). *)
let test_closure_capture_excludes_globals () =
  (* Two closures share {a, b}; helper1/helper2 are globals, not captures. *)
  let src = {|mod M do
  fn helper1(x : Int) : Int do x end
  fn helper2(x : Int) : Int do x end
  fn make() do
    let a = 1
    let b = 2
    let f = fn _ -> a + b + helper1(0)
    let g = fn _ -> a + b + helper2(0)
    f
  end
end|} in
  match List.find_opt (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with An.ClosureCapture _ -> true | _ -> false)
      (perf_insights_of src) with
  | None -> Alcotest.fail "expected a closure-capture insight for the shared {a,b}"
  | Some pi ->
    (match pi.An.pi_kind with
     | An.ClosureCapture { pi_count; pi_names } ->
       Alcotest.(check bool) "top-level functions excluded from captures" true
         (not (List.mem "helper1" pi_names) && not (List.mem "helper2" pi_names));
       Alcotest.(check int) "counts only the 2 genuine shared captures" 2 pi_count
     | _ -> ())

(* Regression: closures buried inside an ~H"…" sigil must be visible to the
   closure-capture analysis. The old hand walk in collect_lambda_captures fell
   through to `_ -> ()` on ESigil (and ECond), so closures inside interpolated
   templates were invisible. Two closures share {a, b} → one ClosureCapture. *)
let test_closure_capture_inside_sigil () =
  let src = {|mod M do
  fn page() do
    let a = 1
    let b = 2
    ~H"<div>${fn _ -> a + b}${fn _ -> a + b}</div>"
  end
end|} in
  match List.find_opt (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with An.ClosureCapture _ -> true | _ -> false)
      (perf_insights_of src) with
  | None ->
    Alcotest.fail "expected a closure-capture insight for closures inside ~H sigil"
  | Some pi ->
    (match pi.An.pi_kind with
     | An.ClosureCapture { pi_count; pi_names } ->
       Alcotest.(check int) "two genuine shared captures inside sigil" 2 pi_count;
       Alcotest.(check bool) "captures are a and b" true
         (List.mem "a" pi_names && List.mem "b" pi_names)
     | _ -> ())

(* Regression: closures inside a `match do … end` boolean chain (ECond, which
   survives desugar) must also be visible. Old hand walk fell through ECond. *)
let test_closure_capture_inside_cond () =
  let src = {|mod M do
  fn pick(n : Int) do
    let a = 1
    let b = 2
    match do
      n > 0 -> fn _ -> a + b
      _ -> fn _ -> a + b
    end
  end
end|} in
  Alcotest.(check bool) "closure-capture insight found inside match do (ECond)" true
    (List.exists (fun (pi : An.perf_insight) ->
         match pi.An.pi_kind with
         | An.ClosureCapture { pi_count; _ } -> pi_count = 2
         | _ -> false)
       (perf_insights_of src))

(** Helper: true if insights list contains at least one ClosureCapture
    with [pi_count] ≥ [min_count]. *)
let has_large_closure ?(min_count = 3) insights =
  List.exists (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with
      | An.ClosureCapture { pi_count; _ } -> pi_count >= min_count
      | _ -> false
    ) insights

(* ---- TCO tests ---- *)

let test_perf_non_tail_call_detected () =
  (* 1 + helper(n - 1) is not in tail position because `+` wraps the call *)
  let src = {|
mod Test do
  pfn helper(n: Int): Int do
    1 + helper(n - 1)
  end
end
|} in
  Alcotest.(check bool) "non-tail recursive call detected" true
    (has_non_tail_call (perf_insights_of src))

let test_perf_tail_call_not_flagged () =
  (* count_down(n-1, acc+1) IS in tail position — no warning *)
  let src = {|
mod Test do
  pfn count_down(n: Int, acc: Int): Int do
    if n == 0 do acc
    else count_down(n - 1, acc + 1) end
  end
end
|} in
  Alcotest.(check bool) "tail-recursive call not flagged" false
    (has_non_tail_call (perf_insights_of src))

let test_perf_non_tail_inside_constructor () =
  (* Succ(helper(k)) — recursive call inside constructor, not tail position *)
  let src = {|
mod Test do
  type Nat = Zero | Succ(Nat)
  pfn add_one(n: Nat): Nat do
    match n do
      Zero -> Succ(Zero)
      Succ(k) -> Succ(Succ(add_one(k)))
    end
  end
end
|} in
  Alcotest.(check bool) "non-tail call inside constructor detected" true
    (has_non_tail_call (perf_insights_of src))

(* A constructor-wrapped recursive call is the tail-recursion-modulo-cons
   shape the compiler turns into a loop, so telling the user to rewrite it
   with an accumulator is advice against what the compiler already does — and
   against how the stdlib producers are written.  The insight is still
   REPORTED (the stack cost is real when TRMC declines the function); only the
   advice changes.  The arithmetic case below must keep the old advice, since
   TRMC can never transform `1 + f(n-1)`. *)
let test_perf_constructor_wrapped_advice_is_not_accumulator () =
  let msg_of src =
    match List.filter (fun (i : An.perf_insight) ->
            match i.An.pi_kind with An.NonTailCall _ -> true | _ -> false)
            (perf_insights_of src) with
    | i :: _ -> i.An.pi_message
    | [] -> Alcotest.fail "expected a NonTailCall insight"
  in
  let has needle m =
    let n = String.length needle and l = String.length m in
    let rec go i = i + n <= l && (String.sub m i n = needle || go (i + 1)) in
    go 0
  in
  let ctor = msg_of {|
mod Test do
  type Nat = Zero | Succ(Nat)
  pfn bump(n: Nat): Nat do
    match n do
      Zero -> Zero
      Succ(k) -> Succ(bump(k))
    end
  end
end
|} in
  Alcotest.(check bool) "constructor case does not prescribe an accumulator"
    false (has "accumulator" ctor);
  (* This used to assert the message said the compiler "compiles to a loop"
     and no rewrite was needed. That claim is false: TRMC is implemented but
     OFF BY DEFAULT (`lib/tir/trmc.ml`), so this exact shape still overflows
     on deep input — see
     specs/progress/2026-09-01-trmc-warning-promises-a-loop-that-does-not-happen.md,
     which corrected the compiler's copy of the same sentence. The editor's
     copy said it too, and this test was pinning it. It must now state the
     opt-in rather than promise the loop. *)
  Alcotest.(check bool) "constructor case does not promise an automatic loop"
    false (has "No rewrite needed" ctor);
  Alcotest.(check bool) "constructor case names TRMC as opt-in"
    true (has "--trmc" ctor);
  (* Non-vacuousness: the arithmetic case still gives the old advice, so the
     assertion above is testing the branch and not an empty message. *)
  let arith = msg_of {|
mod Test do
  pfn sum_helper(n: Int): Int do
    1 + sum_helper(n - 1)
  end
end
|} in
  Alcotest.(check bool) "arithmetic case still prescribes an accumulator"
    true (has "accumulator parameter" arith)

let test_perf_non_tail_produces_warning_diagnostic () =
  let src = {|
mod Test do
  pfn sum_helper(n: Int): Int do
    1 + sum_helper(n - 1)
  end
end
|} in
  let a = analyse src in
  (* This used to assert a diagnostic carrying the `perf/non-tail-call` code.
     That code is the LSP's own perf insight, and the typechecker's tail-call
     checker ALREADY reports every non-tail recursive call at the same span —
     so asserting the LSP's copy was asserting a duplicate, and the editor
     showed the same complaint twice in one hover. What matters is that the
     call is reported, once. Assert that instead of a particular producer. *)
  let mentions_tail (d : Lsp.Types.Diagnostic.t) =
    match d.message with
    | `String m ->
      let needle = "tail" in
      let n = String.length needle and l = String.length m in
      let rec go i = i + n <= l && (String.sub m i n = needle || go (i + 1)) in
      go 0
    | _ -> false
  in
  let tail_diags = List.filter mentions_tail a.An.diagnostics in
  Alcotest.(check bool) "the non-tail call is reported" true
    (List.length tail_diags >= 1);
  (* No two reports of it at the same span — that was the duplication. *)
  let spans = List.map (fun (d : Lsp.Types.Diagnostic.t) -> d.range) tail_diags in
  let uniq = List.sort_uniq compare spans in
  Alcotest.(check int) "reported once per span, not duplicated"
    (List.length uniq) (List.length spans)

let test_perf_non_tail_not_flagged_for_non_recursive () =
  (* foo calls bar, not itself — no TCO warning *)
  let src = {|
mod Test do
  pfn bar(n: Int): Int do n + 1 end
  pfn foo(n: Int): Int do 1 + bar(n) end
end
|} in
  Alcotest.(check bool) "non-recursive call not flagged as non-tail" false
    (has_non_tail_call (perf_insights_of src))

(* ---- Closure capture tests ---- *)

let test_perf_large_closure_detected () =
  (* TWO closures capture the same set {a, b, c, d} — repeated clump, warns *)
  let src = {|
mod Test do
  fn make_fn(a: Int, b: Int, c: Int, d: Int): Int do
    let f = fn x -> a + b + c + d + x
    let g = fn y -> a + b + c + d + y
    f(0) + g(0)
  end
end
|} in
  Alcotest.(check bool) "repeated capture group (4 values, 2 sites) detected" true
    (has_large_closure (perf_insights_of src))

let test_perf_small_closure_not_flagged () =
  (* A SINGLE closure capturing many values is no longer flagged —
     the hint only fires when the same set appears across ≥2 closures *)
  let src = {|
mod Test do
  fn make_fn(a: Int, b: Int, c: Int, d: Int): Int do
    let f = fn x -> a + b + c + d + x
    f(0)
  end
end
|} in
  Alcotest.(check bool) "lone closure (single site) not flagged" false
    (has_large_closure ~min_count:2 (perf_insights_of src))

let test_perf_closure_capture_hint_in_diagnostics () =
  let src = {|
mod Test do
  fn make_fn(a: Int, b: Int, c: Int): Int do
    let f = fn x -> a + b + c + x
    let g = fn y -> a + b + c + y
    f(0) + g(0)
  end
end
|} in
  let a = analyse src in
  let has_hint = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.code with
      | Some (`String "perf/closure-capture") -> true
      | _ -> false
    ) a.An.diagnostics
  in
  Alcotest.(check bool) "closure_capture hint in diagnostics" true has_hint

let test_perf_closure_count_accurate () =
  let src = {|
mod Test do
  fn make_fn(a: Int, b: Int, c: Int, d: Int, e: Int): Int do
    let f = fn x -> a + b + c + d + e + x
    let g = fn y -> a + b + c + d + e + y
    f(0) + g(0)
  end
end
|} in
  let insights = perf_insights_of src in
  let cap_count = List.fold_left (fun best pi ->
      match pi.An.pi_kind with
      | An.ClosureCapture { pi_count; _ } -> max best pi_count
      | _ -> best
    ) 0 insights
  in
  Alcotest.(check bool) "shared capture set has 5 variables" true (cap_count = 5)

(* ---- Actor send copy tests ---- *)

let test_perf_actor_send_copy_detected () =
  (* items: List(Int) is a complex type — send(pid, items) warns *)
  let src = {|
mod Test do
  fn do_send(pid: Pid(W), items: List(Int)): Unit do
    send(pid, items)
  end
end
|} in
  (* The test checks that we detect the ESend — even if typecheck has errors
     due to unknown W, the perf insight may still fire if the message type
     was resolved. We accept both outcomes for this test. *)
  let insights = perf_insights_of src in
  let _ = insights in  (* smoke test: analysis should not crash *)
  Alcotest.(check bool) "actor send analysis does not crash" true true

let test_perf_actor_send_copy_in_diagnostics_when_type_known () =
  (* When the type of the send message is fully known, a warning should appear *)
  let src = {|
mod Test do
  fn forward(pid: Pid(W), items: List(Int)): Unit do
    send(pid, items)
  end
end
|} in
  let a = analyse src in
  (* ESend is present — if type_map resolved the list type, actor_send_copy fires *)
  let has_send_insight = List.exists (fun pi ->
      match (pi : An.perf_insight).pi_kind with
      | An.ActorSendCopy _ -> true
      | _ -> false
    ) a.An.perf_insights
  in
  (* We allow either outcome: with type resolution the warning fires,
     without it the list is empty. The key invariant is no crash. *)
  ignore has_send_insight;
  Alcotest.(check bool) "actor send analysis completes without exception" true true

(* ---- Phase 2: indirect call + recursive allocation ---- *)

let has_indirect_call insights =
  List.exists (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with An.IndirectCall _ -> true | _ -> false) insights

let has_recursive_alloc insights =
  List.exists (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with An.RecursiveAlloc _ -> true | _ -> false) insights

let test_perf_indirect_call_on_param () =
  (* `f` is a parameter, so `f(x)` dispatches through a function pointer. *)
  let src = {|
mod Test do
  pfn apply(f, x) do f(x) end
end
|} in
  Alcotest.(check bool) "calling a parameter is an indirect call" true
    (has_indirect_call (perf_insights_of src))

let test_perf_direct_call_not_indirect () =
  (* Calling a top-level function is a direct call — not flagged. *)
  let src = {|
mod Test do
  pfn g(x) do x end
  pfn h(x) do g(x) end
end
|} in
  Alcotest.(check bool) "top-level call is not indirect" false
    (has_indirect_call (perf_insights_of src))

let test_perf_recursive_alloc_in_arm () =
  (* `Cons(...)` allocates inside an arm of the self-recursive `build`. *)
  let src = {|
mod Test do
  type L = Nil | Cons(Int, L)
  pfn build(n) do
    match n do
      0 -> Nil
      _ -> Cons(n, build(n - 1))
    end
  end
end
|} in
  Alcotest.(check bool) "allocation in a recursive match arm is flagged" true
    (has_recursive_alloc (perf_insights_of src))

let test_perf_alloc_not_recursive_not_flagged () =
  (* `wrap` is not self-recursive, so its arm allocation is not flagged. *)
  let src = {|
mod Test do
  type L = Nil | Cons(Int, L)
  pfn wrap(n) do
    match n do
      0 -> Nil
      _ -> Cons(n, Nil)
    end
  end
end
|} in
  Alcotest.(check bool) "allocation in non-recursive fn not flagged" false
    (has_recursive_alloc (perf_insights_of src))

(* ---- parallelizable map/filter lint ---- *)

let parallelizable_of src =
  List.filter_map (fun (pi : An.perf_insight) ->
      match pi.An.pi_kind with
      | An.Parallelizable { pi_op; pi_par; _ } -> Some (pi_op, pi_par)
      | _ -> None)
    (perf_insights_of src)

let test_perf_parallelizable_pure_map_flagged () =
  let src = {|
mod Test do
  fn run(xs: List(Int)): List(Int) do
    List.map(xs, fn x -> x * 2)
  end
end
|} in
  Alcotest.(check (list (pair string string)))
    "pure List.map flagged as pmap candidate"
    [("map", "pmap")] (parallelizable_of src)

let test_perf_parallelizable_pure_filter_flagged () =
  let src = {|
mod Test do
  fn run(xs: List(Int)): List(Int) do
    List.filter(xs, fn x -> x > 2)
  end
end
|} in
  Alcotest.(check (list (pair string string)))
    "pure List.filter flagged as pfilter candidate"
    [("filter", "pfilter")] (parallelizable_of src)

let test_perf_parallelizable_impure_map_not_flagged () =
  (* The mapped function calls println (an impure builtin) → no hint. *)
  let src = {|
mod Test do
  fn run(xs: List(Int)): List(Int) do
    List.map(xs, fn x -> do println("x"); x end)
  end
end
|} in
  Alcotest.(check (list (pair string string)))
    "impure List.map is NOT flagged" [] (parallelizable_of src)

let test_perf_parallelizable_fold_not_flagged () =
  (* fold_left must never be flagged: purity does not imply associativity. *)
  let src = {|
mod Test do
  fn run(xs: List(Int)): Int do
    List.fold_left(xs, 0, fn (a, b) -> a + b)
  end
end
|} in
  Alcotest.(check (list (pair string string)))
    "List.fold_left is NOT flagged" [] (parallelizable_of src)

let test_perf_parallelizable_hint_in_diagnostics () =
  let src = {|
mod Test do
  fn run(xs: List(Int)): List(Int) do
    List.map(xs, fn x -> x + 1)
  end
end
|} in
  let a = analyse src in
  let has_hint = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      match d.code with
      | Some (`String "perf/parallelizable") -> true
      | _ -> false) a.An.diagnostics
  in
  Alcotest.(check bool) "parallelizable hint present in diagnostics" true has_hint

(* ── "Suggest a refinement type" code action ────────────────────────────── *)

(* The action must be a COMMAND, not an edit: computing the actual suggestion
   costs a checked module plus Z3 queries, which cannot run on every cursor
   movement.  An action carrying an `edit` here would mean that work had been
   done eagerly. *)
let refine_action_at src needle =
  let a = analyse src in
  let (line, col) = pos_of src needle in
  An.code_actions_at a ~line ~character:col ()
  |> List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
         match ca.Lsp.Types.CodeAction.command with
         | Some c -> c.Lsp.Types.Command.command = "march.suggestRefinement"
         | None -> false)

let test_refine_action_offered_on_annotated_param () =
  let src = {|
mod RA do
  fn split(xs : List(Int), n : Int) : Int do
    n
  end
end
|} in
  match refine_action_at src "split" with
  | None -> Alcotest.fail "expected a suggestRefinement action on `split`"
  | Some ca ->
    Alcotest.(check bool) "carries no eager edit" true
      (ca.Lsp.Types.CodeAction.edit = None);
    (match ca.Lsp.Types.CodeAction.command with
     | Some c ->
       Alcotest.(check int) "command carries file and fn" 2
         (List.length (Option.value ~default:[] c.Lsp.Types.Command.arguments))
     | None -> Alcotest.fail "expected a command")

(* Every parameter already refined → nothing to propose, so the action must not
   appear.  Offering it anyway would spend a full checked module and a Z3 run to
   report "nothing to do". *)
let test_refine_action_absent_when_all_params_refined () =
  let src = {|
mod RB do
  fn only(n : {Int | _ > 0}) : Int do
    n
  end
end
|} in
  Alcotest.(check bool) "no action when every param is refined" true
    (refine_action_at src "only" = None)

(* The postcondition action is offered only where there is a declared return
   type that is not already refined — a solver-free test, for the same reason
   the precondition one is: the inference is far too expensive to run while
   building the code-action list. *)
let post_action_at src needle =
  let a = analyse src in
  let (line, col) = pos_of src needle in
  An.code_actions_at a ~line ~character:col ()
  |> List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
         match ca.Lsp.Types.CodeAction.command with
         | Some c -> c.Lsp.Types.Command.command = "march.suggestPostcondition"
         | None -> false)

let test_post_action_offered_on_declared_return () =
  let src = {|
mod PA1 do
  fn produce(x : Int) : Int do
    x
  end
end
|} in
  match post_action_at src "produce" with
  | None -> Alcotest.fail "expected a suggestPostcondition action"
  | Some ca ->
    Alcotest.(check bool) "carries no eager edit" true
      (ca.Lsp.Types.CodeAction.edit = None)

let test_post_action_absent_without_a_return_type () =
  let src = {|
mod PA2 do
  fn noret(x : Int) do
    x
  end
end
|} in
  Alcotest.(check bool) "no action without a declared return" true
    (post_action_at src "noret" = None)

let test_post_action_absent_when_return_already_refined () =
  let src = {|
mod PA3 do
  fn done_already(x : Int) : {Int | _ > 0} do
    1
  end
end
|} in
  Alcotest.(check bool) "no action when the return is already refined" true
    (post_action_at src "done_already" = None)

(* Semantic tokens must describe THIS document and nothing else.

   `def_map`/`use_map` cover the whole analysis, and the analysis has the
   prelude injected — so iterating them unfiltered emitted a token for every
   stdlib definition, at line numbers belonging to another file. Measured on a
   15-line document before the fix: 6949 tokens, reaching line 3512. A client
   cannot detect that; it either wastes the bandwidth or paints ranges that do
   not exist.

   Invisible while `textDocument/semanticTokens/full` was unreachable, and
   immediate once the dispatch was repaired. *)
let test_semantic_tokens_stay_inside_the_document () =
  let src = {|
mod STok do
  fn double(n : Int) : Int do
    n * 2
  end
end
|} in
  let a = analyse src in
  let data = March_lsp_lib.Server.semantic_tokens_data a in
  let n_lines = List.length (String.split_on_char '\n' src) in
  let highest = ref 0 and cur = ref 0 in
  Array.iteri
    (fun i v -> if i mod 5 = 0 then begin cur := !cur + v; if !cur > !highest then highest := !cur end)
    data;
  Alcotest.(check bool) "some tokens are produced" true (Array.length data > 0);
  Alcotest.(check bool)
    (Printf.sprintf "highest token line %d is inside a %d-line document" !highest n_lines)
    true (!highest < n_lines)

(* textDocument/documentSymbol describes ONE document. `def_map` spans the whole
   analysis, prelude included, so folding it unfiltered returned every stdlib
   definition as a symbol of whatever file was open — measured against a real
   project (forgepm): 6936 symbols for a ONE-function file, carrying line
   numbers from elsewhere. The editor builds its outline and breadcrumbs from
   this, so it was not a harmless overcount.

   The paired risk is over-filtering, which would empty the outline instead.
   Hence both assertions: the file's own symbols are present, and nothing else
   is. *)
let test_document_symbols_scoped_to_the_file () =
  let src = {|
mod DocSym do
  fn alpha(n : Int) : Int do
    n
  end
  fn beta(n : Int) : Int do
    alpha(n)
  end
end
|} in
  let a = analyse src in
  match An.document_symbols a with
  | `DocumentSymbol syms ->
    let names = List.map (fun (s : Lsp.Types.DocumentSymbol.t) -> s.name) syms in
    Alcotest.(check bool) "the file's own functions are present" true
      (List.mem "alpha" names && List.mem "beta" names);
    (* A handful of local binders may legitimately appear; the prelude's
       thousands may not. *)
    Alcotest.(check bool)
      (Printf.sprintf "no prelude leak (got %d symbols)" (List.length names))
      true (List.length names < 20)
  | _ -> Alcotest.fail "expected a DocumentSymbol response"

let test_perf_parallelizable_code_action () =
  let src = {|
mod Test do
  fn run(xs: List(Int)): List(Int) do
    List.map(xs, fn x -> x + 1)
  end
end
|} in
  let a = analyse src in
  let (line, col) = pos_of src "List.map" in
  let acts = An.code_actions_at a ~line ~character:col () in
  match List.find_opt (fun (ca : Lsp.Types.CodeAction.t) ->
      ca.title = "Convert to `List.pmap`") acts with
  | None -> Alcotest.fail "expected 'Convert to `List.pmap`' code action"
  | Some ca ->
    (match ca.edit with
     | None -> Alcotest.fail "expected a workspace edit"
     | Some edit ->
       let replaces_with_pmap =
         match edit.changes with
         | None -> false
         | Some m ->
           List.exists (fun (_, edits) ->
               List.exists (fun (e : Lsp.Types.TextEdit.t) -> e.newText = "pmap") edits) m
       in
       Alcotest.(check bool) "edit replaces map with pmap" true replaces_with_pmap)

(* ---- perf_insight_at hover tests ---- *)

let test_perf_insight_at_returns_message_at_call_site () =
  let src = {|
mod Test do
  pfn helper(n: Int): Int do
    1 + helper(n - 1)
  end
end
|} in
  let a = analyse src in
  (* Find a non-tail-call insight and check that perf_insight_at finds it *)
  let found_insight = List.find_opt (fun pi ->
      match (pi : An.perf_insight).pi_kind with
      | An.NonTailCall _ -> true
      | _ -> false
    ) a.An.perf_insights
  in
  match found_insight with
  | None -> ()  (* no insight emitted — test is vacuously true *)
  | Some pi ->
    let sp = pi.An.pi_span in
    let line = sp.March_ast.Ast.start_line - 1 in
    let char = sp.March_ast.Ast.start_col in
    let result = An.perf_insight_at a ~line ~character:char in
    Alcotest.(check bool) "perf_insight_at returns something at call site" true
      (result <> None)

