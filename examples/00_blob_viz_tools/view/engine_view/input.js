// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The controls, the pointer and the keys, loading, saving, and window.engineView for a program to drive the page.

// Each control by element id: the view setting it writes, and how its value reads.
EV.CONTROLS = [
  ["yaw", "turn", "integer"], ["pitch", "tilt", "integer"], ["zoom", "zoom", "integer"], ["zScale", "z_scale", "integer"],
  ["spread", "spread", "integer"], ["body", "body", "body"], ["smoothRadius", "smooth_radius", "integer"],
  ["smoothOpacity", "smooth_opacity", "integer"], ["walls", "walls", "switch"],
  ["wallTone", "wall_tone", "integer"], ["wallOpacity", "wall_opacity", "integer"], ["sliceFollow", "slice_follow", "switch"], ["mapMode", "map", "word"],
  ["palette", "palette", "palette"], ["ghosts", "ghosts", "integer"],
  ["ghostFade", "ghost_fade", "integer"], ["minVoxels", "min_voxels", "power"], ["shadeOn", "light", "switch"],
  ["bodyOpacity", "body_opacity", "integer"], ["slide", "slide", "integer"], ["links", "links", "switch"],
  ["tracks", "tracks", "switch"], ["edges", "edges", "switch"], ["onlyChosen", "only_chosen", "switch"], ["glow", "glow", "switch"],
  ["ride", "ride", "switch"], ["labels", "labels", "switch"], ["status0", "correct", "switch"], ["status1", "branched", "switch"],
  ["status2", "wrong", "switch"], ["status3", "no_link", "switch"], ["slice", "slice", "switch"], ["sliceZ", "slice_z", "integer"],
  ["windowLow", "window_low", "integer"], ["windowHigh", "window_high", "integer"], ["sheer", "sheer", "integer"],
  ["textSize", "text_size", "integer"], ["theme", "theme", "word"], ["rateBox", "rate", "integer"], ["stepBox", "step", "integer"],
  ["loop", "loop", "switch"],
];

EV.BODY_WORDS = ["smooth", "voxels", "centroids"];
EV.PALETTE_WORDS = { 0: "cell", 1: "lineage", 2: "volume", 3: "okabe_ito" };

// Writes the view into every control and the page's own styles.
EV.showView = (app) => {
  const view = app.view;
  for (const [id, name, kind] of EV.CONTROLS) {
    const element = EV.$(id);
    const value = view[name];
    if (kind === "switch") {
      element.checked = !!value;
    } else if (kind === "body") {
      element.value = String(EV.BODY_WORDS.indexOf(value));
    } else if (kind === "palette") {
      element.value = Object.keys(EV.PALETTE_WORDS).find((key) => EV.PALETTE_WORDS[key] === value);
    } else if (kind === "power") {
      element.value = String(value ? 32 - Math.clz32(value) : 0);
    } else if (id === "sliceZ" && value < 0 && app.object) {
      element.value = String(app.object.header.depth >> 1);
    } else {
      element.value = String(value);
    }
    const out = EV.$(`${id}Out`);
    if (out) {
      out.textContent = kind === "power" ? EV.grouped(value) : kind === "switch" ? "" : String(element.value);
    }
  }
  const root = document.documentElement;
  root.dataset.face = view.face;
  root.dataset.theme = view.theme;
  root.style.setProperty("--sheer", String(view.sheer / 100));
  root.style.setProperty("--text", `${Math.floor((12 * view.text_size) / 100)}px`);
  EV.$("faceClinical").classList.toggle("on", view.face === "clinical");
  EV.$("faceMachine").classList.toggle("on", view.face === "machine");
  for (const button of document.querySelectorAll("#menu [data-show]")) {
    const name = button.dataset.show;
    const on = name === "all" ? false : view.panels.includes(name);
    button.classList.toggle("on", on);
    if (name !== "all") {
      EV.$(name).hidden = !on;
    }
  }
  EV.$("tile").innerHTML = EV.helpText();
  EV.showLights(app);
  app.dirty = true;
  app.panelsAt = 0;
  EV.remember(app);
};

