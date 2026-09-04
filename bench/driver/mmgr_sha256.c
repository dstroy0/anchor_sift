/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file mmgr_sha256.c
 * @brief SHA-256 as FIPS 180-4 states it, with the six functions forced inline.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note The six helpers are one expression each and every one is called eight times a round. Left as
 *       calls they cost a frame each time for work that is three instructions, so they carry the
 *       always-inline attribute.
 * @note What inlining buys is not the same on every part. On any of them it removes the call, the
 *       return and the stack traffic. On a superscalar host it also lets the compiler interleave the
 *       independent chains, since S1(e) and Ch(e,f,g) share no operand and can issue together. A
 *       Cortex-M4 is single issue and in order, so it takes the first win and none of the second.
 * @note Everything is unsigned 32 bit and wraps on purpose, which is what the standard specifies.
 */
#include "mmgr_sha256.h"

#include "mmgr.h"

/**
 * @brief Rotates @p value right by @p places, at 32 bits.
 *
 * @param[in] value_  Word to rotate.
 * @param[in] places_ How far, from 1 through 31.
 * @return            The rotated word.
 * @note Both parameters are parenthesized. Without that, a caller passing an expression gets the
 *       shift bound to part of it, and the digest is wrong in a way no vector below would explain.
 * @warning places_ must be 1 through 31. At 0 the left shift is by 32, which is undefined for a 32
 *          bit type, and no call here reaches it.
 */
#define MMGR_SHA256_ROTATE(value_, places_)                                                                            \
    (((value_) >> (places_)) | ((value_) << (32u - (places_))))

/**
 * @brief Chooses between @p y and @p z, bit by bit, on @p x.
 *
 * @param[in] x Selector word.
 * @param[in] y Word taken where a bit of x is set.
 * @param[in] z Word taken where it is clear.
 * @return      The chosen bits, as FIPS 180-4 Ch.
 * @note Written as the standard writes it. A host with BMI2 folds the second half into one andn
 *       instruction; a Cortex-M4 has no such instruction and takes the two operations.
 */
EMBED_INLINE uint32_t mmgr_sha256_choose(uint32_t x, uint32_t y, uint32_t z)
{
    return (x & y) ^ (~x & z);
}

/**
 * @brief Returns the majority bit of @p x, @p y and @p z, bit by bit.
 *
 * @param[in] x First word.
 * @param[in] y Second word.
 * @param[in] z Third word.
 * @return      The majority bits, as FIPS 180-4 Maj.
 */
EMBED_INLINE uint32_t mmgr_sha256_majority(uint32_t x, uint32_t y, uint32_t z)
{
    return (x & y) ^ (x & z) ^ (y & z);
}

/**
 * @brief The upper case sigma zero of FIPS 180-4, over @p x.
 *
 * @param[in] x Word to mix.
 * @return      The mixed word.
 */
EMBED_INLINE uint32_t mmgr_sha256_big_sigma0(uint32_t x)
{
    return MMGR_SHA256_ROTATE(x, 2) ^ MMGR_SHA256_ROTATE(x, 13) ^ MMGR_SHA256_ROTATE(x, 22);
}

/**
 * @brief The upper case sigma one of FIPS 180-4, over @p x.
 *
 * @param[in] x Word to mix.
 * @return      The mixed word.
 */
EMBED_INLINE uint32_t mmgr_sha256_big_sigma1(uint32_t x)
{
    return MMGR_SHA256_ROTATE(x, 6) ^ MMGR_SHA256_ROTATE(x, 11) ^ MMGR_SHA256_ROTATE(x, 25);
}

/**
 * @brief The lower case sigma zero of FIPS 180-4, over @p x.
 *
 * @param[in] x Word to mix.
 * @return      The mixed word.
 * @note The third term is a shift and not a rotate, which is the whole difference between this and
 *       the upper case form.
 */
EMBED_INLINE uint32_t mmgr_sha256_small_sigma0(uint32_t x)
{
    return MMGR_SHA256_ROTATE(x, 7) ^ MMGR_SHA256_ROTATE(x, 18) ^ (x >> 3);
}

/**
 * @brief The lower case sigma one of FIPS 180-4, over @p x.
 *
 * @param[in] x Word to mix.
 * @return      The mixed word.
 */
