// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

static_assert((sizeof(EngineProgramBlock) % 8u) == 0u, "cycle: the block is 64-bit words");
static_assert(sizeof(EngineSignum) == 32u, "cycle: the block's signature is four words");

// every program and the operator block open with this: the launch the kernel takes, the lane a program defines, and
// the operators the block defines. A thread's registers are its places: the file, then the scratch the divisions and
// the ladder work in, laid in the thread block's shared memory across its threads. An operator takes the places and
// limbs of its register and its operands, and one that can refuse a lane returns 0 for it
extern const char g_cycle_prelude[] = R"CYCLE(
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;

struct CycleHot
{
    u64 next_lane;
    u64 launch_start;
    u64 finished;
    u64 checkins;
};

struct CycleCompiledLaunch
{
    const u32 *in[3];
    const u32 *index;
    const u32 *tables;
    u32 *out;
    u32 *refused;
    u64 bodies[3];
    u64 count;
    CycleHot *hot;
    u64 *block;
    u64 ttl;
    u64 checkin_every;
    u64 launch_number;
    u64 places;
};

extern "C" __device__ void cycle_lane(const CycleCompiledLaunch *launch, u64 lane);

extern "C" __device__ void cycle_field(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs);

extern "C" __device__ void cycle_field_signed(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs);

extern "C" __device__ void cycle_constant(u32 low, u32 high, u32 place, u32 limbs);

extern "C" __device__ void cycle_lane_index(u64 lane, u32 place, u32 limbs);

extern "C" __device__ void cycle_product(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs);

extern "C" __device__ void cycle_sum(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 difference);

extern "C" __device__ int cycle_ladder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                       u32 scratch);

extern "C" __device__ void cycle_absolute(u32 place, u32 limbs, u32 left, u32 left_limbs);

extern "C" __device__ void cycle_compare(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs);

extern "C" __device__ void cycle_table(u32 place, u32 limbs, u32 left, const u32 *tables, u32 table_offset,
                                       u32 index_bits);

extern "C" __device__ void cycle_bitwise(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 exclusive);

extern "C" __device__ void cycle_wrap(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 bits);

extern "C" __device__ int cycle_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 scratch, u32 wide);

extern "C" __device__ int cycle_remainder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                          u32 scratch, u32 wide);

extern "C" __device__ void cycle_gcd(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 scratch, u32 wide);

extern "C" __device__ int cycle_exact_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right,
                                               u32 right_limbs, u32 scratch, u32 wide);

extern "C" __device__ void cycle_put(u32 *record, u32 out_limbs, u32 offset, u32 bits, u32 place, u32 limbs);
)CYCLE";

// The operator block: every record operation, each the interpreter's own arithmetic with its widths taken at run time,
// and the resident kernel that runs a program's lanes. A thread's registers lie in the thread block's shared memory,
// laid across its threads: place p of thread t is word p * threads + t, so a warp reading one place reads 32
// consecutive words, one to a bank. Each access translates its place by that one multiply-add, and every operator reads
// the shared array itself, so the device reads it as shared memory. A thread's signs follow its places, one byte a
// place of the file, laid the same way. The divisions and the ladder work in the scratch places the program names,
// laid as the interpreter lays its own at `wide` limbs: wide is at least every width the step reads or writes
extern const char g_cycle_operators[] = R"CYCLE(
// the places, the file's then the scratch's, and the signs after them
extern __shared__ u32 cycle_words[];

// a thread's places, set by the kernel before any lane runs
__shared__ u32 cycle_places;

// a place's word for this thread and a place's sign
__device__ __forceinline__ static u32 &cycle_word(u32 place)
{
    return cycle_words[(place * blockDim.x) + threadIdx.x];
}

__device__ __forceinline__ static s8 &cycle_sign(u32 place)
{
    // the signs are bytes after every place's word, read back as bytes of the same shared array
    s8 *const signs = (s8 *)&cycle_words[cycle_places * blockDim.x];
    return signs[(place * blockDim.x) + threadIdx.x];
}

