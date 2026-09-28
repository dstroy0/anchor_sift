// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_ptx_probe_questions.cu: registers, forms and the questions
#include "cell_ptx_probe_internal.h"

static const unsigned int s_probe_edges[PROBE_EDGES] = {
    0u, 1u, 2u, 3u, 31u, 32u, 33u, 64u, 0x7FFFFFFFu, 0x80000000u, 0x80000001u, 0xFFFFFFFEu, 0xFFFFFFFFu, 0x10000u};

static std::string probe_register(ProbeWriter *writer, const char *bank, unsigned int number)
{
    const std::string written = ruleset_register(writer->rules, bank, number);
    writer->broken = writer->broken || written.empty();
    return written;
}

std::string probe_temporary(ProbeWriter *writer, unsigned int number)
{
    return probe_register(writer, "temporary", number);
}

std::string probe_wide(ProbeWriter *writer, unsigned int number)
{
    return probe_register(writer, "wide", number);
}

static std::string probe_predicate(ProbeWriter *writer, unsigned int number)
{
    return probe_register(writer, "predicate", number);
}

// a scratch register a construct takes, of the temporaries, the 64-bit temporaries or the predicates; empty for
// another bank or past the registers declared
static std::string probe_scratch(ProbeWriter *writer, const std::string &bank)
{
    unsigned int *const next =
        (bank == "temporary")
            ? &writer->scratch_temporary
            : ((bank == "wide") ? &writer->scratch_wide : ((bank == "predicate") ? &writer->scratch_predicate : NULL));
    if ((next == NULL) || (*next >= PROBE_DECLARED))
    {
        return std::string();
    }
    *next += 1u;
    return ruleset_register(writer->rules, bank, *next - 1u);
}

void probe_form(ProbeWriter *writer, std::string &text, const char *name, const std::vector<std::string> &arguments)
{
    const auto scratch = [writer](const std::string &bank) { return probe_scratch(writer, bank); };
    if (!ruleset_opcode(writer->rules, name, arguments, scratch, text))
    {
        fprintf(stderr, "  cell_ptx_probe: the ruleset does not write the form %s with %zu arguments\n", name,
                arguments.size());
        writer->broken = 1;
    }
}

static unsigned long long probe_mix(unsigned long long value)
{
    // splitmix64's finalizer: every case's words from its number alone
    value += 0x9E3779B97F4A7C15ull;
    value = (value ^ (value >> 30u)) * 0xBF58476D1CE4E5B9ull;
    value = (value ^ (value >> 27u)) * 0x94D049BB133111EBull;
    return value ^ (value >> 31u);
}

// a case's input words: each an edge three times in four, else a word drawn whole
void probe_case(unsigned int number, unsigned int *in)
{
    for (unsigned int word = 0u; word < PROBE_IN_WORDS; word += 1u)
    {
        const unsigned long long drawn = probe_mix(((unsigned long long)number * PROBE_IN_WORDS) + word);
        // a drawn word's low 32 bits, and an edge's place below the edges' count
        in[word] = ((drawn & 3ull) == 0ull) ? (unsigned int)(drawn >> 32u)
                                            : s_probe_edges[(unsigned int)((drawn >> 2u) % PROBE_EDGES)];
    }
}

static unsigned long long probe_pair(unsigned int low, unsigned int high)
{
    return ((unsigned long long)high << 32u) | low;
}

