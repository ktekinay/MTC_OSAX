// FSRef functions are deprecated and unavailable to Swift, but still work on Apple silicon, and Apple event
// coercions from `fsrf` (to aliases and file URLs) need them.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#include "CFileReferences.h"
#include <CoreServices/CoreServices.h>
#include <string.h>

_Static_assert(sizeof(FSRef) == MTC_FSREF_SIZE, "FSRef size");

int32_t mtc_fsref_from_path(const char *path, uint8_t out[MTC_FSREF_SIZE]) {
	FSRef ref;
	// The item itself, not what a final symbolic link points to: glob returned, for a link, a reference to its
	// target, so deleting what glob listed deleted the targets and left the links.
	OSStatus status = FSPathMakeRefWithOptions((const UInt8 *)path, kFSPathMakeRefDoNotFollowLeafSymlink, &ref, NULL);
	if (status == noErr) {
		memcpy(out, &ref, sizeof ref);
	}
	return status;
}

int32_t mtc_path_from_fsref(const uint8_t ref[MTC_FSREF_SIZE], char *path, size_t size) {
	FSRef copy;
	memcpy(&copy, ref, sizeof copy);
	return FSRefMakePath(&copy, (UInt8 *)path, (UInt32)size);
}
