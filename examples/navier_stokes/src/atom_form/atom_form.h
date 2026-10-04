// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// atom_form.h: an exact polynomial in atoms with rational coefficients, e held apart at a rational power
#ifndef ATOM_FORM_H
#define ATOM_FORM_H

// An atom is a number held apart and never evaluated: w(z_c) and w'(z_c) for the Kummer solution, z_c^h, E1(x). e is
// held apart from every atom: each term carries its own rational power of e, and e^p e^q is e^(p+q) exactly;
// e^(-1/s_c), e^N and e^(-n/b) are one number at three powers. A form is a sum of rational coefficients times e^q times
// products of atoms. The exponent of atom i in a term is entry i of its power, trailing zeros dropped; one product has
// one key.

#include "sim_rational.h"

#include <map>
#include <string>
#include <vector>

typedef std::vector<unsigned int> AtomPower;

typedef struct
{
    SimRational e;
    AtomPower power;
} AtomKey;

// e's power first, by value, then the atoms' powers
struct AtomKeyOrder
{
    bool operator()(const AtomKey &left, const AtomKey &right) const;
};

// the exact integer 1
AnchorExactInteger atom_form_unit(void);

// A form holds exact integers, entry i the numerator of the term at the program's slot i, over one positive
// denominator. A slot is a key, a power of e and the atoms' powers, numbered as the program first meets it; every form
// in a run shares the numbering. The denominator and the entries share no factor, and the last entry is not 0.
struct AtomForm
{
    std::vector<AnchorExactInteger> magnitude;
    AnchorExactInteger denominator = atom_form_unit();
};

AtomForm atom_form_rational(SimRational value);

// the atom `atom` itself
AtomForm atom_form_atom(unsigned int atom);

// e^power
AtomForm atom_form_e(SimRational power);

AtomForm atom_form_sum(const AtomForm &left, const AtomForm &right);
AtomForm atom_form_difference(const AtomForm &left, const AtomForm &right);
AtomForm atom_form_scaled(const AtomForm &form, SimRational factor);
AtomForm atom_form_product(const AtomForm &left, const AtomForm &right);

// the form under the relation share (1 + e^ratio) = 1: every term holding share whose power of e is a whole positive
// multiple of `ratio` has e^ratio share replaced by 1 - share until none does. The powers of e in the form are the
// ratio's own.
AtomForm atom_form_unit_reduced(const AtomForm &form, SimRational ratio, unsigned int share);

// the form with every square of the atom `root` replaced by the rational `square`, as for 2^(-1/2)
AtomForm atom_form_square_reduced(const AtomForm &form, unsigned int root, SimRational square);

// The atoms of one computation, numbered as they are first named
typedef struct
{
    std::vector<std::string> names;
} AtomBook;

// the number of the atom named `name`, a new one where the book does not hold it
unsigned int atom_book_id(AtomBook *book, const std::string &name);

// a rational as text for an atom's name: p/q, or both parts' limbs in hex where a part passes a word
std::string atom_book_rational(SimRational value);

// 1 where every coefficient is 0
int atom_form_zero(const AtomForm &form);

// the coefficient of the term with no atom and e^0
SimRational atom_form_constant(const AtomForm &form);

// the number of distinct powers of e the form holds
size_t atom_form_e_count(const AtomForm &form);

// the form written term by term, each coefficient with `places`, each atom by its name
void atom_form_print(ScripturaLine *line, const AtomForm &form, const std::vector<std::string> &names,
                     unsigned int places);

// the form written whole to `file`, one term per line: numerator/denominator in decimal, e^(q) where q is not 0, and
// each atom by its name, ^k where its power passes 1
void atom_form_write(FILE *file, const AtomForm &form, const std::vector<std::string> &names);

// the number of terms the form holds
size_t atom_form_terms(const AtomForm &form);

// the slots holding a term, in key order
std::vector<unsigned int> atom_form_slots(const AtomForm &form);

// 1 where the form holds a term at `slot`
int atom_form_holds(const AtomForm &form, unsigned int slot);

// the key at `slot` as text: "1", or e^(q) and each atom by its name, ^k where its power passes 1
std::string atom_form_key_text(unsigned int slot, const std::vector<std::string> &names);

// the entries the form's array holds, its zeros counted
size_t atom_form_entries(const AtomForm &form);

// the most bits any entry or the denominator takes
unsigned long long atom_form_bits(const AtomForm &form);

// 1 where a value in this module outgrew the build's width
int atom_form_short(void);

#endif