EV.readControl = (app, id, name, kind) => {
  const element = EV.$(id);
  const value = kind === "switch" ? element.checked
    : kind === "body" ? EV.BODY_WORDS[Number(element.value)]
      : kind === "palette" ? EV.PALETTE_WORDS[element.value]
        : kind === "power" ? (Number(element.value) ? 2 ** (Number(element.value) - 1) : 0)
          : kind === "word" ? element.value : Math.trunc(Number(element.value));
  const refused = EV.refuseValue(EV.VIEW_SCHEME[name], value);
  if (!refused) {
    app.view[name] = value;
  }
  if (name === "slice_z" || name === "window_low" || name === "window_high" || name === "slice") {
    EV.fetchRaw(app);
  }
  EV.showView(app);
};

// The lights panel: how many lights, which one the sliders edit, and its turn, tilt and strength.
EV.showLights = (app) => {
  const lights = app.view.lights;
  app.lightPick = Math.min(app.lightPick || 0, Math.max(0, lights.length - 1));
  EV.$("lightCount").textContent = String(lights.length);
  EV.$("lightFewer").disabled = lights.length === 0;
  EV.$("lightMore").disabled = lights.length >= 4;
  const pick = EV.$("lightPick");
  pick.replaceChildren(...lights.map((unused, slot) => Object.assign(document.createElement("option"), { value: String(slot), textContent: `light ${slot + 1}` })));
  pick.value = String(app.lightPick);
  const light = lights[app.lightPick];
  for (const [id, key] of [["lightTurnBox", "turn"], ["lightTiltBox", "tilt"], ["lightStrength", "strength"]]) {
    EV.$(id).disabled = !light;
    EV.$(id).value = light ? String(light[key]) : "0";
    EV.$(`${id}Out`).textContent = light ? String(light[key]) : "";
  }
};

EV.bindLights = (app) => {
  EV.$("lightFewer").addEventListener("click", () => { app.view.lights.pop(); EV.showView(app); });
  EV.$("lightMore").addEventListener("click", () => {
    const count = app.view.lights.length;
    // A new light is placed a golden angle round from the last, halfway up.
    app.view.lights.push({ turn: ((count ? app.view.lights[count - 1].turn : 0) + 137) % 360, tilt: 45, strength: 160 });
    app.lightPick = count;
    EV.showView(app);
  });
  EV.$("lightPick").addEventListener("change", (event) => { app.lightPick = Number(event.target.value); EV.showView(app); });
  for (const [id, key] of [["lightTurnBox", "turn"], ["lightTiltBox", "tilt"], ["lightStrength", "strength"]]) {
    EV.$(id).addEventListener("input", (event) => {
      const light = app.view.lights[app.lightPick];
      if (light) {
        light[key] = Math.trunc(Number(event.target.value));
        EV.showView(app);
      }
    });
  }
};

// A marker for each light, where its direction points out of the volume's center on the screen. Dragging one turns
// the light by half a degree a pixel across and tilts it by half a degree a pixel up.
EV.paintLightHandles = (app) => {
  const layer = EV.$("lightHandles");
  if (!app.object) {
    layer.replaceChildren();
    return;
  }
  const lights = EV.lightVectors(app);
  const canvas = app.gpu.canvas;
  const ratio = window.devicePixelRatio || 1;
  const header = app.object.header;
  const reach = Math.max(header.width, header.height) * 1.2;
  while (layer.children.length < lights.length) {
    const handle = document.createElement("div");
    handle.className = "light";
    const slot = layer.children.length;
    handle.textContent = String(slot + 1);
    handle.addEventListener("pointerdown", (event) => {
      event.stopPropagation();
      handle.setPointerCapture(event.pointerId);
      app.lightPick = slot;
      let last = [event.clientX, event.clientY];
      handle.onpointermove = (move) => {
        const light = app.view.lights[slot];
        if (!light) {
          return;
        }
        light.turn = (((light.turn + Math.round((move.clientX - last[0]) / 2)) % 360) + 360) % 360;
        light.tilt = Math.max(-89, Math.min(89, light.tilt - Math.round((move.clientY - last[1]) / 2)));
        last = [move.clientX, move.clientY];
        EV.showView(app);
      };
      handle.onpointerup = () => { handle.onpointermove = null; };
    });
    layer.appendChild(handle);
  }
  while (layer.children.length > lights.length) {
    layer.lastChild.remove();
  }
  lights.forEach((light, slot) => {
    const handle = layer.children[slot];
    const px = (canvas.width >> 1) + Math.floor(((light.screen[0] * reach) / 16384) * app.live.zoom / 256 + app.live.panX / 256);
    const py = (canvas.height >> 1) - Math.floor(((light.screen[1] * reach) / 16384) * app.live.zoom / 256 + app.live.panY / 256);
    handle.style.left = `${px / ratio}px`;
    handle.style.top = `${py / ratio}px`;
    handle.classList.toggle("picked", slot === app.lightPick);
  });
};

