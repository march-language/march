# Perceus releases a parent record before a field projected from it is used

**Found by:** the TIR verifier's RC-balance check (check 3, `--verify-tir-rc`), 2026-10-07.
**Severity:** compiled-only miscompile. The interpreter is correct. Compiled code reads freed
memory: wrong output, or a crash.

A field projected from a record (`let $t = d.f`) is held as a borrow of the parent, not as its own
reference. In three shapes, Perceus then releases the parent's last reference on a path where the
projection is still used afterwards. Each repro below prints different output interpreted and
compiled. They may need separate fixes; they are filed together because the verifier reports all
three the same way.

| Shape | Where it occurs in the stdlib or tests | Interpreted | Compiled |
|---|---|---|---|
| String `match` on a field, binder arm | `test/native/native_node_send_loopback.march` `dispatch_a`/`dispatch_b` | `unknown tag-12345` | `unknown ` (empty) |
| Nested projection, then the parent consumed by a call | `stdlib/topology.march` `offer_lines`, `drain_lines` | `fp fp-1000003` | `fp 2` |
| Record update from a `List.find` result | `stdlib/topology.march:785` (desired-role merge) | `1016893` | SIGTRAP, exit 133 |

The Topology lambdas are reached by every program that links the stdlib, which is why check 3 is
under its own switch and not under plain `--verify-tir`. When this is fixed, move check 3 under
`--verify-tir` (`Tir_verify.rc_enabled`), and update the red tests in `test/test_codegen.ml` that
pin these three verifier findings (search for `perceus-releases-parent`).

## 1. String match on a field (the case handoff drops the parent in the binder arm)

Final TIR for the binder arm: `_ -> __drop$R…(d); ++("unknown ", $t43606)`, where
`$t43606 = d.tag`.

```march
mod StrCase do
  needs IO.Console
  type D = { tag : String, n : Int }

  fn classify(d : D) : String do
    match d.tag do
      "known" ->
        let a = int_to_string(d.n) ++ "a" ++ int_to_string(d.n * 3)
        let b = a ++ int_to_string(d.n * 5) ++ a ++ int_to_string(d.n * 11)
        let c = b ++ a ++ int_to_string(string_byte_length(b))
        c ++ b ++ a
      other -> "unknown " ++ other
    end
  end

  fn go(i : Int, acc : Int) : Int do
    if i == 0 do acc
    else
      let d = { tag: "t" ++ int_to_string(i * 7919), n: i }
      let s = classify(d)
      let junk = "x" ++ int_to_string(i) ++ "yyyyyyyyyyyy"
      go(i - 1, acc + string_byte_length(s) + string_byte_length(junk) - string_byte_length(junk))
    end
  end

  fn main(_c : Cap(IO.Console)) do
    let d = { tag: "tag-" ++ int_to_string(12345), n: 1 }
    println(classify(d))
    println(int_to_string(go(100000, 0)))
  end
end
```

## 2. Nested projection, then the parent consumed

`o.ap.fingerprint` is bound before `active(o)` consumes `o`; the string concatenation reads it after.

```march
mod Nested do
  needs IO.Console
  type Ap = { fingerprint : String, k : Int }
  type Offer = { ap : Ap, sessions : List(Int) }

  pfn active(o : Offer) : Int do
    List.length(o.sessions)
  end

  pfn line(kv : (String, Offer)) : String do
    match kv do
      (name, o) -> "offer " ++ name ++ " fp " ++ o.ap.fingerprint ++ " sessions " ++ int_to_string(active(o)) ++ "\n"
    end
  end

  fn main(_c : Cap(IO.Console)) do
    let offers = List.map([1, 2, 3], fn i ->
      ("role" ++ int_to_string(i), { ap: { fingerprint: "fp-" ++ int_to_string(i * 1000003), k: i }, sessions: [i, i + 1] }))
    print(String.join(List.map(offers, fn kv -> line(kv)), ""))
  end
end
```

## 3. Record update from a `List.find` result

One arm of the update releases `w` before `inc_rc` of `w.w_place`.

```march
mod Shape3 do
  needs IO.Console
  type Place = Here(String) | Nowhere
  type Want = { w_name : String, w_place : Place, w_cap : Int }
  type Run = { name : String, place : Place, cap : Int }

  fn pick(r : Run, wants : List(Want)) : Run do
    match List.find(wants, fn w -> w.w_name == r.name) do
      None -> { r with place: Nowhere }
      Some(w) -> { r with place: w.w_place, cap: if r.cap == 0 do 0 else w.w_cap end }
    end
  end

  fn go(i : Int, acc : Int) : Int do
    if i == 0 do acc
    else
      let wants = [{ w_name: "a", w_place: Here("node-" ++ int_to_string(i)), w_cap: i }]
      let r = pick({ name: "a", place: Nowhere, cap: i % 2 }, wants)
      let n = match r.place do
        Here(s) -> string_byte_length(s)
        Nowhere -> 0
      end
      go(i - 1, acc + n + r.cap)
    end
  end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(go(2000, 0)))
  end
end
```

