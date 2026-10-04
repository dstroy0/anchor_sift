// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// atom_form.cu: forms in atoms (atom_form.h)
#include "atom_form.h"

#include "report.h"

#include <algorithm>

bool AtomKeyOrder::operator()(const AtomKey &left, const AtomKey &right) const
{
    const int lean = sim_rational_sign(sim_rational_difference(left.e, right.e));
    if (lean != 0)
    {
        return lean < 0;
    }
    return left.power < right.power;
}

// the slots of the program: the key at each, the slot of each key, and the slot of each product of two
static std::vector<AtomKey> s_atom_slots;
static std::map<AtomKey, unsigned int, AtomKeyOrder> s_atom_slot_of;
static std::map<std::pair<unsigned int, unsigned int>, unsigned int> s_atom_slot_product;

AnchorExactInteger atom_form_unit(void)
{
    AnchorExactInteger one;
    sim_exact_unsigned(&one, 1ull);
    return one;
}

static AnchorExactInteger atom_form_nothing(void)
{
    AnchorExactInteger zero;
    sim_exact_unsigned(&zero, 0ull);
    return zero;
}

static void atom_form_check(int ok)
{
    if (!ok)
    {
        s_sim_rational_wide = 1;
    }
}

// the power with trailing zeros dropped
static AtomPower atom_form_trimmed(AtomPower power)
{
    while (!power.empty() && (power.back() == 0u))
    {
        power.pop_back();
    }
    return power;
}

static AtomKey atom_form_key(SimRational e, const AtomPower &power)
{
    AtomKey key;
    key.e = e;
    key.power = atom_form_trimmed(power);
    return key;
}

static unsigned int atom_form_slot(const AtomKey &key)
{
    const auto found = s_atom_slot_of.find(key);
    if (found != s_atom_slot_of.end())
    {
        return found->second;
    }
    const unsigned int slot = (unsigned int)s_atom_slots.size();
    s_atom_slots.push_back(key);
    s_atom_slot_of.insert(std::make_pair(key, slot));
    return slot;
}

static unsigned int atom_form_slot_product(unsigned int left, unsigned int right)
{
    const std::pair<unsigned int, unsigned int> pair = (left < right) ? std::make_pair(left, right)
                                                                      : std::make_pair(right, left);
    const auto found = s_atom_slot_product.find(pair);
    if (found != s_atom_slot_product.end())
    {
        return found->second;
    }
    const AtomPower &left_power = s_atom_slots[left].power;
    const AtomPower &right_power = s_atom_slots[right].power;
    const size_t size = (left_power.size() > right_power.size()) ? left_power.size() : right_power.size();
    AtomPower power(size, 0u);
    for (size_t index = 0u; index < size; index += 1u)
    {
        power[index] = ((index < left_power.size()) ? left_power[index] : 0u) +
                       ((index < right_power.size()) ? right_power[index] : 0u);
    }
    const unsigned int slot =
        atom_form_slot(atom_form_key(sim_rational_sum(s_atom_slots[left].e, s_atom_slots[right].e), power));
    s_atom_slot_product.insert(std::make_pair(pair, slot));
    return slot;
}

// the entry at `slot`, the array grown to hold it
static AnchorExactInteger *atom_form_entry(AtomForm *form, unsigned int slot)
{
    if (form->magnitude.size() <= slot)
    {
        form->magnitude.resize((size_t)slot + 1u, atom_form_nothing());
    }
    return &form->magnitude[slot];
}

// trailing zeros dropped, and the entries and the denominator divided by the factor they share
static void atom_form_settle(AtomForm *form)
{
    while (!form->magnitude.empty() && (form->magnitude.back().sign == 0))
    {
        form->magnitude.pop_back();
    }
    const AnchorExactInteger one = atom_form_unit();
    if (form->magnitude.empty())
    {
        form->denominator = one;
        return;
    }
    AnchorExactInteger common = form->denominator;
    for (const AnchorExactInteger &entry : form->magnitude)
    {
        if (entry.sign == 0)
        {
            continue;
        }
        atom_form_check(anchor_exact_gcd(&common, &entry, &common) == ANCHOR_EXACT_OK);
        if (anchor_exact_compare(&common, &one) == 0)
        {
            return;
        }
    }
    for (AnchorExactInteger &entry : form->magnitude)
    {
        if (entry.sign != 0)
        {
            AnchorExactInteger quotient;
            atom_form_check(anchor_exact_divide_exact(&entry, &common, &quotient) == ANCHOR_EXACT_OK);
            entry = quotient;
        }
    }
    AnchorExactInteger quotient;
    atom_form_check(anchor_exact_divide_exact(&form->denominator, &common, &quotient) == ANCHOR_EXACT_OK);
    form->denominator = quotient;
}

