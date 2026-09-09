/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_ancorae_lattice.c
 * @brief Whether an anchor still refutes when the positions are not on a line, the alphabet cannot be
 *        enumerated, and no measure over it exists.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note What this exists to settle. The soundness argument for an anchor uses only that a position is
 *       a position: an anchor is a condition copied out of the pattern, so anything holding the whole
 *       pattern holds that condition. Nothing in it names a dimension, an order on positions, or a
 *       symbol. The sift bench measures byte strings and cannot tell whether that generality is real
 *       or whether the argument quietly leans on the line it was written over.
 * @note How it settles it. The core below takes a list of valid base positions, a list of
 *       displacements, and a callback answering whether two positions carry the same symbol. It never
 *       learns how many dimensions there are, because the geometry is entirely inside the base list
 *       the caller built. It never learns what a symbol is, because it only ever asks whether two of
 *       them agree. A core that cannot see either one cannot depend on either one.
 * @note Counts, not cycles. Every number here is a property of the data and the geometry, identical on
 *       every part, so nothing needs a board and nothing here is a timing claim.
 */
#include <complex.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// The two names this file takes from the vendored embedded_types library, shimmed so the engine's C
// side builds with a C11 compiler alone. Both are written the way the tree writes them, and no
// other line in this file has to change to make it standalone.
typedef bool embed_bool;
#define EMBED_TRUE true
#define EMBED_FALSE false

/**
 * @brief Points in every pattern this bench uses.
 *
 * @note One value across every domain. A row from a volume and a row from a line are comparable.
 *       Eight points over a two symbol alphabet puts the pattern at one position in 256, which leaves
 *       real occurrences to lose in a domain of roughly four thousand positions. A pattern rare enough
 *       to occur once would make the invariant check a test of one sample.
 */
#define PATTERN_POINTS 8u

/**
 * @brief The most points a swept pattern may carry, which sizes every displacement array.
 *
 * @note The hand built geometries below stay at PATTERN_POINTS because their shapes are written out
 *       by hand: a 2 by 4 box, eight scattered cells inside a 5 by 5 window, and that scatter turned
 *       a quarter. There is no generalization of a named shape to an arbitrary point count, so the
 *       sweep runs over the geometries that do generalize, which are the line and the hypercube.
 */
#define PATTERN_POINTS_MAX 32u

/**
 * @brief The most anchors a row will stack.
 *
 * @note Every point the pattern has. Six was a run time choice and it left untested the case the
 *       claim is most exposed at, the improper subset, where the filter is the exact compare and
 *       the candidate count has to fall to the occurrence count. A proposition about any subset has
 *       to include the improper one.
 */
#define LATTICE_MAX_ANCHORS PATTERN_POINTS_MAX

/**
 * @brief Distinct symbols in every domain here.
 *
 * @note Two. The alphabet sits at the bottom of its range to let a pattern recur often enough
 *       for a lost occurrence to have somewhere to hide. What the alphabet costs is measured in the
 *       sift bench; what it is made of is the question here, and two of anything is enough for that.
 */
#define SYMBOL_LEVELS 2u

/**
 * @brief Alphabet sizes the sweep runs over.
 *
 * @note Two was the only alphabet here for a long time, chosen to let a pattern recur often enough
 *       for a lost occurrence to have somewhere to hide. That reasoning is sound and it is also the
 *       bound. An alphabet is a free parameter of the claim, and a claim about any alphabet has to
 *       be asked at more than one. The claim holds as the alphabet grows; the check is what breaks,
 *       since a pattern of p points over L symbols occurs about base_count / L^p times by chance
 *       and that reaches zero fast. Planting occurrences keeps the check alive out here.
 */
static const unsigned ALPHABET_SIZES[] = {2u, 3u, 4u, 16u, 64u, 256u};

/**
 * @brief Point counts the sweep runs over, for the geometries that generalize.
 */
static const unsigned POINT_COUNTS[] = {1u, 2u, 3u, 5u, 8u, 13u, 21u, 32u};

/**
 * @brief Copies of the pattern planted into a swept domain.
 *
 * @note Without these the invariant sweep reports nothing to check the moment the alphabet or the
 *       point count grows, and a row that checked nothing is not evidence that anything held. A
 *       planted copy is a true occurrence by construction, and refusing one is the failure the
 *       proposition forbids. Planting is the only way to have any at 32 points over 256
 *       symbols where chance supplies none.
 */
#define PLANTED_COPIES 24u

/**
 * @brief How many patterns are drawn from each domain.
 */
#define PATTERN_SAMPLES 64u

/**
 * @brief Answers whether two positions in a domain carry the same symbol.
 *
 * @param[in] domain Storage the two positions index into [BORROWS].
 * @param[in] left   One position.
 * @param[in] right  The other.
 * @return           EMBED_TRUE when the two agree.
 * @note This is the only thing the core ever asks about a symbol. It does not read a value, compare
 *       magnitudes, or need the alphabet to be finite or enumerable. A domain whose symbols are
 *       irrational, complex, or simply unknown supplies one of these.
 */
typedef embed_bool (*SameSymbol)(const void *domain, size_t left, size_t right);

