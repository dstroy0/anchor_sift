// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#define SCRIPTURA_POWERS 20u
#define SCRIPTURA_CUT 8u
#define SCRIPTURA_CUT_MAGIC 0xABCC77118461CEFDull
#define SCRIPTURA_CUT_SHIFT 26u
#define SCRIPTURA_DIRECT_BYTES (4u * SCRIPTURA_WORD_BYTES)

static const unsigned long long scriptura_powers[SCRIPTURA_POWERS] = {1ull,
                                                                      10ull,
                                                                      100ull,
                                                                      1000ull,
                                                                      10000ull,
                                                                      100000ull,
                                                                      1000000ull,
                                                                      10000000ull,
                                                                      100000000ull,
                                                                      1000000000ull,
                                                                      10000000000ull,
                                                                      100000000000ull,
                                                                      1000000000000ull,
                                                                      10000000000000ull,
                                                                      100000000000000ull,
                                                                      1000000000000000ull,
                                                                      10000000000000000ull,
                                                                      100000000000000000ull,
                                                                      1000000000000000000ull,
                                                                      10000000000000000000ull};

static const char scriptura_pairs[201] = "00010203040506070809"
                                         "10111213141516171819"
                                         "20212223242526272829"
                                         "30313233343536373839"
                                         "40414243444546474849"
                                         "50515253545556575859"
                                         "60616263646566676869"
                                         "70717273747576777879"
                                         "80818283848586878889"
                                         "90919293949596979899";

static const char scriptura_hex_digits[17] = "0123456789abcdef";

_Static_assert(((64u * 1233u) >> 12u) < SCRIPTURA_POWERS,
               "scriptura: the digit estimate indexes scriptura_powers and must stay inside it");

static unsigned int scriptura_leading_zeros(unsigned long long value)
{
#if ENGINE_HAS_BUILTIN(__builtin_clzll)
    // the count of a non-zero 64 bit value is 0 to 63, held whole in an unsigned int
    return (unsigned int)__builtin_clzll(value);
#elif defined(_MSC_VER)
    unsigned long index = 0ul;
    _BitScanReverse64(&index, value);
    // the bit index of a non-zero 64 bit value is 0 to 63, held whole in an unsigned int
    return 63u - (unsigned int)index;
#else
    unsigned int zeros = 0u;
    while ((value & 0x8000000000000000ull) == 0ull)
    {
        value <<= 1u;
        zeros += 1u;
    }
    return zeros;
#endif
}

static unsigned int scriptura_digits(unsigned long long value)
{
    const unsigned long long odd = value | 1ull;
    const unsigned int bits = 64u - scriptura_leading_zeros(odd);
    const unsigned int estimate = (bits * 1233u) >> 12u;
    return estimate + ((odd >= scriptura_powers[estimate]) ? 1u : 0u);
}

static unsigned int scriptura_hundredth(unsigned int value)
{
    // the product is taken whole in 64 bits, and the quotient after the shift fits the 32 bits it came from
    return (unsigned int)(((unsigned long long)value * 0x51EB851Full) >> 37u);
}

static unsigned long long scriptura_cut(unsigned long long value)
{
    // each half is held at the 32 bits it carries, so the four products are widening
    const unsigned long long value_low = (unsigned int)value;
    // each half is held at the 32 bits it carries, so the four products are widening
    const unsigned long long value_high = (unsigned int)(value >> 32u);
    const unsigned long long magic_low = SCRIPTURA_CUT_MAGIC & 0xFFFFFFFFull;
    const unsigned long long magic_high = SCRIPTURA_CUT_MAGIC >> 32u;
    const unsigned long long low_low = value_low * magic_low;
    const unsigned long long low_high = value_low * magic_high;
    const unsigned long long high_low = value_high * magic_low;
    const unsigned long long high_high = value_high * magic_high;
    const unsigned long long middle = (low_low >> 32u) + (low_high & 0xFFFFFFFFull) + (high_low & 0xFFFFFFFFull);
    const unsigned long long high = high_high + (low_high >> 32u) + (high_low >> 32u) + (middle >> 32u);
    return high >> SCRIPTURA_CUT_SHIFT;
}

