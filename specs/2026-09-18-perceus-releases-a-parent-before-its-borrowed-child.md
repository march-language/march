# Perceus releases a parent before the borrowed child it still has to dup

**Date:** 2026-09-18
**Status:** **LANDED 2026-09-18** — `specs/progress/2026-09-18-perceus-releases-parent-before-borrowed-child.md`.
Option A, implemented at the premise that made the child borrowed (§5); kept as
written for the record.
**Scope:** `specs/progress/2026-09-18-perceus-releases-parent-before-borrowed-child.md` (filed as `2026-09-17-consistent-hash-get-miscompiles-eagerly-loaded.md`),
which this reframes. It was filed as a `ConsistentHash` bug. It is a **general
Perceus use-after-free**, reachable from ordinary user code, and `ConsistentHash`
is one instance.

---

## 1. Symptom

The todo's repro — two `ConsistentHash.add`s and a `get` — prints `SOME 42`
interpreted and SIGBUSes compiled, with the module eagerly loaded. Narrowed:

| program | compiled | interpreted |
|---|---|---|
| one `add`, then `get` | correct | correct |
| **two `add`s, then `size`** | **SIGBUS** | `size 2` |
| two `add`s with `String` payloads, then `get` | `SOME pb` (**wrong value**) | `SOME pa` |

`get` is not needed; the second `add` is enough. And the outcome is
non-deterministic — crash on one run, wrong value on another. Over 20 runs of
the original repro: **0 correct, 3 wrong value, 17 crash.**

## 2. It is not stdlib-specific

A self-contained user program with the same shape — a `List((String, a))` kept
sorted by `ring_insert`, no `ConsistentHash`, no stdlib data structures —
crashes the same way. The minimal fixture:

```march
mod Main do
  needs IO.Console
  type Ring(a) = Ring(List((String, a)), Int)

  pfn ring_insert(lst : List((String, a)), h : String, node : a) : List((String, a)) do
    match lst do
    Nil -> Cons((h, node), Nil)
    Cons((hd, nd), rest) ->
      if h < hd do Cons((h, node), lst)
      else Cons((hd, nd), ring_insert(rest, h, node))
      end
    end
  end

  pfn add_replicas(lst : List((String, a)), name : String, node : a, replicas : Int, i : Int) : List((String, a)) do
    if i >= replicas do lst
    else
      let h = Crypto.sha256(name ++ "#" ++ int_to_string(i))
      add_replicas(ring_insert(lst, h, node), name, node, replicas, i + 1)
    end
  end

  fn add(r : Ring(a), name : String, node : a) : Ring(a) do
    match r do
    Ring(lst, reps) -> Ring(add_replicas(lst, name, node, reps, 0), reps)
    end
  end

  fn size(r : Ring(a)) : Int do
    match r do
    Ring(lst, _) -> List.length(lst)
    end
  end

  fn main(_c : Cap(IO.Console)) do
    let r1 = add(Ring(Nil, 3), "node-a", 42)
    let r2 = add(r1, "node-b", 99)
    println("size " ++ int_to_string(size(r2)))
  end
end
```

Interpreted `size 6`. Compiled: SIGBUS or a wrong answer.

## 3. What it is NOT — measured, because three plausible hypotheses were wrong

| hypothesis | test | result |
|---|---|---|
| TRMC (default since 2026-09-09, inside the window; `ring_insert` is modulo-cons) | 20 runs, default vs `--no-trmc` | **identical**: 0 correct / 3 wrong / 17 crash both ways |
| the 2026-09-16 `if`/`else` dead-side fix (`0a4275849`) | rebuilt without it | **still fails**: 0/20 and 5/20 correct |
| `3bbfc3ed7`, 2026-09-03, "reference-count and deep-drop records and tuples" | built it and its parent | **both pass 20/20** |

## 4. Root cause

### ASAN

Run in `march-sbx-test-ubuntu`, on both the stdlib repro and the user copy:

```
ERROR: AddressSanitizer: heap-use-after-free
WRITE of size 8  in march_incrc  <- march_incrc_local <- ring_insert
freed by         march_decrc      <- march_decrc_local <- ring_insert
allocated by     march_string_alloc <- march_sha256   <- add_replicas
```

An 89-byte string — a sha256 hex digest, stored into the ring as a key — is
freed by one `ring_insert` and then `inc_rc`'d by a later one.

### The TIR

Post-Perceus, `ring_insert`'s `Cons` arm:

```
Cons($f31897, $f31898) -> case $f31897 of          -- $f31897 is the (hd, nd) tuple
  $Tuple2($f31899, $f31900) ->
    let rest = inc_rc $f31898; $f31898
    let nd   = inc_rc $f31900; $f31900
    let hd   = $f31899                             -- ← a BORROWED alias: no inc_rc
    let $t = <(h, hd)
    case $t of
      True -> dec_rc rest; alloc List.Cons((h, node), lst)
      _    -> dec_rc lst;                          -- ← releases the cell hd lives in
              let $t31895 = inc_rc hd; (hd, nd)    -- ← then dups hd: use-after-free
              …
```

In the `_` arm, `dec_rc lst` runs at the head of the arm. When it takes `lst`
to zero, the deep drop cascades through the tuple and frees the digest. `hd`
never held a reference of its own — it is a borrowed alias of a field inside
`lst` — so the `inc_rc hd` two lines later writes into freed memory.

