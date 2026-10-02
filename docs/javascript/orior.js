// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The name on the landing page pours together out of liquid. One filter does it: moving noise
// pushes the name apart, a soft spread copy of it is cut at a hard edge and the pieces read as
// drops that run together, and the cut copy gives way to the name itself. Every term falls to zero
// over the run and the filter comes off at the end, which leaves the name exactly as the page draws
// it.
//
// The line beside the name waits as a pile of its own letters. While the name is still settling, a
// beam leaves the name and runs through the line, and each letter leaves the pile for its place as
// the beam reaches that place. At the end the line is set back to plain text.
//
// The two runs overlap: the beam starts before the pour ends, by an amount drawn at random on each
// load between ORIOR_OVERLAP_MIN_MS and ORIOR_OVERLAP_MAX_MS.
//
// Where the reader asks for reduced motion, or this file does not run, both are drawn plain.

const ORIOR_FLUID_MS = 2600;
const ORIOR_OVERLAP_MIN_MS = 450;
const ORIOR_OVERLAP_MAX_MS = 950;
const ORIOR_BEAM_MS = 650;
const ORIOR_PART_MS = 520;
const ORIOR_SVG = "http://www.w3.org/2000/svg";

function oriorFluidFilter() {
  const found = document.getElementById("orior-fluid");
  if (found) {
    return found.oriorParts;
  }
  const make = (name, attrs, parent) => {
    const node = document.createElementNS(ORIOR_SVG, name);
    for (const [key, value] of Object.entries(attrs)) {
      node.setAttribute(key, value);
    }
    parent.appendChild(node);
    return node;
  };
  const svg = make("svg", { width: "0", height: "0", "aria-hidden": "true", focusable: "false" }, document.body);
  svg.style.position = "absolute";
  const filter = make("filter", {
    id: "orior-fluid",
    x: "-30%", y: "-80%", width: "160%", height: "260%",
    "color-interpolation-filters": "sRGB"
  }, svg);
  const parts = {
    noise: make("feTurbulence", { type: "fractalNoise", baseFrequency: "0.02 0.05", numOctaves: "2", result: "noise" }, filter),
    warp: make("feDisplacementMap", {
      in: "SourceGraphic", in2: "noise", scale: "0", xChannelSelector: "R", yChannelSelector: "G", result: "warp"
    }, filter),
    blur: make("feGaussianBlur", { in: "warp", stdDeviation: "0", result: "blur" }, filter),
    cut: make("feColorMatrix", {
      in: "blur", type: "matrix", values: "1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 20 -8", result: "drops"
    }, filter),
    mix: make("feComposite", { in: "drops", in2: "SourceGraphic", operator: "arithmetic", k1: "0", k2: "1", k3: "0", k4: "0" }, filter)
  };
  filter.oriorParts = parts;
  return parts;
}

function oriorPour(name, done) {
  const parts = oriorFluidFilter();
  parts.noise.setAttribute("seed", String(Math.floor(Math.random() * 1000)));
  name.style.filter = "url(#orior-fluid)";
  name.style.opacity = "0";
  const overlap = ORIOR_OVERLAP_MIN_MS + Math.random() * (ORIOR_OVERLAP_MAX_MS - ORIOR_OVERLAP_MIN_MS);
  const handoff = ORIOR_FLUID_MS - overlap;
  let handed = false;
  let start = null;
  const frame = (now) => {
    if (start === null) {
      start = now;
    }
    if (!handed && now - start >= handoff) {
      handed = true;
      done();
    }
    const t = Math.min((now - start) / ORIOR_FLUID_MS, 1);
    const left = Math.pow(1 - t, 2);
    const drops = t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3;
    parts.noise.setAttribute("baseFrequency", `${(0.006 + 0.02 * left).toFixed(4)} ${(0.015 + 0.05 * left).toFixed(4)}`);
    parts.warp.setAttribute("scale", (110 * left).toFixed(2));
    parts.blur.setAttribute("stdDeviation", (9 * left).toFixed(2));
    parts.mix.setAttribute("k2", drops.toFixed(3));
    parts.mix.setAttribute("k3", (1 - drops).toFixed(3));
    name.style.opacity = Math.min(t / 0.15, 1).toFixed(3);
    if (t < 1) {
      requestAnimationFrame(frame);
    } else {
      name.style.filter = "";
      name.style.opacity = "";
    }
  };
  requestAnimationFrame(frame);
}