EV.choose = (app, cells, mode) => {
  if (mode === "set") {
    app.chosen = new Set(cells);
  } else {
    for (const cell of cells) {
      if (mode === "toggle" && app.chosen.has(cell)) {
        app.chosen.delete(cell);
      } else {
        app.chosen.add(cell);
      }
    }
  }
  app.view.chosen = [...app.chosen].slice(0, 4096);
  EV.writeChosen(app.gpu, app.chosen);
  app.dirty = true;
  app.panelsAt = 0;
  if (!EV.$("review").hidden) {
    EV.paintReview(app);
  }
};

// The raw voxels of the slice, when the page is served beside the stacks. A file opened from disk has none.
EV.fetchRaw = async (app) => {
  const header = app.object && app.object.header;
  const note = EV.$("rawNote");
  if (!header || !app.sample || !app.view.slice || app.fromFile) {
    note.textContent = app.fromFile ? "The microscope image needs the page served beside the stacks; cells are drawn without it." : "";
    return;
  }
  // The whole frame is fetched once: the projection reads every layer, and a slice reads one without a new fetch.
  const frame = Math.min(app.progress >= 2048 ? app.frame + 1 : app.frame, header.frames - 1);
  const key = `${app.sample}|${frame}`;
  if (app.rawKey === key) {
    return;
  }
  app.rawKey = key;
  try {
    const time = app.object.frames[10 * frame];
    const response = await fetch(`/frame?sample=${encodeURIComponent(app.sample)}&t=${time}`, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(String(response.status));
    }
    const voxels = new Uint16Array(await response.arrayBuffer());
    EV.setRaw(app.gpu, voxels, header.width, header.height, header.depth);
    note.textContent = "";
  } catch (error) {
    EV.setRaw(app.gpu, null, 1, 1, 1);
    note.textContent = "No microscope image is served for this frame; cells are drawn without it.";
  }
  app.dirty = true;
};

EV.remember = (app) => {
  try {
    localStorage.setItem("engine_view", JSON.stringify({ face: app.view.face, theme: app.view.theme, text_size: app.view.text_size, sheer: app.view.sheer, pinned: EV.$("panel").classList.contains("pinned") }));
  } catch (error) {
    // Storage can be refused; the page works without it.
  }
};

EV.recall = (app) => {
  try {
    const kept = JSON.parse(localStorage.getItem("engine_view") || "{}");
    EV.applyView(app.view, { face: kept.face, theme: kept.theme, text_size: kept.text_size, sheer: kept.sheer });
    EV.$("panel").classList.toggle("pinned", !!kept.pinned);
  } catch (error) {
    // Nothing remembered.
  }
};

// A served sample's two files, its .vbo and its .ibo.
EV.fetchSample = async (sample) => ({
  vertex: await fetch(`data/${sample}.vbo`, { cache: "no-store" }),
  index: await fetch(`data/${sample}.ibo`, { cache: "no-store" }),
});

// Opens the .vbo and .ibo among the files picked or dropped, the pair named by the .vbo's sample.
EV.openFiles = async (app, files) => {
  const picked = Array.from(files);
  const vertex = picked.find((file) => file.name.endsWith(".vbo"));
  const sample = vertex ? vertex.name.replace(/\.vbo$/, "") : "";
  const index = picked.find((file) => file.name === `${sample}.ibo`);
  if (!vertex || !index) {
    EV.$("where").textContent = "Open a sample's .vbo and its .ibo together.";
    return;
  }
  await EV.openSource(app, { vertex, index }, sample, true);
};

