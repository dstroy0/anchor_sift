/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file sha256_core.c
 * @brief The compression function, the eight-lane arm, and the anchor that ends most nonces early.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The anchor here is the construction anchor_sift.md states in section 2.2, carried onto a
 *       different domain. An occurrence is a nonce whose doubled digest lands at or below the share
 *       target. The domain is the digest's two hundred fifty six bits. The anchor is the most
 *       significant thirty two of them, which every target at difficulty one or above requires to be
 *       zero. Rejection there is exact and final, so no nonce that would have won is ever discarded.
 * @note Section 2.3 applies without softening: passing the anchor establishes nothing, and a survivor
 *       still pays the full ordering against the target. That compare is in sha256_state_within_target
 *       and no amount of knowledge about the digest removes it.
 * @warning What the anchor buys here is the tail of the second compression, alone. Section
 *          2.5 prices a filter by how cheaply its bits can be read, and in a corpus an anchor byte is
 *          one load. Here the anchor bits are an output of the very hash being tested, so the count of
 *          SHA-256 evaluations is untouched. Anyone reading a speedup larger than the tail into this
 *          file has misread it.
 */

#include "sha256_core.h"

#include <math.h>
#include <string.h>

#if defined(__AVX2__)
#include <immintrin.h>
#endif

// Both arms of every gate below are defined, so an #if here always has a value and a missing one
// cannot read as a silent false.
#if defined(_MSC_VER)
#define SHA256_HAS_GNU_CPUID 0
#define SHA256_HAS_MSVC_CPUID 1
#include <intrin.h>
#elif defined(__GNUC__)
#define SHA256_HAS_GNU_CPUID 1
#define SHA256_HAS_MSVC_CPUID 0
#include <cpuid.h>
#else
#define SHA256_HAS_GNU_CPUID 0
#define SHA256_HAS_MSVC_CPUID 0
#endif

// Alignment, spelled the way each compiler spells it. Both arms are defined, and a build where
// neither applies still compiles correctly because the attribute only costs speed when absent.
#if defined(_MSC_VER)
#define SHA256_ALIGN_32 __declspec(align(32))
#elif defined(__GNUC__)
#define SHA256_ALIGN_32 __attribute__((aligned(32)))
#else
#define SHA256_ALIGN_32
#endif

/** @brief The standard's initial chaining value, the first thirty-two bits of the square roots. */
static const uint32_t s_sha256_initial_state[SHA256_STATE_WORDS] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

/** @brief The standard's round constants, the first thirty-two bits of the cube roots. */
static const uint32_t s_sha256_round_constant[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
    0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
    0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
    0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
    0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
    0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
    0xc67178f2u};

/** @brief The message length field for an eighty byte header, in bits. */
#define HEADER_LENGTH_BITS 0x00000280u

/** @brief The message length field for a thirty-two byte digest, in bits. */
#define DIGEST_LENGTH_BITS 0x00000100u

/** @brief The padding word that follows the final message byte. */
#define PADDING_LEAD_WORD 0x80000000u

/** @brief How many nonce groups pass between reads of the abandon flag. */
#define ABANDON_POLL_GROUPS 1024u

/**
 * @brief Rotates a word right, the only rotation SHA-256 uses.
 *
 * @param[in] value    Word to rotate.
 * @param[in] distance How far, between one and thirty-one.
 * @return             The rotated word.
 */
static inline uint32_t rotate_right(uint32_t value, unsigned distance)
{
    return (value >> distance) | (value << (32u - distance));
}

/**
 * @brief Reads four bytes as one big-endian word, the order the standard reads in.
 *
 * @param[in] bytes Four bytes to read [BORROWS].
 * @return          The word they spell.
 */
static inline uint32_t read_big_endian_word(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

/**
 * @brief Writes one word as four big-endian bytes.
 *
 * @param[out] bytes Four bytes to write [BORROWS].
 * @param[in]  value The word to spell.
 */
static inline void write_big_endian_word(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)(value >> 24);
    bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8);
    bytes[3] = (uint8_t)value;
}

/**
 * @brief Reverses a word's bytes, turning a state word into the order the protocol orders in.
 *
 * @param[in] value Word to reverse.
 * @return          The reversed word.
 */
static inline uint32_t reverse_word_bytes(uint32_t value)
{
    return ((value >> 24) & 0x000000FFu) | ((value >> 8) & 0x0000FF00u) |
           ((value << 8) & 0x00FF0000u) | ((value << 24) & 0xFF000000u);
}

void sha256_state_init(Sha256State *state)
{
    memcpy(state->word, s_sha256_initial_state, sizeof(s_sha256_initial_state));
}

