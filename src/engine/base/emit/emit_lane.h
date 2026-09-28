// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_LANE_H
#define EMIT_LANE_H

// The register lane, a shape of the emitter that names no language: each step unrolled at its widths into
// straight-line text over registers the lane holds itself, every line a form of the language's ruleset. A language of
// this shape is a class that inherits it and names its ruleset's file, the toolchain that builds its text, where its
// header comes from, how many memory writes its text can make in one state, and whether it holds the lane's file and
// signs in the thread block's shared memory (emit_ptx.h)

#include "emit.h"
#include "emit_core.h"

#include <map>
#include <string>
#include <vector>

// a budget or a port count that holds anything
#define EMIT_LANE_UNBOUNDED 0xFFFFFFFFu

// how a lane is cut into states, a clock each: the cost of each form by the name its ruleset gives it, as the target's
// construction set measured it, and the cost of a form it does not name; how much cost a state may chain; and how many
// memory writes a state may make, which the language's own write ports bound as well. The budget and the writes are
// the refinement loop's to choose
struct EmitLaneShape
{
    std::map<std::string, unsigned int> cost;
    unsigned int other;
    unsigned int budget;
    unsigned int writes;
};

// a lane as it was cut: its states, the most cost one state chains, and the forms that alone cost more than a state
// holds
struct EmitLaneShaped
{
    unsigned int states;
    unsigned int most;
    unsigned int over;
};

// a shape as the core cuts by it (EmitCoreCut): each form's cost by its number, the cost a state may chain, the writes
// the shape lets a state make and the language's write ports
struct EmitLaneCut
{
    std::vector<unsigned int> cost;
    unsigned int budget;
    unsigned int writes;
    unsigned int ports;
};

class EmitLane : public Emitter
{
public:
    std::string program(const EngineRecordLayout *layout, const EmitTarget *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;

    // the lane cut into states by `shape`, as program() writes it otherwise; `shaped` told how it was cut
    std::string shaped(const EngineRecordLayout *layout, const EmitTarget *target, const std::string &header,
                       unsigned int *places, unsigned int *live, const EmitLaneShape &shape, EmitLaneShaped *report);

    // the forms program() writes the lane in, as the core decides them (emit_core.h), in the text's order, the header's
    // place held by an item of the form EMIT_TEXT_WHOLE, and the places the lane holds in shared memory; 0 where
    // program() writes nothing for want of a form. The device decides the same (emit_device.h)
    int decided(const EngineRecordLayout *layout, unsigned int *places, std::vector<EmitCoreItem> *items);

    // the forms shaped() writes the lane in, as decided() gives program()'s, and `report` told how it was cut
    int decided(const EngineRecordLayout *layout, const EmitLaneShape &shape, EmitLaneShaped *report,
                unsigned int *places, std::vector<EmitCoreItem> *items);

    // `shape` as the core cuts by it, each form's cost found by the name the ruleset gives it, with the language's write
    // ports, on the host and the device alike
    EmitLaneCut cut(const EmitLaneShape &shape) const;

    // the shape program() cuts the lane by, where the language always cuts it into states (a clocked one); NULL where
    // program() writes the lane whole
    virtual const EmitLaneShape *program_shape(void) const;

    // 1 where program() cuts the lane, `laid` then its shape as the core cuts by it, for the device to cut the same
    int program_cut(EmitLaneCut *laid) const;

protected:
    // `shared` is 1 where the language's ruleset lays the file and its signs in shared memory, a thread's places a word
    // each across the thread block's threads and the signs a byte each after them, as the record machine sizes them:
    // the lane then holds the file's places there and opens by finding its signs
    EmitLane(const char *file, const char *toolchain, const char *header, unsigned int write_ports, int shared);

private:
    int decide(const EngineRecordLayout *layout, const EmitLaneShape *shape, EmitLaneShaped *report,
               unsigned int *places, unsigned int *live, std::vector<EmitCoreItem> *items);

    std::string lane(const EngineRecordLayout *layout, const EmitTarget *target, const std::string &header,
                     unsigned int *places, unsigned int *live, const EmitLaneShape *shape, EmitLaneShaped *report);

    unsigned int write_ports;
    int shared;
};

#endif
