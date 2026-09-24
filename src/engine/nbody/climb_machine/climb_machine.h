// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CLIMB_MACHINE_H
#define CLIMB_MACHINE_H

#ifdef __cplusplus
extern "C" {
#endif

#define CLIMB_MACHINE_NO_LEAF (-1)

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int peak_room;
    unsigned int frames;
    unsigned int weight_z;
    unsigned int reserve_bytes;
} ClimbMachineShape;

typedef struct
{
    unsigned int frame;
    unsigned int leaf_count;
    const unsigned int *labels;
    const unsigned long long *positive;
    const unsigned int *peaks;
    const unsigned int *contact_start;
    const unsigned int *contacts;
} ClimbMachineFrame;

typedef struct
{
    unsigned int earlier;
    unsigned int later;
    int lag[3];
    unsigned int earlier_leaves;
    const unsigned int *earlier_peaks;
    unsigned int later_leaves;
    const unsigned int *later_peaks;
    int *forward_lags;
    int *forward;
    int *backward_lags;
    int *backward;
    unsigned int *forward_held;
    unsigned int *backward_held;
} ClimbMachinePair;

typedef struct ClimbMachine ClimbMachine;

#define CLIMB_MACHINE_BOX_NONE 0xFFFFFFFFu

#define CLIMB_MACHINE_BOX_TARGETS 64u

#define CLIMB_MACHINE_BOX_NEIGHBOURS 27u

#define CLIMB_MACHINE_BOX_CENTRE 13u

#define CLIMB_MACHINE_BOX_CELLS (CLIMB_MACHINE_BOX_NEIGHBOURS + 1u)

typedef struct
{
    unsigned int climbers;
    const unsigned int *earlier;
    const unsigned int *later;
    const unsigned int *leaf;
    const unsigned int *cell_first;
    const int *cell_shift;
    const unsigned int *entry_first;
    const unsigned int *target;
    const unsigned int *count;
    unsigned int cells;
    unsigned int entries;
    unsigned int held_differ;
    unsigned int not_highest;
    unsigned int crowded;
    unsigned int broken;
    unsigned long long microseconds;
} ClimbMachineBox;

#define CLIMB_MACHINE_CORE_FIELDS 10u

typedef struct
{
    unsigned int climbers;
    const unsigned int *earlier;
    const unsigned int *later;
    const unsigned int *side;
    const unsigned int *leaf;
    const unsigned int *match;
    const int *lag;
    const unsigned int *width_first;
    const unsigned long long *fields;
    unsigned int widths;
    unsigned long long microseconds;
} ClimbMachineCore;

ClimbMachine *climb_machine_open(const ClimbMachineShape *shape);

int climb_machine_store(ClimbMachine *machine, const ClimbMachineFrame *frame);

const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame);

const unsigned long long *climb_machine_positive(const ClimbMachine *machine, unsigned int frame);

int climb_machine_pend(ClimbMachine *machine, const ClimbMachinePair *pair);

void climb_machine_land_by_mass(ClimbMachine *machine, unsigned int by_mass);

int climb_machine_spiral(ClimbMachine *machine, unsigned int tries);

int climb_machine_run(ClimbMachine *machine);
int climb_machine_box(ClimbMachine *machine, ClimbMachineBox *box);

int climb_machine_core(ClimbMachine *machine, ClimbMachineCore *core);

#define CLIMB_MACHINE_EXTENT_FIELDS 6u

typedef struct
{
    unsigned int frame;
    unsigned int *extents;
} ClimbMachineExtentsRequest;

int climb_machine_extents(ClimbMachine *machine, const ClimbMachineExtentsRequest *request);

void climb_machine_close(ClimbMachine *machine);

#ifdef __cplusplus
}
#endif

#endif
