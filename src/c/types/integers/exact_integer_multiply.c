
// exact_integer_multiply.c: the Fermat transform and exact multiplication
#include "exact_integer_internal.h"

static int fermat_multiply(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs);

// the cyclic transform of count = 2^depth ring elements in place, root 2^root_bits: bit-reversed order, then
// butterflies (u, v) -> (u + w v, u - w v) with w a power of the root, every product by w a shift
static void fermat_fourier(uint32_t *elements, size_t count, unsigned int depth, size_t limbs, size_t root_bits,
                           uint32_t *scratch, uint32_t *turned)
{
    const size_t width = limbs + 1u;
    const size_t cycle = 2u * limbs * LIMB_BITS;
    for (size_t at = 0u; at < count; at++)
    {
        size_t reversed = 0u;
        for (unsigned int bit = 0u; bit < depth; bit++)
        {
            reversed |= ((at >> bit) & 1u) << (depth - 1u - bit);
        }
        if (reversed > at)
        {
            memcpy(turned, &elements[at * width], width * sizeof(uint32_t));
            memcpy(&elements[at * width], &elements[reversed * width], width * sizeof(uint32_t));
            memcpy(&elements[reversed * width], turned, width * sizeof(uint32_t));
        }
    }
    for (size_t span = 2u; span <= count; span <<= 1u)
    {
        const size_t half = span / 2u;
        const size_t stage_bits = (root_bits * (count / span)) % cycle;
        for (size_t start = 0u; start < count; start += span)
        {
            for (size_t step = 0u; step < half; step++)
            {
                uint32_t *const upper = &elements[(start + step) * width];
                uint32_t *const lower = &elements[(start + step + half) * width];
                fermat_shift(turned, lower, (step * stage_bits) % cycle, limbs, scratch);
                fermat_subtract(lower, upper, turned, limbs);
                fermat_add(upper, upper, turned, limbs);
            }
        }
    }
}

// the inner ring for pieces of piece_bits in 2^depth parts: at least 2 piece_bits + depth + 2 bits. A signed
// coefficient of the negacyclic product fits, and a multiple of the part count and of a limb; a ring past the base
// case also leaves room to split in turn
static size_t fermat_inner_bits(size_t piece_bits, unsigned int depth)
{
    const size_t least = (2u * piece_bits) + depth + 2u;
    const size_t parts = (size_t)1u << depth;
    const size_t tight_step = (parts > (size_t)LIMB_BITS) ? parts : (size_t)LIMB_BITS;
    const size_t tight = ((least + tight_step - 1u) / tight_step) * tight_step;
    if ((tight / LIMB_BITS) <= (size_t)TRANSFORM_BASE_LIMBS)
    {
        return tight;
    }
    size_t step = (size_t)LIMB_BITS << ((bits_ceiling_log(least) + 1u) / 2u);
    step = (step < parts) ? parts : step;
    return ((least + step - 1u) / step) * step;
}

// the modeled word operations of a product on the ladder below the transform: long multiplication's square, and
// Karatsuba's three half products and linear passes
static unsigned long long fermat_ladder_cost(size_t limbs)
{
    if (limbs < (size_t)ANCHOR_EXACT_KARATSUBA_LIMBS)
    {
        return (unsigned long long)limbs * limbs;
    }
    return (3ull * fermat_ladder_cost((limbs + 1u) / 2u)) + (8ull * limbs);
}

static unsigned long long fermat_cost(size_t limbs, unsigned int *depth);

// the modeled word operations of the transform at a depth: three transforms of 2^depth depth / 2 butterflies over
// the inner ring's words, a few passes each, and the pointwise products at their own best; a split whose inner ring
// is no smaller than the ring is never taken
static unsigned long long fermat_cost_at(size_t limbs, unsigned int depth)
{
    const size_t parts = (size_t)1u << depth;
    const size_t inner = fermat_inner_bits((limbs / parts) * LIMB_BITS, depth) / LIMB_BITS;
    if (inner >= limbs)
    {
        return ~0ull;
    }
    unsigned int inner_depth = 0u;
    const unsigned long long point = fermat_cost(inner, &inner_depth);
    return (6ull * parts * depth * (inner + 1u)) + (4ull * parts * (inner + 1u)) + (parts * point);
}