void sha256_block_compress(Sha256State *state, const uint32_t *message_block)
{
    uint32_t schedule[64];

    for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
    {
        schedule[slot] = message_block[slot];
    }
    for (unsigned slot = SHA256_BLOCK_WORDS; slot < 64u; slot += 1u)
    {
        const uint32_t back_fifteen = schedule[slot - 15u];
        const uint32_t back_two = schedule[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^ rotate_right(back_fifteen, 18u) ^
                                    (back_fifteen >> 3u);
        const uint32_t spread_high = rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^
                                     (back_two >> 10u);
        schedule[slot] = spread_high + schedule[slot - 7u] + spread_low + schedule[slot - 16u];
    }

    uint32_t state_a = state->word[0];
    uint32_t state_b = state->word[1];
    uint32_t state_c = state->word[2];
    uint32_t state_d = state->word[3];
    uint32_t state_e = state->word[4];
    uint32_t state_f = state->word[5];
    uint32_t state_g = state->word[6];
    uint32_t state_h = state->word[7];

    for (unsigned round = 0u; round < 64u; round += 1u)
    {
        const uint32_t mix_high = rotate_right(state_e, 6u) ^ rotate_right(state_e, 11u) ^
                                  rotate_right(state_e, 25u);
        const uint32_t choose = state_g ^ (state_e & (state_f ^ state_g));
        const uint32_t carry_one = state_h + mix_high + choose + s_sha256_round_constant[round] +
                                   schedule[round];
        const uint32_t mix_low = rotate_right(state_a, 2u) ^ rotate_right(state_a, 13u) ^
                                 rotate_right(state_a, 22u);
        const uint32_t majority = (state_a & state_b) | (state_c & (state_a ^ state_b));
        const uint32_t carry_two = mix_low + majority;

        state_h = state_g;
        state_g = state_f;
        state_f = state_e;
        state_e = state_d + carry_one;
        state_d = state_c;
        state_c = state_b;
        state_b = state_a;
        state_a = carry_one + carry_two;
    }

    state->word[0] += state_a;
    state->word[1] += state_b;
    state->word[2] += state_c;
    state->word[3] += state_d;
    state->word[4] += state_e;
    state->word[5] += state_f;
    state->word[6] += state_g;
    state->word[7] += state_h;
}

void sha256_block_compress_partial(Sha256State *state, const uint32_t *message_block,
                                   unsigned rounds)
{
    uint32_t schedule[64];

    if (rounds > 64u)
    {
        rounds = 64u;
    }

    for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
    {
        schedule[slot] = message_block[slot];
    }
    for (unsigned slot = SHA256_BLOCK_WORDS; slot < 64u; slot += 1u)
    {
        const uint32_t back_fifteen = schedule[slot - 15u];
        const uint32_t back_two = schedule[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^ rotate_right(back_fifteen, 18u) ^
                                    (back_fifteen >> 3u);
        const uint32_t spread_high = rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^
                                     (back_two >> 10u);
        schedule[slot] = spread_high + schedule[slot - 7u] + spread_low + schedule[slot - 16u];
    }

    uint32_t state_a = state->word[0];
    uint32_t state_b = state->word[1];
    uint32_t state_c = state->word[2];
    uint32_t state_d = state->word[3];
    uint32_t state_e = state->word[4];
    uint32_t state_f = state->word[5];
    uint32_t state_g = state->word[6];
    uint32_t state_h = state->word[7];

    for (unsigned round = 0u; round < rounds; round += 1u)
    {
        const uint32_t mix_high = rotate_right(state_e, 6u) ^ rotate_right(state_e, 11u) ^
                                  rotate_right(state_e, 25u);
        const uint32_t choose = state_g ^ (state_e & (state_f ^ state_g));
        const uint32_t carry_one = state_h + mix_high + choose + s_sha256_round_constant[round] +
                                   schedule[round];
        const uint32_t mix_low = rotate_right(state_a, 2u) ^ rotate_right(state_a, 13u) ^
                                 rotate_right(state_a, 22u);
        const uint32_t majority = (state_a & state_b) | (state_c & (state_a ^ state_b));
        const uint32_t carry_two = mix_low + majority;

        state_h = state_g;
        state_g = state_f;
        state_f = state_e;
        state_e = state_d + carry_one;
        state_d = state_c;
        state_c = state_b;
        state_b = state_a;
        state_a = carry_one + carry_two;
    }

    state->word[0] += state_a;
    state->word[1] += state_b;
    state->word[2] += state_c;
    state->word[3] += state_d;
    state->word[4] += state_e;
    state->word[5] += state_f;
    state->word[6] += state_g;
    state->word[7] += state_h;
}

void sha256_hash(const uint8_t *message, size_t message_len, uint8_t *digest)
{
    Sha256State state;
    uint32_t message_block[SHA256_BLOCK_WORDS];
    size_t consumed = 0u;

    sha256_state_init(&state);

    while ((message_len - consumed) >= SHA256_BLOCK_BYTES)
    {
        for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
        {
            message_block[slot] = read_big_endian_word(message + consumed + (slot * 4u));
        }
        sha256_block_compress(&state, message_block);
        consumed += SHA256_BLOCK_BYTES;
    }

    uint8_t tail[SHA256_BLOCK_BYTES * 2u];
    const size_t remaining = message_len - consumed;
    memset(tail, 0, sizeof(tail));
    memcpy(tail, message + consumed, remaining);
    tail[remaining] = 0x80u;

    // A message with more than fifty-five bytes left over pushes the length field into a second
    // padding block, and so the tail buffer holds two.
    const size_t tail_blocks = (remaining >= 56u) ? 2u : 1u;
    const uint64_t message_bits = (uint64_t)message_len * 8u;
    uint8_t *const length_field = tail + (tail_blocks * SHA256_BLOCK_BYTES) - 8u;
    write_big_endian_word(length_field, (uint32_t)(message_bits >> 32));
    write_big_endian_word(length_field + 4u, (uint32_t)message_bits);

    for (size_t block = 0u; block < tail_blocks; block += 1u)
    {
        for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
        {
            message_block[slot] =
                read_big_endian_word(tail + (block * SHA256_BLOCK_BYTES) + (slot * 4u));
        }
        sha256_block_compress(&state, message_block);
    }

    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        write_big_endian_word(digest + (slot * 4u), state.word[slot]);
    }
}

void sha256_double_hash(const uint8_t *message, size_t message_len, uint8_t *digest)
{
    uint8_t first_pass[32];

    sha256_hash(message, message_len, first_pass);
    sha256_hash(first_pass, sizeof(first_pass), digest);
}

void sha256_header_midstate(Sha256State *midstate, const uint8_t *header)
{
    uint32_t message_block[SHA256_BLOCK_WORDS];

    sha256_state_init(midstate);
    for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
    {
        message_block[slot] = read_big_endian_word(header + (slot * 4u));
    }
    sha256_block_compress(midstate, message_block);
}

/**
 * @brief Orders a finished chaining value against a threshold without serializing it first.
 *
 * @param[in] state     Chaining value of the second hash [BORROWS].
 * @param[in] threshold Eight words, most significant first [BORROWS].
 * @return              Nonzero where the digest the state spells is at or below the threshold.
 * @note The protocol reads the digest little-endian, so state word seven byte-reversed is the most
 *       significant word of the number and state word zero byte-reversed is the least.
 */
static int sha256_state_within_target(const Sha256State *state, const uint32_t *threshold)
{
    for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
    {
        const uint32_t digest_word = reverse_word_bytes(state->word[7u - rank]);

        if (digest_word != threshold[rank])
        {
            return (digest_word < threshold[rank]) ? 1 : 0;
        }
    }
    return 1;
}

int sha256_digest_within_target(const uint8_t *digest, const uint32_t *threshold)
{
    Sha256State state;

    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        state.word[slot] = read_big_endian_word(digest + (slot * 4u));
    }
    return sha256_state_within_target(&state, threshold);
}

