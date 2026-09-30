// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DIVIDE_H
#define DIVIDE_H

// S7's divisions, beside each sample's .links as <sample>.divide. Every word is little-endian.
//
// .divide opens with frames, depth, height and width, which are the .points' and the .links', and then the CRC-64 of
// the whole .links it was made from, its low word first. engine/codecs/crc/crc.h computes that CRC (CRC-64/XZ:
// the reflected polynomial 0xC96C5795D7870F42, starting from all ones and ending complemented), taken over every byte
// of the file. Each frame pair (t, t + 1) follows, in order: its count of divisions, and then each division's four
// words:
//   the parent, a point of frame t;
//   daughter one, the parent's chosen link into t + 1 as the sort chose it;
//   daughter two, another point of t + 1;
//   the point of frame t whose chosen link went to daughter two, or DIVIDE_NONE when daughter two was a start.
// A division is a link moved: the parent keeps daughter one and takes daughter two as its second link, and the point
// daughter two leaves loses its link and ends at t. The divisions of a pair come in their parents' order, each parent
// once. No division takes daughter two from a point that divides. Each point keeps at most one link in (O20), and
// only a parent has two out
#define DIVIDE_HEADER_WORDS 6u

#define DIVIDE_WORDS 4u

#define DIVIDE_NONE 0xFFFFFFFFu

#endif
