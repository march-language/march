/* test_cap_lattice.c — generated runtime/march_cap_lattice.{h,c} must agree
 * with the OCaml source of truth (lib/caps/cap_lattice.ml).
 *
 * This mirrors test/test_caps.ml's OCaml-side assertions on
 * Cap_lattice.cap_subsumes / normalize so the two can't silently drift:
 * if lib/caps/cap_lattice.ml's hierarchy or algorithm changes without
 * regenerating runtime/march_cap_lattice.{h,c}, either this test or the
 * "cap lattice freshness" dune rule (test/dune) will catch it.
 *
 * Exhaustively checks march_cap_subsumes over every (a, b) pair drawn from
 * the full hierarchy (20 caps => 400 pairs) against the known-correct
 * ancestor relationship, plus root/sibling/unrelated/FFI-not-in-table cases
 * and march_cap_normalize on representative inputs.
 */
#include "../runtime/march_cap_lattice.h"
#include <stdio.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

/* The full hierarchy, verbatim from lib/caps/cap_lattice.ml, paired with
 * each entry's parent index (-1 = root) so we can compute the expected
 * ancestor set independently of the generated table (i.e. not just
 * re-deriving the same table and comparing it to itself). */
typedef struct { const char *path; int parent_idx; } expect_entry_t;

static const expect_entry_t EXPECT[] = {
  { "IO",                  -1 }, /* 0 */
  { "IO.Console",           0 }, /* 1 */
  { "IO.FileSystem",        0 }, /* 2 */
  { "IO.FileRead",          2 }, /* 3 */
  { "IO.FileWrite",         2 }, /* 4 */
  { "IO.Network",           0 }, /* 5 */
  { "IO.NetConnect",        5 }, /* 6 */
  { "IO.NetListen",         5 }, /* 7 */
  { "IO.Process",           0 }, /* 8 */
  { "IO.Clock",             0 }, /* 9 */
  { "IO.Random",            0 }, /* 10 */
  { "IO.Database",          6 }, /* 11 */
  { "IO.Spawn",             0 }, /* 12 */
  { "IO.Mut",               0 }, /* 13 */
  { "IO.Telemetry",         0 }, /* 14 */
  { "IO.NetConnect.TLS",    6 }, /* 15 */
  { "IO.Foreign",           0 }, /* 16 */
  { "IO.Foreign.Blocking", 16 }, /* 17 */
  { "IO.Signal",            0 }, /* 18: child of IO */
  { "IO.WebSocket",         6 }, /* 19: child of IO.NetConnect */
};
#define N_EXPECT (int)(sizeof(EXPECT) / sizeof(EXPECT[0]))

/* True iff EXPECT[parent_i] is an ancestor-or-equal of EXPECT[child_i],
 * computed by walking EXPECT's parent_idx chain (independent of the
 * generated march_cap_lattice table under test). */
static int expected_subsumes(int parent_i, int child_i) {
  int cur = child_i;
  while (cur != -1) {
    if (cur == parent_i) return 1;
    cur = EXPECT[cur].parent_idx;
  }
  return 0;
}

static void test_exhaustive_pairs_against_hierarchy(void) {
  int i, j;
  for (i = 0; i < N_EXPECT; i++) {
    for (j = 0; j < N_EXPECT; j++) {
      int expected = expected_subsumes(i, j);
      int actual = march_cap_subsumes(EXPECT[i].path, EXPECT[j].path);
      if (expected != actual) {
        fprintf(stderr, "  FAIL [%s]: march_cap_subsumes(%s, %s) = %d, expected %d\n",
                __func__, EXPECT[i].path, EXPECT[j].path, actual, expected);
        g_failed++;
      }
    }
  }
  printf("PASS: test_exhaustive_pairs_against_hierarchy (%d pairs)\n", N_EXPECT * N_EXPECT);
}

static void test_table_size_matches(void) {
  CHECK(march_cap_lattice_size == N_EXPECT, "generated table size matches hand-verified hierarchy count");
  printf("PASS: test_table_size_matches\n");
}

static void test_root_subsumes_deep_descendant(void) {
  CHECK(march_cap_subsumes("IO", "IO.NetConnect.TLS") == 1, "IO subsumes IO.NetConnect.TLS");
  printf("PASS: test_root_subsumes_deep_descendant\n");
}

static void test_mid_level_subsumes_own_child(void) {
  CHECK(march_cap_subsumes("IO.FileSystem", "IO.FileRead") == 1, "IO.FileSystem subsumes IO.FileRead");
  printf("PASS: test_mid_level_subsumes_own_child\n");
}

