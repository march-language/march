/* test_free_dtor.c — march_free runs a resource cell's destructor.
 *
 * Perceus frees a dead LINEAR binding through EFree, which lowers to
 * march_free, bypassing march_decrc.  march_decrc at zero runs the destructor
 * a MARCH_RESOURCE_TAG cell carries (native_ptr@16, dtor@24); march_free used
 * to be a plain free() that skipped it, so a dead RingBuf or FFI resource
 * shallow-freed its cell and leaked its native store and elements.  Phase C0
 * of specs/plans/2026-09-25-send-data-race-freedom-plan.md made march_free
 * run the same destructor; this pins it, and pins that an ordinary cell and
 * an immortal cell are still left alone.  Also pins march_rc_is_unique, the
 * acquire-load sole-ownership test the same phase introduced. */
#include "../runtime/march_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

static int   g_dtor_calls = 0;
static void *g_dtor_arg   = NULL;

static void counting_dtor(void *native) {
    g_dtor_calls++;
    g_dtor_arg = native;
    free(native);
}

/* The same 40-byte resource-cell layout ring_buf_make builds. */
static void *make_resource_cell(void *native) {
    void *cell = march_alloc(40);
    ((march_hdr *)cell)->tag = MARCH_RESOURCE_TAG;
    *(void **)((char *)cell + 16) = native;
    *(void (**)(void *))((char *)cell + 24) = counting_dtor;
    *(int64_t *)((char *)cell + 32) = 0;
    return cell;
}

static void test_free_runs_resource_dtor(void) {
    void *native = malloc(64);
    void *cell = make_resource_cell(native);
    g_dtor_calls = 0; g_dtor_arg = NULL;
    march_free(cell);
    CHECK(g_dtor_calls == 1, "march_free must run the resource destructor once");
    CHECK(g_dtor_arg == native, "destructor must receive the wrapped native pointer");
}

static void test_decrc_still_runs_resource_dtor(void) {
    void *native = malloc(64);
    void *cell = make_resource_cell(native);
    g_dtor_calls = 0;
    march_decrc(cell);             /* rc 1 -> 0: the pre-existing path */
    CHECK(g_dtor_calls == 1, "march_decrc at zero must still run the destructor");
}

static void test_free_leaves_ordinary_cells_alone(void) {
    void *cell = march_alloc(24);  /* an ordinary constructor cell, tag 0 */
    ((march_hdr *)cell)->tag = 0;
    g_dtor_calls = 0;
    march_free(cell);
    CHECK(g_dtor_calls == 0, "an ordinary cell has no destructor to run");
}

static void test_free_skips_immortal_resource_cell(void) {
    void *native = malloc(64);
    void *cell = make_resource_cell(native);
    ((march_hdr *)cell)->rc = MARCH_RC_IMMORTAL;
    g_dtor_calls = 0;
    march_free(cell);              /* immortal guard comes first: no-op */
    CHECK(g_dtor_calls == 0, "an immortal cell is neither freed nor destructed");
    free(native);                  /* leak-free test: release by hand */
    ((march_hdr *)cell)->rc = 1;
    *(void (**)(void *))((char *)cell + 24) = NULL;
    march_free(cell);
}

static void test_rc_is_unique(void) {
    void *cell = march_alloc(24);
    ((march_hdr *)cell)->tag = 0;
    CHECK(march_rc_is_unique(cell) == 1, "a fresh cell (rc 1) is unique");
    march_incrc(cell);
    CHECK(march_rc_is_unique(cell) == 0, "rc 2 is not unique");
    march_decrc(cell);
    CHECK(march_rc_is_unique(cell) == 1, "back to rc 1 is unique again");
    ((march_hdr *)cell)->rc = MARCH_RC_IMMORTAL;
    CHECK(march_rc_is_unique(cell) == 0, "an immortal cell is never unique");
    ((march_hdr *)cell)->rc = 1;
    march_free(cell);
}

int main(void) {
    test_free_runs_resource_dtor();
    test_decrc_still_runs_resource_dtor();
    test_free_leaves_ordinary_cells_alone();
    test_free_skips_immortal_resource_cell();
    test_rc_is_unique();
    if (g_failed) { fprintf(stderr, "test_free_dtor: %d failure(s)\n", g_failed); return 1; }
    printf("test_free_dtor: all passed\n");
    return 0;
}