// the term coefficient times the key
static AtomForm atom_form_term(const AtomKey &key, SimRational coefficient)
{
    AtomForm form;
    if (sim_rational_sign(coefficient) == 0)
    {
        return form;
    }
    *atom_form_entry(&form, atom_form_slot(key)) = coefficient.numerator;
    form.denominator = coefficient.denominator;
    return form;
}

// the coefficient at `slot` as a rational in lowest terms
static SimRational atom_form_coefficient(const AtomForm &form, size_t slot)
{
    SimRational value;
    value.numerator = form.magnitude[slot];
    value.denominator = form.denominator;
    sim_rational_settle(&value);
    return value;
}

// the slots holding a term, in key order
static std::vector<unsigned int> atom_form_held(const AtomForm &form)
{
    std::vector<unsigned int> held;
    for (size_t slot = 0u; slot < form.magnitude.size(); slot += 1u)
    {
        if (form.magnitude[slot].sign != 0)
        {
            held.push_back((unsigned int)slot);
        }
    }
    const AtomKeyOrder order;
    std::sort(held.begin(), held.end(),
              [&order](unsigned int left, unsigned int right) { return order(s_atom_slots[left], s_atom_slots[right]); });
    return held;
}

AtomForm atom_form_rational(SimRational value)
{
    return atom_form_term(atom_form_key(sim_rational(0ll, 1ll), AtomPower()), value);
}

AtomForm atom_form_atom(unsigned int atom)
{
    AtomPower power(atom + 1u, 0u);
    power[atom] = 1u;
    return atom_form_term(atom_form_key(sim_rational(0ll, 1ll), power), sim_rational(1ll, 1ll));
}

AtomForm atom_form_e(SimRational power)
{
    return atom_form_term(atom_form_key(power, AtomPower()), sim_rational(1ll, 1ll));
}

AtomForm atom_form_sum(const AtomForm &left, const AtomForm &right)
{
    if (left.magnitude.empty())
    {
        return right;
    }
    if (right.magnitude.empty())
    {
        return left;
    }
    AtomForm sum;
    AnchorExactInteger left_factor = atom_form_unit();
    AnchorExactInteger right_factor = atom_form_unit();
    if (anchor_exact_compare(&left.denominator, &right.denominator) == 0)
    {
        sum.denominator = left.denominator;
    }
    else
    {
        // the least common denominator, each side lifted to it
        AnchorExactInteger common;
        atom_form_check(anchor_exact_gcd(&left.denominator, &right.denominator, &common) == ANCHOR_EXACT_OK);
        atom_form_check(anchor_exact_divide_exact(&right.denominator, &common, &left_factor) == ANCHOR_EXACT_OK);
        atom_form_check(anchor_exact_divide_exact(&left.denominator, &common, &right_factor) == ANCHOR_EXACT_OK);
        atom_form_check(sim_exact_product(&left.denominator, &left_factor, &sum.denominator));
    }
    const size_t size = (left.magnitude.size() > right.magnitude.size()) ? left.magnitude.size() : right.magnitude.size();
    sum.magnitude.assign(size, atom_form_nothing());
    for (size_t slot = 0u; slot < size; slot += 1u)
    {
        AnchorExactInteger first = atom_form_nothing();
        AnchorExactInteger second = atom_form_nothing();
        if ((slot < left.magnitude.size()) && (left.magnitude[slot].sign != 0))
        {
            atom_form_check(sim_exact_product(&left.magnitude[slot], &left_factor, &first));
        }
        if ((slot < right.magnitude.size()) && (right.magnitude[slot].sign != 0))
        {
            atom_form_check(sim_exact_product(&right.magnitude[slot], &right_factor, &second));
        }
        atom_form_check(sim_exact_sum(&first, &second, &sum.magnitude[slot]));
    }
    atom_form_settle(&sum);
    return sum;
}