/**
 * @brief One domain, its geometry, and how to compare two of its positions.
 *
 * @note The geometry lives in @c bases and @c displacements and nowhere else. A grid, a volume and a
 *       line differ here only in which integers those two arrays hold, and one core serves all
 *       three without a dimension parameter.
 */
typedef struct
{
    const char *name;
    const void *domain;
    SameSymbol same;
    const size_t *bases;
    size_t base_count;
    const ptrdiff_t *displacements;
    unsigned point_count;
} LatticeCase;

/**
 * @brief How an anchor subset gets chosen from a pattern's points.
 *
 * @note All three are uninformed. There is no cost table in this file and there cannot be one, since
 *       a domain whose alphabet cannot be enumerated has no frequencies to weigh. That is the setting
 *       the claim has to survive, so the rules here differ from each other and none of them looks at
 *       the data.
 */
typedef enum
{
    ANCHOR_LEADING = 0,
    ANCHOR_SPREAD = 1,
    ANCHOR_SHUFFLED = 2
} LatticeRule;

/**
 * @brief Names a rule for the row it is printed on.
 *
 * @param[in] rule Which selection rule.
 * @return         Text naming it [BORROWS].
 */
static const char *rule_name(LatticeRule rule)
{
    switch (rule)
    {
        case ANCHOR_SPREAD:
        {
            return "spread";
        }
        case ANCHOR_SHUFFLED:
        {
            return "shuffled";
        }
        case ANCHOR_LEADING:
        default:
        {
            return "leading";
        }
    }
}

/**
 * @brief Fills @p into with @p length bytes drawn from SHA-256 in counter mode.
 *
 * @param[out] into   Storage to fill [BORROWS].
 * @param[in]  length Bytes to write.
 * @param[in]  salt   Distinguishes one stream from another.
 * @note Every domain and every shuffle in this file comes from here. A run reproduces exactly, and
 *       two domains built with different salts share no structure.
 */
/**
 * @brief One step of splitmix64.
 *
 * @param[in,out] state Generator state, advanced by the call [BORROWS].
 * @return              The next value in the stream.
 */
static uint64_t next_random(uint64_t *state)
{
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t held = *state;

    held = (held ^ (held >> 30)) * 0xBF58476D1CE4E5B9ULL;
    held = (held ^ (held >> 27)) * 0x94D049BB133111EBULL;
    return held ^ (held >> 31);
}

static void draw_bytes(uint8_t *into, size_t length, uint64_t salt)
{
    // splitmix64, which reproduces exactly from the salt and needs nothing linked. It replaces the
    // SHA-256 counter mode this file used to draw from. That was the right generator for the sift
    // bench, where the control corpus carries every independence claim and its uniformity has to be
    // one somebody checked against published vectors. Nothing here rests on the generator: the
    // question is whether an anchor can lose a true occurrence, and a true occurrence is true
    // whatever drew the domain it sits in.
    uint64_t state = salt;
    size_t written = 0u;

    while (written < length)
    {
        const uint64_t held = next_random(&state);
        size_t taking = length - written;

        if (taking > sizeof held)
        {
            taking = sizeof held;
        }
        memcpy(into + written, &held, taking);
        written += taking;
    }
}

/**
 * @brief Counts positions where every anchor agrees with the pattern.
 *
 * @param[in] same          How to compare two positions.
 * @param[in] domain        Storage both positions index into [BORROWS].
 * @param[in] bases         Every position a pattern could start at [BORROWS].
 * @param[in] base_count    How many.
 * @param[in] pattern_base  Where the pattern itself sits.
 * @param[in] displacements Offsets from a base to each of the pattern's points [BORROWS].
 * @param[in] anchors       Which displacements are being used as anchors [BORROWS].
 * @param[in] anchor_count  How many.
 * @return                  Positions that survive every anchor.
 * @note The core, and the whole point of the file. It has no dimension parameter because the geometry
 *       is already inside @p bases and @p displacements. It has no symbol type because it only calls
 *       @p same. Neither omission is an economy: a core that cannot see the dimension or the alphabet
 *       cannot have an argument that depends on either.
 */
static uint32_t candidates_lattice(SameSymbol same, const void *domain, const size_t *bases, size_t base_count,
                                   size_t pattern_base, const ptrdiff_t *displacements, const unsigned *anchors,
                                   unsigned anchor_count)
{
    uint32_t surviving = 0u;

    for (size_t index = 0u; index < base_count; index++)
    {
        // Signed arithmetic on the way in, because a displacement can reach backward from its base and
        // an unsigned intermediate would wrap instead of subtracting
        const ptrdiff_t base = (ptrdiff_t)bases[index];
        unsigned matched = 0u;

        while ((matched < anchor_count) &&
               (same(domain, (size_t)(base + displacements[anchors[matched]]),
                     (size_t)((ptrdiff_t)pattern_base + displacements[anchors[matched]])) != EMBED_FALSE))
        {
            matched++;
        }
        if (matched == anchor_count)
        {
            surviving++;
        }
    }
    return surviving;
}

