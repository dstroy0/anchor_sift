// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// A probe for the cell's PTX test (engine_table.md item 11(f) 4): questions asked of the device in the ruleset's own
// words. Each question's kernel is written from ptx.krs, one form by its name at a time (emit.h), around a frame of this
// probe's own that loads a case's eight input words and stores four output words, and nvJitLink assembles it as the
// engine's PTX path does. The header is asked of NVRTC. One question a process, named by the first word:
//   membership   every arithmetic, test and conversion form the emitter writes, over 65,536 cases of input words, each
//                answer held to the host's integers; a form's answer where PTX leaves it undefined (a divisor of 0) is
//                printed and not held. Exit 0 where every defined answer agrees, 1 where one does not
//   address      a load from address 16, which no allocation holds
//   misaligned   a 32-bit load from an address one byte past an allocation's start
//   trap         PTX's trap instruction
//   lacking      elect.sync, which PTX gives sm_90 and later, in a kernel for this device
//   alive        one form over one case, to show a fresh process's device answers
// A question the device refuses prints "error <code> <name>" for the CUDA error it gave, then the error the next
// allocation gives, "after <code> <name>", and exits 3. One the toolchain refuses prints "refused" and its log, and
// exits 4. Exit 2 where the probe could not ask at all
#include "../../src/engine/base/emit/emit_ptx.h"

#include <cuda_runtime.h>
#include <nvJitLink.h>
#include <nvrtc.h>

#include <stdio.h>
#include <string.h>

#include <functional>
#include <string>
#include <vector>

#define PROBE_CASES 65536u
#define PROBE_IN_WORDS 8u
#define PROBE_OUT_WORDS 4u
#define PROBE_THREADS 256u
// the operands every case draws most of its words from, the edges of 32-bit arithmetic and of a shift
#define PROBE_EDGES 14u

static const unsigned int s_probe_edges[PROBE_EDGES] = {0u,          1u,          2u,          3u,
                                                          31u,         32u,         33u,         64u,
                                                          0x7FFFFFFFu, 0x80000000u, 0x80000001u, 0xFFFFFFFEu,
                                                          0xFFFFFFFFu, 0x10000u};

// the answer the host's integers give a case: the output words, and 0 where the rule leaves the answer undefined
typedef std::function<int(const unsigned int *in, unsigned int *out)> ProbeRule;

// one question: its name, the forms that ask it as the kernel's body, the output words it writes and the host's rule
struct ProbeQuestion
{
    std::string name;
    std::string body;
    unsigned int outputs;
    ProbeRule rule;
};

// the registers of each bank a kernel declares: the questions' own below, and above them the scratch a construct
// takes, numbered on through the whole process so that no two scratch registers share a number
#define PROBE_TEMPORARIES 12u
#define PROBE_WIDES 4u
#define PROBE_PREDICATES 4u
#define PROBE_DECLARED 1024u

// the ruleset's spellings and a writer for its forms, which marks the text broken where a form is not written; the
// next scratch register of each bank a construct may take
struct ProbeWriter
{
    const CycleRuleset *rules;
    int broken;
    unsigned int scratch_temporary;
    unsigned int scratch_wide;
    unsigned int scratch_predicate;
};

static std::string probe_register(ProbeWriter *writer, const char *bank, unsigned int number)
{
    const std::string spelled = cycle_ruleset_register(writer->rules, bank, number);
    writer->broken = writer->broken || spelled.empty();
    return spelled;
}

static std::string probe_temporary(ProbeWriter *writer, unsigned int number)
{
    return probe_register(writer, "temporary", number);
}

static std::string probe_wide(ProbeWriter *writer, unsigned int number)
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
    unsigned int *const next = (bank == "temporary") ? &writer->scratch_temporary
                             : ((bank == "wide") ? &writer->scratch_wide
                                                 : ((bank == "predicate") ? &writer->scratch_predicate : NULL));
    if ((next == NULL) || (*next >= PROBE_DECLARED))
    {
        return std::string();
    }
    *next += 1u;
    return cycle_ruleset_register(writer->rules, bank, *next - 1u);
}