static void scriptura_emit_small(char *out, unsigned int value, unsigned int digits)
{
    unsigned int index = digits;
    while (index >= 2u)
    {
        const unsigned int quotient = scriptura_hundredth(value);
        const unsigned int remainder = value - (quotient * 100u);
        index -= 2u;
        out[index] = scriptura_pairs[remainder * 2u];
        out[index + 1u] = scriptura_pairs[(remainder * 2u) + 1u];
        value = quotient;
    }
    if (index != 0u)
    {
        // a single decimal digit's character is held whole in a char
        out[0] = (char)('0' + value);
    }
}

static void scriptura_emit(char *out, unsigned long long value, unsigned int digits)
{
    if (value <= 0xFFFFFFFFull)
    {
        // the test above holds the value inside 32 bits
        scriptura_emit_small(out, (unsigned int)value, digits);
        return;
    }
    const unsigned long long rest = scriptura_cut(value);
    // the remainder below ten to the eighth fits 32 bits
    const unsigned int low = (unsigned int)(value - (rest * scriptura_powers[SCRIPTURA_CUT]));
    if (rest <= 0xFFFFFFFFull)
    {
        // the test above holds the rest inside 32 bits
        scriptura_emit_small(out, (unsigned int)rest, digits - SCRIPTURA_CUT);
    }
    else
    {
        const unsigned long long top = scriptura_cut(rest);
        // the remainder below ten to the eighth fits 32 bits
        const unsigned int middle = (unsigned int)(rest - (top * scriptura_powers[SCRIPTURA_CUT]));
        // a 64 bit value over ten to the sixteenth is below two thousand and fits 32 bits
        scriptura_emit_small(out, (unsigned int)top, digits - (2u * SCRIPTURA_CUT));
        scriptura_emit_small(out + (digits - (2u * SCRIPTURA_CUT)), middle, SCRIPTURA_CUT);
    }
    scriptura_emit_small(out + (digits - SCRIPTURA_CUT), low, SCRIPTURA_CUT);
}

static int scriptura_room(const ScripturaLine *line, unsigned long long want)
{
    return (line->at < line->room) && (want <= ((line->room - line->at) - 1ull));
}

void scriptura_counted(ScripturaLine *line, const char *text, unsigned long long length)
{
    if (!scriptura_room(line, length))
    {
        line->at = line->room;
        return;
    }
    scriptura_copy(line->out + line->at, text, length);
    line->at += length;
}

void scriptura_text(ScripturaLine *line, const char *text)
{
    const unsigned long long room = (line->at < line->room) ? (line->room - line->at) : 0ull;
    const unsigned long long length = scriptura_length(text, room);
    scriptura_counted(line, text, length);
}

void scriptura_text_columns(ScripturaLine *line, const char *text, unsigned int columns)
{
    const unsigned long long room = (line->at < line->room) ? (line->room - line->at) : 0ull;
    const unsigned long long length = scriptura_length(text, room);
    const unsigned long long width = (length < columns) ? columns : length;
    if (!scriptura_room(line, width))
    {
        line->at = line->room;
        return;
    }
    scriptura_copy(line->out + line->at, text, length);
    scriptura_fill(line->out + line->at + length, ' ', width - length);
    line->at += width;
}

void scriptura_character(ScripturaLine *line, char character)
{
    if (!scriptura_room(line, 1ull))
    {
        line->at = line->room;
        return;
    }
    line->out[line->at] = character;
    line->at += 1ull;
}

void scriptura_decimal(ScripturaLine *line, unsigned long long value, unsigned int digits_least)
{
    const unsigned int needed = scriptura_digits(value);
    const unsigned int digits = (needed < digits_least) ? digits_least : needed;
    if (!scriptura_room(line, digits))
    {
        line->at = line->room;
        return;
    }
    const unsigned int pad = digits - needed;
    scriptura_fill(line->out + line->at, '0', pad);
    scriptura_emit(line->out + line->at + pad, value, needed);
    line->at += digits;
}

void scriptura_decimal_columns(ScripturaLine *line, unsigned long long value, unsigned int columns)
{
    const unsigned int needed = scriptura_digits(value);
    const unsigned int width = (needed < columns) ? columns : needed;
    if (!scriptura_room(line, width))
    {
        line->at = line->room;
        return;
    }
    const unsigned int pad = width - needed;
    scriptura_fill(line->out + line->at, ' ', pad);
    scriptura_emit(line->out + line->at + pad, value, needed);
    line->at += width;
}