/**
 * @brief Fills the second header block, whose only nonce-dependent word is the fourth.
 *
 * @param[out] message_block Sixteen words to fill [BORROWS].
 * @param[in]  request       Header tail the caller assembled [BORROWS].
 * @param[in]  nonce         The nonce this block carries, as the header stores it, little-endian.
 * @note The header holds the nonce little-endian and SHA-256 reads its message big-endian, so the
 *       word entering the schedule is the nonce byte-reversed. Genesis carries nonce 0x7c2bac1d and
 *       hashes the word 0x1dac2b7c. Feeding the counter in unreversed hashes a header nobody asked
 *       for, which still produces digests and never produces the recorded one.
 */
static void fill_header_tail_block(uint32_t *message_block, const Sha256ScanRequest *request,
                                   uint32_t nonce)
{
    message_block[0] = request->merkle_root_tail;
    message_block[1] = request->ntime;
    message_block[2] = request->nbits;
    message_block[3] = reverse_word_bytes(nonce);
    message_block[4] = PADDING_LEAD_WORD;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        message_block[slot] = 0u;
    }
    message_block[15] = HEADER_LENGTH_BITS;
}

/**
 * @brief Fills the second hash's only block, the first hash's digest plus padding.
 *
 * @param[out] message_block Sixteen words to fill [BORROWS].
 * @param[in]  first_pass    Chaining value the first hash finished on [BORROWS].
 */
static void fill_digest_block(uint32_t *message_block, const Sha256State *first_pass)
{
    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        message_block[slot] = first_pass->word[slot];
    }
    message_block[8] = PADDING_LEAD_WORD;
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        message_block[slot] = 0u;
    }
    message_block[15] = DIGEST_LENGTH_BITS;
}

/** @brief Rounds of the second block that need running before the anchor word can be read. */
#define ANCHOR_ROUNDS 61u

/** @brief Rounds of the first block that no nonce can affect. */
#define SHARED_ROUNDS 3u

/** @brief Schedule words of the first block that no nonce can affect. */
#define SHARED_SCHEDULE 18u

/**
 * @brief Everything about a header that does not change when the nonce does.
 *
 * @note Section 2b of docs/sha256-topology.md prices this exactly. The nonce is message word three,
 *       and W[at] draws on at-16, at-15, at-7 and at-2, so taint from word three leaves the first
 *       eighteen schedule words untouched and the first three rounds do identical work for every
 *       nonce. Both are hoisted here.
 */
typedef struct
{
    uint32_t schedule[SHARED_SCHEDULE]; /**< The nonce-independent head of the schedule. */
    uint32_t state[SHA256_STATE_WORDS]; /**< The chaining value after the shared rounds. */

    /** @brief The block's input chaining value, which the feedforward adds at the end.
     *  @note Not the same as state above. Davies-Meyer adds the value the block *started* from, so
     *        resuming from a partly-advanced state does not change what gets added back. Adding the
     *        advanced state instead produces a digest that is wrong in a way the anchor cannot see,
     *        since it is wrong for almost every nonce equally. */
    uint32_t feedforward[SHA256_STATE_WORDS];
} PreparedHeader;

/**
 * @brief Computes the part of the first block every nonce shares.
 *
 * @param[out] prepared Where to put it [BORROWS].
 * @param[in]  request  The header being scanned [BORROWS].
 */
