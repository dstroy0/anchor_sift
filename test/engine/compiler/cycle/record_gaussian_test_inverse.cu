// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_gaussian_test_inverse.cu: values, words and the inverse
#include "record_gaussian_test_internal.h"

static unsigned long long s_gaussian_state = 0x6A09E667F3BCC908ull;

unsigned int gaussian_random(void)
{
    s_gaussian_state ^= s_gaussian_state << 13u;
    s_gaussian_state ^= s_gaussian_state >> 7u;
    s_gaussian_state ^= s_gaussian_state << 17u;
    // the state's high half is its best mixed, and it is exactly 32 bits
    return (unsigned int)(s_gaussian_state >> 32u);
}

// a signed 24-bit field value of the given kind: an edge, or a drawn word's low 24 bits read back signed
long long gaussian_value(unsigned int kind)
{
    const long long maximum = 1ll << (GAUSSIAN_TEST_FIELD_BITS - 1u);
    const long long edges[GAUSSIAN_TEST_EDGES] = {0ll, -1ll, 1ll, -maximum, maximum - 1ll};
    if (kind < GAUSSIAN_TEST_EDGES)
    {
        return edges[kind];
    }
    // the masked word is below 2^24. It widens to long long exactly
    const long long drawn = (long long)(gaussian_random() & ((1u << GAUSSIAN_TEST_FIELD_BITS) - 1u));
    return (drawn >= maximum) ? (drawn - (2ll * maximum)) : drawn;
}

// a field's word: the value's low 24 bits of two's complement
unsigned int gaussian_word(long long value)
{
    // the mask keeps the low 24 bits, which is the field's whole content
    return (unsigned int)((unsigned long long)value & ((1ull << GAUSSIAN_TEST_FIELD_BITS) - 1ull));
}

// the inverse programs' fields: floor 8's registers are 28 bits signed, and the chosen pairs' below 32
#define GAUSSIAN_TEST_INVERSE_FIELD_BITS 32u

// `floors` inverse floors on (c, d) in fields 0 and 1, every floor's two registers output; encoded and laid out, and
// loaded onto the device by the caller once the job is admitted
int gaussian_inverse_build(unsigned int floors, GaussianLoaded *loaded, EngineError *error)
{
    EngineRecordStep steps[GAUSSIAN_TEST_INVERSE_STEPS];
    unsigned int outputs[GAUSSIAN_TEST_OUTPUTS];
    steps[0] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u};
    steps[1] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u};
    steps[2] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 2u, 0u, 0u};
    unsigned int real_before = 0u;
    unsigned int imaginary_before = 1u;
    for (unsigned int level = 1u; level <= floors; level += 1u)
    {
        const unsigned int at = 3u + (GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR * (level - 1u));
        steps[at] = EngineRecordStep{ENGINE_RECORD_SUM, real_before, imaginary_before, 0u};
        steps[at + 1u] = EngineRecordStep{ENGINE_RECORD_DIFFERENCE, imaginary_before, real_before, 0u};
        steps[at + 2u] = EngineRecordStep{ENGINE_RECORD_EXACT_QUOTIENT, at, 2u, 0u};
        steps[at + 3u] = EngineRecordStep{ENGINE_RECORD_EXACT_QUOTIENT, at + 1u, 2u, 0u};
        outputs[2u * (level - 1u)] = at + 2u;
        outputs[(2u * (level - 1u)) + 1u] = at + 3u;
        real_before = at + 2u;
        imaginary_before = at + 3u;
    }
    const unsigned int field_bits[2] = {GAUSSIAN_TEST_INVERSE_FIELD_BITS, GAUSSIAN_TEST_INVERSE_FIELD_BITS};
    const unsigned int field_offset[2] = {0u, 32u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {2u, 0u, 0u};
    memset(loaded, 0, sizeof(*loaded));
    const KeymathRecordRequest encode_request = {steps,       3u + (GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR * floors),
                                                 field_bits,  2u,
                                                 1u,          outputs,
                                                 2u * floors, NULL,
                                                 0u,          &loaded->key,
                                                 error};
    const KeyScheduleRecordRequest layout_request = {&loaded->key,    field_offset, 2u, in_limbs, 1,
                                                     &loaded->layout, error};
    return (keymath_record_encode(&encode_request) != KEYMATH_ERROR) &&
           (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
}

void gaussian_inverse_release(GaussianLoaded *loaded)
{
    if (loaded->record != NULL)
    {
        cycle_record_release(loaded->record);
    }
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// One run of a loaded inverse program over `lanes` pairs, on the host and on the device: 1 where both ran and their
// records agree word for word, 0 where both errored, and -1 where they part.
int gaussian_inverse_run(const GaussianLoaded *loaded, const unsigned int *atoms, unsigned int lanes,
                         unsigned int *host_out, unsigned int *device_out, EngineError *error)
{
    const size_t out_bytes = (size_t)lanes * loaded->layout.out_limbs * sizeof(unsigned int);
    const CycleRecordHostRequest host = {
        &loaded->layout, {atoms, NULL, NULL}, {lanes, 0ull, 0ull}, NULL, lanes, host_out, error};
    const int host_ran = cycle_record_run_host(&host) == (long)lanes;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    const int placed = (cudaMalloc((void **)&device_atoms, (size_t)lanes * 2u * sizeof(unsigned int)) == cudaSuccess) &&
                       (cudaMalloc((void **)&device_record, out_bytes) == cudaSuccess) &&
                       (cudaMemcpy(device_atoms, atoms, (size_t)lanes * 2u * sizeof(unsigned int),
                                   cudaMemcpyHostToDevice) == cudaSuccess);
    int device_ran = 0;
    if (placed != 0)
    {
        const CycleRecordRunRequest run = {
            loaded->record, {device_atoms, NULL, NULL}, {lanes, 0ull, 0ull}, NULL, lanes, device_record, error};
        device_ran = (cycle_record_run(&run) == (long)lanes) &&
                     (cudaMemcpy(device_out, device_record, out_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    if ((placed == 0) || (host_ran != device_ran))
    {
        return -1;
    }
    if (host_ran == 0)
    {
        return 0;
    }
    return (memcmp(host_out, device_out, out_bytes) == 0) ? 1 : -1;
}

// the (1 + i)-adic valuation of c + d i, counted up to `maximum`: 0 counts as `maximum`, since every power divides it
unsigned int gaussian_valuation(long long real_part, long long imaginary_part, unsigned int maximum)
{
    unsigned int valuation = 0u;
    while ((valuation < maximum) && ((real_part != 0ll) || (imaginary_part != 0ll)) &&
           (((real_part - imaginary_part) % 2ll) == 0ll))
    {
        const long long next_real = (real_part + imaginary_part) / 2ll;
        imaginary_part = (imaginary_part - real_part) / 2ll;
        real_part = next_real;
        valuation += 1u;
    }
    return ((real_part == 0ll) && (imaginary_part == 0ll)) ? maximum : valuation;
}

// `bits` of a record at `offset` as two's complement
long long gaussian_take(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        word |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if (((word >> (bits - 1u)) & 1ull) != 0ull)
    {
        word |= ~0ull << bits;
    }
    // the word is the value's two's complement. The conversion reads it back signed
    return (long long)word;
}
