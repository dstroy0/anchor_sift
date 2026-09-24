// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The panels, the labels and their leader lines, and the lines of text along the edges of the view. The clinical face
// names things in words; the machine face shows the integers the file holds.

EV.ease = (progress) => {
  const p = Math.min(progress, 4096);
  return (((p * p) >> 12) * (12288 - 2 * p)) >> 12;
};

// A cell's centroid on the screen, in CSS pixels, by the same integer steps the vertex stage takes.
EV.screenOf = (app, cell) => {
  const object = app.object;
  const header = object.header;
  const live = app.live;
  const zScale = app.view.z_scale;
  const frame = object.cellFrame[cell];
  const eased = EV.ease(app.progress);
  let x = object.centre[3 * cell];
  let y = object.centre[3 * cell + 1];
  let z = Math.trunc((zScale * (object.centre[3 * cell + 2] - header.depth)) / 2);
  const at = 8 * cell;
  if (frame === app.frame) {
    x += Math.trunc((object.motion[at] * eased) / 4096);
    y += Math.trunc((object.motion[at + 1] * eased) / 4096);
    z += Math.trunc((Math.trunc((object.motion[at + 2] * zScale) / 2) * eased) / 4096);
  }
  if (frame === app.frame + 1) {
    x -= Math.trunc((object.motion[at + 3] * (4096 - eased)) / 4096);
    y -= Math.trunc((object.motion[at + 4] * (4096 - eased)) / 4096);
    z -= Math.trunc((Math.trunc((object.motion[at + 5] * zScale) / 2) * (4096 - eased)) / 4096);
  }
  const yc = EV.cosine16(live.turn);
  const ys = EV.sine16(live.turn);
  const pc = EV.cosine16(live.tilt);
  const ps = EV.sine16(live.tilt);
  const x1 = (yc * x - ys * y) >> 14;
  const y1 = (ys * x + yc * y) >> 14;
  const z2 = (ps * y1 + pc * z) >> 14;
  const shift = (frame - app.frame) * live.spread - ((eased * live.spread) >> 12);
  const canvas = app.gpu.canvas;
  const ratio = window.devicePixelRatio || 1;
  const px = (canvas.width >> 1) + Math.floor(((x1 + shift) * live.zoom + live.panX) / 256);
  const py = (canvas.height >> 1) - Math.floor((z2 * live.zoom + live.panY) / 256);
  return [px / ratio, py / ratio];
};

EV.centroidText = (object, cell, places) => {
  const size = Math.max(object.cells[4 * cell], 1);
  return [1, 2, 3].map((axis) => EV.decimal(object.cells[4 * cell + axis], size, places)).join(", ");
};

EV.table = (element, rows) => {
  element.replaceChildren(...rows.map(([name, value, kind]) => {
    const row = document.createElement("tr");
    const left = document.createElement("td");
    const right = document.createElement("td");
    left.textContent = name;
    right.className = "num" + (kind ? ` ${kind}` : "");
    right.textContent = value;
    row.append(left, right);
    return row;
  }));
};

EV.clinical = () => document.documentElement.dataset.face === "clinical";

EV.paintCounts = (app) => {
  const object = app.object;
  const header = object.header;
  const frame = app.frame;
  const table = object.frames;
  const events = EV.frameEvents(object, frame);
  const status = [0, 0, 0, 0, 0];
  for (let edge = 0; edge < header.edge_total; edge += 1) {
    const source = object.edges[3 * edge];
    if (source !== EV.NONE && object.cellFrame[source] === frame) {
      status[Math.min(object.edges[3 * edge + 2], 4)] += 1;
    }
  }
  const control = header.aberrant_leaves + header.aberrant_voxels + header.wide_sums;
  const cells = table[10 * frame + 6];
  if (EV.clinical()) {
    EV.table(EV.$("countTable"), [
      ["frame", `${frame + 1} of ${header.frames}`],
      ["time point", EV.grouped(table[10 * frame])],
      ["cells found", EV.grouped(cells)],
      ["dividing", EV.grouped(events.divisions)],
      ["tracks ending", EV.grouped(events.ends)],
      ["tracks starting", EV.grouped(events.starts)],
      ["volume, voxels", EV.grouped(events.voxels)],
      ["answer key: correct", EV.grouped(status[0]), "good"],
      ["answer key: wrong", EV.grouped(status[2]), status[2] ? "bad" : ""],
      ["answer key: no link", EV.grouped(status[3]), status[3] ? "bad" : ""],
      ["data check", control ? "failed" : "passed", control ? "bad" : "good"],
    ]);
    return;
  }
  EV.table(EV.$("countTable"), [
    ["frame / t", `${frame} / ${table[10 * frame]}`],
    ["cells", EV.grouped(cells)],
    ["leaves", EV.grouped(table[10 * frame + 2])],
    ["runs", EV.grouped(table[10 * frame + 4])],
    ["voxels", EV.grouped(events.voxels)],
    ["links out", EV.grouped(table[10 * frame + 8])],
    ["divisions / ends / starts", `${events.divisions} / ${events.ends} / ${events.starts}`],
    ["edges c/b/w/n/m", status.join(" / ")],
    ["drawn instances", EV.grouped(app.drawn)],
    ["aberrant leaves", header.aberrant_leaves, header.aberrant_leaves ? "bad" : "good"],
    ["aberrant voxels", header.aberrant_voxels, header.aberrant_voxels ? "bad" : "good"],
    ["wide sums", header.wide_sums, header.wide_sums ? "bad" : "good"],
    ["object bytes", EV.grouped(object.bytes)],
    ["dense bytes", EV.grouped(header.frames * header.depth * header.plane * 4)],
  ]);
};