static void prepare_header(PreparedHeader *prepared, const Sha256ScanRequest *request)
{
    uint32_t message_block[SHA256_BLOCK_WORDS];
    fill_header_tail_block(message_block, request, 0u);

    for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
    {
        prepared->schedule[slot] = message_block[slot];
    }

    // Words sixteen and seventeen draw only on words no nonce reaches, so they are shared too.
    // Word eighteen draws on word three and is where the per-nonce work has to begin.
    for (unsigned slot = SHA256_BLOCK_WORDS; slot < SHARED_SCHEDULE; slot += 1u)
    {
        const uint32_t back_fifteen = prepared->schedule[slot - 15u];
        const uint32_t back_two = prepared->schedule[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^
                                    rotate_right(back_fifteen, 18u) ^ (back_fifteen >> 3u);
        const uint32_t spread_high = rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^
                                     (back_two >> 10u);
        prepared->schedule[slot] =
            spread_high + prepared->schedule[slot - 7u] + spread_low + prepared->schedule[slot - 16u];
    }

    uint32_t state_a = request->midstate.word[0];
    uint32_t state_b = request->midstate.word[1];
    uint32_t state_c = request->midstate.word[2];
    uint32_t state_d = request->midstate.word[3];
    uint32_t state_e = request->midstate.word[4];
    uint32_t state_f = request->midstate.word[5];
    uint32_t state_g = request->midstate.word[6];
    uint32_t state_h = request->midstate.word[7];

    for (unsigned round = 0u; round < SHARED_ROUNDS; round += 1u)
    {
        const uint32_t mix_high = rotate_right(state_e, 6u) ^ rotate_right(state_e, 11u) ^
                                  rotate_right(state_e, 25u);
        const uint32_t choose = state_g ^ (state_e & (state_f ^ state_g));
        const uint32_t carry_one = state_h + mix_high + choose + s_sha256_round_constant[round] +
                                   prepared->schedule[round];
        const uint32_t mix_low = rotate_right(state_a, 2u) ^ rotate_right(state_a, 13u) ^
                                 rotate_right(state_a, 22u);
        const uint32_t majority = (state_a & state_b) | (state_c & (state_a ^ state_b));

        state_h = state_g;
        state_g = state_f;
        state_f = state_e;
        state_e = state_d + carry_one;
        state_d = state_c;
        state_c = state_b;
        state_b = state_a;
        state_a = carry_one + mix_low + majority;
    }

    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        prepared->feedforward[slot] = request->midstate.word[slot];
    }

    prepared->state[0] = state_a;
    prepared->state[1] = state_b;
    prepared->state[2] = state_c;
    prepared->state[3] = state_d;
    prepared->state[4] = state_e;
    prepared->state[5] = state_f;
    prepared->state[6] = state_g;
    prepared->state[7] = state_h;
}

/**
 * @brief The anchor word of a nonce, computed without the work the anchor cannot read.
 *
 * @param[in] prepared The shared head of the first block [BORROWS].
 * @param[in] nonce    The nonce to try.
 * @return             Word seven of the doubled digest.
 * @note Two savings, both exact and not heuristic. The first block resumes from the shared
 *       state and expands its schedule from word eighteen. The second block stops after
 *       ANCHOR_ROUNDS, because the round moves e to f to g to h and so the final word seven is the
 *       e of sixty-one rounds - the last three rounds cannot change it and are not run.
 * @warning This returns the anchor word only. A nonce that passes it must be re-evaluated exactly
 *          before it is believed, as the caller does.
 */
