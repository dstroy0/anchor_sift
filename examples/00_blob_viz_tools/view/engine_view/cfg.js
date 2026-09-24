// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The view section of a .cfg: every setting the page has, by the name the .cfg uses, with its kind and its range.
// The tracker copies this section into each object untouched and the page opens in it. Applying a .cfg is partial:
// names it does not carry keep their values. A name the scheme does not have, a fraction, a value of the wrong kind
// or one outside its range is reported by name and not applied.

EV.VIEW_SCHEME = {
  face: { kind: "word", words: ["clinical", "machine"], fallback: "clinical" },
  frame: { kind: "integer", low: 0, high: 65535, fallback: 0 },
  ghosts: { kind: "integer", low: 0, high: 8, fallback: 0 },
  ghost_fade: { kind: "integer", low: 0, high: 224, fallback: 48 },
  turn: { kind: "integer", low: 0, high: 359, fallback: 30 },
  tilt: { kind: "integer", low: -89, high: 89, fallback: 35 },
  zoom: { kind: "integer", low: 0, high: 1024, fallback: 0 },
  pan_x: { kind: "integer", low: -1048576, high: 1048576, fallback: 0 },
  pan_y: { kind: "integer", low: -1048576, high: 1048576, fallback: 0 },
  z_scale: { kind: "integer", low: 2, high: 16, fallback: 8 },
  spread: { kind: "integer", low: 0, high: 2048, fallback: 0 },
  body: { kind: "word", words: ["smooth", "voxels", "centroids"], fallback: "smooth" },
  smooth_radius: { kind: "integer", low: 1, high: 8, fallback: 3 },
  smooth_opacity: { kind: "integer", low: 1, high: 255, fallback: 16 },
  walls: { kind: "switch", fallback: true },
  wall_tone: { kind: "integer", low: 0, high: 255, fallback: 110 },
  wall_opacity: { kind: "integer", low: 1, high: 255, fallback: 220 },
  slice_follow: { kind: "switch", fallback: true },
  map: { kind: "word", words: ["projection", "slice"], fallback: "projection" },
  palette: { kind: "word", words: ["lineage", "okabe_ito", "cell", "volume"], fallback: "okabe_ito" },
  min_voxels: { kind: "integer", low: 0, high: 65536, fallback: 0 },
  light: { kind: "switch", fallback: true },
  lights: { kind: "lights", fallback: [{ turn: 300, tilt: 50, strength: 210 }, { turn: 130, tilt: 20, strength: 90 }] },
  body_opacity: { kind: "integer", low: 0, high: 255, fallback: 160 },
  // Nothing of the microscope at 0, all of it at 255, and the two of them together anywhere between.
  slide: { kind: "integer", low: 0, high: 255, fallback: 0 },
  links: { kind: "switch", fallback: true },
  tracks: { kind: "switch", fallback: false },
  edges: { kind: "switch", fallback: true },
  correct: { kind: "switch", fallback: true },
  branched: { kind: "switch", fallback: true },
  wrong: { kind: "switch", fallback: true },
  no_link: { kind: "switch", fallback: true },
  only_chosen: { kind: "switch", fallback: false },
  glow: { kind: "switch", fallback: true },
  labels: { kind: "switch", fallback: true },
  ride: { kind: "switch", fallback: false },
  slice: { kind: "switch", fallback: true },
  slice_z: { kind: "integer", low: -1, high: 65535, fallback: -1 },
  window_low: { kind: "integer", low: 0, high: 65535, fallback: 0 },
  window_high: { kind: "integer", low: 1, high: 65535, fallback: 1024 },
  rate: { kind: "integer", low: 0, high: 60, fallback: 2 },
  step: { kind: "integer", low: 1, high: 64, fallback: 1 },
  loop: { kind: "switch", fallback: true },
  sheer: { kind: "integer", low: 20, high: 100, fallback: 90 },
  text_size: { kind: "integer", low: 80, high: 200, fallback: 100 },
  theme: { kind: "word", words: ["dark", "light"], fallback: "dark" },
  panels: { kind: "words", words: ["counts", "dims", "lineage", "legend", "review", "machine"], fallback: ["counts"] },
  chosen: { kind: "integers", low: 0, high: 4294967294, fallback: [] },
};

EV.defaultView = () => {
  const view = {};
  for (const [name, rule] of Object.entries(EV.VIEW_SCHEME)) {
    view[name] = Array.isArray(rule.fallback) ? rule.fallback.map((one) => (one && typeof one === "object" ? { ...one } : one)) : rule.fallback;
  }
  return view;
};

// Checks one value against its rule; returns the reason it is refused, or null.
EV.refuseValue = (rule, value) => {
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

// Applies a view section over a view. Returns what was applied and what was refused, by name.
EV.applyView = (view, section) => {
  const applied = [];
  const refused = [];
  if (!section || typeof section !== "object" || Array.isArray(section)) {
    return { applied, refused: ["view: an object of name to value"] };
  }
  for (const [name, value] of Object.entries(section)) {
    const rule = EV.VIEW_SCHEME[name];
    if (!rule) {
      refused.push(`${name}: the view has no such setting`);
      continue;
    }
    const reason = EV.refuseValue(rule, value);
    if (reason) {
      refused.push(`${name}: ${reason}`);
      continue;
    }
    view[name] = Array.isArray(value) ? value.map((one) => (one && typeof one === "object" ? { ...one } : one)) : value;
    applied.push(name);
  }
  return { applied, refused };
};

// The whole .cfg: the object's own sections as the tracker wrote them, with the page's view in place of its view.
EV.cfgText = (objectCfgText, view) => {
  let base = {};
  try {
    base = objectCfgText ? JSON.parse(objectCfgText) : {};
  } catch (error) {
    base = {};
  }
  const cfg = { scheme: "cell_tracking.cfg", version: 1, track: base.track || {}, input: base.input || {}, output: base.output || {}, view };
  return JSON.stringify(cfg, null, 2) + "\n";
};

// The specimen the input section names: species, voxel size z y x and membrane thickness, in picometers. An object
// written before the input section carried them reads as unknown, with a membrane of 0.
EV.specimen = (cfgText) => {
  let input = {};
  try {
    input = (JSON.parse(cfgText || "{}").input) || {};
  } catch (error) {
    input = {};
  }
  const whole = (value) => Number.isInteger(value) && value >= 0;
  const voxel = Array.isArray(input.voxel_pm) && input.voxel_pm.length === 3 && input.voxel_pm.every(whole) ? input.voxel_pm : [0, 0, 0];
  return {
    species: typeof input.species === "string" ? input.species : "",
    voxel_pm: voxel,
    membrane_pm: whole(input.membrane_pm) ? input.membrane_pm : 0,
  };
};

// Reads a .cfg's text for the page: checks the scheme, version and every section name, and hands back the view.
EV.parseCfg = (text) => {
  let cfg;
  try {
    cfg = JSON.parse(text);
  } catch (error) {
    return { refused: [`that is not JSON: ${error.message}`] };
  }
  if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) {
    return { refused: ["a .cfg is one object"] };
  }
  const refused = [];
  if (cfg.scheme !== undefined && cfg.scheme !== "cell_tracking.cfg") {
    refused.push("scheme: always cell_tracking.cfg");
  }
  if (cfg.version !== undefined && cfg.version !== 1) {
    refused.push("version: this page reads version 1");
  }
  for (const name of Object.keys(cfg)) {
    if (!["scheme", "version", "track", "input", "output", "view"].includes(name)) {
      refused.push(`${name}: a .cfg has scheme, version, track, input, output and view`);
    }
  }
  return { refused, view: cfg.view };
};
