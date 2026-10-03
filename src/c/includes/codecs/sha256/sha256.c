// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sha256.c: SHA-256 as FIPS 180-4 states it. The constants are section 4.2.2's and 5.3.3's, the functions section
// 4.1.2's, the padding section 5.1.1's and the compression section 6.2.2's
#include "sha256.h"

#include <limits.h>
#include <string.h>

_Static_assert(CHAR_BIT == 8, "sha256: a byte holds 8 bits");
_Static_assert(UINT_MAX >= 0xFFFFFFFFu, "sha256: an unsigned int holds a 32-bit word");

// the words of the hash value, of the message schedule and of a block
#define SHA256_STATE_WORDS 8u
#define SHA256_SCHEDULE_WORDS 64u
#define SHA256_BLOCK_WORDS 16u
// the bytes the padding ends on, the message length in bits
#define SHA256_LENGTH_BYTES 8u

// the first 32 bits of the fractional parts of the cube roots of the first 64 primes (section 4.2.2)
static const unsigned int s_round_constant[SHA256_SCHEDULE_WORDS] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

// the first 32 bits of the fractional parts of the square roots of the first 8 primes (section 5.3.3)
static const unsigned int s_initial_state[SHA256_STATE_WORDS] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                                                 0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

// `word` rotated right by `count`, 0 < count < 32, kept to 32 bits
static unsigned int sha256_rotate(unsigned int word, unsigned int count)
{
    return ((word >> count) | (word << (32u - count))) & 0xFFFFFFFFu;
}

// the four big-endian bytes at `bytes` as one word
static unsigned int sha256_word_read(const unsigned char *bytes)
{
    return ((unsigned int)bytes[0] << 24) | ((unsigned int)bytes[1] << 16) | ((unsigned int)bytes[2] << 8) |
           (unsigned int)bytes[3];
}

// the hash value `state` carried through the 64-byte block at `block` (section 6.2.2)
static void sha256_compress(unsigned int state[SHA256_STATE_WORDS], const unsigned char block[SHA256_BLOCK_BYTES])
{
    unsigned int schedule[SHA256_SCHEDULE_WORDS];
    for (unsigned int round = 0u; round < SHA256_BLOCK_WORDS; round += 1u)
    {
        schedule[round] = sha256_word_read(&block[4u * round]);
    }
    for (unsigned int round = SHA256_BLOCK_WORDS; round < SHA256_SCHEDULE_WORDS; round += 1u)
    {
        const unsigned int far = schedule[round - 15u];
        const unsigned int near = schedule[round - 2u];
        const unsigned int small_sigma0 = sha256_rotate(far, 7u) ^ sha256_rotate(far, 18u) ^ (far >> 3);
        const unsigned int small_sigma1 = sha256_rotate(near, 17u) ^ sha256_rotate(near, 19u) ^ (near >> 10);
        schedule[round] = (small_sigma1 + schedule[round - 7u] + small_sigma0 + schedule[round - 16u]) & 0xFFFFFFFFu;
    }
    // the working variables a to h of section 6.2.2 step 2, in that order
    unsigned int working[SHA256_STATE_WORDS];
    memcpy(working, state, sizeof(working));
    for (unsigned int round = 0u; round < SHA256_SCHEDULE_WORDS; round += 1u)
    {
        const unsigned int big_sigma1 =
            sha256_rotate(working[4], 6u) ^ sha256_rotate(working[4], 11u) ^ sha256_rotate(working[4], 25u);
        const unsigned int choose = (working[4] & working[5]) ^ (~working[4] & working[6]);
        const unsigned int first =
            (working[7] + big_sigma1 + choose + s_round_constant[round] + schedule[round]) & 0xFFFFFFFFu;
        const unsigned int big_sigma0 =
            sha256_rotate(working[0], 2u) ^ sha256_rotate(working[0], 13u) ^ sha256_rotate(working[0], 22u);
        const unsigned int majority = (working[0] & working[1]) ^ (working[0] & working[2]) ^ (working[1] & working[2]);
        const unsigned int second = (big_sigma0 + majority) & 0xFFFFFFFFu;
        working[7] = working[6];
        working[6] = working[5];
        working[5] = working[4];
        working[4] = (working[3] + first) & 0xFFFFFFFFu;
        working[3] = working[2];
        working[2] = working[1];
        working[1] = working[0];
        working[0] = (first + second) & 0xFFFFFFFFu;
    }
    for (unsigned int word = 0u; word < SHA256_STATE_WORDS; word += 1u)
    {
        state[word] = (state[word] + working[word]) & 0xFFFFFFFFu;
    }
}

void sha256_bits(const void *data, unsigned long long bits, unsigned char digest[SHA256_BYTES])
{
    const unsigned char *const message = (const unsigned char *)data;
    unsigned int state[SHA256_STATE_WORDS];
    memcpy(state, s_initial_state, sizeof(state));
    // every whole block of the message, then the bytes past the last one, the padding laid after them (section 5.1.1)
    const unsigned long long whole_bytes = bits / 8ull;
    const unsigned int spare_bits = (unsigned int)(bits % 8ull);
    const unsigned long long blocks = whole_bytes / SHA256_BLOCK_BYTES;
    for (unsigned long long block = 0ull; block < blocks; block += 1ull)
    {
        sha256_compress(state, &message[block * SHA256_BLOCK_BYTES]);
    }
    unsigned char tail[2u * SHA256_BLOCK_BYTES];
    memset(tail, 0, sizeof(tail));
    const size_t left = (size_t)(whole_bytes - (blocks * SHA256_BLOCK_BYTES));
    memcpy(tail, &message[blocks * SHA256_BLOCK_BYTES], left);
    // the bits of a byte the message ends partway through are its most significant, and the 1 the padding begins
    // with is the next bit down
    const unsigned int kept = (spare_bits == 0u) ? 0u : (unsigned int)message[whole_bytes] & (0xFF00u >> spare_bits);
    tail[left] = (unsigned char)(kept | (0x80u >> spare_bits));
    const size_t tail_bytes =
        ((left + 1u + SHA256_LENGTH_BYTES) <= SHA256_BLOCK_BYTES) ? SHA256_BLOCK_BYTES : (2u * SHA256_BLOCK_BYTES);
    for (unsigned int at = 0u; at < SHA256_LENGTH_BYTES; at += 1u)
    {
        tail[tail_bytes - 1u - at] = (unsigned char)((bits >> (8u * at)) & 0xFFull);
    }
    for (size_t block = 0u; block < tail_bytes; block += SHA256_BLOCK_BYTES)
    {
        sha256_compress(state, &tail[block]);
    }
    for (unsigned int word = 0u; word < SHA256_STATE_WORDS; word += 1u)
    {
        digest[4u * word] = (unsigned char)(state[word] >> 24);
        digest[(4u * word) + 1u] = (unsigned char)(state[word] >> 16);
        digest[(4u * word) + 2u] = (unsigned char)(state[word] >> 8);
        digest[(4u * word) + 3u] = (unsigned char)state[word];
    }
}

void sha256(const void *data, size_t bytes, unsigned char digest[SHA256_BYTES])
{
    sha256_bits(data, 8ull * (unsigned long long)bytes, digest);
}
