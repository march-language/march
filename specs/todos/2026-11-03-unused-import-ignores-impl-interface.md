`[P3]` `use Algebra.*` draws "Unused import: nothing from `Algebra` is used" when the file's
only use of `Algebra` is `impl Monoid(Int)` of `Algebra`'s interface `Monoid`. The impl's
interface name is not counted as a use. Seen while testing cross-file interface laws.