AtomForm atom_form_difference(const AtomForm &left, const AtomForm &right)
{
    AtomForm negative = right;
    for (AnchorExactInteger &entry : negative.magnitude)
    {
        entry.sign = -entry.sign;
    }
    return atom_form_sum(left, negative);
}

AtomForm atom_form_scaled(const AtomForm &form, SimRational factor)
{
    AtomForm scaled;
    if ((sim_rational_sign(factor) == 0) || form.magnitude.empty())
    {
        return scaled;
    }
    scaled.magnitude.assign(form.magnitude.size(), atom_form_nothing());
    for (size_t slot = 0u; slot < form.magnitude.size(); slot += 1u)
    {
        if (form.magnitude[slot].sign != 0)
        {
            atom_form_check(sim_exact_product(&form.magnitude[slot], &factor.numerator, &scaled.magnitude[slot]));
        }
    }
    atom_form_check(sim_exact_product(&form.denominator, &factor.denominator, &scaled.denominator));
    atom_form_settle(&scaled);
    return scaled;
}

AtomForm atom_form_product(const AtomForm &left, const AtomForm &right)
{
    AtomForm product;
    if (left.magnitude.empty() || right.magnitude.empty())
    {
        return product;
    }
    for (size_t first = 0u; first < left.magnitude.size(); first += 1u)
    {
        if (left.magnitude[first].sign == 0)
        {
            continue;
        }
        for (size_t second = 0u; second < right.magnitude.size(); second += 1u)
        {
            if (right.magnitude[second].sign == 0)
            {
                continue;
            }
            const unsigned int slot = atom_form_slot_product((unsigned int)first, (unsigned int)second);
            AnchorExactInteger part;
            atom_form_check(sim_exact_product(&left.magnitude[first], &right.magnitude[second], &part));
            AnchorExactInteger *const entry = atom_form_entry(&product, slot);
            AnchorExactInteger total;
            atom_form_check(sim_exact_sum(entry, &part, &total));
            *entry = total;
        }
    }
    atom_form_check(sim_exact_product(&left.denominator, &right.denominator, &product.denominator));
    atom_form_settle(&product);
    return product;
}

// 1 where e's power is ratio times a whole number 1 or more
static int atom_form_multiple(SimRational e, SimRational ratio)
{
    if ((sim_rational_sign(e) == 0) || (sim_rational_sign(ratio) == 0))
    {
        return 0;
    }
    const SimRational times = sim_rational_product(e, sim_rational_reciprocal(ratio));
    long long denominator = 0ll;
    return (sim_rational_sign(times) > 0) && sim_rational_small(&times.denominator, &denominator) &&
           (denominator == 1ll);
}

AtomForm atom_form_unit_reduced(const AtomForm &form, SimRational ratio, unsigned int share)
{
    AtomForm reduced = form;
    for (;;)
    {
        size_t mixed = reduced.magnitude.size();
        for (size_t slot = 0u; slot < reduced.magnitude.size(); slot += 1u)
        {
            const AtomPower &power = s_atom_slots[slot].power;
            if ((reduced.magnitude[slot].sign != 0) && (power.size() > share) && (power[share] > 0u) &&
                atom_form_multiple(s_atom_slots[slot].e, ratio))
            {
                mixed = slot;
                break;
            }
        }
        if (mixed == reduced.magnitude.size())
        {
            atom_form_settle(&reduced);
            return reduced;
        }
        // e^ratio share -> 1 - share, over the same denominator
        const AnchorExactInteger value = reduced.magnitude[mixed];
        const SimRational lowered_e = sim_rational_difference(s_atom_slots[mixed].e, ratio);
        AtomPower lowered = s_atom_slots[mixed].power;
        reduced.magnitude[mixed] = atom_form_nothing();
        lowered[share] -= 1u;
        AtomPower kept = lowered;
        kept[share] += 1u;
        const unsigned int lowered_slot = atom_form_slot(atom_form_key(lowered_e, lowered));
        const unsigned int kept_slot = atom_form_slot(atom_form_key(lowered_e, kept));
        AnchorExactInteger total;
        atom_form_check(sim_exact_sum(atom_form_entry(&reduced, lowered_slot), &value, &total));
        *atom_form_entry(&reduced, lowered_slot) = total;
        atom_form_check(sim_exact_less(atom_form_entry(&reduced, kept_slot), &value, &total));
        *atom_form_entry(&reduced, kept_slot) = total;
    }
}

