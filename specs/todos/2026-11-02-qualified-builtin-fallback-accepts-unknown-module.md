`[P1]` `Lsit.length([1,2])` (misspelled module) passes `march --check` with exit 0 and fails at run time
with "unbound variable: Lsit.length". `Lsit.nope(...)` is correctly rejected ("Unknown module `Lsit`. Did you
mean `List`?"), so qualified-name resolution appears to fall back to the unqualified builtin when the last
segment names one. Also: that program's run-time stack trace names line 7 for a call on line 4.

Repro: `mod T do needs IO  fn f() : Int do Lsit.length([1,2]) end  fn main(cap : Cap(IO)) do println(int_to_string(f())) end end`.
Plan: specs/plans/2026-11-02-diagnostics-depth-plan.md §X9.
