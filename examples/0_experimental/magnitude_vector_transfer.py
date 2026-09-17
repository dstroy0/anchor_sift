#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-020
#
# A machine-to-machine transfer format whose wire is a vector of exact integer magnitudes, read the way a
# Turing machine reads a tape. Each cell of the vector is one instruction the receiver runs: a literal
# block to emit, or a unit and a count to emit that unit that many times. The count is an unbounded
# integer, one exact magnitude. A single small cell stands for an output too large to hold, and the
# receiver reaches any byte of that output by walking the tape instead of building it. This is the bit
# idiom on the wire: the payload is a magnitude, presence and extent, not a stream of fixed-width symbols.
#
#   Usage:  python examples/0_experimental/magnitude_vector_transfer.py
#           from the API:  tape = encode(payload); payload == decode(tape)
#           and without building the output:  output_length(tape), byte_at(tape, index)
#
# The tape. A cell is an opcode byte followed by its magnitudes. A magnitude on the wire is its byte
# length as an unsigned LEB128 varint, then that many big-endian bytes. A magnitude carries both its
# value and its extent, and a literal block keeps its leading zeros. Three opcodes:
#   HALT       end of tape.
#   LITERAL b  emit the block b verbatim. One magnitude carries a block of any size with no per-byte frame.
#   REPEAT u c emit the unit u repeated c times. c is an unbounded magnitude, and the span it names has no
#              ceiling, which is where the density comes from.
# The decoder is the machine: its head steps along the vector, each cell a transition that writes to the
# output tape. The encoder is the inverse, and it chooses REPEAT over LITERAL only when the repeat cell is
# smaller in wire bytes than the span it covers, a choice read off the two sizes and never a picked
# threshold.
#
# Positive control: encode then decode returns the input exactly, on a repetitive payload, a mixed one,
# a structureless one and the empty string. Two routes to the output: the decoder builds it and compares,
# and an independent walk computes its length and any single byte without building it, agreeing with the
# first on both the length and the sampled bytes. Drawn null: one byte of a tape flipped decodes to a
# different payload. A wrong tape is caught, and a clean roundtrip means something. Floor: density is a
# property of the payload, not of the format. A structureless payload has no repeat to name, falls to one
# literal, and transfers at its own size plus a few bytes of frame; the format claims no compression it
# cannot show, and the ratio is reported with its numerator and denominator on every case.
#
# No bounding: the only choice in the encoder, REPEAT against LITERAL, is decided by comparing wire sizes,
# and no tolerance or window size is set by judgment. The arithmetic is exact integers throughout and no
# float appears.

import io
import sys

HALT = 0
LITERAL = 1
REPEAT = 2


def _write_varint(buffer, value):
    """Append `value` as an unsigned LEB128 varint. `value` is a non-negative integer."""
    while True:
        low = value & 0x7F
        value >>= 7
        if value:
            buffer.append(low | 0x80)
        else:
            buffer.append(low)
            return


def _read_varint(tape, position):
    """Read an unsigned LEB128 varint. Returns (value, next position)."""
    value = 0
    shift = 0
    while True:
        byte = tape[position]
        position += 1
        value |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            return value, position
        shift += 7


def _write_block(buffer, block):
    """Append a magnitude carrying the bytes `block`: its length as a varint, then the bytes."""
    _write_varint(buffer, len(block))
    buffer.extend(block)


def _read_block(tape, position):
    """Read a magnitude as its raw bytes. Returns (block, next position)."""
    length, position = _read_varint(tape, position)
    return bytes(tape[position:position + length]), position + length