// the device's timer, in nanoseconds
__device__ __forceinline__ static u64 cycle_clock(void)
{
    u64 now;
    asm volatile("mov.u64 %0, %%globaltimer;" : "=l"(now));
    return now;
}

__device__ __forceinline__ static u32 cycle_limb(u32 value, u32 limbs, u32 at)
{
    return (at < limbs) ? cycle_word(value + at) : 0u;
}

__device__ static int cycle_order(u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    u32 at = (left_limbs > right_limbs) ? left_limbs : right_limbs;
    while (at > 0u)
    {
        at -= 1u;
        const u32 one = cycle_limb(left, left_limbs, at);
        const u32 other = cycle_limb(right, right_limbs, at);
        if (one != other)
        {
            return (one < other) ? -1 : 1;
        }
    }
    return 0;
}

__device__ static int cycle_is_zero(u32 value, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        if (cycle_word(value + at) != 0u)
        {
            return 0;
        }
    }
    return 1;
}

// a limb of an atom, which lies in device memory
__device__ __forceinline__ static u32 cycle_atom_limb(const u32 *atom, u32 in_limbs, u32 at)
{
    return (at < in_limbs) ? atom[at] : 0u;
}

__device__ static void cycle_gather(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 value, u32 limbs)
{
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        const u32 bit = offset + (32u * limb);
        const u32 word = bit / 32u;
        const u32 shift = bit % 32u;
        u32 gathered = cycle_atom_limb(atom, in_limbs, word) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_atom_limb(atom, in_limbs, word + 1u) << (32u - shift);
        }
        const u32 left = bits - (32u * limb);
        cycle_word(value + limb) = (left < 32u) ? (gathered & ((1u << left) - 1u)) : gathered;
    }
}

__device__ static void cycle_negate(u32 value, u32 limbs, u32 bits)
{
    u64 carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (u64)(~cycle_word(value + at)) + carry;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    const u32 left = bits - (32u * (limbs - 1u));
    const u32 top = cycle_word(value + limbs - 1u);
    cycle_word(value + limbs - 1u) = (left < 32u) ? (top & ((1u << left) - 1u)) : top;
}

// limb `at` of a register's two's complement: the magnitude's limb, or its complement where the sign is negative,
// with `carry` running the negation's one up the limbs; it starts at 1 and the limbs are taken from the lowest up
__device__ static u32 cycle_complement(u32 value, u32 limbs, u32 at, int sign, u64 *carry)
{
    const u32 held = cycle_limb(value, limbs, at);
    if (sign >= 0)
    {
        return held;
    }
    const u64 total = (u64)(~held) + *carry;
    *carry = total >> 32u;
    return (u32)(total & 0xFFFFFFFFull);
}