static uint32_t anchor_word_of(const PreparedHeader *prepared, uint32_t nonce)
{
    uint32_t schedule[64];
    for (unsigned slot = 0u; slot < SHARED_SCHEDULE; slot += 1u)
    {
        schedule[slot] = prepared->schedule[slot];
    }
    schedule[3] = reverse_word_bytes(nonce);

    // Word eighteen is the first the nonce reaches, so it is the first that has to be recomputed.
    for (unsigned slot = SHARED_SCHEDULE; slot < 64u; slot += 1u)
    {
        const uint32_t back_fifteen = schedule[slot - 15u];
        const uint32_t back_two = schedule[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^
                                    rotate_right(back_fifteen, 18u) ^ (back_fifteen >> 3u);
        const uint32_t spread_high = rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^
                                     (back_two >> 10u);
        schedule[slot] = spread_high + schedule[slot - 7u] + spread_low + schedule[slot - 16u];
    }

    uint32_t state_a = prepared->state[0];
    uint32_t state_b = prepared->state[1];
    uint32_t state_c = prepared->state[2];
    uint32_t state_d = prepared->state[3];
    uint32_t state_e = prepared->state[4];
    uint32_t state_f = prepared->state[5];
    uint32_t state_g = prepared->state[6];
    uint32_t state_h = prepared->state[7];

    for (unsigned round = SHARED_ROUNDS; round < 64u; round += 1u)
    {
        const uint32_t mix_high = rotate_right(state_e, 6u) ^ rotate_right(state_e, 11u) ^
                                  rotate_right(state_e, 25u);
        const uint32_t choose = state_g ^ (state_e & (state_f ^ state_g));
        const uint32_t carry_one = state_h + mix_high + choose + s_sha256_round_constant[round] +
                                   schedule[round];
        const uint32_t mix_low = rotate_right(state_a, 2u) ^ rotate_right(state_a, 13u) ^
                                 rotate_right(state_a, 22u);
        const uint32_t majority = (state_a & state_b) | (state_c & (state_a ^ state_b));

        state_h = state_g;
        state_g = state_f;
        state_f = state_e;
        state_e = state_d + carry_one;
        state_d = state_c;
        state_c = state_b;
        state_b = state_a;
        state_a = carry_one + mix_low + majority;
    }

    // Written straight into the second block's schedule and not into a block that is then
    // copied into it, because the copy is sixteen words per nonce and buys nothing.
    uint32_t second[64];
    second[0] = prepared->feedforward[0] + state_a;
    second[1] = prepared->feedforward[1] + state_b;
    second[2] = prepared->feedforward[2] + state_c;
    second[3] = prepared->feedforward[3] + state_d;
    second[4] = prepared->feedforward[4] + state_e;
    second[5] = prepared->feedforward[5] + state_f;
    second[6] = prepared->feedforward[6] + state_g;
    second[7] = prepared->feedforward[7] + state_h;
    second[8] = PADDING_LEAD_WORD;
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        second[slot] = 0u;
    }
    second[15] = DIGEST_LENGTH_BITS;

    for (unsigned slot = SHA256_BLOCK_WORDS; slot < ANCHOR_ROUNDS; slot += 1u)
    {
        const uint32_t back_fifteen = second[slot - 15u];
        const uint32_t back_two = second[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^
                                    rotate_right(back_fifteen, 18u) ^ (back_fifteen >> 3u);
        const uint32_t spread_high = rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^
                                     (back_two >> 10u);
        second[slot] = spread_high + second[slot - 7u] + spread_low + second[slot - 16u];
    }

    uint32_t pass_a = s_sha256_initial_state[0];
    uint32_t pass_b = s_sha256_initial_state[1];
    uint32_t pass_c = s_sha256_initial_state[2];
    uint32_t pass_d = s_sha256_initial_state[3];
    uint32_t pass_e = s_sha256_initial_state[4];
    uint32_t pass_f = s_sha256_initial_state[5];
    uint32_t pass_g = s_sha256_initial_state[6];
    uint32_t pass_h = s_sha256_initial_state[7];

    for (unsigned round = 0u; round < ANCHOR_ROUNDS; round += 1u)
    {
        const uint32_t mix_high = rotate_right(pass_e, 6u) ^ rotate_right(pass_e, 11u) ^
                                  rotate_right(pass_e, 25u);
        const uint32_t choose = pass_g ^ (pass_e & (pass_f ^ pass_g));
        const uint32_t carry_one = pass_h + mix_high + choose + s_sha256_round_constant[round] +
                                   second[round];
        const uint32_t mix_low = rotate_right(pass_a, 2u) ^ rotate_right(pass_a, 13u) ^
                                 rotate_right(pass_a, 22u);
        const uint32_t majority = (pass_a & pass_b) | (pass_c & (pass_a ^ pass_b));

        pass_h = pass_g;
        pass_g = pass_f;
        pass_f = pass_e;
        pass_e = pass_d + carry_one;
        pass_d = pass_c;
        pass_c = pass_b;
        pass_b = pass_a;
        pass_a = carry_one + mix_low + majority;
    }

    // The final word seven is the e of ANCHOR_ROUNDS rounds, carried down the chain by the last
    // three rounds without being changed by them.
    return s_sha256_initial_state[7] + pass_e;
}

uint32_t sha256_anchor_word(const Sha256ScanRequest *request, uint32_t nonce)
{
    PreparedHeader prepared;
    prepare_header(&prepared, request);
    return anchor_word_of(&prepared, nonce);
}

void sha256_scan_scalar_early(const Sha256ScanRequest *request, Sha256ScanResult *result)
{
    const int anchor_is_sound = (request->share_target[0] == 0u);

    result->nonces_evaluated = 0u;
    result->anchors_survived = 0u;
    result->winning_nonce = 0u;
    result->found = 0;

    // Where the anchor is unsound this arm has no shortcut to take and defers instead of inventing
    // one, because a fast path that can refuse a winning nonce costs more than it saves.
    if (anchor_is_sound == 0)
    {
        sha256_scan_scalar(request, result);
        return;
    }

    PreparedHeader prepared;
    prepare_header(&prepared, request);

    for (uint32_t step = 0u; step < request->nonce_count; step += 1u)
    {
        if (((step % ABANDON_POLL_GROUPS) == 0u) && (request->abandon != NULL) &&
            (*request->abandon != 0))
        {
            return;
        }

        const uint32_t nonce = request->nonce_start + step;
        result->nonces_evaluated += 1u;

        if (anchor_word_of(&prepared, nonce) != 0u)
        {
            continue;
        }
        result->anchors_survived += 1u;

        // The shortcut got us here and is not trusted past here. Everything a share depends on is
        // recomputed by the arm that has never been optimised.
        uint32_t message_block[SHA256_BLOCK_WORDS];
        Sha256State first_pass = request->midstate;
        fill_header_tail_block(message_block, request, nonce);
        sha256_block_compress(&first_pass, message_block);

        Sha256State second_pass;
        sha256_state_init(&second_pass);
        fill_digest_block(message_block, &first_pass);
        sha256_block_compress(&second_pass, message_block);

        if (sha256_state_within_target(&second_pass, request->share_target) != 0)
        {
            result->winning_nonce = nonce;
            result->found = 1;
            return;
        }
    }
}

void sha256_scan_scalar(const Sha256ScanRequest *request, Sha256ScanResult *result)
{
    // The anchor is only a necessary condition where the target leaves the top word at zero. A
    // difficulty below one lifts the threshold past that, and there the anchor would refuse a nonce
    // that wins, which section 2.2 forbids. Fall back to the exact compare on every nonce instead.
    const int anchor_is_sound = (request->share_target[0] == 0u);

    result->nonces_evaluated = 0u;
    result->anchors_survived = 0u;
    result->winning_nonce = 0u;
    result->found = 0;

    for (uint32_t step = 0u; step < request->nonce_count; step += 1u)
    {
        if (((step % ABANDON_POLL_GROUPS) == 0u) && (request->abandon != NULL) &&
            (*request->abandon != 0))
        {
            return;
        }

        const uint32_t nonce = request->nonce_start + step;
        uint32_t message_block[SHA256_BLOCK_WORDS];
        Sha256State first_pass = request->midstate;

        fill_header_tail_block(message_block, request, nonce);
        sha256_block_compress(&first_pass, message_block);

        Sha256State second_pass;
        sha256_state_init(&second_pass);
        fill_digest_block(message_block, &first_pass);
        sha256_block_compress(&second_pass, message_block);

        result->nonces_evaluated += 1u;

        if (anchor_is_sound && (second_pass.word[7] != 0u))
        {
            continue;
        }
        result->anchors_survived += 1u;

        if (sha256_state_within_target(&second_pass, request->share_target) != 0)
        {
            result->winning_nonce = nonce;
            result->found = 1;
            return;
        }
    }
}

#if defined(__AVX2__)

/**
 * @brief Rotates eight words right in parallel.
 *
 * @param[in] value    Eight words to rotate.
 * @param[in] distance How far, between one and thirty-one.
 * @return             The rotated words.
 */
static inline __m256i lane_rotate_right(__m256i value, int distance)
{
    return _mm256_or_si256(_mm256_srli_epi32(value, distance),
                           _mm256_slli_epi32(value, 32 - distance));
}

/** @brief One round of the compression function across eight lanes. */
#define LANE_ROUND(state_a_, state_b_, state_c_, state_d_, state_e_, state_f_, state_g_, state_h_,  \
                   round_, schedule_word_)                                                          \
    do                                                                                              \
    {                                                                                               \
        const __m256i mix_high = _mm256_xor_si256(                                                  \
            _mm256_xor_si256(lane_rotate_right(state_e_, 6), lane_rotate_right(state_e_, 11)),      \
            lane_rotate_right(state_e_, 25));                                                       \
        const __m256i choose = _mm256_xor_si256(                                                    \
            state_g_, _mm256_and_si256(state_e_, _mm256_xor_si256(state_f_, state_g_)));            \
        const __m256i carry_one = _mm256_add_epi32(                                                 \
            _mm256_add_epi32(_mm256_add_epi32(state_h_, mix_high),                                  \
                             _mm256_add_epi32(choose, _mm256_set1_epi32(                            \
                                                          (int)s_sha256_round_constant[round_]))),  \
            schedule_word_);                                                                        \
        const __m256i mix_low = _mm256_xor_si256(                                                   \
            _mm256_xor_si256(lane_rotate_right(state_a_, 2), lane_rotate_right(state_a_, 13)),      \
            lane_rotate_right(state_a_, 22));                                                       \
        const __m256i majority = _mm256_or_si256(                                                   \
            _mm256_and_si256(state_a_, state_b_),                                                   \
            _mm256_and_si256(state_c_, _mm256_xor_si256(state_a_, state_b_)));                      \
        state_h_ = state_g_;                                                                        \
        state_g_ = state_f_;                                                                        \
        state_f_ = state_e_;                                                                        \
        state_e_ = _mm256_add_epi32(state_d_, carry_one);                                           \
        state_d_ = state_c_;                                                                        \
        state_c_ = state_b_;                                                                        \
        state_b_ = state_a_;                                                                        \
        state_a_ = _mm256_add_epi32(carry_one, _mm256_add_epi32(mix_low, majority));                \
    } while (0)