EV.openSource = async (app, sources, sample, fromFile) => {
  const gpu = app.gpu;
  EV.$("where").textContent = `opening ${sample} …`;
  app.object = null;
  const object = await EV.loadObject(gpu, sources);
  app.sample = sample;
  app.fromFile = fromFile;
  app.compacted = "";
  app.rawKey = "";
  // The object opens in the view its .cfg carries; the page's remembered face, theme and text size stay the reader's.
  const kept = { face: app.view.face, theme: app.view.theme, text_size: app.view.text_size, sheer: app.view.sheer };
  app.view = EV.defaultView();
  const parsed = EV.parseCfg(object.cfgText);
  if (parsed.view) {
    EV.applyView(app.view, parsed.view);
  }
  EV.applyView(app.view, kept);
  // What the object's .cfg says about the specimen: the voxel's size and the membrane's thickness, both in picometers,
  // give the wall's inset as the membrane in voxels times 65536.
  const specimen = EV.specimen(object.cfgText);
  app.specimen = specimen;
  app.wallInset = specimen.voxel_pm[2] ? Math.floor((specimen.membrane_pm * 65536) / specimen.voxel_pm[2]) : 0;
  const asked = new URLSearchParams(location.search);
  if (asked.get("face")) {
    EV.applyView(app.view, { face: asked.get("face") });
  }
  app.gpu.object = object;
  app.object = object;
  app.frame = Math.min(app.view.frame, object.header.frames - 1);
  app.progress = 0;
  app.heading = 0;
  app.playing = false;
  // The resolve reads the sections' offsets from the layout, so the layout is written for this object first.
  EV.fit(gpu);
  EV.writeLayout(gpu, EV.layoutValues(app, EV.frameRange(app), EV.regions(app)));
  app.resolveMs = await EV.resolveRuns(gpu);
  EV.choose(app, app.view.chosen.filter((cell) => cell < object.header.cell_total), "set");
  app.live.zoom = app.view.zoom || EV.fitZoom(app);
  EV.$("sliceZ").max = String(object.header.depth - 1);
  EV.showView(app);
  EV.paintReview(app);
  EV.paintLegend(app);
  EV.fetchRaw(app);
  if (!fromFile) {
    const url = new URL(location.href);
    url.searchParams.set("sample", sample);
    history.replaceState(null, "", url);
  }
};

EV.download = (name, blob) => {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
};

EV.snapshot = (app) => new Promise((resolve) => {
  app.dirty = true;
  EV.frameLoop(app, performance.now());
  app.gpu.canvas.toBlob((blob) => resolve(blob), "image/png");
});

EV.csv = (app) => {
  const object = app.object;
  const cells = app.chosen.size ? [...app.chosen].sort((left, right) => left - right) : Array.from({ length: object.header.cell_total }, (unused, cell) => cell);
  const lines = ["cell,frame,t,voxels,sum_z,sum_y,sum_x,centroid_z,centroid_y,centroid_x,parents,children,lineage_root"];
  for (const cell of cells) {
    const frame = object.cellFrame[cell];
    const size = Math.max(object.cells[4 * cell], 1);
    lines.push([cell, frame, object.frames[10 * frame], object.cells[4 * cell], object.cells[4 * cell + 1], object.cells[4 * cell + 2], object.cells[4 * cell + 3],
      EV.decimal(object.cells[4 * cell + 1], size, 3), EV.decimal(object.cells[4 * cell + 2], size, 3), EV.decimal(object.cells[4 * cell + 3], size, 3),
      EV.parentsOf(object, cell).join(";"), EV.childrenOf(object, cell).join(";"), object.root[cell]].join(","));
  }
  return lines.join("\n") + "\n";
};

