// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

static_assert((sizeof(EngineProgramBlock) % 8u) == 0u, "cycle: the block is 64-bit words");
static_assert(sizeof(EngineSignum) == 32u, "cycle: the block's signature is four words");

// every C lane opens with this: the launch the kernel takes, and the lane a program defines. launch.places is the
// words a thread holds in shared memory, a program's file where its language lays out the file there. The resident
// kernel that runs the lanes is no longer here: each language writes it after the lane from its own ruleset
// (program_unit)
extern const char g_cycle_prelude[] = R"CYCLE(
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;

struct CycleHot
{
    u64 next_lane;
    u64 launch_start;
    u64 finished;
    u64 checkins;
};

struct CycleCompiledLaunch
{
    const u32 *in[3];
    const u32 *index;
    const u32 *tables;
    u32 *out;
    u32 *error;
    u64 bodies[3];
    u64 count;
    CycleHot *hot;
    u64 *block;
    u64 ttl;
    u64 checkin_every;
    u64 launch_number;
    u64 places;
};

extern "C" __device__ void cycle_lane(const CycleCompiledLaunch *launch, u64 lane);
)CYCLE";