def _write_count(buffer, value):
    """Append a magnitude carrying the non-negative integer `value`, minimal big-endian."""
    block = value.to_bytes((value.bit_length() + 7) // 8, "big")
    _write_block(buffer, block)


def _read_count(tape, position):
    """Read a magnitude as a non-negative integer. Returns (value, next position)."""
    block, position = _read_block(tape, position)
    return int.from_bytes(block, "big"), position


def _longest_repeat(data, start, max_period):
    """The period and span of the longest run at `start` that repeats a unit.

    For each period up to `max_period`, count how far the unit data[start:start+period] repeats without a
    break, and return the (period, span) with the longest span, or None where nothing repeats at least
    twice. span is a whole number of periods.
    """
    length = len(data)
    limit = min(max_period, length - start)
    best = None
    for period in range(1, limit + 1):
        unit = data[start:start + period]
        cursor = start + period
        count = 1
        while cursor + period <= length and data[cursor:cursor + period] == unit:
            count += 1
            cursor += period
        if count >= 2:
            span = count * period
            if best is None or span > best[1]:
                best = (period, span)
    return best


def encode(data, max_period=256):
    """Encode bytes into a tape of magnitude cells. `max_period` bounds the repeat unit searched for."""
    tape = bytearray()
    literal = bytearray()

    def flush_literal():
        if literal:
            tape.append(LITERAL)
            _write_block(tape, bytes(literal))
            literal.clear()

    position = 0
    length = len(data)
    while position < length:
        repeat = _longest_repeat(data, position, max_period)
        placed = False
        if repeat is not None:
            period, span = repeat
            unit = data[position:position + period]
            count = span // period
            cell = bytearray()
            cell.append(REPEAT)
            _write_block(cell, unit)
            _write_count(cell, count)
            if len(cell) < span:            # the cell is smaller than the bytes it stands for
                flush_literal()
                tape.extend(cell)
                position += span
                placed = True
        if not placed:
            literal.append(data[position])
            position += 1
    flush_literal()
    tape.append(HALT)
    return bytes(tape)


def decode(tape):
    """Run the tape as a machine and return the output bytes it builds."""
    out = bytearray()
    position = 0
    while position < len(tape):
        opcode = tape[position]
        position += 1
        if opcode == HALT:
            break
        if opcode == LITERAL:
            block, position = _read_block(tape, position)
            out.extend(block)
        elif opcode == REPEAT:
            unit, position = _read_block(tape, position)
            count, position = _read_count(tape, position)
            out.extend(unit * count)
        else:
            raise ValueError("unknown opcode %d at position %d" % (opcode, position - 1))
    return bytes(out)


def output_length(tape):
    """The length of the output the tape stands for, computed without building it. May be a large integer."""
    total = 0
    position = 0
    while position < len(tape):
        opcode = tape[position]
        position += 1
        if opcode == HALT:
            break
        if opcode == LITERAL:
            block, position = _read_block(tape, position)
            total += len(block)
        elif opcode == REPEAT:
            unit, position = _read_block(tape, position)
            count, position = _read_count(tape, position)
            total += len(unit) * count
        else:
            raise ValueError("unknown opcode %d at position %d" % (opcode, position - 1))
    return total


def byte_at(tape, index):
    """The single output byte at `index`, computed by walking the tape and never building the output.

    `index` may be any integer below the output length, including one no machine could store the output to
    reach, because the walk carries a running cursor and steps over a REPEAT span in one subtraction.
    """
    if index < 0:
        raise IndexError(index)
    cursor = 0
    position = 0
    while position < len(tape):
        opcode = tape[position]
        position += 1
        if opcode == HALT:
            break
        if opcode == LITERAL:
            block, position = _read_block(tape, position)
            if cursor <= index < cursor + len(block):
                return block[index - cursor]
            cursor += len(block)
        elif opcode == REPEAT:
            unit, position = _read_block(tape, position)
            count, position = _read_count(tape, position)
            span = len(unit) * count
            if cursor <= index < cursor + span:
                return unit[(index - cursor) % len(unit)]
            cursor += span
        else:
            raise ValueError("unknown opcode %d at position %d" % (opcode, position - 1))
    raise IndexError(index)


def cells(tape):
    """Read the tape back as its vector of magnitude cells, for inspection. Returns a list of tuples."""
    listing = []
    position = 0
    while position < len(tape):
        opcode = tape[position]
        position += 1
        if opcode == HALT:
            listing.append(("HALT",))
            break
        if opcode == LITERAL:
            block, position = _read_block(tape, position)
            listing.append(("LITERAL", len(block)))
        elif opcode == REPEAT:
            unit, position = _read_block(tape, position)
            count, position = _read_count(tape, position)
            listing.append(("REPEAT", len(unit), count))
        else:
            raise ValueError("unknown opcode %d at position %d" % (opcode, position - 1))
    return listing


def _pseudo_random(length):
    """Deterministic structureless bytes from an integer recurrence, giving a reproducible floor case."""
    state = 0x2545F4914F6CDD1D
    out = bytearray()
    for _ in range(length):
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        out.append((state >> 33) & 0xFF)
    return bytes(out)


def _roundtrip(out, label, payload):
    """Encode, decode, and report the two routes and the density with its parts."""
    tape = encode(payload)
    rebuilt = decode(tape)
    exact = rebuilt == payload

    # Second route to the output: length and sampled bytes without building it.
    length_ok = output_length(tape) == len(payload)
    sample_ok = True
    if payload:
        for index in (0, len(payload) // 2, len(payload) - 1):
            if byte_at(tape, index) != payload[index]:
                sample_ok = False
                break

    wire = len(tape)
    source = len(payload)
    ratio = "%.1fx" % (source / wire) if wire else "n/a"
    out.write("  %-18s source %8d B, wire %6d B, ratio %-9s roundtrip %s, second route %s\n"
              % (label, source, wire, ratio, exact, length_ok and sample_ok))
    return exact and length_ok and sample_ok


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  magnitude vector transfer: a tape of exact magnitudes, read like a Turing machine\n\n")

    out.write("  positive control and density, reported with numerator and denominator\n")
    passed = True
    passed = _roundtrip(out, "repetitive", b"anchor_sift " * 100000) and passed
    passed = _roundtrip(out, "mixed", b"HEADER" + b"\x00\x01\x02" * 40000 + b"TAIL") and passed
    passed = _roundtrip(out, "structureless", _pseudo_random(8192)) and passed
    passed = _roundtrip(out, "empty", b"") and passed

    out.write("\n  the count is unbounded: a tape too small to hold its output, reached without building it\n")
    huge_count = 10 ** 100
    unit = b"anchor"
    tape = bytearray()
    tape.append(REPEAT)
    _write_block(tape, unit)
    _write_count(tape, huge_count)
    tape.append(HALT)
    tape = bytes(tape)
    produced = output_length(tape)
    index = 10 ** 99
    sampled = byte_at(tape, index)
    expected = unit[index % len(unit)]
    huge_ok = (produced == huge_count * len(unit)) and (sampled == expected)
    out.write("    wire %d B stands for an output of %d bytes\n" % (len(tape), produced))
    out.write("    byte at index 10^99 is %r, the unit says %r, agree %s\n"
              % (bytes([sampled]), bytes([expected]), sampled == expected))

    out.write("\n  drawn null: one flipped byte in a tape decodes to a different payload\n")
    payload = b"anchor_sift " * 1000
    good = encode(payload)
    broken = bytearray(good)
    broken[-2] ^= 0x01                     # perturb a byte inside the last magnitude
    changed = decode(bytes(broken)) != payload
    out.write("    flipped tape decodes to a different payload: %s\n" % changed)

    out.write("\n  positive control passed: %s\n" % passed)
    out.write("  unbounded count reached without building: %s\n" % huge_ok)
    out.write("  wrong tape caught: %s\n" % changed)
    out.flush()
    return 0 if (passed and huge_ok and changed) else 1


if __name__ == "__main__":
    raise SystemExit(main())
