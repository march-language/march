/* A fragment whose manifest declares two caps: it runs only when the signed
 * line lists exactly those, and the policy allows them. */
#include <stdint.h>
const char __march_cap_manifest[] = "IO.Console\nIO.NetConnect";
void *march_string_lit(const char *utf8, int64_t len);
void *__shell_frag_caps(void) {
    return march_string_lit("caps", 4);
}