/**
 * @brief Extends sixteen scheduled words to sixty-four across eight lanes.
 *
 * @param[in,out] schedule Sixty-four vectors, the first sixteen already filled [BORROWS].
 */
static inline void lane_extend_schedule(__m256i *schedule)
{
    for (unsigned slot = SHA256_BLOCK_WORDS; slot < 64u; slot += 1u)
    {
        const __m256i back_fifteen = schedule[slot - 15u];
        const __m256i back_two = schedule[slot - 2u];
        const __m256i spread_low = _mm256_xor_si256(
            _mm256_xor_si256(lane_rotate_right(back_fifteen, 7), lane_rotate_right(back_fifteen, 18)),
            _mm256_srli_epi32(back_fifteen, 3));
        const __m256i spread_high = _mm256_xor_si256(
            _mm256_xor_si256(lane_rotate_right(back_two, 17), lane_rotate_right(back_two, 19)),
            _mm256_srli_epi32(back_two, 10));
        schedule[slot] = _mm256_add_epi32(_mm256_add_epi32(spread_high, schedule[slot - 7u]),
                                          _mm256_add_epi32(spread_low, schedule[slot - 16u]));
    }
}

/**
 * @brief Runs sixty-four rounds across eight lanes and adds the incoming chaining value back in.
 *
 * @param[in,out] lane_state Eight vectors of chaining value, advanced in place [BORROWS].
 * @param[in]     schedule   Sixty-four scheduled vectors [BORROWS].
 */
static inline void lane_compress(__m256i *lane_state, const __m256i *schedule)
{
    __m256i state_a = lane_state[0];
    __m256i state_b = lane_state[1];
    __m256i state_c = lane_state[2];
    __m256i state_d = lane_state[3];
    __m256i state_e = lane_state[4];
    __m256i state_f = lane_state[5];
    __m256i state_g = lane_state[6];
    __m256i state_h = lane_state[7];

    for (unsigned round = 0u; round < 64u; round += 1u)
    {
        LANE_ROUND(state_a, state_b, state_c, state_d, state_e, state_f, state_g, state_h, round,
                   schedule[round]);
    }

    lane_state[0] = _mm256_add_epi32(lane_state[0], state_a);
    lane_state[1] = _mm256_add_epi32(lane_state[1], state_b);
    lane_state[2] = _mm256_add_epi32(lane_state[2], state_c);
    lane_state[3] = _mm256_add_epi32(lane_state[3], state_d);
    lane_state[4] = _mm256_add_epi32(lane_state[4], state_e);
    lane_state[5] = _mm256_add_epi32(lane_state[5], state_f);
    lane_state[6] = _mm256_add_epi32(lane_state[6], state_g);
    lane_state[7] = _mm256_add_epi32(lane_state[7], state_h);
}