EV.bindControls = (app) => {
  for (const [id, name, kind] of EV.CONTROLS) {
    const element = EV.$(id);
    element.addEventListener(element.type === "range" ? "input" : "change", () => EV.readControl(app, id, name, kind));
  }
  EV.$("sample").addEventListener("change", async (event) => {
    await EV.openSource(app, await EV.fetchSample(event.target.value), event.target.value, false);
  });
  for (const button of document.querySelectorAll("#menu [data-show]")) {
    button.addEventListener("click", () => {
      const name = button.dataset.show;
      const every = ["counts", "dims", "lineage", "legend", "review"].concat(app.view.face === "machine" ? ["machine"] : []);
      app.view.panels = name === "all" ? every
        : app.view.panels.includes(name) ? app.view.panels.filter((one) => one !== name) : [...app.view.panels, name];
      EV.showView(app);
      EV.paintReview(app);
    });
  }
  EV.$("faceClinical").addEventListener("click", () => { app.view.face = "clinical"; EV.showView(app); EV.paintReview(app); });
  EV.$("faceMachine").addEventListener("click", () => { app.view.face = "machine"; EV.showView(app); EV.paintReview(app); });
  EV.$("grip").addEventListener("click", () => { EV.$("panel").classList.toggle("pinned"); EV.remember(app); });
  EV.$("openFile").addEventListener("click", () => EV.$("fileInput").click());
  EV.$("fileInput").addEventListener("change", async (event) => EV.openFiles(app, event.target.files));
  EV.$("snapshot").addEventListener("click", async () => EV.download(`engine_view_frame_${app.frame + 1}.png`, await EV.snapshot(app)));
  EV.$("exportCsv").addEventListener("click", () => EV.download("engine_view_cells.csv", new Blob([EV.csv(app)], { type: "text/csv" })));
  EV.$("play").addEventListener("click", () => { app.playing = !app.playing; app.heading = app.playing ? 1 : app.heading; });
  EV.$("forth").addEventListener("click", () => EV.stepFrames(app, app.view.step));
  EV.$("back").addEventListener("click", () => EV.stepFrames(app, -app.view.step));
  EV.$("frameBox").addEventListener("change", (event) => EV.goTo(app, Number(event.target.value) - (EV.clinical() ? 1 : 0)));
  EV.$("clock").addEventListener("input", (event) => {
    const value = Number(event.target.value);
    app.playing = false;
    app.heading = 0;
    app.frame = Math.floor(value / 64);
    app.progress = (value % 64) << 6;
    app.dirty = true;
  });

  // The .cfg box.
  const said = EV.$("configSaid");
  const readPage = () => { EV.$("configText").value = EV.cfgText(app.object ? app.object.cfgText : "", app.view); said.textContent = "Read from the page."; said.className = "note"; };
  EV.$("configOpen").addEventListener("click", () => { const box = EV.$("configBox"); box.hidden = !box.hidden; if (!box.hidden) readPage(); });
  EV.$("configClose").addEventListener("click", () => { EV.$("configBox").hidden = true; });
  EV.$("configRead").addEventListener("click", readPage);
  EV.$("configApply").addEventListener("click", () => {
    const report = EV.apply(app, EV.$("configText").value);
    said.textContent = `${report.applied.length} applied.` + (report.refused.length ? ` Refused: ${report.refused.join("; ")}` : "");
    said.className = report.refused.length ? "note bad" : "note";
  });
  EV.$("configCopy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(EV.$("configText").value);
      said.textContent = "Copied.";
    } catch (error) {
      EV.$("configText").select();
      said.textContent = "The clipboard refused; the text is selected.";
    }
  });
  EV.$("configSave").addEventListener("click", () => EV.download("engine_view.cfg", new Blob([EV.$("configText").value], { type: "application/json" })));
  EV.$("configLoad").addEventListener("click", () => EV.$("configFile").click());
  EV.$("configFile").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (file) {
      EV.$("configText").value = await file.text();
      said.textContent = "Loaded. Apply to use it.";
    }
    event.target.value = "";
  });

  // Help.
  const ask = EV.$("ask");
  const tile = EV.$("tile");
  ask.addEventListener("mouseenter", () => { tile.hidden = false; });
  ask.addEventListener("click", () => { tile.hidden = !tile.hidden; });
  tile.addEventListener("mouseleave", () => { tile.hidden = true; });

  // Boxes move by their titles.
  for (const title of document.querySelectorAll(".box h4")) {
    title.addEventListener("pointerdown", (event) => {
      const box = title.parentElement;
      const rect = box.getBoundingClientRect();
      if (box.parentElement.id === "right") {
        document.body.appendChild(box);
      }
      box.style.position = "fixed";
      box.style.transform = "none";
      box.style.width = `${rect.width}px`;
      const offset = [event.clientX - rect.left, event.clientY - rect.top];
      title.setPointerCapture(event.pointerId);
      title.onpointermove = (move) => {
        box.style.left = `${move.clientX - offset[0]}px`;
        box.style.top = `${move.clientY - offset[1]}px`;
        box.style.right = "auto";
      };
      title.onpointerup = () => { title.onpointermove = null; };
    });
  }
};