/**
 * @brief Counts true occurrences of the pattern that the anchor subset refuses to admit.
 *
 * @param[in]  same          How to compare two positions.
 * @param[in]  domain        Storage both positions index into [BORROWS].
 * @param[in]  bases         Every position a pattern could start at [BORROWS].
 * @param[in]  base_count    How many.
 * @param[in]  pattern_base  Where the pattern itself sits.
 * @param[in]  displacements Offsets from a base to each of the pattern's points [BORROWS].
 * @param[in]  point_count   How many points the whole pattern has.
 * @param[in]  anchors       Which displacements are being used as anchors [BORROWS].
 * @param[in]  anchor_count  How many.
 * @param[out] found         Receives how many true occurrences the domain holds [BORROWS].
 * @return                   How many of those an anchor rejected.
 * @note The same obligation the sift bench checks over byte strings, asked here where the positions
 *       are not on a line and the symbols may not be readable. An anchor is one of the pattern's own
 *       points, so anything matching every point matches that one. A nonzero return is a defect in
 *       this file and never a property of a geometry.
 */
static uint32_t refused_lattice(SameSymbol same, const void *domain, const size_t *bases, size_t base_count,
                                size_t pattern_base, const ptrdiff_t *displacements, unsigned point_count,
                                const unsigned *anchors, unsigned anchor_count, uint32_t *found)
{
    uint32_t refused = 0u;
    uint32_t occurrences = 0u;

    for (size_t index = 0u; index < base_count; index++)
    {
        const ptrdiff_t base = (ptrdiff_t)bases[index];
        unsigned matched = 0u;

        while ((matched < point_count) &&
               (same(domain, (size_t)(base + displacements[matched]),
                     (size_t)((ptrdiff_t)pattern_base + displacements[matched])) != EMBED_FALSE))
        {
            matched++;
        }
        if (matched < point_count)
        {
            continue;
        }
        occurrences++;

        for (unsigned which = 0u; which < anchor_count; which++)
        {
            const ptrdiff_t reach = displacements[anchors[which]];

            if (same(domain, (size_t)(base + reach), (size_t)((ptrdiff_t)pattern_base + reach)) == EMBED_FALSE)
            {
                refused++;
                break;
            }
        }
    }
    *found = occurrences;
    return refused;
}

/**
 * @brief Chooses @p want anchor positions out of @p point_count under @p rule.
 *
 * @param[in]  rule        Which selection rule.
 * @param[in]  point_count How many points the pattern has.
 * @param[in]  want        How many anchors to choose.
 * @param[out] anchors     Receives the chosen indices [BORROWS].
 * @param[in]  salt        Varies the shuffled rule between samples.
 * @return                 How many were chosen, short of want only when the pattern has fewer points.
 * @note Three rules that share nothing. Leading takes the first points, spread walks them at an even
 *       stride, and shuffled draws a permutation from SHA-256. If the choice mattered to correctness,
 *       three rules disagreeing this much would show it.
 */
static unsigned pick_lattice_anchors(LatticeRule rule, unsigned point_count, unsigned want, unsigned *anchors,
                                     uint64_t salt)
{
    if (want > point_count)
    {
        return 0u;
    }

    switch (rule)
    {
        case ANCHOR_SPREAD:
        {
            for (unsigned index = 0u; index < want; index++)
            {
                anchors[index] = (index * point_count) / want;
            }
            break;
        }
        case ANCHOR_SHUFFLED:
        {
            unsigned order[PATTERN_POINTS_MAX];
            uint8_t noise[PATTERN_POINTS_MAX];

            draw_bytes(noise, sizeof noise, salt);

            for (unsigned index = 0u; index < point_count; index++)
            {
                order[index] = index;
            }
            for (unsigned slot = point_count - 1u; slot > 0u; slot--)
            {
                const unsigned pick = (unsigned)noise[slot] % (slot + 1u);
                const unsigned held = order[slot];

                order[slot] = order[pick];
                order[pick] = held;
            }
            for (unsigned index = 0u; index < want; index++)
            {
                anchors[index] = order[index];
            }
            break;
        }
        case ANCHOR_LEADING:
        default:
        {
            for (unsigned index = 0u; index < want; index++)
            {
                anchors[index] = index;
            }
            break;
        }
    }
    return want;
}

/**
 * @brief Sweeps rules and anchor counts over one case, reporting refusals and candidates.
 *
 * @param[in] shape Which domain, geometry and comparison to sweep [BORROWS].
 * @note Two columns per row and they are graded differently. Refused is a correctness claim and has
 *       one acceptable value. Candidates is a cost measurement and is expected to move with the rule,
 *       the count and the geometry.
 */