// the questions, each written in the ruleset's forms. Inputs lie in temporaries 0 to 7 and outputs in 8 to 11, each
// output set to 0 before the body
std::vector<ProbeQuestion> probe_questions(ProbeWriter *writer)
{
    std::vector<std::string> t;
    for (unsigned int number = 0u; number < 12u; number += 1u)
    {
        t.push_back(probe_temporary(writer, number));
    }
    std::vector<std::string> w;
    std::vector<std::string> p;
    for (unsigned int number = 0u; number < 4u; number += 1u)
    {
        w.push_back(probe_wide(writer, number));
        p.push_back(probe_predicate(writer, number));
    }
    std::vector<ProbeQuestion> questions;
    std::string body;
    const auto ask = [&](const char *name, unsigned int outputs, ProbeRule rule) {
        questions.push_back(ProbeQuestion{name, body, outputs, rule});
        body.clear();
    };
    const auto form = [&](const char *name, const std::vector<std::string> &arguments) {
        probe_form(writer, body, name, arguments);
    };
    // a predicate read out as 1 or 0
    const auto read_out = [&](unsigned int output, unsigned int predicate) {
        form("word_select", {t[8u + output], "1", "0", p[predicate]});
    };

    form("add_alone", {t[8], t[0], t[1]});
    ask("add_alone", 1u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] + in[1];
        return 1;
    });
    form("add_first", {t[8], t[0], t[3]});
    form("add_middle", {t[9], t[1], t[4]});
    form("add_last", {t[10], t[2], t[5]});
    ask("add_first, add_middle, add_last: 96 bits", 3u, [](const unsigned int *in, unsigned int *out) {
        unsigned long long carry = 0ull;
        for (unsigned int limb = 0u; limb < 3u; limb += 1u)
        {
            const unsigned long long sum = (unsigned long long)in[limb] + in[3u + limb] + carry;
            out[limb] = (unsigned int)sum;
            carry = sum >> 32u;
        }
        return 1;
    });
    form("subtract_alone", {t[8], t[0], t[1]});
    ask("subtract_alone", 1u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] - in[1];
        return 1;
    });
    form("subtract_first", {t[8], t[0], t[3]});
    form("subtract_middle", {t[9], t[1], t[4]});
    form("subtract_last", {t[10], t[2], t[5]});
    ask("subtract_first, subtract_middle, subtract_last: 96 bits", 3u, [](const unsigned int *in, unsigned int *out) {
        unsigned long long borrow = 0ull;
        for (unsigned int limb = 0u; limb < 3u; limb += 1u)
        {
            const unsigned long long difference = (unsigned long long)in[limb] - in[3u + limb] - borrow;
            out[limb] = (unsigned int)difference;
            borrow = (difference >> 32u) & 1ull;
        }
        return 1;
    });
    form("borrow_alone", {t[8], t[0], t[1]});
    form("borrow_read", {t[9], p[0]});
    read_out(2u, 0u);
    ask("borrow_alone, borrow_read", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] - in[1];
        out[1] = (in[0] < in[1]) ? 0xFFFFFFFFu : 0u;
        out[2] = (in[0] < in[1]) ? 1u : 0u;
        return 1;
    });
    form("borrow_first", {t[8], t[0], t[3]});
    form("borrow_middle", {t[9], t[1], t[4]});
    form("borrow_last", {t[10], t[2], t[5]});
    form("borrow_read", {t[11], p[0]});
    ask("borrow_first, borrow_middle, borrow_last, borrow_read: 96 bits", 4u,
        [](const unsigned int *in, unsigned int *out) {
            unsigned long long borrow = 0ull;
            for (unsigned int limb = 0u; limb < 3u; limb += 1u)
            {
                const unsigned long long difference = (unsigned long long)in[limb] - in[3u + limb] - borrow;
                out[limb] = (unsigned int)difference;
                borrow = (difference >> 32u) & 1ull;
            }
            out[3] = (borrow != 0ull) ? 0xFFFFFFFFu : 0u;
            return 1;
        });
    form("word_copy", {t[8], t[0]});
    form("word_set", {t[9], "4294967295"});
    form("word_set", {t[10], "2147483648"});
    ask("word_copy, word_set", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0];
        out[1] = 0xFFFFFFFFu;
        out[2] = 0x80000000u;
        return 1;
    });
    form("word_and", {t[8], t[0], t[1]});
    form("word_or", {t[9], t[0], t[1]});
    form("word_xor", {t[10], t[0], t[1]});
    ask("word_and, word_or, word_xor", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] & in[1];
        out[1] = in[0] | in[1];
        out[2] = in[0] ^ in[1];
        return 1;
    });
    // a shift of the register's width or more leaves 0 (PTX clamps the amount to the width)
    form("word_shift_left", {t[8], t[0], t[1]});
    form("word_shift_right", {t[9], t[0], t[1]});
    ask("word_shift_left, word_shift_right", 2u, [](const unsigned int *in, unsigned int *out) {
        out[0] = (in[1] < 32u) ? (in[0] << in[1]) : 0u;
        out[1] = (in[1] < 32u) ? (in[0] >> in[1]) : 0u;
        return 1;
    });
    // the pair's low word after a right shift by the amount clamped to 32
    form("word_funnel_right", {t[8], t[0], t[1], t[2]});
    ask("word_funnel_right", 1u, [](const unsigned int *in, unsigned int *out) {
        const unsigned int bits = (in[2] < 32u) ? in[2] : 32u;
        out[0] = (unsigned int)(probe_pair(in[0], in[1]) >> bits);
        return 1;
    });
    form("word_multiply", {t[8], t[0], t[1]});
    form("word_multiply_add", {t[9], t[0], t[1], t[2]});
    ask("word_multiply, word_multiply_add", 2u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] * in[1];
        out[1] = (in[0] * in[1]) + in[2];
        return 1;
    });
    form("word_divide", {t[8], t[0], t[1]});
    ask("word_divide", 1u, [](const unsigned int *in, unsigned int *out) {
        out[0] = (in[1] != 0u) ? (in[0] / in[1]) : 0u;
        return in[1] != 0u;
    });
    form("test_nonzero", {p[0], t[2]});
    form("word_select", {t[8], t[0], t[1], p[0]});
    ask("word_select, test_nonzero", 1u, [](const unsigned int *in, unsigned int *out) {
        out[0] = (in[2] != 0u) ? in[0] : in[1];
        return 1;
    });
    // a product and its carry in: a b + c never passes 64 bits
    form("product_low", {t[8], t[0], t[1], t[2]});
    form("product_high", {t[9], t[0], t[1]});
    ask("product_low, product_high", 2u, [](const unsigned int *in, unsigned int *out) {
        const unsigned long long product = ((unsigned long long)in[0] * in[1]) + in[2];
        out[0] = (unsigned int)product;
        out[1] = (unsigned int)(product >> 32u);
        return 1;
    });
    form("sign_set", {t[8], "-1"});
    form("sign_set", {t[9], "1"});
    form("test_nonzero", {p[0], t[2]});
    form("sign_select", {t[10], t[0], t[1], p[0]});
    ask("sign_set, sign_select", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = 0xFFFFFFFFu;
        out[1] = 1u;
        out[2] = (in[2] != 0u) ? in[0] : in[1];
        return 1;
    });
    // the signed product's low word, and the absolute value and negation modulo 2^32: |-2^31| is -2^31
    form("sign_multiply", {t[8], t[0], t[1]});
    form("sign_absolute", {t[9], t[0]});
    form("sign_negate", {t[10], t[0]});
    ask("sign_multiply, sign_absolute, sign_negate", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0] * in[1];
        out[1] = ((in[0] & 0x80000000u) != 0u) ? (0u - in[0]) : in[0];
        out[2] = 0u - in[0];
        return 1;
    });
    form("test_nonzero", {p[0], t[0]});
    form("test_zero", {p[1], t[0]});
    form("test_negative", {p[2], t[0]});
    read_out(0u, 0u);
    read_out(1u, 1u);
    read_out(2u, 2u);
    ask("test_nonzero, test_zero, test_negative", 3u, [](const unsigned int *in, unsigned int *out) {
        out[0] = (in[0] != 0u) ? 1u : 0u;
        out[1] = (in[0] == 0u) ? 1u : 0u;
        out[2] = ((in[0] & 0x80000000u) != 0u) ? 1u : 0u;
        return 1;
    });
    form("test_signed_zero", {p[0], t[0]});
    form("test_signed_differ", {p[1], t[0], t[1]});
    form("test_signed_greater", {p[2], t[0], t[1]});
    read_out(0u, 0u);
    read_out(1u, 1u);
    read_out(2u, 2u);
    ask("test_signed_zero, test_signed_differ, test_signed_greater", 3u, [](const unsigned int *in, unsigned int *out) {
        // a word read as its two's complement value
        const long long left = (long long)(int)in[0];
        // a word read as its two's complement value
        const long long right = (long long)(int)in[1];
        out[0] = (left == 0ll) ? 1u : 0u;
        out[1] = (left != right) ? 1u : 0u;
        out[2] = (left > right) ? 1u : 0u;
        return 1;
    });
    form("wide_pack", {w[0], t[0], t[1]});
    form("wide_pack", {w[1], t[2], t[3]});
    form("test_nonzero", {p[3], t[4]});
    form("test_wide_nonzero", {p[0], w[0]});
    form("test_wide_equal", {p[1], w[0], w[1]});
    form("test_wide_below", {p[2], w[0], w[1]});
    form("test_wide_below_and", {p[3], w[0], w[1], p[3]});
    read_out(0u, 0u);
    read_out(1u, 1u);
    read_out(2u, 2u);
    read_out(3u, 3u);
    ask("test_wide_nonzero, test_wide_equal, test_wide_below, test_wide_below_and", 4u,
        [](const unsigned int *in, unsigned int *out) {
            const unsigned long long left = probe_pair(in[0], in[1]);
            const unsigned long long right = probe_pair(in[2], in[3]);
            out[0] = (left != 0ull) ? 1u : 0u;
            out[1] = (left == right) ? 1u : 0u;
            out[2] = (left < right) ? 1u : 0u;
            out[3] = ((left < right) && (in[4] != 0u)) ? 1u : 0u;
            return 1;
        });
    form("test_nonzero", {p[0], t[0]});
    form("test_nonzero", {p[1], t[1]});
    form("predicate_xor", {p[2], p[0], p[1]});
    form("predicate_and", {p[3], p[0], p[1]});
    read_out(0u, 2u);
    read_out(1u, 3u);
    ask("predicate_xor, predicate_and", 2u, [](const unsigned int *in, unsigned int *out) {
        out[0] = ((in[0] != 0u) != (in[1] != 0u)) ? 1u : 0u;
        out[1] = ((in[0] != 0u) && (in[1] != 0u)) ? 1u : 0u;
        return 1;
    });
    form("wide_from_word", {w[0], t[0]});
    form("wide_unpack", {t[8], t[9], w[0]});
    form("wide_pack", {w[1], t[1], t[2]});
    form("word_from_wide", {t[10], w[1]});
    form("wide_unpack", {t[11], t[7], w[1]});
    ask("wide_from_word, word_from_wide, wide_pack, wide_unpack", 4u, [](const unsigned int *in, unsigned int *out) {
        out[0] = in[0];
        out[1] = 0u;
        out[2] = in[1];
        out[3] = in[1];
        return 1;
    });
    form("wide_pack", {w[0], t[0], t[1]});
    form("wide_pack", {w[1], t[2], t[3]});
    form("wide_multiply", {w[2], w[0], w[1]});
    form("wide_unpack", {t[8], t[9], w[2]});
    form("wide_multiply_word", {w[3], t[4], t[5]});
    form("wide_unpack", {t[10], t[11], w[3]});
    ask("wide_multiply, wide_multiply_word", 4u, [](const unsigned int *in, unsigned int *out) {
        const unsigned long long product = probe_pair(in[0], in[1]) * probe_pair(in[2], in[3]);
        const unsigned long long word_product = (unsigned long long)in[4] * in[5];
        out[0] = (unsigned int)product;
        out[1] = (unsigned int)(product >> 32u);
        out[2] = (unsigned int)word_product;
        out[3] = (unsigned int)(word_product >> 32u);
        return 1;
    });
    form("wide_pack", {w[0], t[0], t[1]});
    form("wide_pack", {w[1], t[2], t[3]});
    form("wide_add", {w[2], w[0], w[1]});
    form("wide_unpack", {t[8], t[9], w[2]});
    form("wide_add_unsigned", {w[3], w[0], w[1]});
    form("wide_unpack", {t[10], t[11], w[3]});
    ask("wide_add, wide_add_unsigned", 4u, [](const unsigned int *in, unsigned int *out) {
        const unsigned long long sum = probe_pair(in[0], in[1]) + probe_pair(in[2], in[3]);
        out[0] = (unsigned int)sum;
        out[1] = (unsigned int)(sum >> 32u);
        out[2] = out[0];
        out[3] = out[1];
        return 1;
    });
    // a shift of 64 bits or more leaves 0
    form("wide_pack", {w[0], t[0], t[1]});
    form("wide_shift_left", {w[2], w[0], t[2]});
    form("wide_unpack", {t[8], t[9], w[2]});
    form("wide_pack", {w[1], t[3], t[4]});
    form("test_nonzero", {p[0], t[5]});
    form("wide_select", {w[3], w[0], w[1], p[0]});
    form("wide_unpack", {t[10], t[11], w[3]});
    ask("wide_shift_left, wide_select", 4u, [](const unsigned int *in, unsigned int *out) {
        const unsigned long long shifted = (in[2] < 64u) ? (probe_pair(in[0], in[1]) << in[2]) : 0ull;
        const unsigned long long chosen = (in[5] != 0u) ? probe_pair(in[0], in[1]) : probe_pair(in[3], in[4]);
        out[0] = (unsigned int)shifted;
        out[1] = (unsigned int)(shifted >> 32u);
        out[2] = (unsigned int)chosen;
        out[3] = (unsigned int)(chosen >> 32u);
        return 1;
    });
    form("wide_pack", {w[0], t[0], t[1]});
    form("wide_pack", {w[1], t[2], t[3]});
    form("wide_divide", {w[2], w[0], w[1]});
    form("wide_unpack", {t[8], t[9], w[2]});
    ask("wide_divide", 2u, [](const unsigned int *in, unsigned int *out) {
        const unsigned long long divisor = probe_pair(in[2], in[3]);
        const unsigned long long quotient = (divisor != 0ull) ? (probe_pair(in[0], in[1]) / divisor) : 0ull;
        out[0] = (unsigned int)quotient;
        out[1] = (unsigned int)(quotient >> 32u);
        return divisor != 0ull;
    });
    return questions;
}