EV.focusCell = (app) => (app.hover ? app.hover - 1 : app.chosen.size ? [...app.chosen][0] : -1);

EV.paintDims = (app) => {
  const object = app.object;
  const cell = EV.focusCell(app);
  const clinical = EV.clinical();
  if (cell < 0) {
    EV.table(EV.$("dimTable"), [["cell", clinical ? "point at or click a cell" : "none"]]);
  } else {
    const size = object.cells[4 * cell];
    const parents = EV.parentsOf(object, cell);
    const children = EV.childrenOf(object, cell);
    const frame = object.cellFrame[cell];
    EV.table(EV.$("dimTable"), clinical ? [
      ["cell", `#${cell}`],
      ["frame", `${frame + 1}`],
      ["volume, voxels", EV.grouped(size)],
      ["center z, y, x", EV.centroidText(object, cell, 1)],
      ["came from", parents.length ? parents.map((one) => `#${one}`).join(", ") : "no earlier cell"],
      ["becomes", children.length ? children.map((one) => `#${one}`).join(", ") : "no later cell"],
      ["lineage starts at", `#${object.root[cell]}`],
    ] : [
      ["cell / frame", `${cell} / ${frame}`],
      ["n", size],
      ["sum z, y, x", `${object.cells[4 * cell + 1]}, ${object.cells[4 * cell + 2]}, ${object.cells[4 * cell + 3]}`],
      ["centroid", EV.centroidText(object, cell, 3)],
      ["doubled centre", `${object.centre[3 * cell]}, ${object.centre[3 * cell + 1]}, ${object.centre[3 * cell + 2]}`],
      ["step to children", `${object.motion[8 * cell]}, ${object.motion[8 * cell + 1]}, ${object.motion[8 * cell + 2]}`],
      ["parents", parents.join(", ") || "none"],
      ["children", children.join(", ") || "none"],
      ["root", object.root[cell]],
    ]);
  }
  // Volumes of the frame's cells by power of two: bin b holds sizes from 2^b to 2^(b+1) - 1.
  const table = object.frames;
  const first = table[10 * app.frame + 5];
  const past = first + table[10 * app.frame + 6];
  const bins = new Array(24).fill(0);
  for (let one = first; one < past; one += 1) {
    bins[31 - Math.clz32(Math.max(object.cells[4 * one], 1))] += 1;
  }
  const canvas = EV.$("bars");
  const context = canvas.getContext("2d");
  const tallest = Math.max(1, ...bins);
  context.clearRect(0, 0, canvas.width, canvas.height);
  const barWidth = Math.floor(canvas.width / bins.length);
  const focusBin = cell >= 0 ? 31 - Math.clz32(Math.max(object.cells[4 * cell], 1)) : -1;
  bins.forEach((count, bin) => {
    const height = Math.floor(((canvas.height - 14) * count) / tallest);
    context.fillStyle = bin === focusBin ? "#e69f00" : "#56b4e9";
    context.fillRect(bin * barWidth + 1, canvas.height - 12 - height, barWidth - 2, height);
  });
  context.fillStyle = getComputedStyle(document.body).color;
  context.font = "10px sans-serif";
  context.fillText("1", 1, canvas.height - 1);
  context.fillText("2^23 voxels", canvas.width - 64, canvas.height - 1);
  EV.$("barNote").textContent = clinical
    ? `How many cells in this frame have each size. The tallest bar holds ${tallest} cells.`
    : `bins by floor(log2 n), 24 bins, tallest ${tallest}`;
};

