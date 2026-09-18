# FIXED 2026-09-18 — Perceus released a parent before the borrowed child it still had to dup

Design and root cause: `specs/2026-09-18-perceus-releases-a-parent-before-its-borrowed-child.md`.

## The fix

The spec recommended option A — *bind a field-borrowed variable owned when its
source is released earlier on the same path.* Implemented at the level of WHY
the variable was borrowed at all, which turned out to be a single premise
leaking one level down.

`Perceus_core.insert_rc_expr`'s `ECase` arm already refused to take
`scrutinee_borrowed`'s conservatism as proof that a scrutinee outlives its arm.
The comment on `scrutinee_live_across_case` says so explicitly, and names the
use-after-free that doing so would cause. But when an arm re-adds its
pattern-bound fields to the live set **conservatively** — because the scrutinee
is mentioned somewhere in the arm — those fields land in `live_after`, and a
NESTED case over one of them then read that membership as a guarantee. So the
premise the outer case declined came back one level down:

| level | case | what it concluded |
|---|---|---|
| outer | `case lst of Cons($f97, $f98)` | `lst` merely mentioned in the arm → fields re-added to the live set, conservatively |
| inner | `case $f97 of $Tuple2($f99, $f100)` | `$f97 ∈ live_after` → "outlives the case" → fields marked **borrowed** |
| body | `let hd = $f99` | alias of a borrowed field → no reference of its own |

The new `env.cons_live` set records fields that are live only conservatively.
`scrutinee_live_across_case` now also requires the scrutinee NOT be in it, and
the set propagates into nested arms. `hd` is then an ordinary owned alias and
gets `inc_rc` at its binding, exactly like `rest` beside it:

```
let hd = inc_rc $f31899; $f31899
True -> dec_rc rest; dec_rc hd; …Cons((h, node), lst)    -- dead here: released
_    -> dec_rc lst; let $t = (hd, nd) in …               -- consumed: no extra inc
```

+1 at the binding, then -1 or a transfer on each arm: balanced on both paths.

## Verification

- **The three repros, 20 runs each:** user copy `size 6`, stdlib `SOME 42`,
  String payload `SOME pa` — **20/20 correct on all three**, from 0/20.
- **`test/native/perceus_borrowed_child_release.march`**, four legs (the SIGBUS
  mode; the wrong-VALUE mode a crash-only test would miss; a control where every
  insert takes the arm that returns the list intact; a 400-insert stress loop).
  Matches the interpreter exactly. **RED against the unfixed compiler: 0/10
  runs match**, and the runtime aborts with `RC underflow (rc was 0)`.
- **The other failure direction:** `efb15d8b1`'s own
  `test/native/builtin_borrow_leak_probe` still matches. A fix that worked by
  reintroducing an owned argument would pass the use-after-free leg and fail
  this one.
- **ASAN gate:** 89 programs swept, 89 clean — golden, curated native (the new
  fixture added) and the two-node scenarios.
- **Full suite**, and no TIR snapshot moved: none of the 45 fixtures has this
  shape, which is why nothing pinned it before.
- **Benchmarks**, interleaved five rounds against a compiler built without the
  fix, round-1 warm-up excluded — medians `list_ops` 68 vs 69.5 ms,
  `tree_transform` 624 vs 610 ms, `binary_trees` 217.5 vs 216 ms; peak RSS
  identical within noise.

The original filing follows.

---

`[P1]` # Perceus releases a parent before the borrowed child it still has to dup

> **Reframed 2026-09-18.** Filed as a `ConsistentHash` bug; it is a **general
> Perceus use-after-free** reachable from ordinary user code, and
> `ConsistentHash` is one instance. Root cause established — ASAN, the TIR on
> both sides, and a bisect to `efb15d8b1` — in
> **`specs/2026-09-18-perceus-releases-a-parent-before-its-borrowed-child.md`**,
> which also carries the fix options (recommended: bind a field-borrowed
> variable owned when its source is released earlier on the same path) and the
> verification bar. The notes below are the original filing, kept because its
> repro is still the right starting point.
>
> Three hypotheses in the original "Where to start" were measured and are
> wrong: it is **not** TRMC (fails 20/20 either way), **not** the 2026-09-16
> `if`/`else` fix, and **not** `3bbfc3ed7`'s tuple deep-drop (passes 20/20). And
> `efb15d8b1`, the first bad commit, is a correct leak fix that removed an
> accidental leak which had been masking the use-after-free — **do not revert
> it.**

(original filing, as `2026-09-17-consistent-hash-get-miscompiles-eagerly-loaded.md`:)

# `ConsistentHash.get` miscompiles compiled-only, with the module EAGERLY loaded

Found 2026-09-17 while building the REJECT witness for
`specs/progress/2026-09-17-mono-refuses-a-repr-disagreeing-call.md`. **Not** the
lazy-stdlib representation class, and not caused by that change — reproduced on
a compiler built from a clean `origin/main`.

## Repro

```march
mod Main do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let r0 = ConsistentHash.new(3)
    let r1 = ConsistentHash.add(r0, "node-a", 42)
    let r2 = ConsistentHash.add(r1, "node-b", 99)
    match ConsistentHash.get(r2, "hello") do
    Some(v) -> println("SOME " ++ int_to_string(v))
    None -> println("NONE")
    end
  end
end
```

| backend | result |
|---|---|
| interpreted | `SOME 42` |
| compiled | `march: fatal SIGBUS si_code=1 ... fault outside its stack` |

`consistent_hash.march` **is** in `Stdlib_manifest.stdlib_file_list` (verified),
so the module is eagerly loaded and this is not the lazy-load path.

## Why it is not the representation class

The mono repr-disagreement instrumentation added the same day
(`MARCH_MONO_REPR_REPORT=1`) reports **zero** disagreements for this program on
the real manifest — while reporting exactly one when the module is made lazy.
So the two failures are distinct mechanisms that happen to share a repro:

| configuration | disagreements | outcome |
|---|---|---|
| module eager (shipping) | 0 | SIGBUS ← **this todo** |
| module lazy | 1 | now a compile error |

## It is a regression

`specs/progress/2026-09-18-lazy-stdlib-niche-miscompile-closed.md`
records this exact repro printing `SOME 42` compiled, after
`consistent_hash.march` was added to the eager list on 2026-08-01. It does not
now. Something between 2026-08-01 and today broke it, with the module still
eagerly loaded the whole time.

## Where to start

- Bisect between 2026-08-01 and 2026-09-17 on the repro above. It is fast,
  deterministic, and needs no flags — a good bisect subject.
- `--emit-llvm` the program and look at `ConsistentHash.get`'s call site and
  the `Option` match: SIGBUS with `si_code=1` and a `0x4000...` address reads
  like a tagged/erased integer being dereferenced, the same family as the
  niche-match-on-unresolved-scrutinee bugs
  (`specs/progress/2026-06-23-codegen-hardening-niche-match-on-an-unresolved-scrutinee-type-lib.md`).
- `ConsistentHash` builds on a `HashRing(a)`; check whether the ring's own
  generic structure, not `get`'s return, is what is mis-represented.

## Why P1

Same severity as the class bug it was found next to: a stdlib function
returning a wrong result / crashing, compiled only, with the interpreter
disagreeing — and the module is configured the way the previous fix intended.
