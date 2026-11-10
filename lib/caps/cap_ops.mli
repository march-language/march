(** Which capability builtins are capability OPERATIONS (checked at run time
    through [Authority.check]), which are USES of something already opened,
    and which are runtime-internal.  The ocap phase 1 classification
    (specs/plans/2026-11-10-ocap-p1-result-plan.md, Inventory), from §6 of
    specs/2026-11-10-object-capability-design.md: using a handle needs no
    authority, opening one does.

    Total over [builtin_cap_table] (lib/typecheck/typecheck_builtins.ml): the
    freshness test in test/test_cap_ops.ml fails on a capability builtin with
    no row, or a row naming no builtin. *)

type cls =
  | Checked of { entry : string list; gated : bool }
      (** A capability operation.  Every stdlib function that calls it must
          call [Authority.check] first (test/test_cap_check_coverage.ml).
          [entry] are the public stdlib functions a program calls instead,
          the first being what the stdlib-only gate suggests.  [gated] is
          whether user code may no longer call the builtin directly: false
          for builtins ocap phase 2 wraps in handle types and gates itself. *)
  | Use
      (** Operates on a value an earlier, checked operation produced (a
          socket, a table handle, an open process): needs no authority. *)
  | Internal
      (** Runtime plumbing called only from private stdlib functions; the
          authority behind it is checked where the feature starts. *)

val table : (string * cls) list
(** Keyed by builtin (March) name. *)

val classify : string -> cls option

val gated : (string * string list) list
(** The [Checked { gated = true }] rows: builtin name and entry points. *)
