`[P1]` # `ConsistentHash.get` miscompiles compiled-only, with the module EAGERLY loaded

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

`specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`
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