static void report_lattice(const LatticeCase *shape)
{
    static const LatticeRule rules[] = {ANCHOR_LEADING, ANCHOR_SPREAD, ANCHOR_SHUFFLED};

    const size_t step = (shape->base_count > PATTERN_SAMPLES) ? (shape->base_count / PATTERN_SAMPLES) : 1u;

    for (size_t which = 0u; which < (sizeof rules / sizeof rules[0]); which++)
    {
        const LatticeRule rule = rules[which];

        for (unsigned count = 1u; (count <= LATTICE_MAX_ANCHORS) && (count <= shape->point_count); count++)
        {
            uint32_t checked = 0u;
            uint32_t refused = 0u;
            double candidates = 0.0;
            unsigned samples = 0u;

            for (size_t index = 0u; index < shape->base_count; index += step)
            {
                const size_t pattern_base = shape->bases[index];
                unsigned anchors[LATTICE_MAX_ANCHORS];
                uint32_t found = 0u;

                if (pick_lattice_anchors(rule, shape->point_count, count, anchors, (uint64_t)index) < count)
                {
                    continue;
                }

                refused += refused_lattice(shape->same, shape->domain, shape->bases, shape->base_count, pattern_base,
                                           shape->displacements, shape->point_count, anchors, count, &found);
                checked += found;
                candidates += (double)candidates_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                                         pattern_base, shape->displacements, anchors, count);
                samples++;
            }

            if (samples == 0u)
            {
                continue;
            }

            printf("ancorae_lattice,%s,%s,%u,%u,%u,%u,%u,%.2f,%s\n", shape->name, rule_name(rule),
                   shape->point_count, count, (unsigned)shape->base_count, samples, checked,
                   candidates / (double)samples,
                   (checked == 0u) ? "none" : ((refused == 0u) ? "hold" : "BROKEN"));
        }
    }
}

/**
 * @brief Bytes in the one dimensional domain.
 */
#define LINE_LENGTH 4096u

/**
 * @brief Side of the square grid, chosen so the grid holds as many positions as the line.
 */
#define GRID_SIDE 64u

/**
 * @brief Side of the cube, chosen for the same reason.
 */
#define CUBE_SIDE 16u

/**
 * @brief Symbols in the complex valued domain.
 */
#define FIELD_LENGTH 4096u

/**
 * @brief The window a scattered two dimensional pattern is drawn inside.
 */
#define SCATTER_SIDE 5u

static uint8_t s_line[LINE_LENGTH];
static uint8_t s_grid[GRID_SIDE * GRID_SIDE];
static uint8_t s_cube[CUBE_SIDE * CUBE_SIDE * CUBE_SIDE];

/**
 * @brief A domain whose symbols are complex numbers with irrational parts.
 *
 * @note Here to make one point concretely. Nothing below ever reads one of these values, compares
 *       their magnitudes, or orders them. The comparison is over their storage. A symbol that
 *       cannot be written down exactly, or interpreted at all, is handled the same as a byte.
 */
static double _Complex s_field[FIELD_LENGTH];

static size_t s_line_bases[LINE_LENGTH];

/**
 * @brief The same base positions in an order nothing chose.
 *
 * @note The core never sorts its bases and never compares two of them, so it cannot depend on their
 *       order. That is an argument about the code, and the point of this array is to put it in the
 *       rows instead. It holds exactly the positions the line holds, permuted, so it has to return
 *       the identical occurrence count and the identical verdict. A difference between the two rows
 *       would be an order dependence nobody intended.
 */
static size_t s_shuffled_bases[LINE_LENGTH];
static size_t s_grid_bases[GRID_SIDE * GRID_SIDE];
static size_t s_cube_bases[CUBE_SIDE * CUBE_SIDE * CUBE_SIDE];
static size_t s_field_bases[FIELD_LENGTH];

static ptrdiff_t s_line_points[PATTERN_POINTS_MAX];
static ptrdiff_t s_grid_box[PATTERN_POINTS];
static ptrdiff_t s_grid_scatter[PATTERN_POINTS];
static ptrdiff_t s_grid_turned[PATTERN_POINTS];
static ptrdiff_t s_cube_box[PATTERN_POINTS];

/**
 * @brief Writes copies of the pattern sitting at @p pattern_base into the domain at other bases.
 *
 * @param[in,out] domain        Byte storage to plant into [BORROWS].
 * @param[in]     bases         Every position a pattern could start at [BORROWS].
 * @param[in]     base_count    How many.
 * @param[in]     pattern_base  Where the pattern being copied sits.
 * @param[in]     displacements Offsets from a base to each of the pattern's points [BORROWS].
 * @param[in]     point_count   How many points the pattern has.
 * @param[in]     copies        How many copies to write.
 * @return                      How many were written.
 * @note Why this exists. A pattern of p points over an alphabet of L symbols occurs by chance about
 *       base_count / L^p times, which is already under one at eight points over sixteen symbols. The
 *       invariant sweep then reports that it had nothing to check, and a row that checked nothing is
 *       not evidence that anything held. A planted copy is a true occurrence by construction, so
 *       refusing one is the failure the proposition forbids.
 * @note Copies are spread across the base list instead of placed adjacently, since overlapping
 *       plants would overwrite each other and the last one written would be the only whole copy.
 *       Two plants can still overlap where the pattern is long, and that costs nothing: the check
 *       counts the occurrences it actually finds and never assumes the planted count.
 */