EV.bindPointer = (app) => {
  const canvas = app.gpu.canvas;
  const pointers = new Map();
  let moved = 0;
  let pinch = 0;
  canvas.addEventListener("pointerdown", (event) => {
    canvas.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, [event.clientX, event.clientY]);
    moved = 0;
  });
  canvas.addEventListener("pointermove", async (event) => {
    const last = pointers.get(event.pointerId);
    const ratio = window.devicePixelRatio || 1;
    if (last) {
      const dx = event.clientX - last[0];
      const dy = event.clientY - last[1];
      moved += Math.abs(dx) + Math.abs(dy);
      pointers.set(event.pointerId, [event.clientX, event.clientY]);
      if (pointers.size === 2) {
        const [first, second] = [...pointers.values()];
        const span = Math.hypot(first[0] - second[0], first[1] - second[1]);
        if (pinch) {
          app.view.zoom = Math.max(1, Math.min(8192, Math.round(((app.view.zoom || app.live.zoom) * span) / pinch)));
        }
        pinch = span;
      } else if (event.shiftKey || event.buttons === 4) {
        // Middle drag, or Shift drag, carries the picture with the pointer.
        app.view.pan_x += Math.round(dx * ratio) * 256;
        app.view.pan_y -= Math.round(dy * ratio) * 256;
        app.live.panX = app.view.pan_x;
        app.live.panY = app.view.pan_y;
      } else {
        // Left or right drag moves the camera around the volume; the volume turns the way the pointer goes.
        app.view.turn = (((app.view.turn + Math.round(dx / 2)) % 360) + 360) % 360;
        app.view.tilt = Math.max(-89, Math.min(89, app.view.tilt - Math.round(dy / 2)));
        app.live.turn = app.view.turn * 16;
        app.live.tilt = app.view.tilt * 16;
      }
      app.dirty = true;
      return;
    }
    // Hovering: the cell under the pointer, read back at most every 80 ms.
    const now = performance.now();
    if (!app.object || app.picking || now - (app.hoverAt || 0) < 80) {
      return;
    }
    app.hoverAt = now;
    app.picking = true;
    const picked = await EV.pickAt(app.gpu, Math.floor(event.clientX * ratio), Math.floor(event.clientY * ratio));
    app.picking = false;
    const box = EV.$("hover");
    if (picked !== app.hover) {
      app.hover = picked;
      app.dirty = true;
      app.panelsAt = 0;
    }
    if (!picked) {
      box.hidden = true;
      return;
    }
    const cell = picked - 1;
    const object = app.object;
    box.hidden = false;
    box.style.left = `${event.clientX + 14}px`;
    box.style.top = `${event.clientY + 14}px`;
    box.textContent = EV.clinical()
      ? `Cell #${cell}\n${EV.grouped(object.cells[4 * cell])} voxels · frame ${object.cellFrame[cell] + 1}`
      : `cell ${cell} f${object.cellFrame[cell]} n=${object.cells[4 * cell]}\ncentroid ${EV.centroidText(object, cell, 3)}`;
  });
  const release = async (event) => {
    const had = pointers.has(event.pointerId);
    pointers.delete(event.pointerId);
    pinch = pointers.size === 2 ? pinch : 0;
    if (!had || moved > 4 || !app.object || app.picking || event.type !== "pointerup") {
      return;
    }
    const ratio = window.devicePixelRatio || 1;
    app.picking = true;
    const picked = await EV.pickAt(app.gpu, Math.floor(event.clientX * ratio), Math.floor(event.clientY * ratio));
    app.picking = false;
    EV.choose(app, picked ? [picked - 1] : [], event.shiftKey ? "toggle" : "set");
  };
  canvas.addEventListener("pointerup", release);
  canvas.addEventListener("pointercancel", release);
  canvas.addEventListener("dblclick", () => { if (app.object && app.chosen.size) EV.choose(app, EV.lineage(app.object, [...app.chosen]), "set"); });
  canvas.addEventListener("contextmenu", (event) => event.preventDefault());
  canvas.addEventListener("wheel", (event) => {
    event.preventDefault();
    const zoom = app.view.zoom || app.live.zoom;
    const step = Math.max(1, zoom >> 3);
    app.view.zoom = Math.max(1, Math.min(8192, zoom + (event.deltaY < 0 ? step : -step)));
    EV.showView(app);
  }, { passive: false });

  // Dropping a sample's .vbo and .ibo anywhere opens them.
  const drop = EV.$("drop");
  window.addEventListener("dragover", (event) => { event.preventDefault(); drop.hidden = false; });
  window.addEventListener("dragleave", (event) => { if (!event.relatedTarget) drop.hidden = true; });
  window.addEventListener("drop", async (event) => {
    event.preventDefault();
    drop.hidden = true;
    await EV.openFiles(app, event.dataTransfer.files);
  });
  window.addEventListener("resize", () => { app.dirty = true; });
};

