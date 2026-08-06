# `get_cap` bypasses R2: a module with no grant can obtain `Cap(IO)`

Found by the R8 audit, 2026-08-06 (`specs/2026-08-06-r8-runtime-hatch-audit.md`).

- [ ] **`get_cap(self())` yields the root capability, defeating R2.** Measured
  against `40191c2a`; `--check` exit 0, no diagnostic:

  ```march
  mod PidRoot do
    needs IO
    pfn wants_root(r : Cap(IO)) : Int do 1 end
    fn main() do                       -- no parameter: this module is granted NOTHING
      match get_cap(self()) do
        Some(c) -> println(int_to_string(wants_root(c)))
        None    -> println("none")
      end
    end
  end
  ```

  No actor need be declared — `self()` is enough. R2's entire content is that
  the root is *granted to `main`, not taken*; here it is taken from a process
  id the module already has.

  **Mechanism.** `get_cap : Pid(a) -> Option(Cap(a))` (`typecheck.ml`, the
  builtin table). `a` is unconstrained, so it unifies with `IO` at the use site
  and `Cap(a)` becomes `Cap(IO)`. Structurally identical to `from_json`'s free
  result variable that R3 closed: a capability-producing builtin whose result
  type nothing pins.

  **Not caused by R4a** — the probe never calls `cap_narrow`, and a pre-R4a
  control accepts the equivalent program.

  **Why it matters beyond the hole itself.** It makes a shipped claim false.
  `specs/2026-08-04-provable-sandbox-design.md` §5 says a capability "can only
  be received"; with this reachable, it cannot be. The §5 wording was
  deliberately NOT edited when this was found, because the right sentence
  depends on which fix lands.

  **Options, roughly in increasing severity:**
  1. Constrain `get_cap`'s result so `a` cannot unify with an IO-lattice
     capability. `Pid(a)`'s `a` is an actor STATE type; an IO capability there
     is meaningless, so this may cost nothing real. Cheapest, and probably
     right.
  2. Record `get_cap` sites and sweep them like `mint_cap`/`cap_narrow`,
     rejecting an IO-lattice result. More machinery, but consistent with how
     every other capability-producing builtin is now gated.
  3. Remove `get_cap`. Only if (1) turns out to break its legitimate
     process-capability use.

  Whichever lands needs the same shape of witness as R3's `t143`: a case where
  the result type is pinned by LATER unification, since an eager check reads an
  unsolved variable and passes.

  Related: `revoke_cap : Cap(a) -> Atom` and `is_cap_valid : Cap(a) -> Bool`
  take a `Cap(a)` with the same unconstrained `a` — they consume rather than
  produce, so they are not forges, but they should be checked for the same
  IO/process confusion when this is fixed.
