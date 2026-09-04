#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Emit the DMA correctness scenarios as a C table.

Python decides what the scenarios are. C decides what happens when one runs. The moment the
engine's behavior lives here, the port stops being a port.

A scenario carries two lists. The program is what the case calls into the library. The script is
what the engine answers, one reaction per call. Both are the fixture, because what the library is
asked to do decides as much of the outcome as what the engine answers.

Every scenario is emitted twice, once per arm. The interrupt arm reports at the first hook call at
or after a transfer is due; the software arm reports only when a poll selects the channel and it is
due. Same fixture, one difference, so a divergence in outcome is the arm and nothing else - which is
the whole question behind falling back to a busy timer where there is no vector to spare.

The expectations are computed here by walking the program against the script. They are never derived
by the engine or by the library, so an expectation that agrees with the run is evidence rather than a
tautology. That includes the order completions arrive in, which a total count cannot express: two
completions on the wrong channels sum to the same number as two on the right ones.

DMA owns no bytes and no buffer. A transfer names the caller's storage and its extent. Nothing here
configures a size for the engine, and channels are logical - one engine schedules all of them, which
is what a part with fewer channels than a program wants actually does.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(ROOT, "test", "integration", "test_praet_correctness", "praet_scenarios.h")

# Hook identifiers, matching PraetHook in praet_engine.h. Written out rather than imported, because
# the C header is the interface and a mismatch has to fail the compile, not go unnoticed.
OPEN = 0
SUBMIT = 1
CLOSE = 2
POLL = 3

# Completion timings, matching PraetCompleteWhen in praet_engine.h.
NEVER = 0
INSIDE_CALL = 1
WHEN_DUE = 2

# Arms, matching PraetEngineArm in praet_engine.h.
INTERRUPT = 0
SOFTWARE = 1
ARM_NAMES = {INTERRUPT: "interrupt", SOFTWARE: "software"}

# Matching PRAET_RELEASE_EVERY_CHANNEL and PRAET_ENGINE_CHANNELS in praet_engine.h.
EVERY_CHANNEL = 0xFF
ENGINE_CHANNELS = 8

REFUSE = 0
ACCEPT = 1


def call(hook, channel=0, byte_count=0):
    """One call the case makes into the library."""
    return {"call": hook, "channel": channel, "bytes": byte_count}


def react(hook, channel=0, accepted=ACCEPT, when=NEVER, completions=0, moved=0, settle=0, cycle=0, progress=0):
    """One scripted reaction. @p channel is read by a poll reaction alone, as the release selector.

    @p progress is read by a poll reaction, and is how far the polled channel has got by then, as a
    controller's remaining count would say. Zero reports nothing and leaves the last figure standing,
    which is what every scenario here does: the correctness arm reads completions and their order, and
    what a partial report does to a schedule is driven by the cases that join the two.
    """
    return {
        "hook": hook,
        "channel": channel,
        "accepted": accepted,
        "when": when,
        "completions": completions,
        "moved": moved,
        "settle": settle,
        "cycle": cycle,
        "progress": progress,
    }


