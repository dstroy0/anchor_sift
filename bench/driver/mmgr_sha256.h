/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file mmgr_sha256.h
 * @brief SHA-256 over a span of bytes, for suites that need to say what a region holds.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note Test support, and an oracle. Nothing here is in the library and nothing in the library
 *       reaches it. A digest computed by the code under test would agree with that code whatever it
 *       did, which is the one thing an oracle may not do.
 * @note Written from FIPS 180-4 and checked against its published vectors by mmgr_sha256_self_test.
 *       A hash nobody verified is a number, not evidence.
 * @note What it buys over comparing bytes: a fingerprint survives where the bytes do not. A part can
 *       report 32 bytes over a serial line for a region too large to send, and a destination can be
 *       checked against an expectation nobody kept a copy of.
 */
#ifndef MMGR_TEST_SHA256_H
#define MMGR_TEST_SHA256_H

#include <stddef.h>
#include <stdint.h>

/**
 * @brief Bytes in a SHA-256 digest.
 */
#define MMGR_SHA256_BYTES 32u

/**
 * @brief Bytes in the block SHA-256 compresses.
 */
#define MMGR_SHA256_BLOCK_BYTES 64u

/**
 * @brief A digest being taken over bytes that arrive in pieces.
 *
 * @param state  The eight word hash state, as FIPS 180-4 carries it between blocks.
 * @param bits   Message length so far, in bits, which is what the padding writes at the end.
 * @param block  Bytes taken that do not yet fill a block.
 * @param filled How many of those there are.
 * @note Streaming rather than one shot, because the standard's own vectors do not fit otherwise. RFC
 *       6234 TEST3 is one million bytes and a Cortex-M4 has 192 KB of RAM, so a one shot form cannot
 *       run the case that exercises a length field past 2^23 bits.
 * @note Also the shape a caller wants for a transfer. A destination is hashed as it fills, without a
 *       second copy of it anywhere.
 */
typedef struct
{
    uint32_t state[8];
    uint64_t bits;
    uint8_t block[MMGR_SHA256_BLOCK_BYTES];
    size_t filled;
} MmgrSha256;

/**
 * @brief Starts a digest.
 *
 * @param[out] running Context to start [BORROWS].
 */
void mmgr_sha256_begin(MmgrSha256 *running);

/**
 * @brief Takes @p length more bytes into @p running.
 *
 * @param[in,out] running Context taking the bytes [BORROWS].
 * @param[in]     bytes   First byte to take [BORROWS].
 * @param[in]     length  How many. Zero takes nothing and is legal.
 * @note Any split gives the same answer as any other. That is what the streaming case proves, and it
 *       is why one vector below is fed in pieces that do not line up with the block.
 */
void mmgr_sha256_take(MmgrSha256 *running, const uint8_t *bytes, size_t length);

/**
 * @brief Finishes @p running and writes its digest.
 *
 * @param[in,out] running Context to finish [BORROWS].
 * @param[out]    digest  Where the 32 byte result is written [BORROWS].
 * @warning Leaves running spent. Start another with mmgr_sha256_begin.
 */
void mmgr_sha256_finish(MmgrSha256 *running, uint8_t digest[MMGR_SHA256_BYTES]);

/**
 * @brief Hashes @p length bytes at @p bytes in one call.
 *
 * @param[in]  bytes  First byte to hash [BORROWS].
 * @param[in]  length Bytes to hash. Zero is legal and gives the digest of the empty message.
 * @param[out] digest Where the 32 byte result is written [BORROWS].
 * @note The three above, in order. It exists because most callers hold the whole region already.
 * @warning bytes may be NULL only where length is zero.
 */
void mmgr_sha256(const uint8_t *bytes, size_t length, uint8_t digest[MMGR_SHA256_BYTES]);

