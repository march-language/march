(* Synthesized actor-handler fn name → declaring module.

   A handler lowered from `actor Weeble ... on Zorp` is named `Weeble_Zorp` —
   BARE, never qualified by its declaring module, and that spelling is
   load-bearing twice over: the HCR manifest format asserts it, and
   `spawn(Weeble)` emits `_Weeble_spawn` from the actor's short name. So the
   name cannot carry the module, and any analysis that derives ownership from
   the name ([Cap_attrib.attribute]'s [owner_of]) resolves it to the entry
   module. For a handler declared in a nested module that is WRONG: its
   capability use was charged to the entry module, the nested module's own
   `needs` could not satisfy the now-default ceiling, and a future
   per-dependency capability budget would bill an actor-using dependency's
   IO to the app.

   This table is the ownership channel the name cannot be: lowering records
   each synthesized handler name with the module prefix it was lowered under,
   and [Cap_attrib] consults it before the entry-module fallback.

   Process-global and reset at the top of [Lower.lower_module], the same
   lifecycle as [Lower]'s other cross-pass tables (`_module_aliases` etc.) —
   one compilation's handlers must not leak into the next in a long-lived
   process (tests, REPL, LSP). [register] uses replace: the same handler name
   re-lowered in the same run (REPL redefinition) takes the latest owner.

   Names are recorded exactly as synthesized. Handlers are monomorphic (an
   actor's state and message payloads are concrete), so the name survives
   mono/defun unchanged; if a pass ever starts suffixing them, the lookup
   misses and attribution falls back to the entry module — the pre-fix
   behavior, caught by the `nested actor handler` ceiling tests rather than
   silently misattributed to a THIRD module. *)

let tbl : (string, string) Hashtbl.t = Hashtbl.create 16

let reset () = Hashtbl.reset tbl

(** [register ~fn_name ~owner] — [owner] is the dotted module path with no
    trailing dot ("Inner", "Outer.Deep"); "" (the entry module) need not be
    registered, the fallback already lands there. *)
let register ~fn_name ~owner =
  (if Sys.getenv_opt "MARCH_DEBUG_HANDLER_OWNER" <> None then
     Printf.eprintf "HANDLER_OWNER register %s -> %s\n%!" fn_name owner);
  if owner <> "" then Hashtbl.replace tbl fn_name owner

let owner_of (fn_name : string) : string option =
  let r = Hashtbl.find_opt tbl fn_name in
  (if Sys.getenv_opt "MARCH_DEBUG_HANDLER_OWNER" <> None then
     Printf.eprintf "HANDLER_OWNER lookup %s -> %s\n%!" fn_name
       (Option.value ~default:"<none>" r));
  r