// the cheapest way to multiply in the ring of the given limbs: the depth of the transform, or 0 for the ladder
// below; depths are tried near the balanced split of sqrt(n) pieces, where the inner ring is near sqrt(n) bits, and
// the model's own recursion is therefore a few levels deep
static unsigned long long fermat_cost(size_t limbs, unsigned int *depth)
{
    unsigned long long best = fermat_ladder_cost(limbs) + (2ull * limbs);
    *depth = 0u;
    if (limbs <= (size_t)TRANSFORM_BASE_LIMBS)
    {
        return best;
    }
    const unsigned int balanced = (bits_ceiling_log(limbs * LIMB_BITS) + 1u) / 2u;
    const unsigned int lowest = (balanced > 4u) ? (balanced - 2u) : 2u;
    for (unsigned int trial = lowest; (trial <= (balanced + 1u)) && (((limbs >> trial) << trial) == limbs); trial++)
    {
        const unsigned long long cost = fermat_cost_at(limbs, trial);
        if (cost < best)
        {
            best = cost;
            *depth = trial;
        }
    }
    return best;
}

// the number of pieces a ring of the given limbs splits into, 2^depth pieces of whole limbs, chosen by the cost
// model; 0 is the ladder below the transform
static unsigned int fermat_depth(size_t limbs)
{
    unsigned int depth = 0u;
    (void)fermat_cost(limbs, &depth);
    return depth;
}