void scriptura_signed(ScripturaLine *line, long long value)
{
    if (value < 0ll)
    {
        scriptura_character(line, '-');
    }
    // the magnitude of the most negative value is taken as one past the negation of one more than it, in range
    const unsigned long long magnitude = (value < 0ll) ? ((unsigned long long)(-(value + 1ll)) + 1ull)
                                                       : (unsigned long long)value;
    scriptura_decimal(line, magnitude, 1u);
}

void scriptura_hex(ScripturaLine *line, unsigned long long value, unsigned int digits_least)
{
    unsigned int digits = 1u;
    for (unsigned long long probe = value >> 4u; probe != 0ull; probe >>= 4u)
    {
        digits += 1u;
    }
    digits = (digits < digits_least) ? digits_least : digits;
    if (!scriptura_room(line, digits))
    {
        line->at = line->room;
        return;
    }
    unsigned long long rest = value;
    for (unsigned int index = digits; index > 0u; index -= 1u)
    {
        line->out[line->at + index - 1u] = scriptura_hex_digits[rest & 0xFull];
        rest >>= 4u;
    }
    line->at += digits;
}

unsigned long long scriptura_finish(ScripturaLine *line)
{
    if (line->at >= line->room)
    {
        return 0ull;
    }
    line->out[line->at] = '\0';
    return line->at;
}

int scriptura_held(const ScripturaLine *line)
{
    return (line->at < line->room) ? 1 : 0;
}

int scriptura_write(ScripturaLine *line, FILE *file)
{
    const unsigned long long length = scriptura_finish(line);
    return (scriptura_held(line) != 0) && (fwrite(line->out, 1u, (size_t)length, file) == (size_t)length);
}

#if defined(_MSC_VER) && !defined(__clang__)
static const ScripturaArm *volatile scriptura_chosen = NULL;
#else
static const ScripturaArm *scriptura_chosen = NULL;
#endif

static const ScripturaArm *scriptura_choose(void)
{
    const ScripturaArm *const avx512 = scriptura_avx512_arm();
    if (avx512 != NULL)
    {
        return avx512;
    }
    const ScripturaArm *const avx2 = scriptura_avx2_arm();
    if (avx2 != NULL)
    {
        return avx2;
    }
    const ScripturaArm *const sve = scriptura_sve_arm();
    if (sve != NULL)
    {
        return sve;
    }
    const ScripturaArm *const neon = scriptura_neon_arm();
    if (neon != NULL)
    {
        return neon;
    }
    return scriptura_portable_arm();
}

static const ScripturaArm *scriptura_chosen_arm(void)
{
#if defined(_MSC_VER) && !defined(__clang__)
    const ScripturaArm *const held = scriptura_chosen;
#else
    const ScripturaArm *const held = __atomic_load_n(&scriptura_chosen, __ATOMIC_RELAXED);
#endif
    if (held != NULL)
    {
        return held;
    }
    const ScripturaArm *const chosen = scriptura_choose();
#if defined(_MSC_VER) && !defined(__clang__)
    scriptura_chosen = chosen;
#else
    __atomic_store_n(&scriptura_chosen, chosen, __ATOMIC_RELAXED);
#endif
    return chosen;
}

const char *scriptura_arm(void)
{
    return scriptura_chosen_arm()->name;
}

unsigned long long scriptura_length(const char *text, unsigned long long room)
{
    return scriptura_chosen_arm()->length(text, room);
}

unsigned long long scriptura_find(const void *from, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_DIRECT_BYTES)
    {
        return scriptura_portable_find(from, value, bytes);
    }
    return scriptura_chosen_arm()->find(from, value, bytes);
}

void scriptura_copy(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_DIRECT_BYTES)
    {
        scriptura_portable_copy(to, from, bytes);
        return;
    }
    scriptura_chosen_arm()->copy(to, from, bytes);
}

void scriptura_move_up(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_DIRECT_BYTES)
    {
        scriptura_portable_move_up(to, from, bytes);
        return;
    }
    scriptura_chosen_arm()->move_up(to, from, bytes);
}

int scriptura_compare(const void *one, const void *other, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_DIRECT_BYTES)
    {
        return scriptura_portable_compare(one, other, bytes);
    }
    return scriptura_chosen_arm()->compare(one, other, bytes);
}

void scriptura_fill(void *to, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_DIRECT_BYTES)
    {
        scriptura_portable_fill(to, value, bytes);
        return;
    }
    scriptura_chosen_arm()->fill(to, value, bytes);
}