AtomForm atom_form_square_reduced(const AtomForm &form, unsigned int root, SimRational square)
{
    AtomForm reduced;
    for (size_t slot = 0u; slot < form.magnitude.size(); slot += 1u)
    {
        if (form.magnitude[slot].sign == 0)
        {
            continue;
        }
        AtomPower power = s_atom_slots[slot].power;
        SimRational value = atom_form_coefficient(form, slot);
        if (power.size() > root)
        {
            while (power[root] >= 2u)
            {
                power[root] -= 2u;
                value = sim_rational_product(value, square);
            }
        }
        reduced = atom_form_sum(reduced, atom_form_term(atom_form_key(s_atom_slots[slot].e, power), value));
    }
    return reduced;
}

unsigned int atom_book_id(AtomBook *book, const std::string &name)
{
    for (size_t index = 0u; index < book->names.size(); index += 1u)
    {
        if (book->names[index] == name)
        {
            return (unsigned int)index;
        }
    }
    book->names.push_back(name);
    return (unsigned int)(book->names.size() - 1u);
}

// every limb in hex from the highest held; two values share a text only where they are equal
static std::string atom_book_limbs(const AnchorExactInteger &value)
{
    static const char digits[] = "0123456789abcdef";
    std::string text = (value.sign < 0) ? "-0x" : "0x";
    const unsigned long long bits = sim_exact_bits(&value);
    const unsigned int used = (unsigned int)((bits + 31ull) / 32ull);
    if (used == 0u)
    {
        return "0";
    }
    for (unsigned int limb = used; limb > 0u; limb -= 1u)
    {
        for (int shift = 28; shift >= 0; shift -= 4)
        {
            text.push_back(digits[(value.limb[limb - 1u] >> shift) & 0xFu]);
        }
    }
    return text;
}

std::string atom_book_rational(SimRational value)
{
    long long numerator = 0ll;
    long long denominator = 0ll;
    if (!sim_rational_small(&value.numerator, &numerator) || !sim_rational_small(&value.denominator, &denominator))
    {
        return "(" + atom_book_limbs(value.numerator) + "/" + atom_book_limbs(value.denominator) + ")";
    }
    return (denominator == 1ll) ? std::to_string(numerator)
                                : (std::to_string(numerator) + "/" + std::to_string(denominator));
}

int atom_form_zero(const AtomForm &form)
{
    return form.magnitude.empty();
}

SimRational atom_form_constant(const AtomForm &form)
{
    const auto found = s_atom_slot_of.find(atom_form_key(sim_rational(0ll, 1ll), AtomPower()));
    if ((found == s_atom_slot_of.end()) || (found->second >= form.magnitude.size()) ||
        (form.magnitude[found->second].sign == 0))
    {
        return sim_rational(0ll, 1ll);
    }
    return atom_form_coefficient(form, found->second);
}

size_t atom_form_e_count(const AtomForm &form)
{
    size_t count = 0u;
    const AtomKey *last = NULL;
    for (unsigned int slot : atom_form_held(form))
    {
        if ((last == NULL) || !sim_rational_equal(last->e, s_atom_slots[slot].e))
        {
            count += 1u;
        }
        last = &s_atom_slots[slot];
    }
    return count;
}

