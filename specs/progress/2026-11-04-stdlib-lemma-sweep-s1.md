# Stdlib lemma sweep, phase S1: the laws a caller needs (2026-11-04)

Design: `specs/2026-11-04-stdlib-lemma-sweep-design.md` §3 "S1". The open phases S2 and S3 are
`specs/todos/2026-11-04-stdlib-lemma-sweep-s2-s3.md`.

## What shipped

- **`stdlib/list.march`, four lemmas** after `take_drop`, admitted by `stdlib/lemmas.verified`
  (now 17 entries):
  - `take_onto_append(xs, ys, acc)`: `take_onto(append(xs, ys), len(xs), acc) == append(reverse(acc), xs)`,
    the accumulator lemma, proved like `take_onto_drop`;
  - `take_append(xs, ys)`: `take(append(xs, ys), len(xs)) == xs`;
  - `drop_append(xs, ys)`: `drop(append(xs, ys), len(xs)) == ys`;
  - `nth_opt_append(xs, ys, i)` for `0 <= i < len(xs)`: `nth_opt(append(xs, ys), i) == nth_opt(xs, i)`.
- **`stdlib/math.march`, three result types:**
  - `min_int : {Int | _ <= a && _ <= b && (_ == a || _ == b)}`, and `max_int` dually;
  - `clamp_int : {Int | high < low || (_ >= low && _ <= high)}`, a conditional result, so no
    existing caller gains an obligation (the sweep's rule: no new preconditions on the stdlib).

## Ruling: the design's §2.1 list was cut to what a caller needs

§2.1 listed the laws whose theorems prove. Building S1 checked each one at a caller, with and
without the law (probe programs, `--refine-report-sites=all`):

| Law | Without the law | With the lemma | Shipped |
|---|---|---|---|
| `drop(append(xs, ys), len(xs)) == ys` | `reflect-fuel` | proved | yes |
| `take(append(xs, ys), len(xs)) == xs` | not proved | proved | yes (+ `take_onto_append`) |
| `nth_opt(append(xs, ys), i) == nth_opt(xs, i)` | `unconstrained-subject` | proved | yes |
| `Math` laws (`min + max == a + b`, `clamp_int` in range) | proved by unfolding | n/a | as result types only |
| `len(Option.to_list(o)) <= 1`, `to_result` / `to_option` round trip, `let`-bound `Result.unwrap_or(Ok(x), d)` | proved by unfolding | n/a | no |
| `Option.unwrap_or` as an argument, `is_some` / `is_none`, `is_ok` / `is_err`, `List.head_opt(Cons(x, xs))` | `unreflectable-subject` | still `unreflectable-subject` | no: `specs/todos/2026-11-04-stdlib-call-subjects-unreflectable.md` |

A lemma no caller can use is a stdlib name to maintain for nothing, so those wait for the
subject todo. The `Math` result types shipped although callers already unfold the bodies: they
state the law in the signature, where a reader sees it.

## Verification

| Check | Result |
|---|---|
| `reflect-stdlib-sweep` (8 cases: each lemma with and without its call, a REJECT control for `nth_opt_append`'s index bound, manifest admission, `Math` result types proved, `clamp_int` at a caller and a REJECT control with `high` below `low`) | 8/8 |
| RED: the same group before the stdlib change | cases 0–5 fail. Cases 6 and 7 (`clamp_int` at a caller) already pass by unfolding; they pin that behaviour |
| The new lemmas and result types proved from scratch (`MARCH_LEMMA_MANIFEST=/dev/null`) | all `proved` |
| `reflect-stdlib-list` with `reflect-stdlib-sweep` (incl. Slow: manifest fresh) | 17/17 |
| `audit-baseline`, regenerated | +8 enforced on every fixture's `user + stdlib` slice (214 → 222). The `user code` slice moved only for `stdlib_list` (50 → 55: four lemmas and `nth_opt_append`'s index bound) and `stdlib_math` (0 → 3) |
| CI `conformance` skip ceiling (`--check --stdlib-source --refine-report stdlib/list.march`, `user + stdlib`) | 135 proved / 42 skipped → 148 proved / 43 skipped. The one new skip row is `take_append`'s theorem (unreflectable-predicate). Checked as user code, `reverse` is ambiguous, so `take` is not reflected; `len_take` and `take_drop` already skip there for the same reason. Ceiling raised 42 → 43 in `ci.yml`, attributed in its comment |

## Found on the way

- `specs/todos/2026-11-04-stdlib-call-subjects-unreflectable.md`: the subject gap above.
- `specs/todos/2026-11-04-refine-pred-str-drops-parens.md`: `min_int`'s row prints
  `_ <= a && _ <= b && _ == a || _ == b`.