static void probe_form(ProbeWriter *writer, std::string &text, const char *name, const std::vector<std::string> &arguments)
{
    const auto scratch = [writer](const std::string &bank) { return probe_scratch(writer, bank); };
    if (!cycle_ruleset_form(writer->rules, name, arguments, scratch, text))
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
static void probe_case(unsigned int number, unsigned int *in)
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
static std::vector<ProbeQuestion> probe_questions(ProbeWriter *writer)
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

// PTX's header for the device, asked of NVRTC by compiling an empty kernel to PTX: the .version, .target and
// .address_size lines. Empty where NVRTC does not answer
static std::string probe_header(int major, int minor)
{
    const char question[] = "extern \"C\" __global__ void cell_header(void)\n{\n}\n";
    nvrtcProgram program = NULL;
    std::string lines;
    if (nvrtcCreateProgram(&program, question, "cell_header.cu", 0, NULL, NULL) != NVRTC_SUCCESS)
    {
        return lines;
    }
    char architecture[48];
    snprintf(architecture, sizeof(architecture), "--gpu-architecture=compute_%d%d", major, minor);
    const char *const options[] = {architecture};
    size_t size = 0u;
    if ((nvrtcCompileProgram(program, 1, options) == NVRTC_SUCCESS) && (nvrtcGetPTXSize(program, &size) == NVRTC_SUCCESS)
        && (size > 1u))
    {
        std::vector<char> ptx(size);
        if (nvrtcGetPTX(program, ptx.data()) == NVRTC_SUCCESS)
        {
            ptx[size - 1u] = '\0';
            const char *const wanted[] = {".version ", ".target ", ".address_size "};
            for (const char *const start : wanted)
            {
                const char *const found = strstr(ptx.data(), start);
                const char *const end = (found != NULL) ? strchr(found, '\n') : NULL;
                // a line ends past its start
                lines += (end != NULL) ? (std::string(found, (size_t)(end - found)) + "\n") : std::string();
            }
        }
    }
    nvrtcDestroyProgram(&program);
    return lines;
}

// the kernel: the header, then an entry of this probe's own that finds its case, loads its eight words into
// temporaries 0 to 7 through the ruleset's global_load, sets outputs 8 to 11 to 0, runs the body, and stores the
// outputs through the ruleset's record_store, the record register set to the case's output
static std::string probe_kernel(ProbeWriter *writer, const std::string &header, const std::string &body)
{
    std::string text = header;
    text += "\n.visible .entry cell_ask(\n\t.param .u64 cell_ask_in,\n\t.param .u64 cell_ask_out,\n\t.param .u32 "
            "cell_ask_count\n)\n{\n";
    text += "\t.reg .pred \t%cell_past;\n\t.reg .b32 \t%cell_word<4>;\n\t.reg .b64 \t%cell_wide<4>;\n";
    const std::string declared = std::to_string(PROBE_DECLARED);
    probe_form(writer, text, "declare_predicates", {declared});
    probe_form(writer, text, "declare_fixed_predicates", {});
    probe_form(writer, text, "declare_temporaries", {declared});
    probe_form(writer, text, "declare_wides", {declared});
    probe_form(writer, text, "declare_fixed_words", {});
    probe_form(writer, text, "declare_fixed_wides", {});
    probe_form(writer, text, "word_set", {cycle_ruleset_fixed(writer->rules, "zero"), "0"});
    text += "\tld.param.u64 \t%cell_wide0, [cell_ask_in];\n\tld.param.u64 \t%cell_wide1, [cell_ask_out];\n";
    text += "\tld.param.u32 \t%cell_word0, [cell_ask_count];\n\tmov.u32 \t%cell_word1, %ctaid.x;\n";
    text += "\tmov.u32 \t%cell_word2, %ntid.x;\n\tmov.u32 \t%cell_word3, %tid.x;\n";
    text += "\tmad.lo.u32 \t%cell_word1, %cell_word1, %cell_word2, %cell_word3;\n";
    text += "\tsetp.ge.u32 \t%cell_past, %cell_word1, %cell_word0;\n\t@%cell_past bra \t$Lcell_done;\n";
    text += "\tcvta.to.global.u64 \t%cell_wide0, %cell_wide0;\n\tcvta.to.global.u64 \t%cell_wide1, %cell_wide1;\n";
    text += "\tmul.wide.u32 \t%cell_wide2, %cell_word1, 32;\n\tadd.s64 \t%cell_wide2, %cell_wide0, %cell_wide2;\n";
    text += "\tmul.wide.u32 \t%cell_wide3, %cell_word1, 16;\n\tadd.s64 \t%cell_wide3, %cell_wide1, %cell_wide3;\n";
    for (unsigned int word = 0u; word < PROBE_IN_WORDS; word += 1u)
    {
        probe_form(writer, text, "global_load",
                   {probe_temporary(writer, word), "%cell_wide2", std::to_string(word * 4u)});
    }
    for (unsigned int word = 0u; word < PROBE_OUT_WORDS; word += 1u)
    {
        probe_form(writer, text, "word_set", {probe_temporary(writer, 8u + word), "0"});
    }
    text += body;
    text += "\tmov.b64 \t" + cycle_ruleset_fixed(writer->rules, "record") + ", %cell_wide3;\n";
    for (unsigned int word = 0u; word < PROBE_OUT_WORDS; word += 1u)
    {
        probe_form(writer, text, "record_store", {std::to_string(word * 4u), probe_temporary(writer, 8u + word)});
    }
    text += "$Lcell_done:\n";
    probe_form(writer, text, "return", {});
    text += "}\n";
    return text;
}

// the kernel's text assembled by nvJitLink for the device and loaded: 1 and the kernel, or 0 with the log printed
static int probe_build(const std::string &text, int major, int minor, cudaLibrary_t *library, cudaKernel_t *kernel)
{
    char architecture[32];
    snprintf(architecture, sizeof(architecture), "-arch=sm_%d%d", major, minor);
    const char *options[] = {architecture};
    nvJitLinkHandle handle = NULL;
    if (nvJitLinkCreate(&handle, 1u, options) != NVJITLINK_SUCCESS)
    {
        printf("refused: nvJitLink could not be made\n");
        return 0;
    }
    size_t size = 0u;
    const int linked = (nvJitLinkAddData(handle, NVJITLINK_INPUT_PTX, text.c_str(), text.size() + 1u, "cell_ask")
                        == NVJITLINK_SUCCESS)
                    && (nvJitLinkComplete(handle) == NVJITLINK_SUCCESS)
                    && (nvJitLinkGetLinkedCubinSize(handle, &size) == NVJITLINK_SUCCESS) && (size != 0u);
    std::vector<char> cubin(linked ? size : 0u);
    const int taken = linked && (nvJitLinkGetLinkedCubin(handle, cubin.data()) == NVJITLINK_SUCCESS);
    if (!taken)
    {
        size_t log_size = 0u;
        std::vector<char> log(1u, '\0');
        if ((nvJitLinkGetErrorLogSize(handle, &log_size) == NVJITLINK_SUCCESS) && (log_size > 1u))
        {
            log.assign(log_size, '\0');
            nvJitLinkGetErrorLog(handle, log.data());
        }
        printf("refused: nvJitLink did not assemble the kernel\n%s\n", log.data());
    }
    nvJitLinkDestroy(&handle);
    return taken && (cudaLibraryLoadData(library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u) == cudaSuccess)
        && (cudaLibraryGetKernel(kernel, *library, "cell_ask") == cudaSuccess);
}

// the kernel run over `count` cases of `in`, its outputs into `out`; the CUDA error the run gave
static cudaError_t probe_run(cudaKernel_t kernel, const unsigned int *in, unsigned int *out, unsigned int count)
{
    unsigned int *device_in = NULL;
    unsigned int *device_out = NULL;
    const size_t in_bytes = (size_t)count * PROBE_IN_WORDS * sizeof(unsigned int);
    const size_t out_bytes = (size_t)count * PROBE_OUT_WORDS * sizeof(unsigned int);
    cudaError_t status = cudaMalloc((void **)&device_in, in_bytes);
    status = (status == cudaSuccess) ? cudaMalloc((void **)&device_out, out_bytes) : status;
    status = (status == cudaSuccess) ? cudaMemcpy(device_in, in, in_bytes, cudaMemcpyHostToDevice) : status;
    void *arguments[] = {(void *)&device_in, (void *)&device_out, (void *)&count};
    const unsigned int blocks = (count + PROBE_THREADS - 1u) / PROBE_THREADS;
    status = (status == cudaSuccess)
               ? cudaLaunchKernel((const void *)kernel, dim3(blocks), dim3(PROBE_THREADS), arguments, 0u, NULL)
               : status;
    status = (status == cudaSuccess) ? cudaDeviceSynchronize() : status;
    status = (status == cudaSuccess) ? cudaMemcpy(out, device_out, out_bytes, cudaMemcpyDeviceToHost) : status;
    cudaFree(device_in);
    cudaFree(device_out);
    return status;
}

// the error a question the device refused gave, then the error the next allocation gives: whether the context
// survived the refusal
static int probe_refused(cudaError_t status)
{
    printf("error %d %s\n", (int)status, cudaGetErrorName(status));
    void *after = NULL;
    const cudaError_t next = cudaMalloc(&after, 4u);
    printf("after %d %s\n", (int)next, cudaGetErrorName(next));
    return 3;
}

static int probe_membership(ProbeWriter *writer, const std::string &header, int major, int minor)
{
    const std::vector<ProbeQuestion> questions = probe_questions(writer);
    if (writer->broken)
    {
        return 2;
    }
    std::vector<unsigned int> in((size_t)PROBE_CASES * PROBE_IN_WORDS);
    for (unsigned int number = 0u; number < PROBE_CASES; number += 1u)
    {
        probe_case(number, &in[(size_t)number * PROBE_IN_WORDS]);
    }
    std::vector<unsigned int> out((size_t)PROBE_CASES * PROBE_OUT_WORDS);
    unsigned int disagreed = 0u;
    for (const ProbeQuestion &question : questions)
    {
        const std::string text = probe_kernel(writer, header, question.body);
        cudaLibrary_t library = NULL;
        cudaKernel_t kernel = NULL;
        if (writer->broken || !probe_build(text, major, minor, &library, &kernel))
        {
            printf("%s: not built\n", question.name.c_str());
            return 2;
        }
        const cudaError_t status = probe_run(kernel, in.data(), out.data(), PROBE_CASES);
        cudaLibraryUnload(library);
        if (status != cudaSuccess)
        {
            printf("%s: ", question.name.c_str());
            return probe_refused(status);
        }
        unsigned int held = 0u;
        unsigned int differ = 0u;
        unsigned int undefined = 0u;
        std::vector<unsigned int> seen;
        for (unsigned int number = 0u; number < PROBE_CASES; number += 1u)
        {
            const unsigned int *const case_in = &in[(size_t)number * PROBE_IN_WORDS];
            const unsigned int *const case_out = &out[(size_t)number * PROBE_OUT_WORDS];
            unsigned int wanted[PROBE_OUT_WORDS] = {0u, 0u, 0u, 0u};
            if (!question.rule(case_in, wanted))
            {
                undefined += 1u;
                // the device's answer to a question the rule leaves undefined, each distinct word once, the first four
                for (unsigned int word = 0u; (word < question.outputs) && (seen.size() < 4u); word += 1u)
                {
                    int known = 0;
                    for (const unsigned int earlier : seen)
                    {
                        known = known || (earlier == case_out[word]);
                    }
                    if (!known)
                    {
                        seen.push_back(case_out[word]);
                    }
                }
                continue;
            }
            int agrees = 1;
            for (unsigned int word = 0u; word < question.outputs; word += 1u)
            {
                agrees = agrees && (case_out[word] == wanted[word]);
            }
            held += agrees ? 1u : 0u;
            if (!agrees && (differ < 3u))
            {
                printf("  %s differs on case %u: in %08x %08x %08x %08x %08x %08x, device %08x %08x %08x %08x, host "
                       "%08x %08x %08x %08x\n",
                       question.name.c_str(), number, case_in[0], case_in[1], case_in[2], case_in[3], case_in[4],
                       case_in[5], case_out[0], case_out[1], case_out[2], case_out[3], wanted[0], wanted[1], wanted[2],
                       wanted[3]);
            }
            differ += agrees ? 0u : 1u;
        }
        disagreed += (differ != 0u) ? 1u : 0u;
        printf("form %s: %u cases, %u agree, %u differ", question.name.c_str(), held + differ, held, differ);
        if (undefined != 0u)
        {
            printf(", %u undefined, the device answering", undefined);
            for (const unsigned int word : seen)
            {
                printf(" %08x", word);
            }
        }
        printf("\n");
    }
    printf("membership: %zu questions, %u with a case that differs\n", questions.size(), disagreed);
    return (disagreed == 0u) ? 0 : 1;
}

// a kernel whose body is `body` alone, run over one case; `address` names the case's input, which the body may
// replace. Exit 0 where the device answers, 3 where it refuses the run, 4 where the toolchain refuses the kernel
static int probe_single(ProbeWriter *writer, const std::string &header, const std::string &body, int major, int minor)
{
    const std::string text = probe_kernel(writer, header, body);
    cudaLibrary_t library = NULL;
    cudaKernel_t kernel = NULL;
    if (writer->broken)
    {
        return 2;
    }
    if (!probe_build(text, major, minor, &library, &kernel))
    {
        return 4;
    }
    unsigned int in[PROBE_IN_WORDS] = {6u, 7u, 0u, 0u, 0u, 0u, 0u, 0u};
    unsigned int out[PROBE_OUT_WORDS] = {0u, 0u, 0u, 0u};
    const cudaError_t status = probe_run(kernel, in, out, 1u);
    if (status != cudaSuccess)
    {
        return probe_refused(status);
    }
    printf("answered %08x %08x %08x %08x\n", out[0], out[1], out[2], out[3]);
    cudaLibraryUnload(library);
    return 0;
}

int main(int count, char **arguments)
{
    const char *const question = (count > 1) ? arguments[1] : "";
    int device = 0;
    cudaDeviceProp properties;
    if ((cudaGetDevice(&device) != cudaSuccess) || (cudaGetDeviceProperties(&properties, device) != cudaSuccess))
    {
        printf("no device\n");
        return 2;
    }
    const int major = properties.major;
    const int minor = properties.minor;
    const std::string header = probe_header(major, minor);
    ProbeWriter writer = {cycle_emit_ptx().ruleset(1), 0, PROBE_TEMPORARIES, PROBE_WIDES, PROBE_PREDICATES};
    if ((writer.rules == NULL) || header.empty())
    {
        printf("the ruleset was refused, or NVRTC gave no header\n");
        return 2;
    }
    printf("sm_%d%d, %s", major, minor, header.c_str());
    const std::string t8 = probe_temporary(&writer, 8u);
    const std::string t0 = probe_temporary(&writer, 0u);
    const std::string w0 = probe_wide(&writer, 0u);
    if (strcmp(question, "membership") == 0)
    {
        return probe_membership(&writer, header, major, minor);
    }
    if (strcmp(question, "alive") == 0)
    {
        std::string body;
        probe_form(&writer, body, "add_alone", {t8, t0, probe_temporary(&writer, 1u)});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "address") == 0)
    {
        // the load reads the sixteenth byte of the device's address space
        std::string body;
        probe_form(&writer, body, "word_set", {t0, "16"});
        probe_form(&writer, body, "wide_from_word", {w0, t0});
        probe_form(&writer, body, "global_load", {t8, w0, "0"});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "misaligned") == 0)
    {
        // the case's own input, one byte in: a 32-bit load from an address that is not a multiple of 4
        std::string body = "\tadd.s64 \t%cell_wide2, %cell_wide2, 1;\n";
        probe_form(&writer, body, "global_load", {t8, "%cell_wide2", "0"});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "trap") == 0)
    {
        return probe_single(&writer, header, "\ttrap;\n", major, minor);
    }
    if (strcmp(question, "lacking") == 0)
    {
        return probe_single(&writer, header, "\t{\n\t.reg .pred \t%cell_elected;\n\t.reg .b32 \t%cell_leader;\n"
                                             "\telect.sync \t%cell_leader|%cell_elected, 0xffffffff;\n\t}\n",
                            major, minor);
    }
    printf("no question \"%s\"\n", question);
    return 2;
}