EV.paintLineage = (app) => {
  const object = app.object;
  const cell = app.chosen.size ? [...app.chosen][0] : -1;
  const clinical = EV.clinical();
  const note = EV.$("lineageNote");
  if (cell < 0) {
    EV.table(EV.$("lineageTable"), []);
    note.textContent = clinical ? "Click a cell to see where it came from and what it became." : "choose a cell";
    return;
  }
  const family = EV.lineage(object, [cell]);
  const byFrame = new Map();
  for (const one of family) {
    const frame = object.cellFrame[one];
    byFrame.set(frame, [...(byFrame.get(frame) || []), one]);
  }
  const shownPerFrame = 12;
  const rows = [...byFrame.entries()].sort((left, right) => left[0] - right[0]).map(([frame, members]) => {
    const more = members.length - shownPerFrame;
    const words = members.slice(0, shownPerFrame).map((one) => {
      const children = object.forward.start[one + 1] - object.forward.start[one];
      const onward = object.frames[10 * frame + 8] > 0;
      const mark = children >= 2 ? (clinical ? " divides" : " /2+") : onward && children === 0 ? (clinical ? " ends" : " end") : "";
      return clinical ? `#${one} (${EV.grouped(object.cells[4 * one])})${mark}` : `${one}:${object.cells[4 * one]}${mark}`;
    });
    const rest = more > 0 ? (clinical ? `, and ${more} more` : `, +${more}`) : "";
    return [clinical ? `frame ${frame + 1}` : `f${frame}`, words.join(", ") + rest];
  });
  EV.table(EV.$("lineageTable"), rows);
  note.textContent = clinical
    ? `${family.length} cells in this lineage across ${byFrame.size} frames. Numbers in brackets are volumes in voxels.`
    : `${family.length} cells, ${byFrame.size} frames, cell:n`;
};

EV.paintLegend = (app) => {
  const clinical = EV.clinical();
  const swatch = (color, text) => `<div class="row"><span style="display:inline-block;width:14px;height:14px;border-radius:3px;background:${color}"></span><span>${text}</span></div>`;
  const palette = {
    lineage: "Each lineage has its own color, kept from frame to frame.",
    okabe_ito: "Each lineage has one of eight colors chosen to stay distinct under color blindness.",
    cell: "Each cell has its own color in every frame.",
    volume: "Color runs from purple for the smallest cells to yellow for the largest.",
  }[app.view.palette];
  EV.$("legendBody").innerHTML = [
    `<p class="note">${palette}</p>`,
    swatch("#009E73", clinical ? "answer key link the tracker got right" : "edge status 0 correct"),
    swatch("#E69F00", clinical ? "the right cell, among several the tracker kept" : "edge status 1 branched"),
    swatch("#D55E00", clinical ? "answer key link the tracker got wrong" : "edge status 2 wrong"),
    swatch("#CC79A7", clinical ? "answer key link the tracker did not make" : "edge status 3 no link"),
    `<p class="note">${clinical
      ? "Between frames each cell slides toward what it becomes while the next frame fades in. A cell that divides slides toward the middle of its two daughters."
      : "transition: runs of frame t move by the step to their children's joint centroid and dissolve by a run hash against the eased progress; frame t+1 enters the same way from its parents"}</p>`,
  ].join("");
};

EV.paintReview = (app) => {
  const object = app.object;
  const clinical = EV.clinical();
  const list = EV.$("reviewList");
  EV.$("reviewNote").textContent = clinical
    ? "Links the answer key marks wrong or missing, then the most linked and the largest cells, which can be several cells counted as one. Click an item to go to it."
    : "status 2 and 3 edges, then top 12 by degree and by n";
  list.replaceChildren(...object.review.slice(0, 80).map((item) => {
    const entry = document.createElement("li");
    const cells = item.cells.map((one) => `#${one}`).join(" to ");
    entry.textContent = item.text || (item.kind === "most linked"
      ? `${cells}, ${item.degree} links, frame ${item.frame + (clinical ? 1 : 0)}`
      : item.kind === "largest"
        ? `${cells}, ${EV.grouped(item.voxels)} voxels, frame ${item.frame + (clinical ? 1 : 0)}`
        : `${item.kind}: ${cells}, frame ${item.frame + (clinical ? 1 : 0)}`);
    entry.className = item.kind === "wrong" || item.kind === "no link" || item.kind === "control" ? "bad" : "";
    entry.addEventListener("click", () => {
      EV.goTo(app, item.frame);
      EV.choose(app, item.cells, "set");
    });
    return entry;
  }));
};