// Schonhage-Strassen modulo 2^n + 1: the value is cut into 2^depth pieces; the pieces are weighted by powers of
// psi = 2^(n' / 2^depth), whose 2^depth-th power is -1 in the inner ring 2^n' + 1, which turns the cyclic transform
// into the negacyclic product the outer ring needs; the transforms multiply point by point, recursively, and the
// inverse transform, the division by 2^depth and the unweighting are shifts
static int fermat_transform(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs,
                            unsigned int depth)
{
    const size_t count = (size_t)1u << depth;
    const size_t piece = limbs / count;
    const size_t inner_bits = fermat_inner_bits(piece * LIMB_BITS, depth);
    const size_t inner = inner_bits / LIMB_BITS;
    const size_t width = inner + 1u;
    const size_t cycle = 2u * inner_bits;
    const size_t total = limbs + width + 1u;
    uint32_t *const workspace =
        (uint32_t *)calloc((2u * count * width) + (4u * width) + (2u * total) + 2u, sizeof(uint32_t));
    if (workspace == NULL)
    {
        return 0;
    }
    uint32_t *const first = workspace;
    uint32_t *const second = &workspace[count * width];
    uint32_t *const scratch = &workspace[2u * count * width];
    uint32_t *const turned = &scratch[(2u * inner) + 2u];
    uint32_t *const product = &turned[width];
    uint32_t *const positive = &product[width];
    uint32_t *const negative = &positive[total];
    for (size_t at = 0u; at < count; at++)
    {
        memcpy(&first[at * width], &left[at * piece], piece * sizeof(uint32_t));
        memcpy(&second[at * width], &right[at * piece], piece * sizeof(uint32_t));
        fermat_shift(&first[at * width], &first[at * width], at * (inner_bits / count), inner, scratch);
        fermat_shift(&second[at * width], &second[at * width], at * (inner_bits / count), inner, scratch);
    }
    fermat_fourier(first, count, depth, inner, (2u * inner_bits) / count, scratch, turned);
    fermat_fourier(second, count, depth, inner, (2u * inner_bits) / count, scratch, turned);
    for (size_t at = 0u; at < count; at++)
    {
        if (fermat_multiply(product, &first[at * width], &second[at * width], inner) == 0)
        {
            free(workspace);
            return 0;
        }
        memcpy(&first[at * width], product, width * sizeof(uint32_t));
    }
    fermat_fourier(first, count, depth, inner, cycle - ((2u * inner_bits) / count), scratch, turned);
    for (size_t at = 0u; at < count; at++)
    {
        uint32_t *const coefficient = &first[at * width];
        // divide by 2^depth and unweight by psi^-at in one shift
        const size_t back = ((2u * cycle) - depth - (at * (inner_bits / count))) % cycle;
        fermat_shift(coefficient, coefficient, back, inner, scratch);
        // above half the ring is a negative coefficient
        const int below_zero = (coefficient[inner] != 0u) || ((coefficient[inner - 1u] >> (LIMB_BITS - 1u)) != 0u);
        if (below_zero)
        {
            fermat_negate(coefficient, inner);
        }
        (void)limbs_accumulate(&(below_zero ? negative : positive)[at * piece], total - (at * piece), coefficient,
                               width);
    }
    // each sum folds into the ring, n bits at a time with alternating signs, 2^n being -1
    uint32_t *const folded = product;
    memset(result, 0, (limbs + 1u) * sizeof(uint32_t));
    uint32_t *const chunk = (uint32_t *)calloc(limbs + 1u, sizeof(uint32_t));
    if (chunk == NULL)
    {
        free(workspace);
        return 0;
    }
    for (unsigned int sign = 0u; sign < 2u; sign++)
    {
        const uint32_t *const sum = (sign == 0u) ? positive : negative;
        uint32_t *const into = (uint32_t *)calloc(limbs + 1u, sizeof(uint32_t));
        if (into == NULL)
        {
            free(chunk);
            free(workspace);
            return 0;
        }
        for (size_t start = 0u, index = 0u; start < total; start += limbs, index++)
        {
            const size_t taken = ((total - start) < limbs) ? (total - start) : limbs;
            memset(chunk, 0, (limbs + 1u) * sizeof(uint32_t));
            memcpy(chunk, &sum[start], taken * sizeof(uint32_t));
            if ((index & 1u) == 0u)
            {
                fermat_add(into, into, chunk, limbs);
            }
            else
            {
                fermat_subtract(into, into, chunk, limbs);
            }
        }
        if (sign == 0u)
        {
            memcpy(result, into, (limbs + 1u) * sizeof(uint32_t));
        }
        else
        {
            fermat_subtract(result, result, into, limbs);
        }
        free(into);
    }
    (void)folded;
    free(chunk);
    free(workspace);
    return 1;
}

// result = left . right modulo 2^n + 1; result is distinct from both
static int fermat_multiply(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    if ((left[limbs] != 0u) || (right[limbs] != 0u))
    {
        // 2^n is -1
        memcpy(result, (left[limbs] != 0u) ? right : left, (limbs + 1u) * sizeof(uint32_t));
        if ((left[limbs] != 0u) && (right[limbs] != 0u))
        {
            memset(result, 0, (limbs + 1u) * sizeof(uint32_t));
            result[0] = 1u;
            return 1;
        }
        fermat_negate(result, limbs);
        return 1;
    }
    const unsigned int depth = fermat_depth(limbs);
    if (depth < 2u)
    {
        uint32_t *const product = (uint32_t *)calloc((2u * limbs) + 1u, sizeof(uint32_t));
        if ((product == NULL) || (limbs_product(product, left, limbs, right, limbs) == 0))
        {
            free(product);
            return 0;
        }
        memcpy(result, product, limbs * sizeof(uint32_t));
        result[limbs] = 0u;
        fermat_subtract(result, result, &product[limbs], limbs);
        free(product);
        return 1;
    }
    return fermat_transform(result, left, right, limbs, depth);
}

