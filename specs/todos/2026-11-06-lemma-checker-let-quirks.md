`[P3]` Two lemma-checker quirks met writing Session.Theory C4

Found 2026-11-06 (progress `2026-11-06-session-theory-c3-c5`). Both have workarounds; both
cost an hour to find because the symptom names something else.

1. **A `let` that reuses another arm's pattern variable breaks the termination check.** In a
   recursive lemma whose `GMsg(f, t, p, k)` arm recurses on `k`, a `let k = gcont(bs, lab)`
   in ANOTHER arm (`GChoice`) made the lemma `invalid_lemma` (L4: "cannot prove the recursion
   terminates"). Renaming the `let` (`nxt`) fixed it. The termination analysis appears to key
   the structural variable by name across arms.
2. **An `assert` through a `let` bound to a constructor value does not prove.**
   `let a = AMsg(f, t, p)` then `assert trace(...) == ACons(a, ...)` is `reflect-fuel`;
   the same assert with `AMsg(f, t, p)` written inline proves. A `let` bound to a call
   (`let lab = pick(bs, picks)`) is linked; one bound to a constructor apparently is not.

Also, for the diagnostics: a lemma path that fails because a CALLEE lemma was never admitted
reports `reflect-fuel` / `opaque-application` at the call, which points at unfolding. The
gate bug fixed in that progress entry was found only by instrumenting the gate; a hint that
says "calls to `compose_msg` give no facts: it is not admitted" at the call would have named it.