EMBED_INLINE uint32_t mmgr_sha256_small_sigma1(uint32_t x)
{
    return MMGR_SHA256_ROTATE(x, 17) ^ MMGR_SHA256_ROTATE(x, 19) ^ (x >> 10);
}

/**
 * @brief The sixty four round constants, which are the cube roots of the first sixty four primes.
 *
 * @note Written out rather than computed. The standard publishes them, and a table derived here
 *       would be this file checking its own arithmetic.
 */
static const uint32_t s_round_constants[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

/**
 * @brief The eight starting words, which are the square roots of the first eight primes.
 */
static const uint32_t s_initial_state[8] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au, 0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
};

/**
 * @brief Compresses one 64 byte block into @p state.
 *
 * @param[in,out] state One eight word hash state [BORROWS].
 * @param[in]     block The 64 bytes to take in [BORROWS].
 * @note The message schedule is 64 words and lives here, so nothing carries it between blocks.
 * @note Big endian on the way in, whatever the part is. The standard reads the message as bytes and
 *       assembles them, which is what the shifts below do without asking what order the part stores
 *       a word in.
 */
static void mmgr_sha256_compress(uint32_t *state, const uint8_t *block)
{
    uint32_t schedule[64];

    for (unsigned index = 0u; index < 16u; index++)
    {
        // Assembled from bytes rather than read as a word, so the part's own byte order takes no
        // part in the answer
        schedule[index] = ((uint32_t)block[(index * 4u) + 0u] << 24) | ((uint32_t)block[(index * 4u) + 1u] << 16) |
                          ((uint32_t)block[(index * 4u) + 2u] << 8) | ((uint32_t)block[(index * 4u) + 3u]);
    }

    for (unsigned index = 16u; index < 64u; index++)
    {
        schedule[index] = mmgr_sha256_small_sigma1(schedule[index - 2u]) + schedule[index - 7u] +
                          mmgr_sha256_small_sigma0(schedule[index - 15u]) + schedule[index - 16u];
    }

    uint32_t working[8];

    for (unsigned index = 0u; index < 8u; index++)
    {
        working[index] = state[index];
    }

    for (unsigned round = 0u; round < 64u; round++)
    {
        const uint32_t first = working[7] + mmgr_sha256_big_sigma1(working[4]) +
                               mmgr_sha256_choose(working[4], working[5], working[6]) + s_round_constants[round] +
                               schedule[round];
        const uint32_t second = mmgr_sha256_big_sigma0(working[0]) +
                                mmgr_sha256_majority(working[0], working[1], working[2]);

        working[7] = working[6];
        working[6] = working[5];
        working[5] = working[4];
        working[4] = working[3] + first;
        working[3] = working[2];
        working[2] = working[1];
        working[1] = working[0];
        working[0] = first + second;
    }

    for (unsigned index = 0u; index < 8u; index++)
    {
        state[index] += working[index];
    }
}

void mmgr_sha256_begin(MmgrSha256 *running)
{
    for (unsigned index = 0u; index < 8u; index++)
    {
        running->state[index] = s_initial_state[index];
    }
    running->bits = 0u;
    running->filled = 0u;
}

void mmgr_sha256_take(MmgrSha256 *running, const uint8_t *bytes, size_t length)
{
    running->bits += (uint64_t)length * 8u;

    size_t taken = 0u;

    // Fill whatever the last call left part done, and compress it once it is a whole block
    if (running->filled != 0u)
    {
        while ((taken < length) && (running->filled < MMGR_SHA256_BLOCK_BYTES))
        {
            running->block[running->filled] = bytes[taken];
            running->filled++;
            taken++;
        }
        if (running->filled == MMGR_SHA256_BLOCK_BYTES)
        {
            mmgr_sha256_compress(running->state, running->block);
            running->filled = 0u;
        }
    }

    // Whole blocks straight out of the caller's bytes, with nothing copied
    while ((length - taken) >= MMGR_SHA256_BLOCK_BYTES)
    {
        mmgr_sha256_compress(running->state, &bytes[taken]);
        taken += MMGR_SHA256_BLOCK_BYTES;
    }

    while (taken < length)
    {
        running->block[running->filled] = bytes[taken];
        running->filled++;
        taken++;
    }
}

