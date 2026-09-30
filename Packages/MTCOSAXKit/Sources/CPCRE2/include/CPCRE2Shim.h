// MTC_OSAX: PCRE2's 16-bit library, as Swift sees it. Swift can't use pcre2.h's width-neutral macro names
// (pcre2_compile and so on), so Swift code calls the `_16` functions directly.
#ifndef CPCRE2_SHIM_H
#define CPCRE2_SHIM_H

#define PCRE2_CODE_UNIT_WIDTH 16
#include "pcre2.h"
#include <stdint.h>

/// A deadline for searches on this thread, in CLOCK_UPTIME_RAW nanoseconds (0 for none), and whether the last one
/// stopped for it (see mtc_deadline.c).
void mtc_pcre2_set_deadline(uint64_t nanoseconds);
int mtc_pcre2_took_too_long(void);

#endif
