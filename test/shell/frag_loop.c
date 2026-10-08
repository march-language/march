/* A fragment that never returns but passes cancellation points, as compiled
 * code's yield checks do: the node's timeout cancels it. */
#include <stdint.h>
const char __march_cap_manifest[] = "";
void march_sched_cancel_point(void);
void *__shell_frag_loop(void) {
    for (;;) march_sched_cancel_point();
    return 0;
}