// the product of used limbs by the transform, into wide (left_used + right_used limbs); 0 when workspace cannot be held
int transform_product(uint32_t *wide, const uint32_t *left, size_t left_used, const uint32_t *right, size_t right_used)
{
    const size_t bits = (left_used + right_used) * LIMB_BITS;
    const size_t step = (size_t)LIMB_BITS << ((bits_ceiling_log(bits) + 1u) / 2u);
    const size_t limbs = (((bits + step - 1u) / step) * step) / LIMB_BITS;
    uint32_t *const workspace = (uint32_t *)calloc(3u * (limbs + 1u), sizeof(uint32_t));
    if (workspace == NULL)
    {
        return 0;
    }
    uint32_t *const first = workspace;
    uint32_t *const second = &workspace[limbs + 1u];
    uint32_t *const product = &workspace[2u * (limbs + 1u)];
    memcpy(first, left, left_used * sizeof(uint32_t));
    memcpy(second, right, right_used * sizeof(uint32_t));
    // the product is below 2^bits <= 2^n. The ring leaves it whole
    const int product_ok = fermat_multiply(product, first, second, limbs);
    if (product_ok != 0)
    {
        memcpy(wide, product, (left_used + right_used) * sizeof(uint32_t));
    }
    free(workspace);
    return product_ok;
}

// the product by the rung of the ladder the operands reach, or by the transform alone when it is asked for; a rung
// that cannot hold its workspace steps down to the one below, and long multiplication needs none
static AnchorExactStatus exact_multiply_by(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                           AnchorExactInteger *result, int transform_only)
{
    if ((left->sign == 0) || (right->sign == 0))
    {
        anchor_exact_zero(result);
        return ANCHOR_EXACT_OK;
    }

    // A factor using n limbs is at least 2^(32 * (n - 1)). The product of factors using n and m limbs
    // is at least 2^(32 * (n + m - 2)). Where n + m passes the width by more than one limb, that
    // product already overruns and nothing is multiplied.
    const size_t left_used = magnitude_used(left->limb);
    const size_t right_used = magnitude_used(right->limb);
    const size_t range = left_used + right_used;
    if (range > (EXACT_LIMBS + 1u))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    // The product is below 2^(32 * range) and occupies at most `range` limbs, at most one past the
    // width. An overrun shows in that extra limb, and the accumulator keeps it instead of wrapping
    // it away.
    EXACT_SCRATCH(wide, EXACT_LIMBS + 1u);
    if (!EXACT_SCRATCH_VALID(wide))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    const size_t shorter = (left_used < right_used) ? left_used : right_used;
    int ok = 0;
    if ((transform_only != 0) || (shorter >= (size_t)ANCHOR_EXACT_TRANSFORM_LIMBS))
    {
        ok = transform_product(wide, left->limb, left_used, right->limb, right_used);
    }
    if ((ok == 0) && (transform_only == 0))
    {
        ok = limbs_product(wide, left->limb, left_used, right->limb, right_used);
        if (ok == 0)
        {
            limbs_long_product(wide, left->limb, left_used, right->limb, right_used);
            ok = 1;
        }
    }
    AnchorExactStatus status = ANCHOR_EXACT_OK;
    if ((ok == 0) || ((range > EXACT_LIMBS) && (wide[EXACT_LIMBS] != 0u)))
    {
        status = ANCHOR_EXACT_WILL_NOT_FIT;
    }
    else
    {
        // Written only now, and the sign taken first, since `result` may be either factor.
        const int32_t sign = (left->sign == right->sign) ? 1 : -1;
        const size_t kept = (range < EXACT_LIMBS) ? range : EXACT_LIMBS;
        memcpy(result->limb, wide, kept * sizeof(uint32_t));
        memset(&result->limb[kept], 0, (EXACT_LIMBS - kept) * sizeof(uint32_t));
        settle_sign(result, sign);
    }
    EXACT_SCRATCH_RELEASE(wide);
    return status;
}

AnchorExactStatus anchor_exact_multiply_transform(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                                  AnchorExactInteger *result)
{
    return exact_multiply_by(left, right, result, 1);
}

AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    return exact_multiply_by(left, right, result, 0);
}