// Split the line into one box per letter and pile the letters in rows that narrow toward the top,
// each turned at random. The place of a letter in the line is where its box sits, and the pile is an
// offset from it: taking the offset away puts the letter home.
function oriorPile(line) {
  const text = line.textContent;
  line.setAttribute("aria-label", text);
  line.textContent = "";
  const letters = [];
  for (const ch of text) {
    const box = document.createElement("span");
    box.className = "orior-part";
    box.setAttribute("aria-hidden", "true");
    box.textContent = ch === " " ? " " : ch;
    line.appendChild(box);
    if (ch !== " ") {
      letters.push(box);
    }
  }
  const em = parseFloat(getComputedStyle(line).fontSize);
  const lineBox = line.getBoundingClientRect();
  const heapX = lineBox.left + lineBox.width * 0.5;
  const order = letters.map((box, i) => [Math.random(), i]).sort((a, b) => a[0] - b[0]).map(([, i]) => i);
  let row = 0;
  let width = Math.max(4, Math.ceil(letters.length * 0.4));
  let seat = 0;
  for (const i of order) {
    if (seat === width) {
      row += 1;
      seat = 0;
      width = Math.max(1, width - 3);
    }
    const box = letters[i];
    const home = box.getBoundingClientRect();
    box.oriorHomeX = home.left + home.width / 2;
    const x = heapX + (seat - (width - 1) / 2) * em * 0.42 + (Math.random() - 0.5) * em * 0.2;
    const y = lineBox.top + lineBox.height * 0.5 - row * em * 0.48;
    const dx = x - (home.left + home.width / 2);
    const dy = y - (home.top + home.height / 2);
    const turn = (Math.random() - 0.5) * 140;
    box.oriorHeap = `translate(${dx.toFixed(1)}px, ${dy.toFixed(1)}px) rotate(${turn.toFixed(0)}deg)`;
    box.style.transform = box.oriorHeap;
    box.style.opacity = "0.55";
    seat += 1;
  }
  return { line, text, letters };
}

// The beam starts at the right edge of the name, or at the start of the line where the line has
// wrapped under the name, and runs at a constant speed to the end of the line. A letter leaves the
// pile at the moment the head of the beam crosses the middle of its place.
function oriorAssemble(name, pile) {
  const { line, text, letters } = pile;
  const title = line.parentElement;
  const titleBox = title.getBoundingClientRect();
  const nameBox = name.getBoundingClientRect();
  const lineBox = line.getBoundingClientRect();
  const wrapped = lineBox.top >= nameBox.bottom - 2;
  const from = wrapped ? lineBox.left : nameBox.right;
  const to = lineBox.right + 24;
  const beam = document.createElement("div");
  beam.className = "orior-beam";
  beam.style.left = `${(from - titleBox.left).toFixed(1)}px`;
  beam.style.top = `${(lineBox.top + lineBox.height * 0.55 - titleBox.top).toFixed(1)}px`;
  beam.style.width = `${(to - from).toFixed(1)}px`;
  title.appendChild(beam);
  beam.animate(
    [
      { transform: "scaleX(0)", opacity: 1 },
      { transform: "scaleX(1)", opacity: 1, offset: 0.75 },
      { transform: "scaleX(1)", opacity: 0 }
    ],
    { duration: ORIOR_BEAM_MS / 0.75, easing: "linear", fill: "forwards" }
  );
  const ink = getComputedStyle(line).color;
  let last = 0;
  for (const box of letters) {
    const across = (box.oriorHomeX - from) / (to - from);
    const delay = Math.max(0, Math.min(1, across)) * ORIOR_BEAM_MS;
    last = Math.max(last, delay);
    box.animate(
      [
        { transform: box.oriorHeap, opacity: 0.55, color: ink, textShadow: "0 0 0 rgba(94, 234, 212, 0)" },
        { color: "#5eead4", textShadow: "0 0 0.6em rgba(94, 234, 212, 0.8)", opacity: 1, offset: 0.2 },
        { transform: "translate(0, 0) rotate(0deg)", opacity: 1, color: ink, textShadow: "0 0 0 rgba(94, 234, 212, 0)" }
      ],
      { duration: ORIOR_PART_MS, delay, easing: "cubic-bezier(0.2, 1.3, 0.4, 1)", fill: "both" }
    );
  }
  window.setTimeout(() => {
    line.textContent = text;
    line.removeAttribute("aria-label");
    beam.remove();
  }, Math.max(last + ORIOR_PART_MS, ORIOR_BEAM_MS / 0.75) + 50);
}

document$.subscribe(() => {
  const name = document.querySelector(".orior-title h1");
  if (!name || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return;
  }
  const line = document.querySelector(".orior-title .orior-lede");
  const pile = line ? oriorPile(line) : null;
  oriorPour(name, () => {
    if (pile) {
      oriorAssemble(name, pile);
    }
  });
});
