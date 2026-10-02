// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// A field on the sphere, as real spherical harmonics. The basis is orthonormal over the sphere, in the storage order
// sphere_field uses: degree d starts at d*d, order zero sits at d*d + d, cosine orders above it and sine orders below.
// A seed gives the same coefficients every time, each degree's power falling as one over (d + 1).

EV.FOUR_PI = 4 * Math.PI;

// The normalized associated Legendre values of one order at x = cos(colatitude), every degree from the order to top.
EV.legendreColumn = (top, order, x) => {
  const out = new Float64Array(top + 1);
  const sine = Math.sqrt(Math.max(0, 1 - x * x));
  let value = Math.sqrt(1 / EV.FOUR_PI);
  for (let step = 1; step <= order; step++) {
    value *= Math.sqrt((2 * step + 1) / (2 * step)) * sine;
  }
  if (order <= top) {
    out[order] = value;
  }
  if (order + 1 <= top) {
    out[order + 1] = Math.sqrt(2 * order + 3) * x * value;
  }
  for (let degree = order + 2; degree <= top; degree++) {
    const lead = Math.sqrt((4 * degree * degree - 1) / (degree * degree - order * order));
    const trail = Math.sqrt(((degree - 1) * (degree - 1) - order * order) / (4 * (degree - 1) * (degree - 1) - 1));
    out[degree] = lead * (x * out[degree - 1] - trail * out[degree - 2]);
  }
  return out;
};

// Every real harmonic at one direction, flat, in the storage order above.
EV.harmonicsAt = (top, colatitude, longitude) => {
  const out = new Float64Array((top + 1) * (top + 1));
  const x = Math.cos(colatitude);
  for (let order = 0; order <= top; order++) {
    const column = EV.legendreColumn(top, order, x);
    if (order === 0) {
      for (let degree = 0; degree <= top; degree++) {
        out[degree * degree + degree] = column[degree];
      }
      continue;
    }
    const cosine = Math.cos(order * longitude) * Math.SQRT2;
    const sine = Math.sin(order * longitude) * Math.SQRT2;
    for (let degree = order; degree <= top; degree++) {
      out[degree * degree + degree + order] = column[degree] * cosine;
      out[degree * degree + degree - order] = column[degree] * sine;
    }
  }
  return out;
};

// Coefficients from a seed: a 32-bit xorshift, each coefficient uniform in -1 to 1 and scaled by 1 / (d + 1).
// Degree zero carries nothing, and the field sums to zero over the sphere.
EV.fieldCoefficients = (top, seed) => {
  let state = (seed >>> 0) || 1;
  const next = () => {
    state ^= state << 13;
    state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5;
    state >>>= 0;
    return state / 4294967296;
  };
  const out = new Float64Array((top + 1) * (top + 1));
  for (let degree = 1; degree <= top; degree++) {
    for (let at = degree * degree; at < (degree + 1) * (degree + 1); at++) {
      out[at] = (next() * 2 - 1) / (degree + 1);
    }
  }
  return out;
};

// The field's value in one direction.
EV.fieldAt = (coefficients, top, colatitude, longitude) => {
  const basis = EV.harmonicsAt(top, colatitude, longitude);
  let sum = 0;
  for (let at = 0; at < basis.length; at++) {
    sum += coefficients[at] * basis[at];
  }
  return sum;
};