void atom_form_print(ScripturaLine *line, const AtomForm &form, const std::vector<std::string> &names,
                     unsigned int places)
{
    if (form.magnitude.empty())
    {
        scriptura_character(line, '0');
        return;
    }
    int first = 1;
    for (unsigned int slot : atom_form_held(form))
    {
        const AtomKey &key = s_atom_slots[slot];
        if (!first)
        {
            scriptura_text(line, " + ");
        }
        first = 0;
        report_value(line, atom_form_coefficient(form, slot), places);
        if (sim_rational_sign(key.e) != 0)
        {
            scriptura_text(line, " e^(");
            scriptura_text(line, atom_book_rational(key.e).c_str());
            scriptura_character(line, ')');
        }
        for (size_t atom = 0u; atom < key.power.size(); atom += 1u)
        {
            if (key.power[atom] == 0u)
            {
                continue;
            }
            scriptura_character(line, ' ');
            scriptura_text(line, (atom < names.size()) ? names[atom].c_str() : "atom");
            if (key.power[atom] > 1u)
            {
                scriptura_character(line, '^');
                scriptura_decimal(line, key.power[atom], 1u);
            }
        }
    }
}

// one exact integer in decimal, its sign first
static void atom_form_write_integer(FILE *file, const AnchorExactInteger &value, std::vector<char> *buffer)
{
    ScripturaLine line;
    line.out = buffer->data();
    line.capacity = buffer->size();
    line.at = 0ull;
    if (value.sign < 0)
    {
        scriptura_character(&line, '-');
    }
    sim_exact_decimal(&line, &value);
    if (line.at >= line.capacity)
    {
        s_sim_rational_wide = 1;
    }
    fwrite(line.out, 1u, (size_t)line.at, file);
}

void atom_form_write(FILE *file, const AtomForm &form, const std::vector<std::string> &names)
{
    // a magnitude of the build's width in decimal, groups of nine, with room for its sign
    std::vector<char> buffer((size_t)(SIM_DECIMAL_GROUPS * SIM_DECIMAL_GROUP_DIGITS + 8ull));
    for (unsigned int slot : atom_form_held(form))
    {
        const AtomKey &key = s_atom_slots[slot];
        const SimRational coefficient = atom_form_coefficient(form, slot);
        atom_form_write_integer(file, coefficient.numerator, &buffer);
        fputc('/', file);
        atom_form_write_integer(file, coefficient.denominator, &buffer);
        if (sim_rational_sign(key.e) != 0)
        {
            fprintf(file, " e^(%s)", atom_book_rational(key.e).c_str());
        }
        for (size_t atom = 0u; atom < key.power.size(); atom += 1u)
        {
            if (key.power[atom] == 0u)
            {
                continue;
            }
            fprintf(file, " %s", (atom < names.size()) ? names[atom].c_str() : "atom");
            if (key.power[atom] > 1u)
            {
                fprintf(file, "^%u", key.power[atom]);
            }
        }
        fputc('\n', file);
    }
}

size_t atom_form_terms(const AtomForm &form)
{
    size_t count = 0u;
    for (const AnchorExactInteger &entry : form.magnitude)
    {
        count += (entry.sign != 0) ? 1u : 0u;
    }
    return count;
}

std::vector<unsigned int> atom_form_slots(const AtomForm &form)
{
    return atom_form_held(form);
}

int atom_form_holds(const AtomForm &form, unsigned int slot)
{
    return (slot < form.magnitude.size()) && (form.magnitude[slot].sign != 0);
}

std::string atom_form_key_text(unsigned int slot, const std::vector<std::string> &names)
{
    const AtomKey &key = s_atom_slots[slot];
    std::string text;
    if (sim_rational_sign(key.e) != 0)
    {
        text = "e^(" + atom_book_rational(key.e) + ")";
    }
    for (size_t atom = 0u; atom < key.power.size(); atom += 1u)
    {
        if (key.power[atom] == 0u)
        {
            continue;
        }
        text += text.empty() ? "" : " ";
        text += (atom < names.size()) ? names[atom] : "atom";
        if (key.power[atom] > 1u)
        {
            text += "^" + std::to_string(key.power[atom]);
        }
    }
    return text.empty() ? "1" : text;
}

size_t atom_form_entries(const AtomForm &form)
{
    return form.magnitude.size();
}

unsigned long long atom_form_bits(const AtomForm &form)
{
    unsigned long long most = sim_exact_bits(&form.denominator);
    for (const AnchorExactInteger &entry : form.magnitude)
    {
        const unsigned long long bits = sim_exact_bits(&entry);
        most = (bits > most) ? bits : most;
    }
    return most;
}

int atom_form_short(void)
{
    return s_sim_rational_wide != 0;
}
