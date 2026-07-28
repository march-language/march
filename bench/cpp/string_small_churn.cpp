// C++ counterpart of bench/string_small_churn.march.
//
// The reason C++ is here at all, when the project otherwise benchmarks against
// C/OCaml/Python/Rust/Go: std::string has SMALL-STRING OPTIMIZATION. Short
// strings live inline in the string object with no heap allocation, which is
// exactly the representation change March's phase 2 Task 4 is considering.
// Rust's String and March's both allocate; this is the only baseline here that
// does not, so it measures the size of the prize.
//
// Must print checksum=17793810, identical to the March version. A different
// checksum means the two are not doing the same work and the timing is void.
#include <cstdio>
#include <string>

int main() {
    long long acc = 0;
    for (long long i = 0; i < 2000000; i++) {
        std::string name  = "x-req-" + std::to_string(i % 97);
        std::string value = "v" + std::to_string(i) + "-abcdefgh";
        std::string pair  = name + ": " + value;
        int bump = pair.rfind("x-req-", 0) == 0 ? 1 : 0;
        acc += (long long)name.size() + bump;
    }
    printf("checksum=%lld\n", acc);
    return 0;
}
