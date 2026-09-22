"""The numerics, written once, with the multiply handed in.

An ENGINE here is one function: `product(left, right)`, and the interface stops there. Everything in
this module - reciprocals, roots, division, modular exponentiation, Chudnovsky's series - is built
from multiplies and shifts. Naming the multiply therefore names the machine, and no second
declaration is needed anywhere.

WHY THE MULTIPLY IS PASSED IN INSTEAD OF BOUND GLOBALLY

This replaces two earlier arrangements, and both failed the same way.

The first was a module-level `product` rebound by a `use_device()` call. Any tool that called it
changed the arithmetic of every other tool in the process, from anywhere, at any time, and a run
could not be described without knowing the call order. That is a monkeypatch whatever it is named.

The second was two engines each carrying their own copy of the recurrences. That removes the
rebinding and buys a worse problem: two copies of a Newton iteration are one edit away from
disagreeing, and nothing reports it when they do - the results simply differ and both look fine.

Passing the multiply in has neither failure. There is one copy of each recurrence, the caller's
import line picks the machine, and the choice is visible at the call instead of hidden in the
history of the process.

    import digit_engine    then digit_engine.chudnovsky(n)    every multiply on the host
    import device_engine   then device_engine.chudnovsky(n)   every multiply on the card

Both bind this module. Neither can change the other's arithmetic, because there is no global here
to change.

NOTHING DIVIDES AT SIZE. Every division below is a Newton reciprocal whose base case runs sixty
four bits past the divisor's width, where a host does it in one machine instruction. Above that
base case there are only multiplies and shifts. That is the property making the engine
substitutable at all: a card that can multiply can run every line of this file.
"""

import math


# Chudnovsky's series, as the constants are usually written.
PER_TERM = 14.181647462725477    # decimal digits gained per term, log10(151931373056000^2 / 24^3)
BASE = 13591409
STEP = 545140134
CUBED = 10939058860032000        # 640320^3 / 24
SCALE = 426880                   # the factor outside, against the root of 10005


def reciprocal(product, value, bits):
    """floor(2^bits / value), using multiplies and shifts and no division at size.

    Newton on f(y) = 1/y - value/2^bits, whose root is the reciprocal wanted. The step is

        y' = 2y - value * y^2 / 2^bits

    which contains no division: two multiplies and a shift. Each step doubles the number of correct
    bits, so the precision is doubled on the way up and the work is dominated by the last step,
    making the whole thing a small multiple of ONE full size multiply.

    The recursion lifts the precision instead of iterating from one bit, so the base case is
    reached once. The final correction is exact by construction: the answer is stepped until it is
    the largest value whose product with the divisor does not exceed the numerator, so the return is
    the true floor and not a value within a tolerance of it.

    THE SQUARING GOES THROUGH THE ENGINE TOO. An earlier device copy of this wrote `lifted * lifted`
    here, which is a host multiply sitting in the middle of a routine advertised as device only, and
    at the sizes this is used at it was the largest multiply in the call.
    """
    if value <= 0:
        raise ValueError("reciprocal of a non-positive value")
    width = value.bit_length()
    if bits < width:
        return 0
    if bits <= width + 64:
        return (1 << bits) // value

    half = (bits + width) // 2
    lifted = reciprocal(product, value, half)
    out = (lifted << (bits - half + 1)) - (product(value, product(lifted, lifted)) >> (2 * half - bits))

    # Newton lands within a couple of units here, so this settles it by stepping, not searching.
    top = 1 << bits
    while product(out, value) > top:
        out -= 1
    while product(out + 1, value) <= top:
        out += 1
    return out


def divide(product, top, bottom, places):
    """floor(top * 10^places / bottom), by reciprocal, so no division happens at size.

    The scale is applied to the numerator before the reciprocal is folded in, which keeps every
    intermediate an exact integer and leaves one shift at the end.
    """
    if bottom <= 0:
        raise ValueError("this divide is for a positive divisor")
    if top < 0:
        # Floor division rounds toward negative infinity, so the sign is carried by negating the
        # answer to the exact division and stepping down when anything was left over.
        out = divide(product, -top, bottom, places)
        return -out if product(out, bottom) == -top * 10 ** places else -out - 1

    lifted = top * 10 ** places
    bits = bottom.bit_length() + lifted.bit_length() + 8
    out = product(lifted, reciprocal(product, bottom, bits)) >> bits
    while product(out, bottom) > lifted:
        out -= 1
    while product(out + 1, bottom) <= lifted:
        out += 1
    return out


