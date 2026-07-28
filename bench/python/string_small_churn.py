# Python counterpart of bench/string_small_churn.march.
#
# CPython's pymalloc is a size-class freelist for small objects -- close to the
# design March's phase 2 Task 4 proposes -- so this is a second data point on
# whether that approach pays, independent of C++'s inline storage.
#
# Must print checksum=17793810, identical to the March version.
acc = 0
for i in range(2_000_000):
    name = "x-req-" + str(i % 97)
    value = "v" + str(i) + "-abcdefgh"
    pair = name + ": " + value
    bump = 1 if pair.startswith("x-req-") else 0
    acc += len(name) + bump
print(f"checksum={acc}")
