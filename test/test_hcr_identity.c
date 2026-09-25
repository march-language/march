#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void check(const char *path, const char *abi, const char *target,
                  const char *prefix) {
  void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!h) { fprintf(stderr, "dlopen %s: %s\n", path, dlerror()); exit(1); }
  const char *got_abi = (const char *)dlsym(h, "__march_hcr_abi");
  const char *got_target = (const char *)dlsym(h, "__march_hcr_target");
  const char *got_prefix = (const char *)dlsym(h, "__march_hcr_prefix");
  if (!got_abi || !got_target || !got_prefix ||
      strcmp(got_abi, abi) || strcmp(got_target, target) || strcmp(got_prefix, prefix)) {
    fprintf(stderr, "identity mismatch in %s\n", path); exit(1);
  }
  dlclose(h);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  check(argv[1], "march-hcr-v3;triple=x86_64-unknown-linux-gnu;ptr=8", "linux/amd64", "HcrSmoke");
  check(argv[2], "march-hcr-v3;triple=aarch64-unknown-linux-gnu;ptr=8", "linux/arm64", "HcrSmoke");
  puts("hcr identity: all checks passed");
  return 0;
}
