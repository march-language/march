#include "march_hcr_identity.h"

#ifndef MARCH_HCR_TRIPLE
#define MARCH_HCR_TRIPLE ""
#endif
#ifndef MARCH_HCR_TARGET
#define MARCH_HCR_TARGET ""
#endif
#ifndef MARCH_HCR_PREFIX
#define MARCH_HCR_PREFIX ""
#endif
#define MARCH_HCR_STRINGIFY1(x) #x
#define MARCH_HCR_STRINGIFY(x) MARCH_HCR_STRINGIFY1(x)

#ifdef MARCH_HCR_ABI_ID
const char __march_hcr_abi[] = MARCH_HCR_ABI_ID;
#else
const char __march_hcr_abi[] = "march-hcr-v2;triple=" MARCH_HCR_STRINGIFY(MARCH_HCR_TRIPLE) ";ptr=8";
#endif
const char __march_hcr_target[] = MARCH_HCR_TARGET;
const char __march_hcr_prefix[] = MARCH_HCR_PREFIX;
