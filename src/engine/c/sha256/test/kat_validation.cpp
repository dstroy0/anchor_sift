/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file kat_validation.cpp
 * @brief Known answer tests whose answers come from outside this tree.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every expected value here was published before this code existed: the NIST digests, the
 *       genesis block, and block 125552. Nothing in this file can be made to pass by editing the
 *       engine's own definition of success, the defect the previous version of this file
 *       carried.
 * @note The scan tests search a real nonce range for a real header and require the engine to land on
 *       the nonce the chain already recorded. A miss is a false negative, which section 2.2 of
 *       anchor-sift.md forbids outright, so it is reported as such instead of as slow.
 */

#include "sha256_core.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace
{

int g_tests_run = 0;
int g_tests_failed = 0;

/**
 * @brief Converts a hex string to bytes.
 *
 * @param[in] hex Characters to convert, an even count.
 * @return        The bytes they spell.
 */
std::vector<uint8_t> bytes_from_hex(const std::string &hex)
{
    std::vector<uint8_t> bytes;

    bytes.reserve(hex.size() / 2u);
    for (size_t at = 0u; (at + 1u) < hex.size(); at += 2u)
    {
        bytes.push_back((uint8_t)std::stoul(hex.substr(at, 2u), nullptr, 16));
    }
    return bytes;
}

/**
 * @brief Renders bytes as hex in the order they sit in memory.
 *
 * @param[in] bytes Bytes to render [BORROWS].
 * @param[in] count How many.
 * @return          The hex string.
 */
std::string hex_from_bytes(const uint8_t *bytes, size_t count)
{
    static const char digits[] = "0123456789abcdef";
    std::string rendered;

    rendered.reserve(count * 2u);
    for (size_t at = 0u; at < count; at += 1u)
    {
        rendered.push_back(digits[bytes[at] >> 4]);
        rendered.push_back(digits[bytes[at] & 0x0Fu]);
    }
    return rendered;
}

/**
 * @brief Renders a digest the way a block explorer prints it, most significant byte first.
 *
 * @param[in] digest Thirty-two bytes as SHA-256 emitted them [BORROWS].
 * @return           The reversed hex string.
 */
std::string block_hash_from_digest(const uint8_t *digest)
{
    uint8_t reversed[32];

    for (size_t at = 0u; at < 32u; at += 1u)
    {
        reversed[at] = digest[31u - at];
    }
    return hex_from_bytes(reversed, sizeof(reversed));
}

/**
 * @brief Records one test outcome and prints it.
 *
 * @param[in] name     What was tested.
 * @param[in] passed   Nonzero where it held.
 * @param[in] detail   What was seen, printed on failure.
 */
void report(const std::string &name, bool passed, const std::string &detail = "")
{
    g_tests_run += 1;
    if (passed)
    {
        std::printf("  [PASS] %s\n", name.c_str());
    }
    else
    {
        g_tests_failed += 1;
        std::printf("  [FAIL] %s\n", name.c_str());
        if (!detail.empty())
        {
            std::printf("         %s\n", detail.c_str());
        }
    }
}

/** @brief A published SHA-256 digest and the message that produces it. */
struct DigestVector
{
    const char *message;
    const char *expected_digest;
    const char *source;
};

/** @brief NIST FIPS 180-4 examples plus the empty-string digest every implementation agrees on. */
const DigestVector DIGEST_VECTORS[] = {
    {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty string"},
    {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "FIPS 180-4 B.1"},
    {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "FIPS 180-4 B.2"},
};

/**
 * @brief Runs the published digest vectors through the reference arm.
 */
void test_published_digests()
{
    std::printf("\n[1] SHA-256 against published digests\n");

    for (const DigestVector &vector : DIGEST_VECTORS)
    {
        uint8_t digest[32];
        sha256_hash((const uint8_t *)vector.message, std::strlen(vector.message), digest);

        const std::string produced = hex_from_bytes(digest, sizeof(digest));
        report(std::string("sha256 ") + vector.source, produced == vector.expected_digest,
               "got " + produced + ", expected " + vector.expected_digest);
    }

    // A message of exactly fifty-six bytes forces the length field into a second padding block. That
    // is the boundary a padding bug hides behind.
    const std::string boundary(56u, 'a');
    uint8_t digest[32];
    sha256_hash((const uint8_t *)boundary.data(), boundary.size(), digest);
    const std::string produced = hex_from_bytes(digest, sizeof(digest));
    report("sha256 fifty-six byte padding boundary",
           produced == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
           "got " + produced);
}

/** @brief A block whose header, hash and nonce the chain already recorded. */
struct HeaderVector
{
    const char *header_hex;
    const char *expected_hash;
    uint32_t expected_nonce;
    const char *source;
};

/** @brief Two headers anyone can check against a block explorer. */
const HeaderVector HEADER_VECTORS[] = {
    {"0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac7"
     "2c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c",
     "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f", 0x7c2bac1du,
     "genesis block, height 0"},
    {"0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
     "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695",
     "00000000000000001e8d6829a8a21adc5d38d0a473b144b6765798e61f98bd1d", 0x9546a142u,
     "block 125552, the classic test vector"},
};

/**
 * @brief Hashes published headers and checks both the hash and the recovered nonce.
 */
void test_published_headers()
{
    std::printf("\n[2] Bitcoin headers against the chain's own record\n");

    for (const HeaderVector &vector : HEADER_VECTORS)
    {
        const std::vector<uint8_t> header = bytes_from_hex(vector.header_hex);
        if (header.size() != BITCOIN_HEADER_BYTES)
        {
            report(std::string("header length for ") + vector.source, false,
                   "got " + std::to_string(header.size()) + " bytes, expected 80");
            continue;
        }

        uint8_t digest[32];
        sha256_double_hash(header.data(), header.size(), digest);

        const std::string produced = block_hash_from_digest(digest);
        report(std::string("hash of ") + vector.source, produced == vector.expected_hash,
               "got " + produced + ", expected " + vector.expected_hash);

        // The nonce sits at header bytes seventy-six through seventy-nine, little-endian.
        const uint32_t header_nonce = (uint32_t)header[76] | ((uint32_t)header[77] << 8) |
                                      ((uint32_t)header[78] << 16) | ((uint32_t)header[79] << 24);
        report(std::string("nonce field of ") + vector.source, header_nonce == vector.expected_nonce,
               "got " + std::to_string(header_nonce));

        // The block's own hash must satisfy the block's own nbits. If it does not, either the target
        // expansion or the ordering is wrong, and both feed the share check.
        const uint32_t nbits = (uint32_t)header[72] | ((uint32_t)header[73] << 8) |
                               ((uint32_t)header[74] << 16) | ((uint32_t)header[75] << 24);
        uint32_t block_target[SHA256_STATE_WORDS];
        sha256_target_from_nbits(block_target, nbits);
        report(std::string("nbits ordering for ") + vector.source,
               sha256_digest_within_target(digest, block_target) != 0,
               "block hash did not satisfy its own nbits");
    }
}

/**
 * @brief Reads a header field as the number it encodes, which is little-endian on the wire.
 *
 * @param[in] header Eighty header bytes [BORROWS].
 * @param[in] offset Byte offset of the field.
 * @return           The number the four bytes encode.
 * @note This is not the same word the SHA-256 schedule sees. The schedule reads those bytes
 *       big-endian, so nbits enters the hash as 0xf2b9441a and enters a target as 0x1a44b9f2.
 *       Handing one to a reader expecting the other yields an exponent of 242 and a target of zero,
 *       which refuses every nonce without ever reporting an error.
 */
uint32_t header_field_value(const uint8_t *header, size_t offset)
{
    return (uint32_t)header[offset] | ((uint32_t)header[offset + 1u] << 8) |
           ((uint32_t)header[offset + 2u] << 16) | ((uint32_t)header[offset + 3u] << 24);
}

/**
 * @brief Builds a scan request from a published header, minus its nonce.
 *
 * @param[out] request Request to fill [BORROWS].
 * @param[in]  header  Eighty header bytes [BORROWS].
 */
void scan_request_from_header(Sha256ScanRequest *request, const uint8_t *header)
{
    std::memset(request, 0, sizeof(*request));
    sha256_header_midstate(&request->midstate, header);

    request->merkle_root_tail = ((uint32_t)header[64] << 24) | ((uint32_t)header[65] << 16) |
                                ((uint32_t)header[66] << 8) | (uint32_t)header[67];
    request->ntime = ((uint32_t)header[68] << 24) | ((uint32_t)header[69] << 16) |
                     ((uint32_t)header[70] << 8) | (uint32_t)header[71];
    request->nbits = ((uint32_t)header[72] << 24) | ((uint32_t)header[73] << 16) |
                     ((uint32_t)header[74] << 8) | (uint32_t)header[75];
}

/**
 * @brief Requires both scan arms to recover a real block's nonce from a range that contains it.
 */
void test_scan_recovers_real_nonce()
{
    std::printf("\n[3] Scan arms recovering a nonce the chain recorded\n");

    for (const HeaderVector &vector : HEADER_VECTORS)
    {
        const std::vector<uint8_t> header = bytes_from_hex(vector.header_hex);
        Sha256ScanRequest request;
        scan_request_from_header(&request, header.data());

        // Start the window below the real nonce so the arm has to search instead of land on it. The
        // window is the smallest that still proves the arm walks forward into the answer.
        const uint32_t window = 4096u;
        request.nonce_start = vector.expected_nonce - (window / 2u);
        request.nonce_count = window;
        sha256_target_from_nbits(request.share_target, header_field_value(header.data(), 72u));

        Sha256ScanResult scalar_result;
        sha256_scan_scalar(&request, &scalar_result);
        report(std::string("scalar arm finds nonce of ") + vector.source,
               (scalar_result.found != 0) && (scalar_result.winning_nonce == vector.expected_nonce),
               scalar_result.found ? ("got " + std::to_string(scalar_result.winning_nonce))
                                   : "FALSE NEGATIVE: no nonce found in a window containing one");

        Sha256ScanResult vector_result;
        sha256_scan_avx2(&request, &vector_result);
        report(std::string("eight-lane arm finds nonce of ") + vector.source,
               (vector_result.found != 0) && (vector_result.winning_nonce == vector.expected_nonce),
               vector_result.found ? ("got " + std::to_string(vector_result.winning_nonce))
                                   : "FALSE NEGATIVE: no nonce found in a window containing one");
    }
}

/**
 * @brief Requires the two arms to agree on a range with no winner in it.
 *
 * @note This is the disagreement test the header calls a defect. A vectorized arm that quietly drops
 *       lanes passes every test above and fails this one.
 */
void test_arms_agree()
{
    std::printf("\n[4] Arms agreeing where no answer exists\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_VECTORS[1].header_hex);
    Sha256ScanRequest request;
    scan_request_from_header(&request, header.data());

    // A window well away from the real nonce, at the block's own difficulty. Nothing here wins.
    request.nonce_start = 1000000u;
    request.nonce_count = 65536u;
    sha256_target_from_nbits(request.share_target, request.nbits);

    Sha256ScanResult scalar_result;
    Sha256ScanResult vector_result;
    sha256_scan_scalar(&request, &scalar_result);
    sha256_scan_avx2(&request, &vector_result);

    report("neither arm invents a winner", (scalar_result.found == 0) && (vector_result.found == 0),
           "scalar found=" + std::to_string(scalar_result.found) + " vector found=" +
               std::to_string(vector_result.found));
    report("both arms evaluated every nonce",
           (scalar_result.nonces_evaluated == request.nonce_count) &&
               (vector_result.nonces_evaluated == request.nonce_count),
           "scalar " + std::to_string(scalar_result.nonces_evaluated) + " vector " +
               std::to_string(vector_result.nonces_evaluated));

    // Section 2.2 gives the anchor a rate of two to the minus thirty-two, leaving a sixty-five thousand
    // nonce window should almost never produce a survivor. Agreement between the arms is the claim
    // being tested; the count itself is only reported.
    report("arms agree on anchor survivors",
           scalar_result.anchors_survived == vector_result.anchors_survived,
           "scalar " + std::to_string(scalar_result.anchors_survived) + " vector " +
               std::to_string(vector_result.anchors_survived));
}

/**
 * @brief Requires an easy target to produce the same winner from both arms.
 *
 * @note At the block difficulty a winner is astronomically rare, so soundness at an easy target is
 *       what actually exercises the compare path on both arms.
 */
void test_arms_agree_on_easy_target()
{
    std::printf("\n[5] Arms agreeing on a target loose enough to hit\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_VECTORS[1].header_hex);
    Sha256ScanRequest request;
    scan_request_from_header(&request, header.data());

    // Sixteen leading zero bits: the top word at or below 0x0000FFFF and every lower word
    // unconstrained. Roughly one nonce in sixty-five thousand clears it, leaving a million-nonce window
    // holds many and the arms have to agree on the lowest.
    //
    // A nonzero top word also makes the anchor unsound by section 2.2, so this exercises the
    // fallback path where every nonce pays the full compare. The anchor path itself is covered by
    // test three, where the real block hashes carry sixty-four leading zero bits.
    std::memset(request.share_target, 0xFF, sizeof(request.share_target));
    request.share_target[0] = 0x0000FFFFu;
    request.nonce_start = 0u;
    request.nonce_count = 1000000u;

    Sha256ScanResult scalar_result;
    Sha256ScanResult vector_result;
    sha256_scan_scalar(&request, &scalar_result);
    sha256_scan_avx2(&request, &vector_result);

    report("both arms find a winner at an easy target",
           (scalar_result.found != 0) && (vector_result.found != 0),
           "scalar found=" + std::to_string(scalar_result.found) + " vector found=" +
               std::to_string(vector_result.found));
    report("both arms report the same lowest nonce",
           scalar_result.winning_nonce == vector_result.winning_nonce,
           "scalar " + std::to_string(scalar_result.winning_nonce) + " vector " +
               std::to_string(vector_result.winning_nonce));

    // The winner has to survive an independent check that never touches the scan path.
    if (scalar_result.found != 0)
    {
        std::vector<uint8_t> candidate = bytes_from_hex(HEADER_VECTORS[1].header_hex);
        const uint32_t nonce = scalar_result.winning_nonce;
        candidate[76] = (uint8_t)nonce;
        candidate[77] = (uint8_t)(nonce >> 8);
        candidate[78] = (uint8_t)(nonce >> 16);
        candidate[79] = (uint8_t)(nonce >> 24);

        uint8_t digest[32];
        sha256_double_hash(candidate.data(), candidate.size(), digest);
        report("winner verified by an independent double hash",
               sha256_digest_within_target(digest, request.share_target) != 0,
               "hash " + block_hash_from_digest(digest) + " is not within the target");
    }
}

/**
 * @brief Checks the difficulty to target conversion against the values the protocol fixes.
 */
void test_difficulty_conversion()
{
    std::printf("\n[6] Difficulty to target conversion\n");

    uint32_t target[SHA256_STATE_WORDS];

    // Difficulty one is 0xFFFF times two to the two hundred eighth. Those bits land at positions 208
    // through 223, which is word one's upper half, so word one reads 0xFFFF0000 and not 0x0000FFFF.
    sha256_share_target_from_difficulty(target, 1.0);
    report("difficulty one is 0x00000000FFFF0000...",
           (target[0] == 0x00000000u) && (target[1] == 0xFFFF0000u) && (target[2] == 0u) &&
               (target[7] == 0u),
           "word zero " + std::to_string(target[0]) + " word one " + std::to_string(target[1]));

    sha256_share_target_from_difficulty(target, 2.0);
    report("difficulty two halves the threshold",
           (target[0] == 0x00000000u) && (target[1] == 0x7FFF8000u),
           "word one is " + std::to_string(target[1]));

    // nbits 0x1d00ffff is difficulty one written the way a header writes it, so the two paths have to
    // land on the same threshold.
    uint32_t from_nbits[SHA256_STATE_WORDS];
    sha256_target_from_nbits(from_nbits, 0x1d00ffffu);
    sha256_share_target_from_difficulty(target, 1.0);
    report("nbits 0x1d00ffff agrees with difficulty one",
           std::memcmp(from_nbits, target, sizeof(target)) == 0,
           "nbits path word one is " + std::to_string(from_nbits[1]));

    // Every target the pool can set must leave the anchor sound. Section 2.2 is only satisfied where
    // the most significant word is zero, and the engine falls back where it is not.
    sha256_share_target_from_difficulty(target, 1.0);
    report("difficulty one leaves the anchor sound", target[0] == 0u,
           "top word is " + std::to_string(target[0]));
}

/**
 * @brief Times the eight-lane arm, so the reported rate is measured instead of asserted.
 */
void measure_scan_rate()
{
    std::printf("\n[7] Measured rate of the eight-lane arm, single thread\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_VECTORS[1].header_hex);
    Sha256ScanRequest request;
    scan_request_from_header(&request, header.data());

    request.nonce_start = 0u;
    request.nonce_count = 2000000u;
    sha256_target_from_nbits(request.share_target, request.nbits);

    const auto started = std::chrono::steady_clock::now();
    Sha256ScanResult result;
    sha256_scan_avx2(&request, &result);
    const auto finished = std::chrono::steady_clock::now();

    const double seconds = std::chrono::duration<double>(finished - started).count();
    const double rate = (seconds > 0.0) ? ((double)result.nonces_evaluated / seconds) : 0.0;

    std::printf("  nonces hashed   : %llu\n", (unsigned long long)result.nonces_evaluated);
    std::printf("  anchor survivors: %llu\n", (unsigned long long)result.anchors_survived);
    std::printf("  elapsed         : %.3f s\n", seconds);
    std::printf("  rate            : %.2f MH/s (one thread)\n", rate / 1.0e6);
}

} // namespace

int main()
{
    std::printf("========================================================\n");
    std::printf("  BTC known answer tests\n");
    std::printf("  Every expected value below was published before this\n");
    std::printf("  code existed. None of them come from the engine.\n");
    std::printf("========================================================\n");
    std::printf("\nAVX2 available: %s\n", (sha256_has_avx2() != 0) ? "yes" : "no");

    test_published_digests();
    test_published_headers();
    test_scan_recovers_real_nonce();
    test_arms_agree();
    test_arms_agree_on_easy_target();
    test_difficulty_conversion();
    measure_scan_rate();

    std::printf("\n========================================================\n");
    std::printf("  %d run, %d failed\n", g_tests_run, g_tests_failed);
    std::printf("  %s\n", (g_tests_failed == 0) ? "ALL TESTS PASS" : "FAILURES PRESENT");
    std::printf("========================================================\n");
    return (g_tests_failed == 0) ? 0 : 1;
}
