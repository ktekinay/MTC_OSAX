// Accessors for Onigmo values that are C macros or addresses of globals, which Swift can't import directly.
// Not part of Onigmo.

#ifndef CONIGMO_SHIM_H
#define CONIGMO_SHIM_H

#include <stdint.h>
#include "onigmo.h"

typedef enum {
	MTCOnigSyntaxRuby,
	MTCOnigSyntaxPerl,
	MTCOnigSyntaxJava,
	MTCOnigSyntaxGnuRegex,
	MTCOnigSyntaxGrep,
	MTCOnigSyntaxEmacs,
	MTCOnigSyntaxPosixBasic,
	MTCOnigSyntaxPosixExtended,
} MTCOnigSyntax;

static inline const OnigSyntaxType *mtc_onig_syntax(MTCOnigSyntax syntax) {
	switch (syntax) {
		case MTCOnigSyntaxPerl: return ONIG_SYNTAX_PERL;
		case MTCOnigSyntaxJava: return ONIG_SYNTAX_JAVA;
		case MTCOnigSyntaxGnuRegex: return ONIG_SYNTAX_GNU_REGEX;
		case MTCOnigSyntaxGrep: return ONIG_SYNTAX_GREP;
		case MTCOnigSyntaxEmacs: return ONIG_SYNTAX_EMACS;
		case MTCOnigSyntaxPosixBasic: return ONIG_SYNTAX_POSIX_BASIC;
		case MTCOnigSyntaxPosixExtended: return ONIG_SYNTAX_POSIX_EXTENDED;
		case MTCOnigSyntaxRuby:
		default: return ONIG_SYNTAX_RUBY;
	}
}

/// A deadline for searches on this thread, in CLOCK_UPTIME_RAW nanoseconds (0 for none), and whether the last one
/// stopped for it (see mtc_deadline.c).
void mtc_onig_set_deadline(uint64_t nanoseconds);
int mtc_onig_took_too_long(void);

/// UTF-16LE with Satimage's line terminators (see mtc_encoding.c).
OnigEncoding mtc_onig_encoding_satimage_utf16le(void);

static const OnigOptionType MTCOnigOptionCaptureGroup = ONIG_OPTION_CAPTURE_GROUP;
static const OnigOptionType MTCOnigOptionIgnoreCase = ONIG_OPTION_IGNORECASE;
static const OnigOptionType MTCOnigOptionExtend = ONIG_OPTION_EXTEND;
static const OnigOptionType MTCOnigOptionMultiline = ONIG_OPTION_MULTILINE;
static const OnigOptionType MTCOnigOptionSingleline = ONIG_OPTION_SINGLELINE;
static const OnigOptionType MTCOnigOptionFindLongest = ONIG_OPTION_FIND_LONGEST;
static const OnigOptionType MTCOnigOptionFindNotEmpty = ONIG_OPTION_FIND_NOT_EMPTY;
static const OnigOptionType MTCOnigOptionNegateSingleline = ONIG_OPTION_NEGATE_SINGLELINE;
static const OnigOptionType MTCOnigOptionDontCaptureGroup = ONIG_OPTION_DONT_CAPTURE_GROUP;
static const OnigOptionType MTCOnigOptionNewlineCRLF = ONIG_OPTION_NEWLINE_CRLF;
static const OnigOptionType MTCOnigOptionNotBOL = ONIG_OPTION_NOTBOL;
static const OnigOptionType MTCOnigOptionNotEOL = ONIG_OPTION_NOTEOL;

static const unsigned int MTCOnigSynNotNewlineInNegativeCC = ONIG_SYN_NOT_NEWLINE_IN_NEGATIVE_CC;

static const int MTCOnigMaxErrorMessageLength = ONIG_MAX_ERROR_MESSAGE_LEN;

/// onig_error_code_to_str is variadic, which Swift can't call; this covers the case with error info.
static inline int mtc_onig_error_message(OnigUChar *buffer, OnigPosition code, OnigErrorInfo *info) {
	return onig_error_code_to_str(buffer, code, info);
}

#endif
