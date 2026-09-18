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

ClimbMachine *climb_machine_open(const ClimbMachineShape *shape);

int climb_machine_store(ClimbMachine *machine, const ClimbMachineFrame *frame);

const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame);

const unsigned long long *climb_machine_positive(const ClimbMachine *machine, unsigned int frame);

int climb_machine_pend(ClimbMachine *machine, const ClimbMachinePair *pair);

void climb_machine_land_by_mass(ClimbMachine *machine, unsigned int by_mass);

int climb_machine_spiral(ClimbMachine *machine, unsigned int tries);

int climb_machine_run(ClimbMachine *machine);

void climb_machine_close(ClimbMachine *machine);

#ifdef __cplusplus
}
#endif

#endif