/**
 * @brief Finishes a digest with the terminator byte and bit count stated outright.
 *
 * @param[in,out] running    Context to finish [BORROWS].
 * @param[in]     marker     Byte written where the message ends: 0x80 on a byte boundary, or the
 *                           partial bits with the terminator bit already set into them.
 * @param[in]     total_bits Message length in bits, which is what the standard's length field holds.
 * @param[out]    digest     Where the 32 byte result is written [BORROWS].
 * @note The standard defines SHA-256 over bit strings and the byte case is the common specialization
 *       of it. Both entries below are this function with the two arguments filled in differently, so
 *       there is one padding implementation and no second copy to disagree with the first.
 */
static void mmgr_sha256_finish_with(MmgrSha256 *running, uint8_t marker, uint64_t total_bits,
                                    uint8_t digest[MMGR_SHA256_BYTES])
{
    // The marker, then zeros, then the length. Where the marker leaves under eight bytes of room the
    // length goes into a second block, which is the case RFC 6234 TEST2_1 exists to reach
    const size_t left = running->filled;
    uint8_t tail[MMGR_SHA256_BLOCK_BYTES * 2u];

    for (size_t index = 0u; index < (MMGR_SHA256_BLOCK_BYTES * 2u); index++)
    {
        tail[index] = 0u;
    }
    for (size_t index = 0u; index < left; index++)
    {
        tail[index] = running->block[index];
    }

    tail[left] = marker;

    const size_t tail_blocks = (left >= (MMGR_SHA256_BLOCK_BYTES - 8u)) ? 2u : 1u;
    const size_t tail_bytes = tail_blocks * MMGR_SHA256_BLOCK_BYTES;

    // The length in bits, big endian, in the last eight bytes. Written a byte at a time so the part's
    // own word order takes no part in where they land
    uint64_t bits = total_bits;

    for (unsigned index = 0u; index < 8u; index++)
    {
        // Explicit cast narrows one byte out of the count. The shift picks it, so nothing is lost
        tail[tail_bytes - 1u - index] = (uint8_t)(bits & 0xFFu);
        bits >>= 8;
    }

    for (size_t block = 0u; block < tail_blocks; block++)
    {
        mmgr_sha256_compress(running->state, &tail[block * MMGR_SHA256_BLOCK_BYTES]);
    }

    for (unsigned index = 0u; index < 8u; index++)
    {
        // Explicit casts narrow each word to the four bytes it occupies, most significant first
        digest[(index * 4u) + 0u] = (uint8_t)((running->state[index] >> 24) & 0xFFu);
        digest[(index * 4u) + 1u] = (uint8_t)((running->state[index] >> 16) & 0xFFu);
        digest[(index * 4u) + 2u] = (uint8_t)((running->state[index] >> 8) & 0xFFu);
        digest[(index * 4u) + 3u] = (uint8_t)(running->state[index] & 0xFFu);
    }
}

void mmgr_sha256_finish(MmgrSha256 *running, uint8_t digest[MMGR_SHA256_BYTES])
{
    mmgr_sha256_finish_with(running, 0x80u, running->bits, digest);
}

void mmgr_sha256(const uint8_t *bytes, size_t length, uint8_t digest[MMGR_SHA256_BYTES])
{
    MmgrSha256 running;

    mmgr_sha256_begin(&running);
    mmgr_sha256_take(&running, bytes, length);
    mmgr_sha256_finish(&running, digest);
}

void mmgr_sha256_bits(const uint8_t *bytes, uint64_t bit_length, uint8_t digest[MMGR_SHA256_BYTES])
{
    MmgrSha256 running;

    // Whole bytes go in the ordinary way. What is left is under eight bits, sitting in the high end
    // of one more byte, which is how the standard writes a partial final byte and how CAVP's bit
    // oriented vectors are packed
    const size_t whole = (size_t)(bit_length / 8u);
    const unsigned spare = (unsigned)(bit_length % 8u);

    mmgr_sha256_begin(&running);
    mmgr_sha256_take(&running, bytes, whole);

    if (spare == 0u)
    {
        mmgr_sha256_finish_with(&running, 0x80u, bit_length, digest);
        return;
    }

    // Keep the spare high bits, drop everything under them, and set the terminator in the next bit
    // down. Explicit casts keep the mask and the result at byte width through the integer promotions
    const uint8_t kept = (uint8_t)(bytes[whole] & (uint8_t)(0xFFu << (8u - spare)));
    const uint8_t marker = (uint8_t)(kept | (uint8_t)(0x80u >> spare));

    mmgr_sha256_finish_with(&running, marker, bit_length, digest);
}

