(* Capability unforgeability (R3) and monotone attenuation (R4).

   The accept/reject corpus under specs/lang/types/ carries most of these
   checks, because it asserts diagnostic TEXT and reads as documentation.
   What it CANNOT express is the absence of a WARNING: check_types.sh only
   inspects exit status, so an accept file passes whether or not it also
   emitted noise.

   That gap matters here. Check B makes a capability named in a type
   declaration or a `let` annotation count as a USE of that capability. If it
   reported the use for the "is it declared?" question but not for the
   "declared but never used" question, then fixing the error from
   reject/t148 would just trade it for a warning — and a check that always
   leaves a diagnostic behind reads as broken whichever way you write the
   program. Only a test asserting SILENCE catches that, so those live here.

   See specs/2026-08-05-cap-unforgeability-design.md. *)

open Test_helpers

let warnings_mentioning ctx needle =
  List.filter (fun d ->
      d.March_errors.Errors.severity = March_errors.Errors.Warning
      && (try
            ignore (Str.search_forward (Str.regexp_string needle)
                      d.March_errors.Errors.message 0);
            true
          with Not_found -> false))
    (March_errors.Errors.sorted ctx)

(* ── Check B: the new positions count as USES ─────────────────────────── *)

(* A capability named only in a type declaration, with a covering `needs`.
   Must be silent in both directions: no "not declared in needs" error (the
   declaration covers it) and no "declared but never used" warning (the field
   IS the use). Before Check B the field was invisible to both questions, so
   this module would have warned that IO.FileWrite was declared and unused. *)
let test_type_decl_position_counts_as_a_use () =
  let ctx = typecheck {|mod DeclUse do
  needs IO.Console
  needs IO.FileWrite

  type Handle = { id : Int, tok : Cap(IO.FileWrite) }

  fn main() do
    println("declared and used")
  end
end|} in
  Alcotest.(check bool) "covering needs: no error" false (has_errors ctx);
  Alcotest.(check int)
    "capability in a type declaration is a use, so no unused-needs warning"
    0 (List.length (warnings_mentioning ctx "IO.FileWrite"))

(* Same requirement for an annotation inside a BODY (reject/t151's shape),
   which is a different walk (cap_annots_in_expr, over expressions) from the
   type-declaration one.

   A lambda parameter, not a `let` annotation, and the choice is forced. R2
   (2026-08-05) removed the ambient `root_cap`, so obtaining a
   Cap(IO.FileWrite) VALUE now requires narrowing from Cap(IO) — which means
   declaring `needs IO`, which subsumes IO.FileWrite and makes a separate
   IO.FileWrite declaration redundant, destroying the very thing this test
   measures. A lambda parameter names the capability without needing a value,
   so IO.FileWrite is declared, used exactly once, and used only in a body
   annotation. *)
let test_body_annotation_position_counts_as_a_use () =
  let ctx = typecheck {|mod AnnUse do
  needs IO.Console
  needs IO.FileWrite

  fn main() do
    let take = fn (w : Cap(IO.FileWrite)) -> 1
    println("declared and used")
  end
end|} in
  Alcotest.(check bool) "covering needs: no error" false (has_errors ctx);
  Alcotest.(check int)
    "capability in a body annotation is a use, so no unused-needs warning"
    0 (List.length (warnings_mentioning ctx "IO.FileWrite"))

(* ── Check A: derive rejection is a DESUGAR-time error ────────────────── *)

(* The corpus proves the message text. This proves the CHANNEL: the derive
   rejection is raised during desugar, not typecheck, so a driver that only
   inspects typecheck diagnostics would run a program whose codec was never
   generated. bin/main.ml threads a shared errors ctx through desugar_module
   and exits 1; desugar_has_errors mirrors that. *)
let test_derive_json_over_cap_is_a_desugar_error () =
  Alcotest.(check bool)
    "derive Json over a Cap-bearing type is rejected at desugar time"
    true
    (desugar_has_errors {|mod DeriveCap do
  needs IO
  type Loot = Loot(Cap(IO))
  derive Json for Loot
  fn main() do
    println("x")
  end
end|});
  Alcotest.(check bool)
    "derive Json over a cap-free type is not"
    false
    (desugar_has_errors {|mod DeriveClean do
  needs IO
  type Loot = Loot(Int)
  derive Json for Loot
  fn main() do
    println("x")
  end
end|})

(* ── R4: monotone attenuation, regression pin ─────────────────────────── *)

(* No production change accompanies these — attenuation is already monotone,
   enforced structurally through unification rather than by a lattice call
   (cap_narrow demands the PARENT Cap(IO) at its argument, so widening fails
   to unify). They are here because the subsumption direction was written
   backwards twice during the sandbox work and shipped once, and because the
   runtime march_cap_narrow is `return cap;` — deliberate erasure, since the
   gating is entirely compile-time. A property test over that runtime
   function would assert nothing; this pair is what actually holds the
   direction in place. *)
let test_attenuation_narrowing_is_accepted () =
  let ctx = typecheck {|mod Narrowing do
  needs IO

  fn main(cap : Cap(IO)) do
    let w : Cap(IO.FileWrite) = cap_narrow(cap)
    println("root narrows to a descendant")
  end
end|} in
  Alcotest.(check bool) "Cap(IO) -> Cap(IO.FileWrite) is accepted"
    false (has_errors ctx)

let test_attenuation_widening_is_rejected () =
  let ctx = typecheck {|mod Widening do
  needs IO

  pfn widen(c : Cap(IO.Console)) : Cap(IO.FileWrite) do
    cap_narrow(c)
  end

  fn main() do
    println("should not typecheck")
  end
end|} in
  Alcotest.(check bool)
    "Cap(IO.Console) -> Cap(IO.FileWrite) is rejected: a sibling is not a parent"
    true (has_errors ctx)

let tests =
  [ Alcotest.test_case "type-decl capability counts as a use" `Quick
      test_type_decl_position_counts_as_a_use;
    Alcotest.test_case "body-annotation capability counts as a use" `Quick
      test_body_annotation_position_counts_as_a_use;
    Alcotest.test_case "derive Json over Cap is a desugar error" `Quick
      test_derive_json_over_cap_is_a_desugar_error;
    Alcotest.test_case "attenuation: narrowing accepted" `Quick
      test_attenuation_narrowing_is_accepted;
    Alcotest.test_case "attenuation: widening rejected" `Quick
      test_attenuation_widening_is_rejected;
  ]