void sha256_scan_avx2(const Sha256ScanRequest *request, Sha256ScanResult *result)
{
    const int anchor_is_sound = (request->share_target[0] == 0u);
    const __m256i lane_offsets = _mm256_setr_epi32(0, 1, 2, 3, 4, 5, 6, 7);

    // Reverses the four bytes of every thirty-two bit lane, applied to nonces on entry.
    const __m256i byte_reversal =
        _mm256_setr_epi8(3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12, 3, 2, 1, 0, 7, 6, 5,
                         4, 11, 10, 9, 8, 15, 14, 13, 12);

    result->nonces_evaluated = 0u;
    result->anchors_survived = 0u;
    result->winning_nonce = 0u;
    result->found = 0;

    __m256i first_schedule[64];
    __m256i second_schedule[64];

    first_schedule[0] = _mm256_set1_epi32((int)request->merkle_root_tail);
    first_schedule[1] = _mm256_set1_epi32((int)request->ntime);
    first_schedule[2] = _mm256_set1_epi32((int)request->nbits);
    first_schedule[4] = _mm256_set1_epi32((int)PADDING_LEAD_WORD);
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        first_schedule[slot] = _mm256_setzero_si256();
    }
    first_schedule[15] = _mm256_set1_epi32((int)HEADER_LENGTH_BITS);

    second_schedule[8] = _mm256_set1_epi32((int)PADDING_LEAD_WORD);
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        second_schedule[slot] = _mm256_setzero_si256();
    }
    second_schedule[15] = _mm256_set1_epi32((int)DIGEST_LENGTH_BITS);

    const uint32_t whole_groups = request->nonce_count / SHA256_LANES;

    for (uint32_t group = 0u; group < whole_groups; group += 1u)
    {
        if (((group % ABANDON_POLL_GROUPS) == 0u) && (request->abandon != NULL) &&
            (*request->abandon != 0))
        {
            return;
        }

        const uint32_t group_base = request->nonce_start + (group * SHA256_LANES);

        // Byte-reverse each lane's nonce on the way into the schedule, for the reason
        // fill_header_tail_block states. One shuffle per eight nonces against a hundred and
        // twenty-eight rounds is not a cost worth designing around.
        const __m256i lane_nonces =
            _mm256_add_epi32(_mm256_set1_epi32((int)group_base), lane_offsets);
        first_schedule[3] = _mm256_shuffle_epi8(lane_nonces, byte_reversal);
        lane_extend_schedule(first_schedule);

        __m256i first_state[SHA256_STATE_WORDS];
        for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
        {
            first_state[slot] = _mm256_set1_epi32((int)request->midstate.word[slot]);
        }
        lane_compress(first_state, first_schedule);

        for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
        {
            second_schedule[slot] = first_state[slot];
        }
        lane_extend_schedule(second_schedule);

        __m256i second_state[SHA256_STATE_WORDS];
        for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
        {
            second_state[slot] = _mm256_set1_epi32((int)s_sha256_initial_state[slot]);
        }
        lane_compress(second_state, second_schedule);

        result->nonces_evaluated += SHA256_LANES;

        // The anchor, tested on all eight lanes with one compare and one mask. Section 2.2 makes a
        // set bit here a permanent refusal, so the lanes it clears are never revisited.
        int survivor_mask = 0xFF;
        if (anchor_is_sound)
        {
            const __m256i anchor_hit =
                _mm256_cmpeq_epi32(second_state[7], _mm256_setzero_si256());
            survivor_mask = _mm256_movemask_ps(_mm256_castsi256_ps(anchor_hit));
            if (survivor_mask == 0)
            {
                continue;
            }
        }

        // Section 2.3: a survivor has proved nothing, so every one of them pays the exact compare.
        SHA256_ALIGN_32 uint32_t finished_state[SHA256_STATE_WORDS][SHA256_LANES];
        for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
        {
            _mm256_store_si256((__m256i *)finished_state[slot], second_state[slot]);
        }

        for (unsigned lane = 0u; lane < SHA256_LANES; lane += 1u)
        {
            if ((survivor_mask & (1 << lane)) == 0)
            {
                continue;
            }
            result->anchors_survived += 1u;

            Sha256State candidate;
            for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
            {
                candidate.word[slot] = finished_state[slot][lane];
            }
            if (sha256_state_within_target(&candidate, request->share_target) != 0)
            {
                // Lanes ascend with the nonce, so the first survivor in lane order is the lowest
                // winning nonce in this group and therefore in the range.
                result->winning_nonce = group_base + lane;
                result->found = 1;
                return;
            }
        }
    }

    const uint32_t tail_start = request->nonce_start + (whole_groups * SHA256_LANES);
    const uint32_t tail_count = request->nonce_count - (whole_groups * SHA256_LANES);
    if (tail_count != 0u)
    {
        Sha256ScanRequest tail_request = *request;
        Sha256ScanResult tail_result;

        tail_request.nonce_start = tail_start;
        tail_request.nonce_count = tail_count;
        sha256_scan_scalar(&tail_request, &tail_result);

        result->nonces_evaluated += tail_result.nonces_evaluated;
        result->anchors_survived += tail_result.anchors_survived;
        if (tail_result.found != 0)
        {
            result->winning_nonce = tail_result.winning_nonce;
            result->found = 1;
        }
    }
}

#else

void sha256_scan_avx2(const Sha256ScanRequest *request, Sha256ScanResult *result)
{
    // Both arms of the gate are defined. Without AVX2 at compile time this arm exists and defers to
    // the reference, so an unported build stays correct instead of pretending it vectorized.
    sha256_scan_scalar(request, result);
}

#endif

/**
 * @brief Folds one finished digest into a survey's counters.
 *
 * @param[in,out] survey Where the counts accumulate [BORROWS].
 * @param[in]     state  Chaining value of the second hash [BORROWS].
 * @note Bit position zero is the most significant bit of the number the protocol reads:
 *       the top of state word seven byte-reversed. Counting in that order keeps a bit index here
 *       comparable to a leading zero count.
 */