void mmgr_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *bytes, size_t length,
                      uint8_t tag[MMGR_SHA256_BYTES])
{
    uint8_t block[MMGR_SHA256_BLOCK_BYTES];
    uint8_t inner[MMGR_SHA256_BYTES];
    MmgrSha256 running;

    for (size_t index = 0u; index < MMGR_SHA256_BLOCK_BYTES; index++)
    {
        block[index] = 0u;
    }

    // A key longer than a block is hashed down to one, which is RFC 2104's rule and also the case
    // Wycheproof reaches with its long key vectors
    if (key_len > MMGR_SHA256_BLOCK_BYTES)
    {
        mmgr_sha256(key, key_len, block);
    }
    else
    {
        for (size_t index = 0u; index < key_len; index++)
        {
            block[index] = key[index];
        }
    }

    uint8_t pad[MMGR_SHA256_BLOCK_BYTES];

    for (size_t index = 0u; index < MMGR_SHA256_BLOCK_BYTES; index++)
    {
        pad[index] = (uint8_t)(block[index] ^ 0x36u);
    }
    mmgr_sha256_begin(&running);
    mmgr_sha256_take(&running, pad, MMGR_SHA256_BLOCK_BYTES);
    mmgr_sha256_take(&running, bytes, length);
    mmgr_sha256_finish(&running, inner);

    for (size_t index = 0u; index < MMGR_SHA256_BLOCK_BYTES; index++)
    {
        pad[index] = (uint8_t)(block[index] ^ 0x5Cu);
    }
    mmgr_sha256_begin(&running);
    mmgr_sha256_take(&running, pad, MMGR_SHA256_BLOCK_BYTES);
    mmgr_sha256_take(&running, inner, MMGR_SHA256_BYTES);
    mmgr_sha256_finish(&running, tag);
}

size_t mmgr_sha256_first_difference(const uint8_t *left, const uint8_t *right, size_t length)
{
    for (size_t offset = 0u; offset < length; offset++)
    {
        if (left[offset] != right[offset])
        {
            return offset;
        }
    }
    return length;
}

unsigned mmgr_sha256_first_bit_difference(uint8_t left, uint8_t right)
{
    const uint8_t differing = (uint8_t)(left ^ right);

    if (differing == 0u)
    {
        return 8u;
    }

    for (unsigned bit = 0u; bit < 8u; bit++)
    {
        // Most significant first, so the answer counts the way the byte is written down
        if ((differing & (uint8_t)(0x80u >> bit)) != 0u)
        {
            return bit;
        }
    }
    return 8u;
}

/**
 * @brief One published vector: a message and the digest FIPS 180-4 says it has.
 *
 * @param message Text to hash, without its terminator.
 * @param digest  The 32 byte answer, as the standard prints it.
 */
typedef struct
{
    const char *message;
    unsigned repeats;
    const uint8_t digest[MMGR_SHA256_BYTES];
} MmgrSha256Vector;

/**
 * @brief The vectors this implementation is held to, and how many times each message repeats.
 *
 * @note RFC 6234 section 8.5 picks these to sit on the padding boundaries. "abc" is one block with
 *       room to spare. The 56 octet message leaves under eight bytes after its marker, so the length
 *       is pushed into a second block. The 64 octet unit fed ten times is 640 octets, an exact
 *       multiple of the block, so the padding forms a whole block on its own with no message in it.
 * @note The empty message is RFC 8448 section 3's Transcript-Hash("").
 * @note The fourth entry repeats, which is also what makes it a streaming case: ten takes of 64
 *       bytes must reach the same digest as one take of 640.
 */
