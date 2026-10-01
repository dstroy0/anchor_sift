// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Two orders that lay a line of cells into a square, each cell's index to its (x, y): Hilbert's, which keeps
// neighbors in the line neighbors in the square, and Morton's, which interleaves the index's bits.

/** Hilbert's curve, index to point. Its locality is the reason binary files are read this way:
  bytes near each other in the file stay near each other on the surface. Cortesi 2011. */
EV.hilbertAt = (side, index) => {
  let x = 0,
    y = 0,
    rx,
    ry,
    t = index,
    s;
  for (s = 1; s < side; s *= 2) {
    rx = 1 & Math.floor(t / 2);
    ry = 1 & (t ^ rx);
    if (ry === 0) {
      if (rx === 1) {
        x = s - 1 - x;
        y = s - 1 - y;
      }
      let swap = x;
      x = y;
      y = swap;
    }
    x += s * rx;
    y += s * ry;
    t = Math.floor(t / 4);
  }
  return [x, y];
};

/** Morton's order, the cheap alternative: interleave the bits. Kept beside Hilbert because the
  difference between them on the same data is the value of locality. */
EV.mortonAt = (index) => {
  let x = 0,
    y = 0,
    bit = 0,
    t = index;
  while (t > 0) {
    x |= (t & 1) << bit;
    t = Math.floor(t / 2);
    y |= (t & 1) << bit;
    t = Math.floor(t / 2);
    bit += 1;
  }
  return [x, y];
};