The release is the cross-branch dead-variable pass
(`Perceus_core.insert_rc_expr`, `ECase`, `add_cross_decrcs`): `lst` is live in
the `True` arm (returned) and dead in the default arm, so it is released at the
default arm's head. That rule is correct on its own. What it does not know is
that a value **borrowed from `lst`** is still going to be consumed later in the
same arm.

### Bisected

`git bisect run --first-parent`, 7 steps between `3bbfc3ed7` (good) and
`f4c97240e` (bad):

> **first bad commit: `95c7f9c4d`** — Merge PR #446 `claude/rc-leaks`,
> 2026-09-13, whose only commit is **`efb15d8b1`**: *"rc: read-only builtins
> release their heap arguments; classify every heap-param builtin."*

### Why that commit, and why it is not the bug

The good side (`99fc2c813`), same function:

```
let $t30096 : Bool = inc_rc h;
                     inc_rc hd;        ← hd gets a reference of its own
                     <(h, hd) in
…
_ -> dec_rc lst;                       ← frees lst; the digest survives
     let $t30098 = inc_rc hd; (hd, nd)
```

Before `efb15d8b1`, `<` was misclassified **owned**, so Perceus `inc_rc`'d its
arguments on the way in, expecting the call to release them. The C comparison
never did — it only reads. Each call leaked one reference per heap argument,
which is exactly the leak `efb15d8b1` fixed.

That leaked reference is what kept the digest alive past `dec_rc lst`.
`efb15d8b1` correctly classified `<` as borrowing, the `inc_rc` went away, and a
use-after-free that had always been in Perceus's release ordering became
reachable.

**Do not revert `efb15d8b1`.** It fixes a real leak on every read-only builtin
call, and the use-after-free is not in it. Reverting would put the leak back and
leave the ordering bug in place, masked again.

## 5. The defect, stated precisely

> A cross-branch release of `x` at the head of arm A is unsafe when a value
> **borrowed from `x`** — a field projected out of it, transitively — is
> consumed later in A.

The borrowed-field machinery exists, but it only marks a projection borrowed
when the scrutinee is live across the WHOLE case (`scrutinee_live_across_case`,
`borrowed_field_vars`). Here `lst` is live on one arm and dead on the other, and
the tuple is a nested scrutinee treated as borrowed under the TTuple rule
(*"treat the aggregate as a borrowed scrutinee so escaping fields get an
EIncRC"*). That rule does insert the `inc_rc` on the escaping use — but at the
use, after the parent's release has already been hoisted above it.

## 6. Reach

Any function that:

1. matches a list or ADT whose element is a tuple or record,
2. binds a heap field of that element,
3. reads it through a borrowing builtin (`<`, `==`, `string_length`, …),
4. returns the scrutinee intact on one branch, and
5. consumes the field on the other.

That is the shape of every sorted insert into a list of pairs — a common thing
to write. It is compiled-only, non-deterministic, and ASAN-clean in no
configuration, so the ASAN gate would catch a fixture of it. There is no such
fixture today, which is why this reached `main`.

## 7. Fix options

**A. Dup the borrowed child before the parent can go (recommended).**
When a field-borrowed variable is consumed on a path where its source is
released earlier by the cross-branch pass, bind it owned — `inc_rc` at the
binding rather than at the use. This is what the owned `<` did by accident,
done deliberately and only where needed.

- Local to where the borrow is established; moves no release.
- Costs one extra `inc_rc`/`dec_rc` pair, only on functions with this shape —
  the pair the borrowed-field optimisation exists to elide, given back only
  where eliding it is unsound.

**B. Defer the parent's release past the child's last use.**
Teach `add_cross_decrcs` the borrowed-from relation, and place a release of `x`
after the last consuming use of anything borrowed from `x` rather than at the
arm head.

- Optimal: no extra RC traffic.
- But the arm head is where releases go for a reason — the arm often ends in a
  tail call or a TRMC hole write, and a release after it is either unreachable
  or defeats TCO. Getting the placement right is the whole difficulty, and it is
  the same placement problem `Perceus.insert_apply_fn_clo_drop` documents at
  length.

**C. Reclassify `<` and friends as owned again.** Rejected — see §4.

Recommend **A**. It is small, obviously sound, and its cost is bounded to the
shape that is currently wrong. B can follow as an optimisation if the extra pair
ever shows up in a profile.

## 8. Verification bar

- The §2 fixture as a native test, **RED** today (crash or wrong value).
- The same fixture in the ASAN gate's curated corpus. The fix releases on a new
  path, and ASAN is what caught this, so it is the gate that matters.
- A string-payload variant asserting the VALUE (`SOME pa`) — the wrong-value
  mode is the one a crash-only test would miss.
- A control on the `True` arm: the scrutinee is returned intact and nothing
  borrowed from it may be released.
- `efb15d8b1`'s own leak probe stays flat. A fix that works by reintroducing an
  owned argument somewhere would pass the ASAN leg and fail this one.
- `bench/list_ops.march` and `tree_transform.march` interleaved, since option A
  adds RC traffic on the affected shape.

## 9. Effort and risk

S–M. The change is local to Perceus's `ECase` arm processing. Risk is moderate
— it is an RC change — and bounded by the ASAN gate plus the leak probe, which
pin both failure directions.