static void test_cap_subsumes_itself(void) {
  CHECK(march_cap_subsumes("IO.FileRead", "IO.FileRead") == 1, "IO.FileRead subsumes IO.FileRead");
  printf("PASS: test_cap_subsumes_itself\n");
}

static void test_child_does_not_subsume_parent(void) {
  CHECK(march_cap_subsumes("IO.FileRead", "IO") == 0, "IO.FileRead does not subsume IO");
  printf("PASS: test_child_does_not_subsume_parent\n");
}

static void test_sibling_caps_neither_subsumes(void) {
  CHECK(march_cap_subsumes("IO.FileRead", "IO.FileWrite") == 0, "IO.FileRead does not subsume IO.FileWrite");
  CHECK(march_cap_subsumes("IO.FileWrite", "IO.FileRead") == 0, "IO.FileWrite does not subsume IO.FileRead");
  printf("PASS: test_sibling_caps_neither_subsumes\n");
}

static void test_unrelated_roots_dont_subsume(void) {
  CHECK(march_cap_subsumes("IO.Clock", "IO.Random") == 0, "IO.Clock does not subsume IO.Random");
  printf("PASS: test_unrelated_roots_dont_subsume\n");
}

static void test_ffi_cap_not_in_table_is_own_root(void) {
  CHECK(march_cap_subsumes("LibC", "LibC") == 1, "LibC subsumes LibC");
  CHECK(march_cap_subsumes("LibC", "IO") == 0, "LibC does not subsume IO");
  CHECK(march_cap_subsumes("IO", "LibC") == 0, "IO does not subsume LibC (LibC is its own root)");
  printf("PASS: test_ffi_cap_not_in_table_is_own_root\n");
}

static void test_normalize_drops_subsumed(void) {
  const char *in1[] = { "IO", "IO.FileRead" };
  const char *out1[2];
  int n1 = march_cap_normalize(in1, 2, out1);
  CHECK(n1 == 1, "IO;IO.FileRead normalizes to 1 entry");
  CHECK(n1 == 1 && strcmp(out1[0], "IO") == 0, "IO;IO.FileRead normalizes to IO");
  printf("PASS: test_normalize_drops_subsumed\n");
}

static void test_normalize_order_independent(void) {
  const char *in2[] = { "IO.FileRead", "IO" };
  const char *out2[2];
  int n2 = march_cap_normalize(in2, 2, out2);
  CHECK(n2 == 1 && strcmp(out2[0], "IO") == 0, "IO.FileRead;IO normalizes to IO regardless of order");
  printf("PASS: test_normalize_order_independent\n");
}

static void test_normalize_keeps_siblings(void) {
  const char *in3[] = { "IO.FileRead", "IO.FileWrite" };
  const char *out3[2];
  int n3 = march_cap_normalize(in3, 2, out3);
  CHECK(n3 == 2, "sibling caps both survive normalize");
  CHECK(n3 == 2 && strcmp(out3[0], "IO.FileRead") == 0 && strcmp(out3[1], "IO.FileWrite") == 0,
        "sibling caps keep relative order");
  printf("PASS: test_normalize_keeps_siblings\n");
}

static void test_normalize_transitively_subsumed(void) {
  const char *in4[] = { "IO", "IO.NetConnect.TLS" };
  const char *out4[2];
  int n4 = march_cap_normalize(in4, 2, out4);
  CHECK(n4 == 1 && strcmp(out4[0], "IO") == 0,
        "IO subsumes IO.NetConnect.TLS transitively via IO.Network/IO.NetConnect");
  printf("PASS: test_normalize_transitively_subsumed\n");
}

static void test_normalize_empty(void) {
  const char *out5[1];
  int n5 = march_cap_normalize(NULL, 0, out5);
  CHECK(n5 == 0, "normalize of empty list stays empty");
  printf("PASS: test_normalize_empty\n");
}

int main(void) {
  test_table_size_matches();
  test_exhaustive_pairs_against_hierarchy();
  test_root_subsumes_deep_descendant();
  test_mid_level_subsumes_own_child();
  test_cap_subsumes_itself();
  test_child_does_not_subsume_parent();
  test_sibling_caps_neither_subsumes();
  test_unrelated_roots_dont_subsume();
  test_ffi_cap_not_in_table_is_own_root();
  test_normalize_drops_subsumed();
  test_normalize_order_independent();
  test_normalize_keeps_siblings();
  test_normalize_transitively_subsumed();
  test_normalize_empty();
  if (g_failed == 0) { printf("test_cap_lattice: all checks passed\n"); return 0; }
  fprintf(stderr, "test_cap_lattice: %d check(s) failed\n", g_failed);
  return 1;
}