def oracle(program, script, arm):
    """What a run of @p program against @p script on @p arm must produce.

    Mirrors the engine's rules: one hook call is one tick; an accepted open starts the channel
    settling; a submit to a settling channel is refused whatever the script said; an accepted
    reaction holds its completions against the channel until the cycle has elapsed. The interrupt arm
    releases every due channel at the end of each call, the software arm only on a poll that selects
    one.
    """
    if len(program) != len(script):
        raise SystemExit("program has %d calls and the script has %d reactions" % (len(program), len(script)))

    opens = 0
    submits = 0
    settling = 0
    order = []
    moved_total = 0
    tick = 0
    settled_at = [0] * ENGINE_CHANNELS
    held_count = [0] * ENGINE_CHANNELS
    held_moved = [0] * ENGINE_CHANNELS
    due_at = [0] * ENGINE_CHANNELS

    def release_one(channel):
        nonlocal moved_total
        if tick < due_at[channel]:
            return
        while held_count[channel] != 0:
            held_count[channel] -= 1
            order.append(channel)
            moved_total += held_moved[channel]

    def hold(channel, answer):
        if held_count[channel] != 0:
            raise SystemExit("channel %d is already holding, so a second hold would restate it" % channel)
        held_count[channel] = answer["completions"]
        held_moved[channel] = answer["moved"]
        due_at[channel] = tick + answer["cycle"]

    def schedule(channel, answer):
        nonlocal moved_total
        if answer["when"] == INSIDE_CALL:
            for _ in range(answer["completions"]):
                order.append(channel)
                moved_total += answer["moved"]
        elif answer["when"] == WHEN_DUE:
            hold(channel, answer)

    def service_interrupt():
        if arm != INTERRUPT:
            return
        for channel in range(ENGINE_CHANNELS):
            release_one(channel)

    for made, answer in zip(program, script):
        if made["call"] != answer["hook"]:
            raise SystemExit("call %d and reaction %d name different hooks" % (made["call"], answer["hook"]))

        tick += 1
        channel = made["channel"]
        accepted = answer["accepted"] == ACCEPT

        if made["call"] == OPEN:
            if accepted:
                opens += 1
                settled_at[channel] = tick + answer["settle"]
                schedule(channel, answer)
            service_interrupt()

        elif made["call"] == SUBMIT:
            if not accepted:
                service_interrupt()
            elif tick < settled_at[channel]:
                settling += 1
                service_interrupt()
            else:
                submits += 1
                schedule(channel, answer)
                service_interrupt()

        elif made["call"] == CLOSE:
            schedule(channel, answer)
            service_interrupt()

        else:
            schedule(channel, answer)
            if arm == SOFTWARE:
                selector = answer["channel"]
                targets = range(ENGINE_CHANNELS) if selector == EVERY_CHANNEL else [selector]
                for target in targets:
                    release_one(target)
            else:
                service_interrupt()

    return {
        "opens": opens,
        "submits": submits,
        "settling": settling,
        "order": order,
        "moved": moved_total,
        "held": sum(held_count),
    }


