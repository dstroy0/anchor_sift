// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// witness_cube.cu: the 8 witnesses and their components (witness_cube.h)
#include "witness_cube.h"

#include <set>

// the sign the corner takes on the axes of component S: -1 where an odd number of them sit at the low end
static long long witness_cube_sign(unsigned int corner, unsigned int component)
{
    long long sign = 1ll;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if (((component >> axis) & 1u) && !((corner >> axis) & 1u))
        {
            sign = -sign;
        }
    }
    return sign;
}

void witness_cube_measure(WitnessSubject subject, const void *context, const SimRational *center,
                          const SimRational *half, AtomBook *book, WitnessCube *cube)
{
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        cube->center[axis] = center[axis];
        cube->half[axis] = half[axis];
    }
    for (unsigned int corner = 0u; corner < 8u; corner += 1u)
    {
        SimRational point[3];
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            point[axis] = ((corner >> axis) & 1u) ? sim_rational_sum(center[axis], half[axis])
                                                  : sim_rational_difference(center[axis], half[axis]);
        }
        cube->corner[corner] = subject(context, point, book);
    }
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        AtomForm sum;
        for (unsigned int corner = 0u; corner < 8u; corner += 1u)
        {
            sum = atom_form_sum(sum, atom_form_scaled(cube->corner[corner],
                                                      sim_rational(witness_cube_sign(corner, component), 1ll)));
        }
        cube->component[component] = atom_form_scaled(sum, sim_rational(1ll, 8ll));
    }
    // every slot any corner holds, in key order as the corners give it
    std::set<unsigned int> seen;
    cube->slot.clear();
    cube->holding.clear();
    for (unsigned int corner = 0u; corner < 8u; corner += 1u)
    {
        for (unsigned int slot : atom_form_slots(cube->corner[corner]))
        {
            if (seen.insert(slot).second)
            {
                cube->slot.push_back(slot);
            }
        }
    }
    for (unsigned int slot : cube->slot)
    {
        unsigned int bits = 0u;
        for (unsigned int component = 0u; component < 8u; component += 1u)
        {
            if (atom_form_holds(cube->component[component], slot))
            {
                bits |= 1u << component;
            }
        }
        cube->holding.push_back(bits);
    }
}

int witness_cube_whole(const WitnessCube *cube)
{
    for (unsigned int corner = 0u; corner < 8u; corner += 1u)
    {
        AtomForm rebuilt;
        for (unsigned int component = 0u; component < 8u; component += 1u)
        {
            rebuilt = atom_form_sum(rebuilt, atom_form_scaled(cube->component[component],
                                                              sim_rational(witness_cube_sign(corner, component), 1ll)));
        }
        if (!atom_form_zero(atom_form_difference(rebuilt, cube->corner[corner])))
        {
            return 0;
        }
    }
    return 1;
}

static unsigned int witness_cube_count(unsigned int bits)
{
    unsigned int count = 0u;
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        count += (bits >> component) & 1u;
    }
    return count;
}

size_t witness_cube_characters(const WitnessCube *cube, unsigned int count)
{
    size_t terms = 0u;
    for (unsigned int bits : cube->holding)
    {
        terms += (witness_cube_count(bits) == count) ? 1u : 0u;
    }
    return terms;
}

void witness_cube_record(FILE *file, const char *name, const WitnessCube *cube, const AtomBook *book)
{
    fprintf(file, "cube %s\ncenter", name);
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        fprintf(file, " %s", atom_book_rational(cube->center[axis]).c_str());
    }
    fprintf(file, "\nhalf");
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        fprintf(file, " %s", atom_book_rational(cube->half[axis]).c_str());
    }
    fputc('\n', file);
    for (unsigned int corner = 0u; corner < 8u; corner += 1u)
    {
        fprintf(file, "form corner_%u %zu\n", corner, atom_form_terms(cube->corner[corner]));
        atom_form_write(file, cube->corner[corner], book->names);
    }
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        fprintf(file, "form component_%u %zu\n", component, atom_form_terms(cube->component[component]));
        atom_form_write(file, cube->component[component], book->names);
    }
    // character: the count, the components as their numbers, the term
    fprintf(file, "characters %zu\n", cube->slot.size());
    for (size_t index = 0u; index < cube->slot.size(); index += 1u)
    {
        fprintf(file, "%u", witness_cube_count(cube->holding[index]));
        for (unsigned int component = 0u; component < 8u; component += 1u)
        {
            if ((cube->holding[index] >> component) & 1u)
            {
                fprintf(file, " c%u", component);
            }
        }
        fprintf(file, " : %s\n", atom_form_key_text(cube->slot[index], book->names).c_str());
    }
}

int witness_cube_short(void)
{
    return s_sim_rational_wide != 0;
}