static unsigned plant(uint8_t *domain, const size_t *bases, size_t base_count, size_t pattern_base,
                      const ptrdiff_t *displacements, unsigned point_count, unsigned copies)
{
    unsigned written = 0u;

    if ((base_count == 0u) || (copies == 0u))
    {
        return 0u;
    }

    const size_t step = (base_count > copies) ? (base_count / copies) : 1u;

    for (size_t index = 0u; (index < base_count) && (written < copies); index += step)
    {
        const ptrdiff_t target = (ptrdiff_t)bases[index];

        if (bases[index] == pattern_base)
        {
            continue;
        }
        for (unsigned point = 0u; point < point_count; point++)
        {
            const ptrdiff_t reach = displacements[point];

            domain[(size_t)(target + reach)] = domain[(size_t)((ptrdiff_t)pattern_base + reach)];
        }
        written++;
    }
    return written;
}

/**
 * @brief Compares two positions of a byte domain.
 *
 * @param[in] domain Byte storage [BORROWS].
 * @param[in] left   One position.
 * @param[in] right  The other.
 * @return           EMBED_TRUE when the two bytes agree.
 */
static embed_bool same_byte(const void *domain, size_t left, size_t right)
{
    const uint8_t *const bytes = (const uint8_t *)domain;

    return (bytes[left] == bytes[right]) ? EMBED_TRUE : EMBED_FALSE;
}

/**
 * @brief Compares two positions of the complex valued domain.
 *
 * @param[in] domain Complex storage [BORROWS].
 * @param[in] left   One position.
 * @param[in] right  The other.
 * @return           EMBED_TRUE when the two symbols agree.
 * @note Compared over their storage and not with the equality operator. An irrational value has no
 *       exact decimal form and a reader has no way to say what it is, and neither fact matters: the
 *       question asked is whether two of them are the same symbol, which their bytes answer.
 */
static embed_bool same_field(const void *domain, size_t left, size_t right)
{
    const double _Complex *const values = (const double _Complex *)domain;

    return (memcmp(&values[left], &values[right], sizeof values[0]) == 0) ? EMBED_TRUE : EMBED_FALSE;
}

/**
 * @brief Reduces drawn bytes to the domain's alphabet and writes them into a byte domain.
 *
 * @param[out] into   Storage to fill [BORROWS].
 * @param[in]  length How many symbols.
 * @param[in]  salt   Which stream to draw from.
 */
static void fill_levels(uint8_t *into, size_t length, uint64_t salt, unsigned levels)
{
    draw_bytes(into, length, salt);

    // A byte carries 256 values, so an alphabet of 256 is the identity here and anything smaller is
    // a fold. The modulus is not quite uniform for a level count that does not divide 256, which
    // costs nothing: the claim under test is that no true occurrence is refused, and a true
    // occurrence is true whatever weight its symbols carry.
    if (levels < 256u)
    {
        for (size_t index = 0u; index < length; index++)
        {
            into[index] = (uint8_t)(into[index] % levels);
        }
    }
}

/**
 * @brief Fills the complex domain with symbols drawn from a small set of irrational values.
 *
 * @note The values are built from square roots of primes so no member of the set has an exact
 *       representation. Which one a position holds is drawn from the same generator everything else
 *       here uses, so the domain has the same statistics as the byte domains and differs only in what
 *       a symbol is made of.
 */
static void fill_field(void)
{
    double _Complex alphabet[SYMBOL_LEVELS];
    uint8_t picks[FIELD_LENGTH];

    for (unsigned level = 0u; level < SYMBOL_LEVELS; level++)
    {
        const double real = sqrt((double)(2u + (level * 3u)));
        const double imaginary = sqrt((double)(5u + (level * 7u)));

        alphabet[level] = real + (imaginary * I);
    }

    draw_bytes(picks, sizeof picks, 0x5EEDu);

    for (size_t index = 0u; index < FIELD_LENGTH; index++)
    {
        s_field[index] = alphabet[picks[index] % SYMBOL_LEVELS];
    }
}

/**
 * @brief Builds the one dimensional geometry: contiguous points, every start that fits.
 *
 * @return How many bases were written.
 */
static size_t build_line(unsigned points)
{
    size_t count = 0u;

    for (unsigned point = 0u; point < points; point++)
    {
        s_line_points[point] = (ptrdiff_t)point;
    }
    for (size_t start = 0u; (start + points) <= LINE_LENGTH; start++)
    {
        s_line_bases[count] = start;
        count++;
    }
    return count;
}

/**
 * @brief Copies the line's bases and permutes them, leaving the set identical and the order not.
 *
 * @param[in] count How many bases the line wrote.
 * @note A Fisher-Yates shuffle, so every base the line holds is still present exactly once. The row
 *       this produces has to match the line's row on occurrences and on verdict. Anything else is an
 *       order dependence in a core written to have none.
 */
static void build_shuffled(size_t count)
{
    uint64_t state = 0x9A17C0DEULL;

    for (size_t index = 0u; index < count; index++)
    {
        s_shuffled_bases[index] = s_line_bases[index];
    }
    for (size_t slot = count - 1u; slot > 0u; slot--)
    {
        const size_t pick = (size_t)(next_random(&state) % (uint64_t)(slot + 1u));
        const size_t kept = s_shuffled_bases[slot];

        s_shuffled_bases[slot] = s_shuffled_bases[pick];
        s_shuffled_bases[pick] = kept;
    }
}

