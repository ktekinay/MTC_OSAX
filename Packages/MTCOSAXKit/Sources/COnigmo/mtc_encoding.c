// MTC_OSAX addition, not part of Onigmo.
//
// UTF-16LE with Satimage's line terminators: LF, CR, NEL (U+0085), LINE SEPARATOR (U+2028) and
// PARAGRAPH SEPARATOR (U+2029), each on its own (CR LF is two line ends). Vertical tab and form feed are
// not line ends, unlike Onigmo's USE_UNICODE_ALL_LINE_TERMINATORS. These decide what `.`, `^`, `$` and `\Z` treat
// as a line end. Recorded from SatimageOSAX: see the line-end-* fixtures.
//
// The text searched can end, or start, with half a surrogate pair (`starting at` and `for` count units, and can
// cut one; text from a script itself can't hold a lone surrogate, which arrives as U+FFFD). Onigmo's UTF-16LE
// reads a high surrogate's pair without looking
// at where the text ends (reading past it in case-insensitive searches), and steps over a lone one by a single
// byte. Here a surrogate without its other half is one 2-byte character, as MTC_OSAX's UTF16Text counts it.

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

static int is_high_surrogate(const OnigUChar *p) {
	return (p[1] & 0xFC) == 0xD8;
}

static int is_low_surrogate(const OnigUChar *p) {
	return (p[1] & 0xFC) == 0xDC;
}

static int is_pair(const OnigUChar *p, const OnigUChar *end) {
	return end - p >= 4 && is_high_surrogate(p) && is_low_surrogate(p + 2);
}

static int satimage_mbc_enc_len(const OnigUChar *p, const OnigUChar *end, const struct OnigEncodingTypeST *enc) {
	(void)enc;
	if (end - p < 2)
		return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(1);
	return ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(is_pair(p, end) ? 4 : 2);
}

static OnigCodePoint satimage_mbc_to_code(const OnigUChar *p, const OnigUChar *end, const struct OnigEncodingTypeST *enc) {
	(void)enc;
	if (is_pair(p, end))
		return ((((OnigCodePoint)p[1] << 8 | p[0]) & 0x3FF) << 10) + (((OnigCodePoint)p[3] << 8 | p[2]) & 0x3FF) + 0x10000;
	return (OnigCodePoint)p[1] << 8 | p[0];
}

/// The start of the character `s` is in: back over a low surrogate only when a high one comes before it (and
/// never reading at the end of the text, which Onigmo's did).
static OnigUChar *satimage_left_adjust_char_head(const OnigUChar *start, const OnigUChar *s, const OnigUChar *end,
                                                 const struct OnigEncodingTypeST *enc) {
	(void)enc;
	if (s <= start)
		return (OnigUChar *)s;
	if ((s - start) % 2 == 1)
		s--;
	if (s - start >= 2 && end - s >= 2 && is_low_surrogate(s) && is_high_surrogate(s - 2))
		s -= 2;
	return (OnigUChar *)s;
}

static OnigEncodingType satimage_utf16le;
static pthread_once_t satimage_utf16le_once = PTHREAD_ONCE_INIT;

static void make_satimage_utf16le(void) {
	memcpy(&satimage_utf16le, ONIG_ENCODING_UTF16_LE, sizeof(OnigEncodingType));
	satimage_utf16le.is_mbc_newline = satimage_is_mbc_newline;
	satimage_utf16le.precise_mbc_enc_len = satimage_mbc_enc_len;
	satimage_utf16le.mbc_to_code = satimage_mbc_to_code;
	satimage_utf16le.left_adjust_char_head = satimage_left_adjust_char_head;
}

OnigEncoding mtc_onig_encoding_satimage_utf16le(void) {
	pthread_once(&satimage_utf16le_once, make_satimage_utf16le);
	return &satimage_utf16le;
}