EV.stateJson = (app) => {
  const object = app.object;
  return {
    sample: app.sample, frame: app.frame, progress: app.progress, playing: app.playing,
    chosen: [...app.chosen], hover: app.hover ? app.hover - 1 : null, drawn: app.drawn,
    view: app.view,
    header: object ? object.header : null,
    timings: object ? { compile_ms: app.gpu.compileMs, stream_ms: object.streamMs, resolve_ms: app.resolveMs, compact_ms: app.compactMs } : null,
  };
};

EV.paintMachine = (app) => {
  const text = JSON.stringify(EV.stateJson(app), null, 1);
  EV.$("machineText").textContent = text;
  EV.$("engine-state").textContent = text;
};

EV.helpText = () => EV.clinical()
  ? `<b>Reading the view</b><p class="note">Each colored shape is one cell as the tracker found it, built from the microscope's voxels. Press play or the arrow keys to move through time; cells slide to where they go next. The square at the lower right is one slice through the volume, like a single microscope image, with each cell outlined.</p>
     <p class="note">Drag with either mouse button to move the camera around the volume, scroll to zoom, hold Shift and drag (or drag with the middle button) to slide the picture. Click a cell to choose it; Shift-click adds more. Press L to choose its whole lineage.</p>
     <p class="note">Keys: arrows frame, Space play, [ ] slice depth, R quarter turn, 0 fit, L lineage, W answer-key problems, F only chosen, B smooth, voxels or centroids, C colors, M machine face, Esc clear.</p>`
  : `<b>engine view, machine face</b><p class="note">window.engineView: state(), cfg(), apply(view or .cfg text), load(sample), open(file), frame(n), play(on), choose(cells, mode), cells(frame), cell(id), lineage(id), review(), pick(x, y), snapshot(), csv(), sections(). The page's state is also JSON in script#engine-state and window.__loopHealth reports the frame loop.</p>
     <p class="note">keys: arrows frame, shift+arrows ghosts, space play, [ ] slice z, r turn 90, t tilt, 0 fit, + - zoom, l lineage, w failing, f only chosen, k links, e edges, b body, c palette, g glow, m clinical face, s snapshot, esc clear</p>`;

EV.paintPanels = (app) => {
  if (!app.object) {
    return;
  }
  EV.paintCounts(app);
  if (!EV.$("dims").hidden) {
    EV.paintDims(app);
  }
  if (!EV.$("lineage").hidden) {
    EV.paintLineage(app);
  }
  if (!EV.$("legend").hidden) {
    EV.paintLegend(app);
  }
  if (!EV.$("machine").hidden || !EV.clinical()) {
    EV.paintMachine(app);
  }
};