/**
 * @brief Builds the complex domain's geometry, the line's geometry over other symbols.
 *
 * @return How many bases were written.
 * @note Deliberately identical in shape to the line. Holding the geometry fixed and changing only
 *       what a symbol is made of is what isolates the alphabet as the variable.
 */
static size_t build_field(void)
{
    size_t count = 0u;

    for (size_t start = 0u; (start + PATTERN_POINTS) <= FIELD_LENGTH; start++)
    {
        s_field_bases[count] = start;
        count++;
    }
    return count;
}

/**
 * @brief Builds the two dimensional geometries: a box, a scatter, and that scatter turned a quarter.
 *
 * @return How many bases were written, shared by all three.
 * @note The box is a 2 by 4 rectangle. The scatter is eight points placed inside a 5 by 5 window with
 *       no row or column filled, a case a rectangle cannot stand in for. The turned set is the
 *       scatter under (row, column) going to (column, 4 - row), so it is the same eight points
 *       rotated a quarter turn. A rotation permutes displacements and changes nothing more, and the
 *       three share one base list so the rows show it.
 */
static size_t build_grid(void)
{
    // Eight points inside a 5 by 5 window, listed as row then column. No row and no column holds more
    // than two of them, so nothing about the set can be read as a run
    static const unsigned scatter[PATTERN_POINTS][2] = {{0u, 0u}, {0u, 3u}, {1u, 1u}, {2u, 4u},
                                                        {3u, 0u}, {3u, 2u}, {4u, 1u}, {4u, 4u}};
    size_t count = 0u;

    for (unsigned point = 0u; point < PATTERN_POINTS; point++)
    {
        const unsigned row = point / 4u;
        const unsigned column = point % 4u;

        s_grid_box[point] = (ptrdiff_t)((row * GRID_SIDE) + column);
        s_grid_scatter[point] = (ptrdiff_t)((scatter[point][0] * GRID_SIDE) + scatter[point][1]);
        // A quarter turn inside the window: (row, column) goes to (column, side - 1 - row)
        s_grid_turned[point] =
            (ptrdiff_t)((scatter[point][1] * GRID_SIDE) + ((SCATTER_SIDE - 1u) - scatter[point][0]));
    }

    for (unsigned row = 0u; (row + SCATTER_SIDE) <= GRID_SIDE; row++)
    {
        for (unsigned column = 0u; (column + SCATTER_SIDE) <= GRID_SIDE; column++)
        {
            s_grid_bases[count] = (size_t)((row * GRID_SIDE) + column);
            count++;
        }
    }
    return count;
}

/**
 * @brief Builds the three dimensional geometry: a 2 by 2 by 2 block inside a cube.
 *
 * @return How many bases were written.
 */
static size_t build_cube(void)
{
    size_t count = 0u;

    for (unsigned point = 0u; point < PATTERN_POINTS; point++)
    {
        const unsigned plane = point / 4u;
        const unsigned row = (point / 2u) % 2u;
        const unsigned column = point % 2u;

        s_cube_box[point] = (ptrdiff_t)((plane * CUBE_SIDE * CUBE_SIDE) + (row * CUBE_SIDE) + column);
    }

    for (unsigned plane = 0u; (plane + 2u) <= CUBE_SIDE; plane++)
    {
        for (unsigned row = 0u; (row + 2u) <= CUBE_SIDE; row++)
        {
            for (unsigned column = 0u; (column + 2u) <= CUBE_SIDE; column++)
            {
                s_cube_bases[count] = (size_t)((plane * CUBE_SIDE * CUBE_SIDE) + (row * CUBE_SIDE) + column);
                count++;
            }
        }
    }
    return count;
}

/**
 * @brief The most dimensions the sweep reaches.
 */
#define MAX_DIMENSION 8u

/**
 * @brief The largest number of positions any swept domain holds.
 */
#define DOMAIN_MAX 65536u

static uint8_t s_hypercube[DOMAIN_MAX];
static size_t s_hypercube_bases[DOMAIN_MAX];
static ptrdiff_t s_hypercube_points[PATTERN_POINTS_MAX];

/**
 * @brief Builds a @p dimension dimensional domain and a pattern that genuinely spans it.
 *
 * @param[in]  dimension How many axes.
 * @param[in]  side      Positions along each axis.
 * @param[out] cells     Receives how many positions the domain holds [BORROWS].
 * @return               How many bases were written.
 * @note The pattern is a star. One point sits at the origin and each of the rest sits one step out
 *       along the next axis, going a further step out once the axes run out. On a line that is eight
 *       contiguous cells, on a plane a cross, and above that a figure touching a new axis for every
 *       point it has. Filling a corner of a hypercube instead would have placed all eight points
 *       inside three axes at every dimension above three, which would have measured a three
 *       dimensional pattern in a larger space and reported it as a higher dimensional result.
 * @note Seven points off the origin can touch at most seven axes, so at dimension eight the pattern
 *       spans seven of them. Every dimension up to seven is spanned completely.
 * @note Bases are every position where the whole pattern stays in bounds, the geometry the core
 *       reads. Nothing about the dimension reaches the core by any other route.
 */