EV.bindKeys = (app) => {
  window.addEventListener("keydown", (event) => {
    if (!app.object || event.target.closest("input, textarea, select")) {
      return;
    }
    const view = app.view;
    const key = event.key;
    const header = app.object.header;
    const actions = {
      ArrowRight: () => (event.shiftKey ? (view.ghosts = Math.min(8, view.ghosts + 1)) : EV.stepFrames(app, view.step)),
      ArrowLeft: () => (event.shiftKey ? (view.ghosts = Math.max(0, view.ghosts - 1)) : EV.stepFrames(app, -view.step)),
      Home: () => EV.goTo(app, 0),
      End: () => EV.goTo(app, header.frames - 1),
      " ": () => { app.playing = !app.playing; },
      "[": () => { view.slice_z = Math.max(0, (view.slice_z < 0 ? header.depth >> 1 : view.slice_z) - 1); EV.fetchRaw(app); },
      "]": () => { view.slice_z = Math.min(header.depth - 1, (view.slice_z < 0 ? header.depth >> 1 : view.slice_z) + 1); EV.fetchRaw(app); },
      r: () => { view.turn = (view.turn + 90) % 360; },
      t: () => { view.tilt = view.tilt > 45 ? 20 : 89; },
      0: () => { view.zoom = 0; view.pan_x = 0; view.pan_y = 0; },
      "=": () => { view.zoom = Math.min(8192, (view.zoom || app.live.zoom) + Math.max(1, (view.zoom || app.live.zoom) >> 3)); },
      "+": () => { view.zoom = Math.min(8192, (view.zoom || app.live.zoom) + Math.max(1, (view.zoom || app.live.zoom) >> 3)); },
      "-": () => { view.zoom = Math.max(1, (view.zoom || app.live.zoom) - Math.max(1, (view.zoom || app.live.zoom) >> 3)); },
      l: () => EV.choose(app, EV.lineage(app.object, [...app.chosen]), "set"),
      w: () => EV.choose(app, app.object.review.filter((item) => item.kind === "wrong" || item.kind === "no link").flatMap((item) => item.cells), "set"),
      f: () => { view.only_chosen = !view.only_chosen; },
      k: () => { view.links = !view.links; },
      e: () => { view.edges = !view.edges; },
      b: () => { const words = EV.VIEW_SCHEME.body.words; view.body = words[(words.indexOf(view.body) + 1) % words.length]; },
      c: () => { const words = EV.VIEW_SCHEME.palette.words; view.palette = words[(words.indexOf(view.palette) + 1) % words.length]; },
      g: () => { view.glow = !view.glow; },
      m: () => { view.face = view.face === "clinical" ? "machine" : "clinical"; EV.paintReview(app); },
      s: async () => EV.download(`engine_view_frame_${app.frame + 1}.png`, await EV.snapshot(app)),
      Escape: () => EV.choose(app, [], "set"),
      "?": () => { EV.$("tile").hidden = !EV.$("tile").hidden; },
    };
    const action = actions[key];
    if (action) {
      event.preventDefault();
      action();
      EV.showView(app);
    }
  });
};

