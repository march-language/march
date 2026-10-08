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