def divide_binary(product, top, bottom, bits):
    """floor(top * 2^bits / bottom). The same routine in the base the fixed point is held in.

    Kept beside the decimal one instead of folded into it because the two are used in different
    places and a single function taking a base would put a branch in front of every call for no
    gain. Each name carries its base, so neither call site has to be read twice.
    """
    if bottom <= 0:
        raise ValueError("this divide is for a positive divisor")
    if top < 0:
        out = divide_binary(product, -top, bottom, bits)
        return -out if product(out, bottom) == -top << bits else -out - 1

    lifted = top << bits
    wide = bottom.bit_length() + lifted.bit_length() + 8
    out = product(lifted, reciprocal(product, bottom, wide)) >> wide
    while product(out, bottom) > lifted:
        out -= 1
    while product(out + 1, bottom) <= lifted:
        out += 1
    return out


def inverse_root(product, value, bits):
    """floor(2^bits / sqrt(value)), by Newton, with no division and no square root under it.

    The step is y' = y * (3 * 2^(2b) - value * y^2) / 2^(2b+1), where the halving is a shift. This
    is the iteration that converges to one over the root, and it is used instead of the iteration
    for the root itself because that one contains a division and this one does not.
    """
    if value <= 0:
        raise ValueError("no inverse root of a non-positive value is wanted here")

    # THE BASE CASE HAS TO KNOW HOW BIG THE VALUE IS. Dividing 2^bits by the root directly returns
    # zero for any value whose root exceeds it, and a zero start leaves the settling loop to climb
    # to the answer one unit at a time, which does not finish. Squaring the scale first and taking
    # one root of the quotient is the same quantity with nothing to underflow: 2^b / sqrt(v) is
    # sqrt(2^(2b) / v).
    if bits <= max(64, value.bit_length() // 2 + 32):
        return math.isqrt((1 << (2 * bits)) // value)

    # HALVE THE SIGNIFICANT BITS, NOT THE SCALE. The answer carries `bits - width/2` significant
    # bits, being the remainder of the scale once the root's own size is taken out. Halving
    # `bits` alone would halve the scale and leave the significant count almost untouched for a
    # large value, so the step below it would arrive with too little precision to double.
    half = (bits + value.bit_length() // 2) // 2 + 16
    lifted = inverse_root(product, value, half)
    shifted = lifted << (bits - half)

    squared = product(shifted, shifted)
    inner = (3 << (2 * bits)) - product(value, squared)
    out = product(shifted, inner) >> (2 * bits + 1)

    # Settle it against the definition, which costs two multiplies and removes any doubt.
    while product(product(out, out), value) > (1 << (2 * bits)):
        out -= 1
    while product(product(out + 1, out + 1), value) <= (1 << (2 * bits)):
        out += 1
    return out


def root_scaled(product, value, places):
    """floor(sqrt(value) * 10^places) with no division at size, from the inverse root.

    sqrt(v) = v / sqrt(v), so multiplying the value by its own inverse root gives the root, and the
    only operations used are the ones the card already does.
    """
    # THE RECIPROCAL ROOT MUST COVER THE VALUE, NOT HALF OF IT. `back` is 2^bits / sqrt(value),
    # which carries bits - bit_length(value)/2 significant bits, and the answer needs
    # bit_length(value)/2 + 4*places of them. Sized at half the bit length, `back` came out with
    # about sixty four good bits and the settling loop had to climb the rest one unit at a time,
    # which does not finish.
    bits = value.bit_length() + 4 * places + 64
    back = inverse_root(product, value, bits)

    # THE SCALE IS FORMED ONCE AND SQUARED. Asking for ten to twice the places builds a number of
    # twice the width from nothing when the narrower one is already in hand and one multiply
    # separates them.
    scale = 10 ** places
    out = product(value * scale, back) >> bits
    target = product(value, product(scale, scale))
    while product(out, out) > target:
        out -= 1
    while product(out + 1, out + 1) <= target:
        out += 1
    return out


def reduce_by(product, value, modulus, folded=None):
    """`value` modulo `modulus`, using the reciprocal so no division happens at size.

    `folded` lets a caller hand in the reciprocal it already has, saving a full Newton lift every
    time the same modulus comes back - thousands of times in one exponentiation.
    """
    if value < modulus:
        return value
    # THE RECIPROCAL HAS TO COVER THE VALUE, NOT JUST THE MODULUS. If `bits` is only wide enough for
    # the modulus then the truncation in `folded` scales with `value` and the quotient comes out low
    # by an amount that grows with it, leaving the correction loop to subtract the modulus that many
    # times. Sizing `bits` to the value keeps the quotient within one of the truth.
    bits = value.bit_length() + modulus.bit_length() + 8
    if folded is None or folded[1] < bits:
        folded = (reciprocal(product, modulus, bits), bits)
    guess = product(value, folded[0]) >> folded[1]
    rest = value - product(guess, modulus)
    while rest < 0:
        rest += modulus
    while rest >= modulus:
        rest -= modulus
    return rest


def power_mod(product, base, power, modulus):
    """`base` to `power` modulo `modulus`, with the reciprocal formed once for the whole climb.

    Square and multiply, which is log(power) squarings, each one a multiply the engine carries. The
    reciprocal of the modulus is computed once and reused at every step, since it does not change
    and forming it per step would cost more than the squaring it serves.
    """
    if modulus <= 1:
        return 0
    # Every reduction inside the climb is of a product of two values below the modulus, so the
    # widest value handed to `reduce_by` is just under the modulus squared. Sizing the reciprocal to
    # that once means no reduction below has to rebuild it.
    bits = 2 * modulus.bit_length() + 8
    folded = (reciprocal(product, modulus, bits), bits)

    out = 1
    walk = reduce_by(product, base, modulus, folded)
    while power > 0:
        if power & 1:
            out = reduce_by(product, product(out, walk), modulus, folded)
        power >>= 1
        if power:
            walk = reduce_by(product, product(walk, walk), modulus, folded)
    return out


def terms_for(digits):
    """How many terms of the series `digits` places needs, from the series' own rate."""
    return max(int(digits / PER_TERM) + 2, 2)


def split(product, first, last):
    """Chudnovsky's series over the terms in [first, last), as the triple binary splitting carries.

    P, Q and T are exact integers: the numerator product, the denominator product, and the partial
    sum already scaled by that denominator. The merge is one line and it is the whole method.

    NOTHING IS DIVIDED HERE. That absence is the method. The linear sum divides at every term at
    full working precision and the squaring is where it loses; this defers the single division to
    the very end, and every intermediate stays an exact integer that no rounding has touched.

    Recursion depth is the log of the term count, and a billion digits is a depth of some twenty six
    and there is no stack concern at any size a desktop can reach.
    """
    if last - first == 1:
        if first == 0:
            return 1, 1, BASE
        upper = (6 * first - 5) * (2 * first - 1) * (6 * first - 1)
        lower = first ** 3 * CUBED
        total = upper * (BASE + STEP * first)
        return upper, lower, -total if first % 2 else total

    middle = (first + last) // 2
    left_upper, left_lower, left_total = split(product, first, middle)
    right_upper, right_lower, right_total = split(product, middle, last)
    return (product(left_upper, right_upper),
            product(left_lower, right_lower),
            product(left_total, right_lower) + product(left_upper, right_total))


def chudnovsky(product, digits, guard=24):
    """Pi to `digits` places, as an integer holding them.

    One division and one square root, both at the end, both at the full working precision. The guard
    digits cover exactly those two roundings instead of an accumulation, because there is no
    accumulation: everything before them is exact.
    """
    work = digits + guard
    upper, lower, total = split(product, 0, terms_for(work))
    root = root_scaled(product, 10005, work)
    return divide(product, product(SCALE * root, lower), total, 0) // 10 ** guard
