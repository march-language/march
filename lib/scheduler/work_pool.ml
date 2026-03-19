(** Work-stealing pool — Phase 2.
    Uses Chase-Lev deques with steal-half semantics.
    Requires Cap(WorkPool) capability for access.

    This module is a placeholder. The cooperative scheduler (Phase 1) is
    implemented first. Work-stealing will be added in a subsequent task. *)

type t = {
  mutable active : bool;
}

let create () : t = { active = false }

let is_active (pool : t) : bool = pool.active