def scenarios():
    """Every correctness scenario, control first.

    The control is the one case that must come out clean on both arms. If it ever fails, nothing else
    in this table can be read, because whatever broke it broke the harness rather than the library.
    """
    out = []

    def add(name, program, script):
        out.append((name, program, script))

    add(
        "control_one_transfer_completes",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=64), react(POLL), react(CLOSE)],
    )

    add(
        "refuse_the_open",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN, accepted=REFUSE), react(SUBMIT, accepted=REFUSE), react(POLL), react(CLOSE)],
    )

    add(
        "accept_the_open_refuse_the_submit",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, accepted=REFUSE), react(POLL), react(CLOSE)],
    )

    add(
        "accept_and_never_complete",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=NEVER), react(POLL), react(CLOSE)],
    )

    add(
        "complete_inside_the_submit_call",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=INSIDE_CALL, completions=1, moved=64), react(POLL), react(CLOSE)],
    )

    add(
        "complete_twice_for_one_transfer",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=2, moved=64), react(POLL), react(CLOSE)],
    )

    add(
        "complete_twelve_of_sixty_four",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=12), react(POLL), react(CLOSE)],
    )

    add(
        "complete_more_than_was_asked",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=100), react(POLL), react(CLOSE)],
    )

    add(
        "complete_after_the_close",
        [call(OPEN), call(SUBMIT, byte_count=64), call(CLOSE), call(POLL)],
        [react(OPEN), react(SUBMIT, when=NEVER), react(CLOSE, when=WHEN_DUE, completions=1, moved=64), react(POLL)],
    )

    add(
        "complete_a_transfer_of_no_bytes",
        [call(OPEN), call(SUBMIT, byte_count=0), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=0), react(POLL), react(CLOSE)],
    )

    add(
        "finish_channel_three_before_channel_one",
        [
            call(OPEN, channel=1),
            call(OPEN, channel=3),
            call(SUBMIT, channel=1, byte_count=64),
            call(SUBMIT, channel=3, byte_count=64),
            call(POLL, channel=3),
            call(POLL, channel=1),
        ],
        [
            react(OPEN),
            react(OPEN),
            react(SUBMIT, when=WHEN_DUE, completions=1, moved=64),
            react(SUBMIT, when=WHEN_DUE, completions=1, moved=64),
            react(POLL, channel=3),
            react(POLL, channel=1),
        ],
    )

    program = [call(OPEN, channel=channel) for channel in range(ENGINE_CHANNELS)]
    script = [react(OPEN) for _ in range(ENGINE_CHANNELS)]
    program += [call(SUBMIT, channel=channel, byte_count=16) for channel in range(ENGINE_CHANNELS)]
    script += [react(SUBMIT, when=WHEN_DUE, completions=1, moved=16) for _ in range(ENGINE_CHANNELS)]
    program += [call(POLL)]
    script += [react(POLL, channel=EVERY_CHANNEL)]
    add("eight_logical_channels_on_one_engine", program, script)

    # The channel is still settling when the transfer arrives. The engine refuses it whatever the
    # script answered, because settling is a rule and not a reaction.
    add(
        "submit_before_the_channel_has_settled",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN, settle=3), react(SUBMIT, when=WHEN_DUE, completions=1, moved=64), react(POLL), react(CLOSE)],
    )

    # The same settle, waited out. Two polls burn the ticks, and the transfer is then taken.
    add(
        "submit_after_the_channel_has_settled",
        [call(OPEN), call(POLL), call(POLL), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [
            react(OPEN, settle=3),
            react(POLL),
            react(POLL),
            react(SUBMIT, when=WHEN_DUE, completions=1, moved=64),
            react(POLL),
            react(CLOSE),
        ],
    )

    # The transfer comes due on the close, and the case never polls afterward. This is the row where
    # the two arms have to disagree: an interrupt reports it, a busy timer nobody reads does not.
    add(
        "due_on_the_close_with_no_poll_after",
        [call(OPEN), call(SUBMIT, byte_count=64), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=64, cycle=1), react(CLOSE)],
    )

    # Out of order driven by cycle time instead of by poll selection. The poll-selected version above
    # reaches it on the software arm alone: with every transfer due at once the interrupt drains in
    # channel order and hands back the submission order, so that row proves nothing on that arm. Here
    # channel 1 is submitted first and takes longer, so both arms must report 3 before 1.
    add(
        "the_shorter_transfer_finishes_first",
        [
            call(OPEN, channel=1),
            call(OPEN, channel=3),
            call(SUBMIT, channel=1, byte_count=64),
            call(SUBMIT, channel=3, byte_count=64),
            call(POLL, channel=EVERY_CHANNEL),
            call(POLL, channel=EVERY_CHANNEL),
            call(POLL, channel=EVERY_CHANNEL),
        ],
        [
            react(OPEN),
            react(OPEN),
            react(SUBMIT, when=WHEN_DUE, completions=1, moved=64, cycle=4),
            react(SUBMIT, when=WHEN_DUE, completions=1, moved=64, cycle=0),
            react(POLL, channel=EVERY_CHANNEL),
            react(POLL, channel=EVERY_CHANNEL),
            react(POLL, channel=EVERY_CHANNEL),
        ],
    )

    # Polled before the cycle elapsed. A busy timer says not yet and the completion stays held.
    add(
        "polled_before_the_cycle_elapsed",
        [call(OPEN), call(SUBMIT, byte_count=64), call(POLL), call(CLOSE)],
        [react(OPEN), react(SUBMIT, when=WHEN_DUE, completions=1, moved=64, cycle=8), react(POLL), react(CLOSE)],
    )

    return out


HEADER = """/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file praet_scenarios.h
 * @brief Correctness scenarios for the scripted DMA engine, and the outcome each one must produce.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @warning Generated by tools/dev_env/gen_praet_scenarios.py. An edit here is discarded the next
 *          time that runs.
 * @note Each scenario appears twice, once per arm. The fixture is identical and only the arm
 *       differs, so a row that disagrees between the two is the arm and nothing else.
 * @note The expectations are computed by the generator, walking each program against its script.
 *       Nothing in C derives them.
 * @note The first entry is the control. It must come out clean, and if it does not, no other row in
 *       this table can be read.
 */
#ifndef MMGR_TEST_PRAET_SCENARIOS_H
#define MMGR_TEST_PRAET_SCENARIOS_H

#include "praet_engine.h"

EMBED_BEGIN_DECLS
"""

FOOTER = """
EMBED_END_DECLS

#endif
"""


