#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlIO.h>
#include <libxml/xmlsave.h>
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xpointer.h>
#include <libxml/xinclude.h>
#include <libxml/c14n.h>
#include <libxml/catalog.h>
#include <libxml/uri.h>
#include <libxml/valid.h>
#include <libxml/xmlschemas.h>
#include <libxml/relaxng.h>
#include <libxml/xmlregexp.h>
#include <libxslt/xslt.h>
#include <libxslt/xsltInternals.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <libexslt/exslt.h>
#include <libxml/xmlreader.h>

#include <stdarg.h>
#include <stdio.h>

// libxslt reports errors through a variadic callback, which Swift can't write. This one formats each message
// and hands it to a plain callback (MTC_OSAX's), which travels as libxslt's error context.
typedef void (*MTCXSLTErrorSink)(const char *text);

static void mtc_xslt_generic_error(void *context, const char *format, ...) {
	char text[4096];
	va_list arguments;
	va_start(arguments, format);
	vsnprintf(text, sizeof text, format, arguments);
	va_end(arguments);
	if (context) {
		((MTCXSLTErrorSink)context)(text);
	}
}

static inline void mtc_xslt_set_error_sink(MTCXSLTErrorSink sink) {
	xsltSetGenericErrorFunc((void *)sink, mtc_xslt_generic_error);
}