static size_t build_hypercube(unsigned dimension, unsigned side, unsigned points, size_t *cells)
{
    // The span along one axis, which is how far the last point reaches once the axes have been
    // cycled through. A pattern of one point is the origin alone and spans a single cell, which the
    // general form would compute by subtracting two from one in unsigned arithmetic.
    const unsigned extent = (points <= 1u) ? 1u : (2u + ((points - 2u) / dimension));

    size_t stride[MAX_DIMENSION];
    size_t total = 1u;

    for (unsigned axis = 0u; axis < dimension; axis++)
    {
        stride[axis] = total;
        total *= side;
    }
    *cells = total;

    // A pattern wider than the domain has nowhere to sit, and the room calculation below would wrap
    // instead of reporting none
    if (side < extent)
    {
        return 0u;
    }

    s_hypercube_points[0] = 0;

    for (unsigned point = 1u; point < points; point++)
    {
        const unsigned axis = (point - 1u) % dimension;
        const unsigned step = 1u + ((point - 1u) / dimension);

        s_hypercube_points[point] = (ptrdiff_t)((size_t)step * stride[axis]);
    }

    // Every base whose pattern stays inside, walked as a mixed radix counter over the reduced side
    const unsigned room = (side - extent) + 1u;
    size_t written = 0u;
    size_t combinations = 1u;

    for (unsigned axis = 0u; axis < dimension; axis++)
    {
        combinations *= room;
    }

    for (size_t which = 0u; which < combinations; which++)
    {
        size_t offset = 0u;
        size_t remaining = which;

        for (unsigned axis = 0u; axis < dimension; axis++)
        {
            offset += (remaining % room) * stride[axis];
            remaining /= room;
        }
        s_hypercube_bases[written] = offset;
        written++;
    }
    return written;
}

/**
 * @brief Sweeps rules and anchor counts against one planted pattern, at one alphabet and size.
 *
 * @param[in] shape        Which domain, geometry and comparison to sweep [BORROWS].
 * @param[in] levels       How many distinct symbols the domain was built over.
 * @param[in] planted      How many copies of the pattern were planted.
 * @param[in] pattern_base Where the planted pattern sits.
 * @note One pattern and not a sample of them, because the sample has to be the pattern that was
 *       planted. Out at 32 points over 256 symbols nothing else in the domain occurs twice. A sweep
 *       over arbitrary bases would report that every row had nothing to check.
 */
static void report_swept(const LatticeCase *shape, unsigned levels, unsigned planted,
                         size_t pattern_base)
{
    static const LatticeRule rules[] = {ANCHOR_LEADING, ANCHOR_SPREAD, ANCHOR_SHUFFLED};

    for (size_t which = 0u; which < (sizeof rules / sizeof rules[0]); which++)
    {
        const LatticeRule rule = rules[which];

        for (unsigned count = 1u; count <= shape->point_count; count++)
        {
            unsigned anchors[LATTICE_MAX_ANCHORS];
            uint32_t found = 0u;

            if (pick_lattice_anchors(rule, shape->point_count, count, anchors, (uint64_t)count) <
                count)
            {
                continue;
            }

            const uint32_t refused =
                refused_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                pattern_base, shape->displacements, shape->point_count, anchors,
                                count, &found);
            const uint32_t surviving =
                candidates_lattice(shape->same, shape->domain, shape->bases, shape->base_count,
                                   pattern_base, shape->displacements, anchors, count);

            printf("ancorae_sweep,%s,%s,%u,%u,%u,%u,%u,%u,%u,%s\n", shape->name, rule_name(rule),
                   levels, shape->point_count, count, (unsigned)shape->base_count, found, planted,
                   surviving, (found == 0u) ? "none" : ((refused == 0u) ? "hold" : "BROKEN"));
        }
    }
}