// Labels for the chosen cells of the frames on screen, with leader lines. In a row along the top they are sorted by
// their cell's position so leaders do not cross, and crossing pairs left over are swapped; riding, they sit beside
// their cell. A dragged label stays where it is put; a double click lets it go.
EV.paintTags = (app) => {
  const tags = EV.$("tags");
  const leads = EV.$("leads");
  const object = app.object;
  if (!app.view.labels || !object) {
    tags.replaceChildren();
    leads.replaceChildren();
    return;
  }
  app.pins = app.pins || new Map();
  const shown = [...app.chosen].filter((cell) => {
    const frame = object.cellFrame[cell];
    return frame === app.frame || (frame === app.frame + 1 && app.progress >= 2048);
  }).slice(0, 24);
  const clinical = EV.clinical();
  const targets = shown.map((cell) => ({ cell, at: EV.screenOf(app, cell) })).sort((left, right) => left.at[0] - right.at[0]);
  const panel = EV.$("panel").getBoundingClientRect();
  let x = Math.max(panel.right + 12, 12);
  const width = window.innerWidth;
  let y = 64;
  for (const target of targets) {
    const text = clinical ? `#${target.cell} · ${EV.grouped(object.cells[4 * target.cell])} voxels` : `${target.cell} n=${object.cells[4 * target.cell]}`;
    target.text = text;
    const guess = text.length * 7 + 14;
    if (app.view.ride) {
      target.place = [target.at[0] + 18, target.at[1] - 30];
    } else {
      if (x + guess > width - 330) {
        x = Math.max(panel.right + 12, 12);
        y += 26;
      }
      target.place = [x, y];
      x += guess + 8;
    }
    const pin = app.pins.get(target.cell);
    target.place = pin ? pin : target.place;
  }
  for (let pass = 0; pass < 4 && !app.view.ride; pass += 1) {
    for (let one = 0; one + 1 < targets.length; one += 1) {
      const left = targets[one];
      const right = targets[one + 1];
      const crossed = (left.place[0] - right.place[0]) * (left.at[0] - right.at[0]) < 0;
      if (crossed && !app.pins.has(left.cell) && !app.pins.has(right.cell)) {
        [left.place, right.place] = [right.place, left.place];
      }
    }
  }
  tags.replaceChildren(...targets.map((target) => {
    const tag = document.createElement("div");
    tag.className = "tag";
    tag.textContent = target.text;
    tag.style.left = `${target.place[0]}px`;
    tag.style.top = `${target.place[1]}px`;
    tag.addEventListener("pointerdown", (event) => {
      event.stopPropagation();
      tag.setPointerCapture(event.pointerId);
      const start = [event.clientX - target.place[0], event.clientY - target.place[1]];
      tag.onpointermove = (move) => {
        app.pins.set(target.cell, [move.clientX - start[0], move.clientY - start[1]]);
        EV.paintTags(app);
      };
      tag.onpointerup = () => { tag.onpointermove = null; };
    });
    tag.addEventListener("dblclick", () => {
      app.pins.delete(target.cell);
      EV.paintTags(app);
    });
    return tag;
  }));
  const svg = "http://www.w3.org/2000/svg";
  leads.replaceChildren(...targets.flatMap((target) => {
    const line = document.createElementNS(svg, "line");
    line.setAttribute("x1", target.place[0] + 10);
    line.setAttribute("y1", target.place[1] + 20);
    line.setAttribute("x2", target.at[0]);
    line.setAttribute("y2", target.at[1]);
    line.setAttribute("stroke", "#56b4e9");
    line.setAttribute("stroke-width", "1.2");
    const ring = document.createElementNS(svg, "circle");
    ring.setAttribute("cx", target.at[0]);
    ring.setAttribute("cy", target.at[1]);
    ring.setAttribute("r", "6");
    ring.setAttribute("fill", "none");
    ring.setAttribute("stroke", "#56b4e9");
    return [line, ring];
  }));
};

EV.paintLines = (app) => {
  const header = app.object.header;
  const clinical = EV.clinical();
  const sliceZ = app.view.slice_z < 0 ? header.depth >> 1 : Math.min(app.view.slice_z, header.depth - 1);
  EV.$("where").textContent = clinical
    ? `frame ${app.frame + 1} of ${header.frames}`
      + (app.view.slice ? (app.view.map === "projection" ? " · map: the whole volume from above" : ` · map: layer ${sliceZ + 1} of ${header.depth}`) : "")
      + ` · ${app.chosen.size} chosen`
    : `F=${app.frame} p=${app.progress} turn=${app.live.turn >> 4} tilt=${app.live.tilt >> 4} zoom=${app.live.zoom} spread=${app.live.spread} z=${sliceZ} drawn=${app.drawn}`;
  const work = app.workMs.length ? app.workMs.reduce((sum, one) => sum + one, 0) / app.workMs.length : 0;
  EV.$("rate").textContent = `work ${work.toFixed(1)} ms mean of ${app.workMs.length} · compact ${app.compactMs} ms · resolve ${app.resolveMs.join("/")} ms\nstream ${app.object.streamMs} ms · compile ${app.gpu.compileMs} ms · drawn ${EV.grouped(app.drawn)}`;
  EV.$("transportOf").textContent = clinical ? `of ${header.frames}` : `of ${header.frames} (0-based)`;
  const frameBox = EV.$("frameBox");
  if (document.activeElement !== frameBox) {
    frameBox.value = clinical ? app.frame + 1 : app.frame;
  }
  const clock = EV.$("clock");
  clock.max = String((header.frames - 1) * 64);
  if (document.activeElement !== clock) {
    clock.value = String(app.frame * 64 + (app.progress >> 6));
  }
  EV.$("play").innerHTML = app.playing ? "&#10074;&#10074;" : "&#9654;";
};

EV.afterRender = (app, regions) => {
  // The right column stops above the slice when the slice is shown.
  const ratio = window.devicePixelRatio || 1;
  const right = EV.$("right");
  const bottom = regions && regions.slice ? Math.floor(regions.slice[1] / ratio) - 12 : window.innerHeight - 80;
  right.style.maxHeight = `${Math.max(120, bottom - 60)}px`;
  EV.paintTags(app);
  EV.paintLightHandles(app);
  const now = performance.now();
  if (now - (app.panelsAt || 0) > 250) {
    app.panelsAt = now;
    EV.fetchRaw(app);
    EV.paintLines(app);
    EV.paintPanels(app);
  }
};