// Applies a view section, or a whole .cfg's text, and reports by name what took and what did not.
EV.apply = (app, input) => {
  const parsed = typeof input === "string" ? EV.parseCfg(input) : { refused: [], view: input };
  const report = parsed.view ? EV.applyView(app.view, parsed.view) : { applied: [], refused: [] };
  report.refused = [...parsed.refused, ...report.refused];
  if (report.applied.includes("chosen") && app.object) {
    EV.choose(app, app.view.chosen.filter((cell) => cell < app.object.header.cell_total), "set");
  }
  if (report.applied.includes("frame") && app.object) {
    EV.goTo(app, app.view.frame);
  }
  EV.fetchRaw(app);
  EV.showView(app);
  return report;
};

EV.exposeApi = (app) => {
  const object = () => app.object;
  window.engineView = {
    version: 1,
    state: () => EV.stateJson(app),
    cfg: () => EV.cfgText(object() ? object().cfgText : "", app.view),
    apply: (input) => EV.apply(app, input),
    load: async (sample) => EV.openSource(app, await EV.fetchSample(sample), sample, false),
    open: (files) => EV.openFiles(app, files),
    frame: (frame) => { if (frame === undefined) return app.frame; EV.goTo(app, frame); return app.frame; },
    play: (on) => { app.playing = !!on; return app.playing; },
    choose: (cells, mode = "set") => { EV.choose(app, cells, mode); return [...app.chosen]; },
    cells: (frame = app.frame) => {
      const table = object().frames;
      const first = table[10 * frame + 5];
      return Array.from({ length: table[10 * frame + 6] }, (unused, slot) => window.engineView.cell(first + slot));
    },
    cell: (cell) => {
      const found = object();
      const size = found.cells[4 * cell];
      return {
        cell, frame: found.cellFrame[cell], t: found.frames[10 * found.cellFrame[cell]], voxels: size,
        sums: [found.cells[4 * cell + 1], found.cells[4 * cell + 2], found.cells[4 * cell + 3]],
        centroid: [1, 2, 3].map((axis) => `${found.cells[4 * cell + axis]}/${size}`),
        parents: EV.parentsOf(found, cell), children: EV.childrenOf(found, cell), root: found.root[cell],
      };
    },
    lineage: (cell) => EV.lineage(object(), [cell]),
    review: () => object().review,
    pick: async (x, y) => {
      const ratio = window.devicePixelRatio || 1;
      const picked = await EV.pickAt(app.gpu, Math.floor(x * ratio), Math.floor(y * ratio));
      return picked ? picked - 1 : null;
    },
    snapshot: async () => {
      const blob = await EV.snapshot(app);
      return new Promise((resolve) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.readAsDataURL(blob); });
    },
    csv: () => EV.csv(app),
    sections: () => object().header,
    // Every function and table the page is built from, for a program that wants to look further in.
    internals: EV,
  };
};

EV.start = async () => {
  const app = EV.app;
  try {
    app.gpu = await EV.startGpu(EV.$("view"));
  } catch (error) {
    EV.$("where").textContent = `error: ${error.message}`;
    return;
  }
  EV.recall(app);
  EV.bindControls(app);
  EV.bindLights(app);
  EV.bindPointer(app);
  EV.bindKeys(app);
  EV.exposeApi(app);
  EV.showView(app);
  EV.startLoop(app);
  let samples = [];
  try {
    const listed = await fetch("/objects", { cache: "no-store" });
    samples = listed.ok ? await listed.json() : [];
  } catch (error) {
    samples = [];
  }
  app.samples = samples;
  EV.$("sample").replaceChildren(...samples.map((name) => Object.assign(document.createElement("option"), { value: name, textContent: name })));
  const asked = new URLSearchParams(location.search).get("sample");
  const sample = samples.includes(asked) ? asked : samples[0];
  if (sample) {
    EV.$("sample").value = sample;
    await EV.openSource(app, await EV.fetchSample(sample), sample, false);
  } else {
    EV.$("where").textContent = "Open a sample's .vbo and .ibo with the open button, or drop them on the page.";
  }
};

EV.start();
