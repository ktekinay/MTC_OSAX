#ifndef CFILEREFERENCES_H
#define CFILEREFERENCES_H

#include <stddef.h>
#include <stdint.h>

/// The size of an FSRef, the file reference SatimageOSAX returns as `fsrf` descriptors.
#define MTC_FSREF_SIZE 80

/// Makes an FSRef for an existing item at a POSIX path. Returns an OSStatus (0 on success, -43 if missing).
int32_t mtc_fsref_from_path(const char *path, uint8_t out[MTC_FSREF_SIZE]);

/// The POSIX path of an FSRef, into a buffer of `size` bytes. Returns an OSStatus.
int32_t mtc_path_from_fsref(const uint8_t ref[MTC_FSREF_SIZE], char *path, size_t size);

#endif
