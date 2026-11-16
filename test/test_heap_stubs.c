/* test_heap links only the heap, message and GC files, not march_runtime.c.
 * march_message.c's copy_value shares a handle box (MARCH_HANDLE_TAG) with
 * march_incrc; test_heap never sends a handle, so reaching this is a bug. */
#include <stdio.h>
#include <stdlib.h>

void march_incrc(void *p) {
    (void)p;
    fprintf(stderr, "test_heap: unexpected march_incrc (handle box in a message)\n");
    abort();
}
