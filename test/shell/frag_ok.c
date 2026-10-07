/* A hand-written shell fragment (test/shell_check.ml): prints a line, which
 * the node must capture, and returns its rendered result. */
#include <stdint.h>
void *march_string_lit(const char *utf8, int64_t len);
void  march_println(void *s);
void *__shell_frag_ok(void) {
    march_println(march_string_lit("hello from the fragment", 23));
    return march_string_lit("42", 2);
}