Reproduce any of them:

```bash
march --compile -o /tmp/repro repro.march && /tmp/repro
MARCH_VERIFY_TIR_RC=1 march --emit-llvm repro.march
```

## Fixed 2026-10-08

All three shapes had one cause. A projection `let v = src.f` is kept as a borrow
of `src` whenever `src` is still in scope, but nothing checked that `src`
outlives the projection's last read. The 2026-09-28 fix
(`specs/progress/2026-09-28-borrowed-field-outlives-owner.md`, `dup_owned_field`)
covered only a one-level `EField` whose source is later used other than as a
projection source. It missed:

- a projection chain (`let t = o.ap in t.fingerprint`, shape 2), which it did
  not match at all;
- a source used only as a projection source but released at the start of a
  case arm where it is dead (shape 1's binder arm, shape 3's `Some(w)` arm),
  which it assumed is released only at scope end.

Rather than predict where Perceus will release the owner, the fix checks the
finished body:

- While classifying, each borrowed field var whose root could be released
  inside its scope (a local `Unr` RC'd value, not in `live_after`, not itself a
  borrow, not a closure FV) is recorded in `env.field_roots` as
  `(root, origin)`. `root` looks through projection chains and earlier borrows;
  an alias keeps its source's `origin`, so the dup happens where the root is
  still alive.
- `Perceus.insert_rc` then runs `Perceus_core.read_after_owner_dies` over the
  finished body, post-passes included (an owned aggregate parameter's drop is
  added by one, at the function's tails, outside any binding's own scope). In
  that code an owned root's last occurrence on a path is its release or
  handoff, so a read of `v` with no later occurrence of `root` on that path
  may read freed memory. The walk runs backwards in evaluation order:
  - an evaluation step that mentions both counts as unsafe (`f(root, v)` may
    release `root` first);
  - an `inc_rc v` taken while `root` is alive covers the one use it was
    emitted for (Perceus dups a borrowed field before a consuming use), and
    nothing after it;
  - reads are attributed to their own binding of `v`, and a binding counts
    only if `root` occurs in it. A function can bind one name once per
    branch (`Toml.parse_number`'s `exp_str`), each from a different tuple.
- If any origin is flagged, the function is redone with those origins in
  `env.must_dup_fields`, which sends them down the existing `dup_owned_field`
  path (`inc_rc` after the projection, released as an owned binding). At most
  four rounds; a round only adds origins. The redo restores Perceus's fresh
  name counter first, so a redone function does not renumber the `$rc_N`
  names of every later one (the TIR snapshots caught that).

A function with no unsafe read is processed once, exactly as before.

### Evidence

- The three repros print the interpreter's output compiled (`--opt 2`); shape 3
  no longer dies with SIGTRAP.
- `test/test_codegen.ml`'s pinned verifier test (`rc: sees the
  perceus-releases-parent bugs`) went red with the fix, as intended, and is
  flipped to `rc: perceus-releases-parent shapes are clean`.
- `test/native/perceus_parent_release.march` runs all three shapes in loops,
  compiled.
- A projection whose owner's last use is the projection itself (owner dropped
  at scope end) gets no dup.
- Over the stdlib a small program links, 9 functions are redone, each in one
  round: the three `Topology` lambdas above, `Session.ip_step`,
  `ClusterNode.keeps_new`, `ClusterNode.start_writers`, the actor's `CtlFrame`
  handler and two `SessionNode.candidates` lambdas.
- Known over-report: when the root is never released on a path (it leaks
  there), its last occurrence is not a release, and a later read gets an
  unneeded dup (one inc/dec pair, no change in behaviour).
  `Session.ip_step`'s crash-handler arm is one: `st` is passed to `ip_forget`
  with a fresh `inc_rc` and its own reference is not released on that path.
  That looks like a separate leak; not investigated here.

- `--emit-llvm --opt 2` over `test/native/` and `bench/` (413 programs with
  IR), old compiler vs new, `%` names and fresh-name/drop-glue type-variable
  ids normalised: 406 identical, 7 differ (`cert_downgrade_after_restart`,
  `cluster_node_vaults_unnamed`, `node_discovery`, `node_send_loopback`,
  `session_party_released`, `topology_place`, and the new fixture). Every
  benchmark's IR is identical, so no benchmark can move.
- `MARCH_VERIFY_TIR_RC=1 --emit-llvm` over all 360 `test/native/` programs: no
  finding (the one non-zero exit is `js_dom_timeout_callback`, a JS-target
  program). Control: the old compiler reports 4 `rc-balance` findings on
  shape 2.

Check 3 now runs under plain `--verify-tir` (`Tir_verify.rc_enabled`);
`--verify-tir-rc` / `MARCH_VERIFY_TIR_RC=1` still turn it on alone.