static void survey_absorb_digest(Sha256Survey *survey, const Sha256State *state)
{
    unsigned leading_zeros = 0u;
    int still_leading = 1;

    for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
    {
        const uint32_t digest_word = reverse_word_bytes(state->word[7u - rank]);

        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            // Bit 31 of the word is the most significant, so walk down from there.
            const unsigned position = (rank * 32u) + bit;
            const uint32_t value = (digest_word >> (31u - bit)) & 1u;

            survey->bit_one_count[position] += value;
            if (still_leading != 0)
            {
                if (value == 0u)
                {
                    leading_zeros += 1u;
                }
                else
                {
                    still_leading = 0;
                }
            }
        }

        for (unsigned byte = 0u; byte < 4u; byte += 1u)
        {
            const unsigned position = (rank * 4u) + byte;
            const uint8_t value = (uint8_t)(digest_word >> (24u - (byte * 8u)));

            survey->byte_histogram[value] += 1u;
            survey->position_histogram[position][value] += 1u;
        }
    }

    for (unsigned width = 0u; (width <= 32u) && (width <= leading_zeros); width += 1u)
    {
        survey->leading_zero_count[width] += 1u;
    }
    survey->nonces_evaluated += 1u;
}

void sha256_survey_avx2(const Sha256ScanRequest *request, Sha256Survey *survey)
{
    const uint32_t whole_groups = request->nonce_count / SHA256_LANES;

    for (uint32_t group = 0u; group < whole_groups; group += 1u)
    {
        const uint32_t group_base = request->nonce_start + (group * SHA256_LANES);

        for (unsigned lane = 0u; lane < SHA256_LANES; lane += 1u)
        {
            uint32_t message_block[SHA256_BLOCK_WORDS];
            Sha256State first_pass = request->midstate;

            fill_header_tail_block(message_block, request, group_base + lane);
            sha256_block_compress(&first_pass, message_block);

            Sha256State second_pass;
            sha256_state_init(&second_pass);
            fill_digest_block(message_block, &first_pass);
            sha256_block_compress(&second_pass, message_block);

            survey_absorb_digest(survey, &second_pass);
        }
    }
}

int sha256_has_avx2(void)
{
    // Bit five of leaf seven's EBX is the AVX2 feature bit, whichever compiler asks for it.
#if SHA256_HAS_GNU_CPUID
    unsigned int signature = 0u;
    unsigned int leaf_seven_ebx = 0u;
    unsigned int leaf_seven_ecx = 0u;
    unsigned int leaf_seven_edx = 0u;

    if (__get_cpuid_max(0, NULL) < 7u)
    {
        return 0;
    }
    __cpuid_count(7, 0, signature, leaf_seven_ebx, leaf_seven_ecx, leaf_seven_edx);
    return ((leaf_seven_ebx & (1u << 5)) != 0u) ? 1 : 0;
#elif SHA256_HAS_MSVC_CPUID
    int leaf_zero[4] = {0, 0, 0, 0};
    int leaf_seven[4] = {0, 0, 0, 0};

    __cpuid(leaf_zero, 0);
    if (leaf_zero[0] < 7)
    {
        return 0;
    }
    __cpuidex(leaf_seven, 7, 0);
    return ((((unsigned int)leaf_seven[1]) & (1u << 5)) != 0u) ? 1 : 0;
#else
    // No way to ask. Report absent so that a caller falls back instead of issuing an illegal
    // instruction on a part that lacks it.
    return 0;
#endif
}

void sha256_target_from_nbits(uint32_t *block_target, uint32_t nbits)
{
    const uint32_t exponent = nbits >> 24;
    const uint32_t mantissa = nbits & 0x007FFFFFu;

    for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
    {
        block_target[rank] = 0u;
    }
    if ((exponent < 3u) || (exponent > 32u))
    {
        return;
    }

    // The mantissa occupies three bytes ending at byte offset exponent from the low end, so its low
    // bit sits at bit position eight times exponent minus twenty-four.
    const unsigned low_bit = (unsigned)((exponent - 3u) * 8u);
    const uint64_t widened = (uint64_t)mantissa << (low_bit % 32u);
    const unsigned low_word_index = low_bit / 32u;

    if (low_word_index < SHA256_STATE_WORDS)
    {
        block_target[7u - low_word_index] |= (uint32_t)widened;
    }
    if ((low_word_index + 1u) < SHA256_STATE_WORDS)
    {
        block_target[7u - (low_word_index + 1u)] |= (uint32_t)(widened >> 32);
    }
}

void sha256_share_target_from_difficulty(uint32_t *share_target, double difficulty)
{
    for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
    {
        share_target[rank] = 0u;
    }
    if (!(difficulty > 0.0))
    {
        return;
    }

    // Difficulty one names the threshold 0xFFFF times two to the two hundred eighth, and every other
    // difficulty divides it. Carry the quotient as a mantissa and an exponent so any difficulty far
    // from one neither overflows nor rounds to nothing.
    int quotient_exponent = 0;
    const double quotient_mantissa = frexp(65535.0 / difficulty, &quotient_exponent);
    const uint64_t mantissa_bits = (uint64_t)(quotient_mantissa * 9007199254740992.0);
    const int shift = (quotient_exponent + 208) - 53;

    if (shift <= -64)
    {
        return;
    }
    if (shift >= 256)
    {
        for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
        {
            share_target[rank] = 0xFFFFFFFFu;
        }
        return;
    }

    for (unsigned bit = 0u; bit < 64u; bit += 1u)
    {
        if (((mantissa_bits >> bit) & 1u) == 0u)
        {
            continue;
        }
        const int position = shift + (int)bit;
        if ((position < 0) || (position >= 256))
        {
            continue;
        }
        // Rank zero is the most significant word, and a bit at position p lands in rank 7 - p/32.
        share_target[7u - ((unsigned)position / 32u)] |= (1u << ((unsigned)position % 32u));
    }
}