__device__ static void cycle_add(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    u64 carry = 0ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (u64)cycle_limb(left, left_limbs, at) + (u64)cycle_limb(right, right_limbs, at) + carry;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static void cycle_subtract(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    u64 borrow = 0ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u64 total = (1ull << 32u) + (u64)cycle_limb(left, left_limbs, at) - (u64)cycle_limb(right, right_limbs, at)
                        - borrow;
        cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__device__ static void cycle_multiply(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = 0u;
    }
    for (u32 low = 0u; low < left_limbs; low += 1u)
    {
        u64 carry = 0ull;
        const u64 multiplier = (u64)cycle_word(left + low);
        for (u32 high = 0u; (high < right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const u64 total = (multiplier * (u64)cycle_word(right + high)) + (u64)cycle_word(value + low + high) + carry;
            cycle_word(value + low + high) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        for (u32 at = low + right_limbs; (carry != 0ull) && (at < limbs); at += 1u)
        {
            const u64 total = (u64)cycle_word(value + at) + carry;
            cycle_word(value + at) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

__device__ static u32 cycle_used(u32 value, u32 limbs)
{
    while ((limbs > 0u) && (cycle_word(value + limbs - 1u) == 0u))
    {
        limbs -= 1u;
    }
    return limbs;
}

// value shifted toward the low end by `bits` (below 32 times its limbs), into `limbs` of out
__device__ static void cycle_shift_down(u32 value, u32 value_limbs, u32 bits, u32 out, u32 limbs)
{
    const u32 words = bits / 32u;
    const u32 shift = bits % 32u;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        u32 gathered = cycle_limb(value, value_limbs, at + words) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_limb(value, value_limbs, at + words + 1u) << (32u - shift);
        }
        cycle_word(out + at) = gathered;
    }
}

// a place that names no register: a division's quotient or rest left out
#define CYCLE_NO_PLACE 0xFFFFFFFFu

// Knuth's Algorithm D on the magnitudes: top = quotient . bottom + rest, each output kept to its own limbs and either
// one left out where it is CYCLE_NO_PLACE; 0 for a zero divisor. scratch holds 2 * wide + 2 limbs.
__device__ static int cycle_divide(u32 top, u32 top_limbs, u32 bottom, u32 bottom_limbs, u32 quotient,
                                   u32 quotient_limbs, u32 rest, u32 rest_limbs, u32 scratch, u32 wide)
{
    const u32 divisor_used = cycle_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    const u32 numerator_used = cycle_used(top, top_limbs);
    for (u32 at = 0u; (quotient != CYCLE_NO_PLACE) && (at < quotient_limbs); at += 1u)
    {
        cycle_word(quotient + at) = 0u;
    }
    if (numerator_used < divisor_used)
    {
        for (u32 at = 0u; (rest != CYCLE_NO_PLACE) && (at < rest_limbs); at += 1u)
        {
            cycle_word(rest + at) = cycle_limb(top, numerator_used, at);
        }
        return 1;
    }
    if (divisor_used == 1u)
    {
        const u64 divisor = (u64)cycle_word(bottom);
        u64 carried = 0ull;
        for (u32 at = numerator_used; at > 0u; at -= 1u)
        {
            const u64 part = (carried << 32u) | (u64)cycle_word(top + at - 1u);
            if ((quotient != CYCLE_NO_PLACE) && ((at - 1u) < quotient_limbs))
            {
                cycle_word(quotient + at - 1u) = (u32)(part / divisor);
            }
            carried = part % divisor;
        }
        for (u32 at = 0u; (rest != CYCLE_NO_PLACE) && (at < rest_limbs); at += 1u)
        {
            cycle_word(rest + at) = (at == 0u) ? (u32)carried : 0u;
        }
        return 1;
    }
    const u32 numerator = scratch;
    const u32 divisor = scratch + wide + 2u;
    const u32 shift = (u32)__clz(cycle_word(bottom + divisor_used - 1u));
    for (u32 at = 0u; at < divisor_used; at += 1u)
    {
        const u32 below = ((shift != 0u) && (at > 0u)) ? (cycle_word(bottom + at - 1u) >> (32u - shift)) : 0u;
        cycle_word(divisor + at) = (cycle_word(bottom + at) << shift) | below;
    }
    for (u32 at = 0u; at <= numerator_used; at += 1u)
    {
        const u32 here = cycle_limb(top, numerator_used, at);
        const u32 below = ((shift != 0u) && (at > 0u)) ? (cycle_word(top + at - 1u) >> (32u - shift)) : 0u;
        cycle_word(numerator + at) = (here << shift) | below;
    }
    const u64 lead = (u64)cycle_word(divisor + divisor_used - 1u);
    const u64 next = (u64)cycle_word(divisor + divisor_used - 2u);
    for (u32 place = numerator_used - divisor_used + 1u; place > 0u; place -= 1u)
    {
        const u32 at = place - 1u;
        const u64 part = ((u64)cycle_word(numerator + at + divisor_used) << 32u)
                       | (u64)cycle_word(numerator + at + divisor_used - 1u);
        u64 guess = part / lead;
        u64 over = part % lead;
        while (((guess >> 32u) != 0ull)
               || ((guess * next) > ((over << 32u) | (u64)cycle_word(numerator + at + divisor_used - 2u))))
        {
            guess -= 1ull;
            over += lead;
            if ((over >> 32u) != 0ull)
            {
                break;
            }
        }
        u64 borrow = 0ull;
        for (u32 limb = 0u; limb < divisor_used; limb += 1u)
        {
            const u64 taken = (guess * (u64)cycle_word(divisor + limb)) + borrow;
            const u64 held = (u64)cycle_word(numerator + at + limb);
            cycle_word(numerator + at + limb) = (u32)((held - (taken & 0xFFFFFFFFull)) & 0xFFFFFFFFull);
            borrow = (taken >> 32u) + ((held < (taken & 0xFFFFFFFFull)) ? 1ull : 0ull);
        }
        const u64 held = (u64)cycle_word(numerator + at + divisor_used);
        cycle_word(numerator + at + divisor_used) = (u32)((held - borrow) & 0xFFFFFFFFull);
        if (held < borrow)
        {
            // the guess was one too many (Knuth D6): add the divisor back
            guess -= 1ull;
            u64 carry = 0ull;
            for (u32 limb = 0u; limb < divisor_used; limb += 1u)
            {
                const u64 total = (u64)cycle_word(numerator + at + limb) + (u64)cycle_word(divisor + limb) + carry;
                cycle_word(numerator + at + limb) = (u32)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
            cycle_word(numerator + at + divisor_used)
                = (u32)((cycle_word(numerator + at + divisor_used) + carry) & 0xFFFFFFFFull);
        }
        if ((quotient != CYCLE_NO_PLACE) && (at < quotient_limbs))
        {
            cycle_word(quotient + at) = (u32)guess;
        }
    }
    if (rest != CYCLE_NO_PLACE)
    {
        cycle_shift_down(numerator, divisor_used + 1u, shift, rest, rest_limbs);
        for (u32 at = divisor_used; at < rest_limbs; at += 1u)
        {
            cycle_word(rest + at) = 0u;
        }
    }
    return 1;
}

// Euclid's gcd of the magnitudes by the long division above, into `limbs` of value; scratch holds 5 * wide + 2
__device__ static void cycle_euclid(u32 left, u32 left_limbs, u32 right, u32 right_limbs, u32 value, u32 limbs,
                                    u32 scratch, u32 wide)
{
    u32 larger = scratch;
    u32 smaller = scratch + wide;
    u32 rest = scratch + (2u * wide);
    for (u32 at = 0u; at < wide; at += 1u)
    {
        cycle_word(larger + at) = cycle_limb(left, left_limbs, at);
        cycle_word(smaller + at) = cycle_limb(right, right_limbs, at);
    }
    while (cycle_used(smaller, wide) != 0u)
    {
        cycle_divide(larger, wide, smaller, wide, CYCLE_NO_PLACE, 0u, rest, wide, scratch + (3u * wide), wide);
        const u32 held = larger;
        larger = smaller;
        smaller = rest;
        rest = held;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = cycle_word(larger + at);
    }
}

// the quotient of an exact division by a multiply with the divisor's inverse and a mask: both are shifted past the
// divisor's low zero bits, the odd divisor's inverse modulo 2^(32 limbs) is grown by Newton's x(2 - dx) from one word,
// and the quotient is the low limbs of numerator . inverse; multiplying back proves it. 0 for a zero divisor or a
// remainder. scratch holds 5 * wide limbs.
__device__ static int cycle_inverse_quotient(u32 top, u32 top_limbs, u32 bottom, u32 bottom_limbs, u32 value,
                                             u32 limbs, u32 scratch, u32 wide)
{
    const u32 divisor_used = cycle_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = 0u;
    }
    if (cycle_used(top, top_limbs) == 0u)
    {
        return 1;
    }
    u32 low_zeros = 0u;
    while (cycle_word(bottom + (low_zeros / 32u)) == 0u)
    {
        low_zeros += 32u;
    }
    low_zeros += (u32)(__ffs((int)cycle_word(bottom + (low_zeros / 32u))) - 1);
    for (u32 bit = 0u; bit < low_zeros; bit += 1u)
    {
        if (((cycle_limb(top, top_limbs, bit / 32u) >> (bit % 32u)) & 1u) != 0u)
        {
            return 0;
        }
    }
    const u32 numerator = scratch;
    const u32 divisor = scratch + wide;
    const u32 inverse = scratch + (2u * wide);
    const u32 stepped = scratch + (3u * wide);
    const u32 grown = scratch + (4u * wide);
    // the work runs at the numerator's width: a quotient by a constant can be narrower than its numerator, and the
    // multiply back must see the numerator whole
    const u32 work = (top_limbs > limbs) ? top_limbs : limbs;
    cycle_shift_down(top, top_limbs, low_zeros, numerator, work);
    cycle_shift_down(bottom, bottom_limbs, low_zeros, divisor, divisor_used);
    // an odd word is its own inverse to 3 bits, and each step doubles the bits: 6, 12, 24, 48
    const u32 odd = cycle_word(divisor);
    u32 word = odd;
    for (u32 round = 0u; round < 4u; round += 1u)
    {
        word *= 2u - (odd * word);
    }
    cycle_word(inverse) = word;
    for (u32 held = 1u; held < work;)
    {
        const u32 reach = ((2u * held) < work) ? (2u * held) : work;
        cycle_multiply(divisor, (divisor_used < reach) ? divisor_used : reach, inverse, held, stepped, reach);
        // 2 - d x modulo 2^(32 reach): the two's complement of d x, plus 2
        u64 carry = 2ull;
        for (u32 at = 0u; at < reach; at += 1u)
        {
            const u64 total = (u64)(~cycle_word(stepped + at)) + ((at == 0u) ? 1ull : 0ull) + carry;
            cycle_word(stepped + at) = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        cycle_multiply(inverse, held, stepped, reach, grown, reach);
        for (u32 at = 0u; at < reach; at += 1u)
        {
            cycle_word(inverse + at) = cycle_word(grown + at);
        }
        held = reach;
    }
    // the whole quotient lands in grown; the inverse and its step product then lie together, room for the whole
    // product of the quotient and the divisor
    const u32 whole = grown;
    cycle_multiply(numerator, work, inverse, work, whole, work);
    const u32 back = inverse;
    cycle_multiply(whole, work, divisor, divisor_used, back, work + divisor_used);
    if (cycle_order(back, work + divisor_used, numerator, work) != 0)
    {
        return 0;
    }
    // a quotient past its register's limbs outgrew it
    for (u32 at = limbs; at < work; at += 1u)
    {
        if (cycle_word(whole + at) != 0u)
        {
            return 0;
        }
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(value + at) = cycle_word(whole + at);
    }
    return 1;
}

extern "C" __device__ void cycle_field(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    cycle_gather(atom, in_limbs, offset, bits, place, limbs);
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

extern "C" __device__ void cycle_field_signed(const u32 *atom, u32 in_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    cycle_gather(atom, in_limbs, offset, bits, place, limbs);
    const u32 top = bits - 1u;
    const int negative = (((cycle_word(place + (top / 32u)) >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_negate(place, limbs, bits);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a constant's two words, and every limb above them cleared
extern "C" __device__ void cycle_constant(u32 low, u32 high, u32 place, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? low : ((at == 1u) ? high : 0u);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

// the lane's own number, its two words and every limb above them cleared; never negative
extern "C" __device__ void cycle_lane_index(u64 lane, u32 place, u32 limbs)
{
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? (u32)(lane & 0xFFFFFFFFull) : ((at == 1u) ? (u32)(lane >> 32u) : 0u);
    }
    cycle_sign(place) = (lane == 0ull) ? 0 : 1;
}

extern "C" __device__ void cycle_product(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    cycle_multiply(left, left_limbs, right, right_limbs, place, limbs);
    cycle_sign(place) = (s8)(left_sign * right_sign);
}

extern "C" __device__ void cycle_sum(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 difference)
{
    const int left_sign = cycle_sign(left);
    const int addend_sign = (difference != 0u) ? -cycle_sign(right) : cycle_sign(right);
    int held = 0;
    if ((left_sign == addend_sign) || (addend_sign == 0) || (left_sign == 0))
    {
        cycle_add(left, left_limbs, right, right_limbs, place, limbs);
        held = (left_sign != 0) ? left_sign : addend_sign;
    }
    else if (cycle_order(left, left_limbs, right, right_limbs) >= 0)
    {
        cycle_subtract(left, left_limbs, right, right_limbs, place, limbs);
        held = left_sign;
    }
    else
    {
        cycle_subtract(right, right_limbs, left, left_limbs, place, limbs);
        held = addend_sign;
    }
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
}

// the golden ladder's band: the rungs of the Fibonacci numbers whose multiple of the right stays at or below the left.
// A right that is not positive refuses the lane; the band is its register's low limb, every limb above cleared. The
// rung's two words lie at the scratch's first two places and its multiple after them
extern "C" __device__ int cycle_ladder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                       u32 scratch)
{
    const int left_sign = cycle_sign(left);
    const int good = (cycle_sign(right) > 0) ? 1 : 0;
    const u32 reached = scratch + 2u;
    u32 band = 0u;
    u64 lower = 0ull;
    u64 upper = 1ull;
    int below = good;
    for (u32 rung = 1u; (below != 0) && (rung < CYCLE_GOLDEN_RUNGS); rung += 1u)
    {
        cycle_word(scratch) = (u32)(upper & 0xFFFFFFFFull);
        cycle_word(scratch + 1u) = (u32)(upper >> 32u);
        cycle_multiply(right, right_limbs, scratch, 2u, reached, right_limbs + 2u);
        below = (cycle_order(reached, right_limbs + 2u, left, left_limbs) <= 0) ? 1 : 0;
        band += (u32)below;
        const u64 next = lower + upper;
        lower = upper;
        upper = next;
    }
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? band : 0u;
    }
    cycle_sign(place) = (band == 0u) ? 0 : (s8)left_sign;
    return good;
}

extern "C" __device__ void cycle_absolute(u32 place, u32 limbs, u32 left, u32 left_limbs)
{
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_word(place + limb) = cycle_limb(left, left_limbs, limb);
    }
    cycle_sign(place) = (cycle_sign(left) != 0) ? 1 : 0;
}

// the order of two signed registers: its sign is the step's, and its low limb 1 where they differ
extern "C" __device__ void cycle_compare(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    const int order = (left_sign != right_sign)
                    ? ((left_sign > right_sign) ? 1 : -1)
                    : (left_sign * cycle_order(left, left_limbs, right, right_limbs));
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = (at == 0u) ? ((order != 0) ? 1u : 0u) : 0u;
    }
    cycle_sign(place) = (s8)order;
}

// the low index_bits of the source register (index_bits <= 32, one limb) select a row of the program's tables
extern "C" __device__ void cycle_table(u32 place, u32 limbs, u32 left, const u32 *tables, u32 table_offset,
                                       u32 index_bits)
{
    const u32 source = cycle_word(left);
    const u32 index = (index_bits >= 32u) ? source : (source & ((1u << index_bits) - 1u));
    const u32 *const entry = &tables[table_offset + (index * limbs)];
    for (u32 limb = 0u; limb < limbs; limb += 1u)
    {
        cycle_word(place + limb) = entry[limb];
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

// the xor (exclusive) or the and of two registers' two's complements over `limbs`, read back as a magnitude. The sign
// is the operands': the xor is negative where exactly one is, the and where both are. A negative result has the
// extra bit over the wider operand in its limbs, so its low limbs read back to the magnitude.
extern "C" __device__ void cycle_bitwise(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 exclusive)
{
    const int left_sign = cycle_sign(left);
    const int right_sign = cycle_sign(right);
    u64 left_carry = 1ull;
    u64 right_carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        const u32 one = cycle_complement(left, left_limbs, at, left_sign, &left_carry);
        const u32 other = cycle_complement(right, right_limbs, at, right_sign, &right_carry);
        cycle_word(place + at) = (exclusive != 0u) ? (one ^ other) : (one & other);
    }
    const int left_negative = (left_sign < 0) ? 1 : 0;
    const int right_negative = (right_sign < 0) ? 1 : 0;
    const int negative = (exclusive != 0u) ? (left_negative ^ right_negative) : (left_negative & right_negative);
    if (negative != 0)
    {
        cycle_negate(place, limbs, 32u * limbs);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a register wrapped to `bits` of two's complement, read back signed as a magnitude over `limbs`. keymath gave the step
// the fewer of the source's bits and the wrap's, so a wrap wider than the step's 32 limbs is a source already inside
// the signed range, passed through, and any other step holds exactly the wrap's limbs.
extern "C" __device__ void cycle_wrap(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 bits)
{
    const int left_sign = cycle_sign(left);
    if (bits > (32u * limbs))
    {
        for (u32 at = 0u; at < limbs; at += 1u)
        {
            cycle_word(place + at) = cycle_limb(left, left_limbs, at);
        }
        cycle_sign(place) = (s8)left_sign;
        return;
    }
    u64 carry = 1ull;
    for (u32 at = 0u; at < limbs; at += 1u)
    {
        cycle_word(place + at) = cycle_complement(left, left_limbs, at, left_sign, &carry);
    }
    const u32 kept = bits - (32u * (limbs - 1u));
    const u32 high = cycle_word(place + limbs - 1u);
    cycle_word(place + limbs - 1u) = (kept < 32u) ? (high & ((1u << kept) - 1u)) : high;
    const u32 top = bits - 1u;
    const int negative = (((cycle_word(place + (top / 32u)) >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_negate(place, limbs, bits);
    }
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

extern "C" __device__ int cycle_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                         u32 scratch, u32 wide)
{
    const int held = cycle_sign(left) * cycle_sign(right);
    const int good = cycle_divide(left, left_limbs, right, right_limbs, place, limbs, CYCLE_NO_PLACE, 0u, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

extern "C" __device__ int cycle_remainder(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                          u32 scratch, u32 wide)
{
    const int held = cycle_sign(left);
    const int good = cycle_divide(left, left_limbs, right, right_limbs, CYCLE_NO_PLACE, 0u, place, limbs, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

extern "C" __device__ void cycle_gcd(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right, u32 right_limbs,
                                     u32 scratch, u32 wide)
{
    cycle_euclid(left, left_limbs, right, right_limbs, place, limbs, scratch, wide);
    cycle_sign(place) = (cycle_is_zero(place, limbs) != 0) ? 0 : 1;
}

extern "C" __device__ int cycle_exact_quotient(u32 place, u32 limbs, u32 left, u32 left_limbs, u32 right,
                                               u32 right_limbs, u32 scratch, u32 wide)
{
    const int held = cycle_sign(left) * cycle_sign(right);
    const int good = cycle_inverse_quotient(left, left_limbs, right, right_limbs, place, limbs, scratch, wide);
    cycle_sign(place) = (s8)((cycle_is_zero(place, limbs) != 0) ? 0 : held);
    return good;
}

// the register's low `bits` bits, as two's complement where its sign is negative, laid into the record at `offset`
extern "C" __device__ void cycle_put(u32 *record, u32 out_limbs, u32 offset, u32 bits, u32 place, u32 limbs)
{
    const int negative = (cycle_sign(place) < 0) ? 1 : 0;
    const u32 words = (bits + 31u) / 32u;
    const u32 top = bits - (32u * (words - 1u));
    const u32 first = offset / 32u;
    const u32 shift = offset % 32u;
    u64 carry = 1ull;
    for (u32 at = 0u; at < words; at += 1u)
    {
        u32 word = cycle_limb(place, limbs, at);
        if (negative != 0)
        {
            const u64 total = (u64)(~word) + carry;
            word = (u32)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        word = ((at == (words - 1u)) && (top < 32u)) ? (word & ((1u << top) - 1u)) : word;
        if ((first + at) < out_limbs)
        {
            record[first + at] |= word << shift;
        }
        if ((shift != 0u) && ((first + at + 1u) < out_limbs))
        {
            record[first + at + 1u] |= word >> (32u - shift);
        }
    }
}

// The program resident: each thread block takes the next round of lanes from the one counter, and before each round
// its first thread reads the clock. Past the launch's time to live, or told by the block's command, the thread block
// leaves without taking more; every so often it checks in to the block. The thread block that opens the launch runs
// one round before the clock can send it out, so every launch moves the program on however short its time to live. A
// launch that does not find its number as the block's owner leaves at once and writes nothing. The last thread block
// out writes where the program stands, its state last.
extern "C" __global__ void __launch_bounds__(256) cycle_program(CycleCompiledLaunch launch)
{
    __shared__ u64 claimed;
    volatile u64 *const block = launch.block;
    u64 checked = 0ull;
    u64 rounds = 0ull;
    int opened = 0;
    if (threadIdx.x == 0u)
    {
        // a program's places are its record's file and scratch limbs, far under 2^32
        cycle_places = (u32)launch.places;
        opened = (atomicCAS(&launch.hot->launch_start, 0ull, cycle_clock()) == 0ull) ? 1 : 0;
    }
    for (;;)
    {
        if (threadIdx.x == 0u)
        {
            const u64 now = cycle_clock();
            const u64 ran = now - *(volatile u64 *)&launch.hot->launch_start;
            int leave = (((opened == 0) || (rounds != 0ull)) && (ran >= launch.ttl)) ? 1 : 0;
            if ((now - checked) >= launch.checkin_every)
            {
                checked = now;
                const int owned = (block[CYCLE_BLOCK_OWNER] == launch.launch_number) ? 1 : 0;
                leave = ((owned == 0) || (block[CYCLE_BLOCK_COMMAND] != CYCLE_PROGRAM_RUN)) ? 1 : leave;
                if (owned != 0)
                {
                    const u64 next = *(volatile u64 *)&launch.hot->next_lane;
                    block[CYCLE_BLOCK_CHECKIN] = atomicAdd(&launch.hot->checkins, 1ull) + 1ull;
                    block[CYCLE_BLOCK_CHECKIN_TIME] = now;
                    block[CYCLE_BLOCK_OFFSET] = (next < launch.count) ? next : launch.count;
                }
            }
            claimed = (leave != 0) ? launch.count : atomicAdd(&launch.hot->next_lane, (u64)blockDim.x);
            rounds += 1ull;
        }
        __syncthreads();
        const u64 first = claimed;
        __syncthreads();
        if (first >= launch.count)
        {
            break;
        }
        if ((first + threadIdx.x) < launch.count)
        {
            cycle_lane(&launch, first + threadIdx.x);
        }
    }
    if (threadIdx.x == 0u)
    {
        __threadfence();
        if (atomicAdd(&launch.hot->finished, 1ull) == ((u64)gridDim.x - 1ull))
        {
            const u64 now = cycle_clock();
            const u64 next = *(volatile u64 *)&launch.hot->next_lane;
            const u64 start = *(volatile u64 *)&launch.hot->launch_start;
            if (block[CYCLE_BLOCK_OWNER] == launch.launch_number)
            {
                const u64 command = block[CYCLE_BLOCK_COMMAND];
                block[CYCLE_BLOCK_OFFSET] = (next < launch.count) ? next : launch.count;
                block[CYCLE_BLOCK_STEP] = 0ull;
                block[CYCLE_BLOCK_LAUNCH_TIME] = start;
                block[CYCLE_BLOCK_EXECTIME] = now - start;
                block[CYCLE_BLOCK_CHECKIN] = atomicAdd(&launch.hot->checkins, 1ull) + 1ull;
                block[CYCLE_BLOCK_CHECKIN_TIME] = now;
                __threadfence();
                block[CYCLE_BLOCK_STATE] = (next >= launch.count) ? CYCLE_PROGRAM_DONE
                                         : ((command == CYCLE_PROGRAM_STOP) ? CYCLE_PROGRAM_STOPPED
                                                                            : CYCLE_PROGRAM_YIELDED);
                __threadfence();
            }
        }
    }
}
)CYCLE";
