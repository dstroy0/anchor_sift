// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Angles are held in sixteenths of a degree and turned through the integer sine table.

// sin of an angle in sixteenths of a degree, scaled by 2^14, interpolated between whole-degree table entries.
EV.sine16 = (angle) => {
  const whole = ((angle % 5760) + 5760) % 5760;
  const at = (degree) => {
    const d = ((degree % 360) + 360) % 360;
    const table = EV.SINE_DEGREES;
    return d <= 90 ? table[d] : d <= 180 ? table[180 - d] : d <= 270 ? -table[d - 180] : -table[360 - d];
  };
  const degree = whole >> 4;
  const low = at(degree);
  return low + (((at(degree + 1) - low) * (whole & 15)) >> 4);
};
EV.cosine16 = (angle) => EV.sine16(angle + 1440);

// One ease step of an integer toward its target: a quarter of the way, at least one unit.
EV.approach = (value, target) => {
  const gap = target - value;
  const step = gap >> 2;
  return value + (step !== 0 ? step : Math.sign(gap));
};
