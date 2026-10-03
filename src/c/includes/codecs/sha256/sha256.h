// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sha256.h: SHA-256 as FIPS 180-4 states it (section 6.2), over a message of whole bytes or of any count of bits
#ifndef SHA256_H
#define SHA256_H

#include <stddef.h>

// the bytes of a digest, and of the block the compression takes
#define SHA256_BYTES 32u
#define SHA256_BLOCK_BYTES 64u

// the digest of the `bytes` bytes at `data` into `digest`
void sha256(const void *data, size_t bytes, unsigned char digest[SHA256_BYTES]);

// the digest of the first `bits` bits at `data` into `digest`, each byte's bits read from its most significant down,
// as FIPS 180-4 and the published vectors order them. A count that is a multiple of 8 gives what sha256 gives
void sha256_bits(const void *data, unsigned long long bits, unsigned char digest[SHA256_BYTES]);

#endif
