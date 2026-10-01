// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Every setting has a kind and a range, held in EV.VIEW_SCHEME by name. Applying a view is partial: names
// it does not carry keep their values. A name the scheme does not have, a fraction, a value of the wrong kind
// or one outside its range is reported by name and not applied.

EV.defaultView = () => {
  const view = {};
  for (const [name, rule] of Object.entries(EV.VIEW_SCHEME)) {
    view[name] = Array.isArray(rule.fallback) ? rule.fallback.map((one) => (one && typeof one === "object" ? { ...one } : one)) : rule.fallback;
  }
  return view;
};

// Checks one value against its rule; returns the reason it errors, or null.
EV.errorValue = (rule, value) => {
  const integer = (one) => Number.isInteger(one) && one >= rule.low && one <= rule.high;
  if (rule.kind === "integer") {
    return integer(value) ? null : `an integer from ${rule.low} to ${rule.high}`;
  }
  if (rule.kind === "switch") {
    return typeof value === "boolean" ? null : "true or false";
  }
  if (rule.kind === "word") {
    return rule.words.includes(value) ? null : `one of ${rule.words.join(", ")}`;
  }
  if (rule.kind === "words") {
    return Array.isArray(value) && value.every((one) => rule.words.includes(one)) ? null : `a list of ${rule.words.join(", ")}`;
  }
  if (rule.kind === "lights") {
    const light = (one) => one && typeof one === "object" && Object.keys(one).every((key) => ["turn", "tilt", "strength"].includes(key))
      && Number.isInteger(one.turn) && one.turn >= 0 && one.turn <= 359
      && Number.isInteger(one.tilt) && one.tilt >= -89 && one.tilt <= 89
      && Number.isInteger(one.strength) && one.strength >= 0 && one.strength <= 255;
    return Array.isArray(value) && value.length <= 4 && value.every(light)
      ? null : "up to four lights, each turn 0 to 359, tilt -89 to 89 and strength 0 to 255, in degrees and 255ths";
  }
  return Array.isArray(value) && value.every(integer) ? null : "a list of cell numbers";
};

// Applies a view section over a view. Returns what was applied and what errored, by name.
EV.applyView = (view, section) => {
  const applied = [];
  const error = [];
  if (!section || typeof section !== "object" || Array.isArray(section)) {
    return { applied, error: ["view: an object of name to value"] };
  }
  for (const [name, value] of Object.entries(section)) {
    const rule = EV.VIEW_SCHEME[name];
    if (!rule) {
      error.push(`${name}: the view has no such setting`);
      continue;
    }
    const reason = EV.errorValue(rule, value);
    if (reason) {
      error.push(`${name}: ${reason}`);
      continue;
    }
    view[name] = Array.isArray(value) ? value.map((one) => (one && typeof one === "object" ? { ...one } : one)) : value;
    applied.push(name);
  }
  return { applied, error };
};
