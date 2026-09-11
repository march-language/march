(** Repr — the representation type, re-exported from [Kind].

    Every classifier that used to live here is in [Kind]
    (specs/2026-09-10-type-kinds-design.md), and the process-global unboxed
    registry this module carried between the Milestone-3 unboxing work and
    the type-kinds refactor is gone: a [Kind.table] is a value built once per
    module by [Contract_pipeline] and threaded to every pass and to the
    emitter.  This re-export exists so [Repr.Boxed] &c. keep reading naturally
    at the remaining pattern-match sites; new code should say [Kind.Boxed]. *)

type repr = Kind.repr =
  | Boxed
  | Newtype of Tir.ty
  | Niche   of { payload : Tir.ty; tagged : bool }
  | Unboxed of { ctor : string; fields : Tir.ty list }
