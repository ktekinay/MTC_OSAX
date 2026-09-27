// MTC_OSAX addition, not part of Onigmo.
//
// UTF-16LE with Satimage's line terminators: LF, CR, NEL (U+0085), LINE SEPARATOR (U+2028) and
// PARAGRAPH SEPARATOR (U+2029), each on its own (CR LF is two line ends). Vertical tab and form feed are
// not line ends, unlike Onigmo's USE_UNICODE_ALL_LINE_TERMINATORS. These decide what `.`, `^`, `$` and `\Z` treat
// as a line end. Recorded from SatimageOSAX: see the line-end-* fixtures.

#include <pthread.h>
#include <string.h>
#include "COnigmoShim.h"

static int satimage_is_mbc_newline(const OnigUChar *p, const OnigUChar *end, const struct OnigEncodingTypeST *enc) {
	(void)enc;
	if (p + 1 < end) {
		OnigUChar low = p[0], high = p[1];
		if (high == 0x00 && (low == 0x0a || low == 0x0d || low == 0x85))
			return 1;
		if (high == 0x20 && (low == 0x28 || low == 0x29))
			return 1;
	}
	return 0;
}

static OnigEncodingType satimage_utf16le;
static pthread_once_t satimage_utf16le_once = PTHREAD_ONCE_INIT;

static void make_satimage_utf16le(void) {
	memcpy(&satimage_utf16le, ONIG_ENCODING_UTF16_LE, sizeof(OnigEncodingType));
	satimage_utf16le.is_mbc_newline = satimage_is_mbc_newline;
}

OnigEncoding mtc_onig_encoding_satimage_utf16le(void) {
	pthread_once(&satimage_utf16le_once, make_satimage_utf16le);
	return &satimage_utf16le;
}