def emit(rows, corrupt=None):
    """The generated header text for @p rows, each emitted once per arm.

    @p corrupt names a scenario whose completion expectation is emitted one too high. That is the
    negative control: a suite that has only ever reported clean has not been shown to tell a passing
    column from a failing one, and both of this project's false results came from exactly that gap.
    The control row still passes in that build, so one run proves both halves.
    """
    parts = [HEADER]

    for name, program, script in rows:
        parts.append("\n/** @brief Calls the %s case makes. */\n" % name)
        parts.append("static const PraetProgramStep praet_program_%s[] = {\n" % name)
        for made in program:
            parts.append("    {%du, %du, %du},\n" % (made["call"], made["channel"], made["bytes"]))
        parts.append("};\n")

        parts.append("\n/** @brief Engine script for the %s case. */\n" % name)
        parts.append("static const PraetEngineStep praet_steps_%s[] = {\n" % name)
        for answer in script:
            parts.append(
                "    {%du, %du, %du, %du, %du, %du, %du, %du, %du},\n"
                % (
                    answer["hook"],
                    answer["channel"],
                    answer["accepted"],
                    answer["when"],
                    answer["completions"],
                    answer["moved"],
                    answer["settle"],
                    answer["cycle"],
                    answer["progress"],
                )
            )
        parts.append("};\n")

        for arm in (INTERRUPT, SOFTWARE):
            found = oracle(program, script, arm)
            label = "%s_%s" % (name, ARM_NAMES[arm])
            parts.append("\n/** @brief Channels the %s completions must arrive on, in order. */\n" % label)
            if found["order"]:
                parts.append(
                    "static const uint8_t praet_order_%s[] = {%s};\n"
                    % (label, ", ".join("%du" % channel for channel in found["order"]))
                )
            else:
                parts.append("static const uint8_t praet_order_%s[1] = {0u};\n" % label)

    parts.append("\n/**\n")
    parts.append(" * @brief Every correctness scenario, on both arms, control first.\n")
    parts.append(" *\n")
    parts.append(" * @note One row per scenario per arm, each carrying its program, its script, and the\n")
    parts.append(" *       outcome the two must produce together. The suite walks this table in order.\n")
    parts.append(" */\n")
    parts.append("static const PraetScenario praet_scenarios[] = {\n")

    for name, program, script in rows:
        for arm in (INTERRUPT, SOFTWARE):
            found = oracle(program, script, arm)
            label = "%s_%s" % (name, ARM_NAMES[arm])
            completions = len(found["order"])
            if label == corrupt:
                completions += 1
            parts.append("    {\n")
            parts.append('        "%s",\n' % label)
            parts.append("        %du,\n" % arm)
            parts.append("        praet_program_%s,\n" % name)
            parts.append("        %du,\n" % len(program))
            parts.append("        praet_steps_%s,\n" % name)
            parts.append("        %du,\n" % len(script))
            parts.append("        %du,\n" % found["opens"])
            parts.append("        %du,\n" % found["submits"])
            parts.append("        %du,\n" % completions)
            parts.append("        %duL,\n" % found["moved"])
            parts.append("        %du,\n" % found["settling"])
            parts.append("        %du,\n" % found["held"])
            parts.append("        praet_order_%s,\n" % label)
            parts.append("        %du,\n" % len(found["order"]))
            parts.append("    },\n")

    parts.append("};\n")
    parts.append(FOOTER)
    return "".join(parts)


def main():
    rows = scenarios()
    corrupt = None
    argv = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    if "--negative-control" in sys.argv[1:]:
        # The last row, so the control and every row above it still pass and the run shows both halves
        corrupt = "%s_%s" % (rows[-1][0], ARM_NAMES[SOFTWARE])
    text = emit(rows, corrupt)
    out = argv[0] if argv else DEFAULT_OUT
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)

    print("wrote %s, %d scenarios on %d arms" % (os.path.relpath(out, ROOT).replace("\\", "/"), len(rows),
                                                 len(ARM_NAMES)))
    if corrupt is not None:
        print("  NEGATIVE CONTROL: %s carries a completion expectation one too high" % corrupt)

    differ = 0
    for name, program, script in rows:
        shown = [oracle(program, script, arm) for arm in (INTERRUPT, SOFTWARE)]
        if shown[0] != shown[1]:
            differ += 1
    print("  %d of %d scenarios come out differently on the two arms" % (differ, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