static const MmgrSha256Vector s_vectors[4] = {
    {
        "",
        1u,
        {0xe3u, 0xb0u, 0xc4u, 0x42u, 0x98u, 0xfcu, 0x1cu, 0x14u, 0x9au, 0xfbu, 0xf4u, 0xc8u, 0x99u, 0x6fu, 0xb9u,
         0x24u, 0x27u, 0xaeu, 0x41u, 0xe4u, 0x64u, 0x9bu, 0x93u, 0x4cu, 0xa4u, 0x95u, 0x99u, 0x1bu, 0x78u, 0x52u,
         0xb8u, 0x55u},
    },
    {
        "abc",
        1u,
        {0xbau, 0x78u, 0x16u, 0xbfu, 0x8fu, 0x01u, 0xcfu, 0xeau, 0x41u, 0x41u, 0x40u, 0xdeu, 0x5du, 0xaeu, 0x22u,
         0x23u, 0xb0u, 0x03u, 0x61u, 0xa3u, 0x96u, 0x17u, 0x7au, 0x9cu, 0xb4u, 0x10u, 0xffu, 0x61u, 0xf2u, 0x00u,
         0x15u, 0xadu},
    },
    {
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        1u,
        {0x24u, 0x8du, 0x6au, 0x61u, 0xd2u, 0x06u, 0x38u, 0xb8u, 0xe5u, 0xc0u, 0x26u, 0x93u, 0x0cu, 0x3eu, 0x60u,
         0x39u, 0xa3u, 0x3cu, 0xe4u, 0x59u, 0x64u, 0xffu, 0x21u, 0x67u, 0xf6u, 0xecu, 0xedu, 0xd4u, 0x19u, 0xdbu,
         0x06u, 0xc1u},
    },
    {
        "0123456701234567012345670123456701234567012345670123456701234567",
        10u,
        {0x59u, 0x48u, 0x47u, 0x32u, 0x84u, 0x51u, 0xbdu, 0xfau, 0x85u, 0x05u, 0x62u, 0x25u, 0x46u, 0x2cu, 0xc1u,
         0xd8u, 0x67u, 0xd8u, 0x77u, 0xfbu, 0x38u, 0x8du, 0xf0u, 0xceu, 0x35u, 0xf2u, 0x5au, 0xb5u, 0x56u, 0x2bu,
         0xfbu, 0xb5u},
    },
};

/**
 * @brief The digest of one million 'a', which RFC 6234 section 8.5 gives as TEST3.
 *
 * @note Its own entry because the message is a megabyte and no table holds one. The length field
 *       lands past 2^23 bits over 15,625 compressions, which nothing else here reaches.
 */
static const uint8_t s_million_a_digest[MMGR_SHA256_BYTES] = {
    0xcdu, 0xc7u, 0x6eu, 0x5cu, 0x99u, 0x14u, 0xfbu, 0x92u, 0x81u, 0xa1u, 0xc7u, 0xe2u, 0x84u, 0xd7u, 0x3eu, 0x67u,
    0xf1u, 0x80u, 0x9au, 0x48u, 0xa4u, 0x97u, 0x20u, 0x0eu, 0x04u, 0x6du, 0x39u, 0xccu, 0xc7u, 0x11u, 0x2cu, 0xd0u,
};

int mmgr_sha256_self_test(void)
{
    for (unsigned index = 0u; index < (sizeof s_vectors / sizeof s_vectors[0]); index++)
    {
        uint8_t got[MMGR_SHA256_BYTES];
        MmgrSha256 running;
        size_t length = 0u;

        while (s_vectors[index].message[length] != '\0')
        {
            length++;
        }

        mmgr_sha256_begin(&running);
        for (unsigned again = 0u; again < s_vectors[index].repeats; again++)
        {
            mmgr_sha256_take(&running, (const uint8_t *)s_vectors[index].message, length);
        }
        mmgr_sha256_finish(&running, got);

        if (mmgr_sha256_first_difference(got, s_vectors[index].digest, MMGR_SHA256_BYTES) != MMGR_SHA256_BYTES)
        {
            return 0;
        }
    }

    // One million 'a', fed as a thousand takes of a thousand bytes. The pieces do not line up with
    // the 64 byte block, which is what makes this the case that proves any split reaches one answer
    uint8_t chunk[1000];
    uint8_t got[MMGR_SHA256_BYTES];
    MmgrSha256 running;

    for (size_t index = 0u; index < sizeof chunk; index++)
    {
        chunk[index] = (uint8_t)'a';
    }

    mmgr_sha256_begin(&running);
    for (unsigned again = 0u; again < 1000u; again++)
    {
        mmgr_sha256_take(&running, chunk, sizeof chunk);
    }
    mmgr_sha256_finish(&running, got);

    if (mmgr_sha256_first_difference(got, s_million_a_digest, MMGR_SHA256_BYTES) != MMGR_SHA256_BYTES)
    {
        return 0;
    }
    return 1;
}