int main(void)
{
    fill_levels(s_line, sizeof s_line, 0x11u, SYMBOL_LEVELS);
    fill_levels(s_grid, sizeof s_grid, 0x22u, SYMBOL_LEVELS);
    fill_levels(s_cube, sizeof s_cube, 0x33u, SYMBOL_LEVELS);
    fill_field();

    const size_t line_bases = build_line(PATTERN_POINTS);

    build_shuffled(line_bases);

    const size_t grid_bases = build_grid();
    const size_t cube_bases = build_cube();
    const size_t field_bases = build_field();

    const LatticeCase cases[] = {
        {"line1d", s_line, same_byte, s_line_bases, line_bases, s_line_points, PATTERN_POINTS},
        {"line1d_unordered", s_line, same_byte, s_shuffled_bases, line_bases, s_line_points,
         PATTERN_POINTS},
        {"grid2d_box", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_box, PATTERN_POINTS},
        {"grid2d_scatter", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_scatter, PATTERN_POINTS},
        {"grid2d_turned", s_grid, same_byte, s_grid_bases, grid_bases, s_grid_turned, PATTERN_POINTS},
        {"cube3d_box", s_cube, same_byte, s_cube_bases, cube_bases, s_cube_box, PATTERN_POINTS},
        {"field1d_complex", s_field, same_field, s_field_bases, field_bases, s_line_points, PATTERN_POINTS},
    };

    printf("bench,domain,rule,points,anchors,positions,samples,occurrences,candidates,verdict\n");

    for (size_t index = 0u; index < (sizeof cases / sizeof cases[0]); index++)
    {
        report_lattice(&cases[index]);
    }

    // Order independence, against a pattern held fixed. The two line rows above cannot show it: the
    // sampling walks the base list by index. A permuted list therefore draws a different set of
    // patterns, and its count is not comparable to the ordered one. What is comparable is the same
    // pattern scanned over both lists, which has to agree on every occurrence and every refusal.
    printf("bench,domain,points,disagreements,verdict\n");
    {
        unsigned anchors[LATTICE_MAX_ANCHORS];
        unsigned disagreed = 0u;

        for (unsigned count = 1u; count <= PATTERN_POINTS; count++)
        {
            if (pick_lattice_anchors(ANCHOR_SPREAD, PATTERN_POINTS, count, anchors, 0u) < count)
            {
                continue;
            }

            for (size_t sample = 0u; sample < PATTERN_SAMPLES; sample++)
            {
                const size_t pattern_base = s_line_bases[(sample * line_bases) / PATTERN_SAMPLES];
                uint32_t ordered_found = 0u;
                uint32_t shuffled_found = 0u;

                const uint32_t ordered_refused =
                    refused_lattice(same_byte, s_line, s_line_bases, line_bases, pattern_base,
                                    s_line_points, PATTERN_POINTS, anchors, count, &ordered_found);
                const uint32_t shuffled_refused =
                    refused_lattice(same_byte, s_line, s_shuffled_bases, line_bases, pattern_base,
                                    s_line_points, PATTERN_POINTS, anchors, count, &shuffled_found);

                if ((ordered_found != shuffled_found) || (ordered_refused != shuffled_refused))
                {
                    disagreed++;
                }
            }
        }
        printf("ancorae_order,line1d,%u,%u,%s\n", PATTERN_POINTS, disagreed,
               (disagreed == 0u) ? "hold" : "BROKEN");
    }

    // Sides chosen so each domain fits the buffer and still leaves enough bases for the invariant to
    // have work to do. They differ per dimension because a fixed side either overflows at eight
    // dimensions or leaves a handful of positions at six
    static const unsigned sides[MAX_DIMENSION + 1u] = {0u, 4096u, 64u, 20u, 10u, 6u, 5u, 4u, 3u};

    for (unsigned dimension = 1u; dimension <= MAX_DIMENSION; dimension++)
    {
        size_t cells = 0u;
        const size_t bases = build_hypercube(dimension, sides[dimension], PATTERN_POINTS, &cells);
        char label[16];

        if (bases == 0u)
        {
            continue;
        }
        fill_levels(s_hypercube, cells, 0x400u + dimension, SYMBOL_LEVELS);
        snprintf(label, sizeof label, "cube%ud", dimension);

        const LatticeCase shape = {label,           s_hypercube,         same_byte, s_hypercube_bases,
                                   bases,           s_hypercube_points,  PATTERN_POINTS};

        report_lattice(&shape);
    }

    // The alphabet and the point count come off here. Both were fixed at one value and neither is
    // part of the claim: the proposition names no alphabet and no pattern size. What breaks as they
    // grow is the check and not the claim, since a pattern of p points over L symbols occurs by
    // chance about base_count / L^p times, so the occurrences are planted.
    printf("bench,geometry,rule,levels,points,anchors,positions,occurrences,planted,candidates,"
           "verdict\n");

    for (size_t which_level = 0u;
         which_level < (sizeof ALPHABET_SIZES / sizeof ALPHABET_SIZES[0]); which_level++)
    {
        const unsigned levels = ALPHABET_SIZES[which_level];

        for (size_t which_points = 0u;
             which_points < (sizeof POINT_COUNTS / sizeof POINT_COUNTS[0]); which_points++)
        {
            const unsigned points = POINT_COUNTS[which_points];

            fill_levels(s_line, sizeof s_line, 0x11u, levels);

            const size_t swept_bases = build_line(points);
            const size_t seat = s_line_bases[0];
            const unsigned planted = plant(s_line, s_line_bases, swept_bases, seat, s_line_points,
                                           points, PLANTED_COPIES);
            const LatticeCase line = {"line1d", s_line,          same_byte, s_line_bases,
                                      swept_bases, s_line_points, points};

            report_swept(&line, levels, planted, seat);

            // The same two parameters over a geometry that is not a line. A reading here cannot be
            // a property of contiguity. Three dimensions is where a pattern of any size still fits.
            size_t cells = 0u;
            const size_t cube_swept = build_hypercube(3u, 20u, points, &cells);

            if (cube_swept == 0u)
            {
                continue;
            }
            fill_levels(s_hypercube, cells, 0x77u, levels);

            const size_t cube_seat = s_hypercube_bases[0];
            const unsigned cube_planted =
                plant(s_hypercube, s_hypercube_bases, cube_swept, cube_seat, s_hypercube_points,
                      points, PLANTED_COPIES);
            const LatticeCase cube = {"cube3d",   s_hypercube,        same_byte, s_hypercube_bases,
                                      cube_swept, s_hypercube_points, points};

            report_swept(&cube, levels, cube_planted, cube_seat);
        }
    }
    return 0;
}