/**
 * @brief Hashes @p bit_length bits at @p bytes, where the length need not be a whole number of them.
 *
 * @param[in]  bytes      First byte to hash [BORROWS].
 * @param[in]  bit_length Message length in bits. Any value, including one that is not a multiple of
 *                        eight.
 * @param[out] digest     Where the 32 byte result is written [BORROWS].
 * @note SHA-256 is defined over bit strings and the byte case is the specialization everyone uses.
 *       This is the general entry, and mmgr_sha256 is it with the length multiplied by eight.
 * @note The trailing bits sit in the high end of the final byte, most significant first, which is how
 *       the standard writes a partial byte and how CAVP's bit oriented vectors are packed. Bits below
 *       the stated length are ignored, so a caller need not clear them.
 * @note uint64_t rather than size_t, because the length field the standard writes is 64 bits and a
 *       16 bit part would otherwise cap the expressible message far below what the padding allows.
 * @warning bytes must hold ceil(bit_length / 8) bytes. Only the top bits of the last one are read.
 */
void mmgr_sha256_bits(const uint8_t *bytes, uint64_t bit_length, uint8_t digest[MMGR_SHA256_BYTES]);

/**
 * @brief Computes HMAC-SHA-256 of @p length bytes at @p bytes under @p key.
 *
 * @param[in]  key     Key bytes [BORROWS].
 * @param[in]  key_len Bytes in the key. Any length, including zero and longer than a block.
 * @param[in]  bytes   Message to authenticate [BORROWS].
 * @param[in]  length  Bytes in the message.
 * @param[out] tag     Where the 32 byte tag is written [BORROWS].
 * @note Here to test the hash, not because this tree needs a MAC. Wycheproof publishes adversarial
 *       HMAC-SHA-256 vectors and no bare SHA-256 vectors, and HMAC exercises the hash with keys, two
 *       nested digests and messages that straddle the block, so a hash that is wrong anywhere cannot
 *       produce a matching tag. It is a third party oracle reached through one extra layer.
 * @note RFC 2104: a key longer than a block is hashed first, a shorter one is zero padded.
 */
void mmgr_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *bytes, size_t length,
                      uint8_t tag[MMGR_SHA256_BYTES]);

/**
 * @brief Returns the offset of the first byte where two regions disagree.
 *
 * @param[in] left   First region [BORROWS].
 * @param[in] right  Second region [BORROWS].
 * @param[in] length Bytes to compare.
 * @return           The offset that disagrees, or @p length where every byte matches.
 * @note Reports where, not whether. A transfer that stopped part way names the byte it stopped at,
 *       and that number is what tells a stall from a wrong direction from a short count.
 * @note Byte exact and cheaper than hashing. Reach for the digest where one side is a fingerprint
 *       rather than a region, and for this where both regions are in front of you.
 */
size_t mmgr_sha256_first_difference(const uint8_t *left, const uint8_t *right, size_t length);

/**
 * @brief Returns the bit position where two bytes first disagree.
 *
 * @param[in] left  First byte.
 * @param[in] right Second byte.
 * @return          0 through 7 counting from the most significant bit, or 8 where they match.
 * @note The other half of locating corruption. The offset says which byte and this says which bit
 *       inside it, which is what separates a dropped bit from a wrong one.
 */
unsigned mmgr_sha256_first_bit_difference(uint8_t left, uint8_t right);

/**
 * @brief Checks this implementation against the RFC 6234 published vectors.
 *
 * @return 1 where every vector matched, 0 where any did not.
 * @note Run before any digest is trusted. The vectors are published, so agreeing with them is
 *       evidence about this code, where agreeing with another copy of this code is not.
 * @note RFC 6234 section 8.5 picks its four messages to sit on the padding boundaries: "abc" is one
 *       block with room, the 56 octet message pushes its padding into a second block, 640 octets is
 *       an exact multiple so the padding forms a whole block of its own, and one million bytes puts
 *       the length field past 2^23 bits over 15,625 compressions. Those four pin the compression
 *       function, the big endian length and the padding rule at once.
 * @note The empty message is the fifth, which RFC 8448 section 3 prints.
 * @warning The million byte vector is streamed in kilobyte pieces, so this needs about a kilobyte of
 *          stack and no more. Hashing it whole would want a megabyte and no part here has one.
 */
int mmgr_sha256_self_test(void);

#endif
