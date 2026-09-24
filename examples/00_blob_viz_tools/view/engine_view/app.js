// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The page's state and its clock. The .cfg view holds the targets; the live values ease toward them every frame, so
// a turn, a zoom, a spread, a choice and a frame change all move instead of jumping. Angles are held in sixteenths of
// a degree and turned through the integer sine table.

EV.$ = (id) => document.getElementById(id);

EV.app = {
  gpu: null, object: null, samples: [], sample: null,
  view: EV.defaultView(),
  live: { turn: 30 * 16, tilt: 35 * 16, zoom: 64, spread: 0, panX: 0, panY: 0, chosenWeight: 0, lights: [] },
  frame: 0, progress: 0, heading: 0, playing: false,
  chosen: new Set(), hover: 0,
  compacted: "", compacting: false, drawn: 0, compactMs: 0,
  dirty: true, workMs: [], resolveMs: [], lastTick: 0, turns: 0,
};

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

EV.frameRange = (app) => {
  const header = app.object.header;
  const table = app.object.frames;
  const first = Math.max(0, app.frame - app.view.ghosts);
  const last = Math.min(header.frames - 1, app.frame + 1);
  return {
    first, last,
    leafFirst: table[10 * first + 1], leafPast: table[10 * last + 1] + table[10 * last + 2],
    runFirst: table[10 * first + 3], runPast: table[10 * last + 3] + table[10 * last + 4],
    cellFirst: table[10 * first + 5], cellPast: table[10 * last + 5] + table[10 * last + 6],
    linkFirst: table[10 * first + 7], linkPast: table[10 * app.frame + 7] + table[10 * app.frame + 8],
  };
};

// The regions of the canvas, in device pixels: the 3D view everywhere, and the slice as an inset at the lower right.
EV.regions = (app) => {
  const canvas = app.gpu.canvas;
  const ratio = window.devicePixelRatio || 1;
  const header = app.object.header;
  const showSlice = app.view.slice;
  const side = Math.floor(Math.min(canvas.height * 0.42, canvas.width * 0.34));
  // The map holds still in a square; the shapes turning on it may leave its corners.
  const scale = Math.max(1, Math.floor((side * 256) / Math.max(header.width, header.height)));
  const sliceWidth = side;
  const sliceHeight = side;
  const margin = Math.floor(12 * ratio);
  const sliceX = canvas.width - sliceWidth - margin;
  const sliceY = canvas.height - sliceHeight - Math.floor(70 * ratio);
  // The cells sit below what is written over them: the menu, whose engine this is, and what it is and is not.
  const under = Math.floor(126 * ratio);
  return { view: [0, under, canvas.width, Math.max(1, canvas.height - under)],
           slice: showSlice ? [sliceX, sliceY, sliceWidth, sliceHeight] : null, scale };
};

EV.layoutValues = (app, range, regions) => {
  const header = app.object.header;
  const view = app.view;
  const live = app.live;
  const leafSpan = range.leafPast - range.leafFirst;
  const lights = EV.lightVectors(app);
  const first = lights[0] || { world: [0, 0, 256], view: [0, 0, 256], strength: 0 };
  const sliceZ = view.slice_z < 0 ? header.depth >> 1 : Math.min(view.slice_z, header.depth - 1);
  return {
    frames_at: header.frames_at, leaves_at: header.leaves_at, cells_at: header.cells_at, runs_at: header.runs_at,
    links_at: header.links_at, edges_at: header.edges_at, depth: header.depth, height: header.height, width: header.width,
    plane: header.plane, frame_total: header.frames, leaf_total: header.leaf_total,
    leaf_first: range.leafFirst, leaf_span: leafSpan, pow2: EV.nextPower(Math.max(1, leafSpan)), only_chosen: view.only_chosen ? 1 : 0,
    run_first: range.runFirst, run_past: range.runPast, run_total: header.run_total, cell_total: header.cell_total,
    yaw_cos: EV.cosine16(live.turn), yaw_sin: EV.sine16(live.turn), pitch_cos: EV.cosine16(live.tilt), pitch_sin: EV.sine16(live.tilt),
    zoom: live.zoom, pan_x: live.panX, pan_y: live.panY, half_w: regions.view[2] >> 1, half_h: regions.view[3] >> 1,
    spread: live.spread, frame_now: app.frame, progress: app.progress, z_scale: view.z_scale, min_voxels: view.min_voxels,
    shade_on: view.light ? 1 : 0,
    light_x: first.world[0], light_y: first.world[1], light_z: first.world[2],
    light_count: lights.length, body_alpha: view.body_opacity, typical_voxels: app.object.frameMedian[app.frame],
    slide: view.slide,
    map_reach: Math.max(1, Math.floor(Math.sqrt(header.width * header.width + header.height * header.height
      + ((header.depth * view.z_scale) >> 1) * ((header.depth * view.z_scale) >> 1)))),
    ...Object.fromEntries(lights.flatMap((light, slot) => [
      [`light${slot}_x`, light.view[0]], [`light${slot}_y`, light.view[1]], [`light${slot}_z`, light.view[2]],
      [`light${slot}_strength`, light.strength],
    ])),
    chosen_weight: live.chosenWeight, glow: view.glow ? 1 : 0,
    status_mask: (view.correct ? 1 : 0) | (view.branched ? 2 : 0) | (view.wrong ? 4 : 0) | (view.no_link ? 8 : 0) | 16,
    palette: { cell: 0, lineage: 1, volume: 2, okabe_ito: 3 }[view.palette], ghost_frames: view.ghosts, ghost_fade: view.ghost_fade,
    slice_z: sliceZ, slice_on: regions.slice ? 1 : 0, window_low: view.window_low, window_high: view.window_high,
    hover_cell: app.hover, body: { voxels: 0, smooth: 1, centroids: 2 }[view.body],
    soft_radius: view.smooth_radius, soft_alpha: view.smooth_opacity,
    wall_inset: app.wallInset || 0, wall_tone: view.wall_tone, wall_alpha: view.wall_opacity, wall_on: view.walls ? 1 : 0,
    slice_w: regions.slice ? regions.slice[2] : 0, slice_h: regions.slice ? regions.slice[3] : 0,
    slice_follow: view.slice_follow ? 1 : 0, map_projection: view.map === "projection" ? 1 : 0,
    slice_x0: regions.slice ? regions.slice[0] : 0, slice_y0: regions.slice ? regions.slice[1] : 0, slice_scale: regions.scale,
    raw_on: app.gpu.rawOn, link_frames: view.tracks ? 1 : 0,
  };
};

// Each light as a direction toward it, times 256: in the volume's own frame for the voxel faces, and turned by the camera
// into view space, x right, y up, z toward the eye, for the lit bodies. A light is fixed to the volume, so turning the
// camera turns its light with the cells. Integers throughout.
EV.lightVectors = (app) => {
  const live = app.live;
  const yc = EV.cosine16(live.turn);
  const ys = EV.sine16(live.turn);
  const pc = EV.cosine16(live.tilt);
  const ps = EV.sine16(live.tilt);
  return app.view.lights.slice(0, 4).map((light, slot) => {
    const angles = live.lights[slot] || { turn: light.turn * 16, tilt: light.tilt * 16 };
    const flat = EV.cosine16(angles.tilt);
    const x = (flat * EV.cosine16(angles.turn)) >> 14;
    const y = (flat * EV.sine16(angles.turn)) >> 14;
    const z = EV.sine16(angles.tilt);
    const x1 = (yc * x - ys * y) >> 14;
    const y1 = (ys * x + yc * y) >> 14;
    const y2 = (pc * y1 - ps * z) >> 14;
    const z2 = (ps * y1 + pc * z) >> 14;
    return { world: [x >> 6, y >> 6, z >> 6], view: [x1 >> 6, z2 >> 6, -(y2 >> 6)], strength: light.strength, screen: [x1, z2] };
  });
};

// The fit: the whole view inside the smaller half of the canvas, with a sixth to spare.
EV.fitZoom = (app) => {
  const header = app.object.header;
  const canvas = app.gpu.canvas;
  const reach = Math.max(header.width, header.height, (header.depth * app.view.z_scale) >> 1) * 2;
  return Math.max(1, Math.floor((Math.min(canvas.width, canvas.height) * 256 * 5) / (12 * reach)));
};

// One ease step of an integer toward its target: a quarter of the way, at least one unit.
EV.approach = (value, target) => {
  const gap = target - value;
  const step = gap >> 2;
  return value + (step !== 0 ? step : Math.sign(gap));
};

EV.tick = (app, now) => {
  const gap = Math.min(100, Math.max(0, Math.floor(now - (app.lastTick || now))));
  app.lastTick = now;
  const view = app.view;
  const live = app.live;
  const before = JSON.stringify(live) + app.progress + app.frame;
  // The turn takes the short way round.
  const turnTarget = view.turn * 16;
  const around = ((turnTarget - live.turn) % 5760 + 8640) % 5760 - 2880;
  live.turn = ((EV.approach(0, around) + live.turn) % 5760 + 5760) % 5760;
  live.tilt = EV.approach(live.tilt, view.tilt * 16);
  live.zoom = EV.approach(live.zoom, view.zoom || EV.fitZoom(app));
  live.spread = EV.approach(live.spread, view.spread);
  live.panX = EV.approach(live.panX, view.pan_x);
  live.panY = EV.approach(live.panY, view.pan_y);
  live.lights = view.lights.map((light, slot) => {
    const was = live.lights[slot] || { turn: light.turn * 16, tilt: light.tilt * 16 };
    const around = ((light.turn * 16 - was.turn) % 5760 + 8640) % 5760 - 2880;
    return { turn: ((was.turn + EV.approach(0, around)) % 5760 + 5760) % 5760, tilt: EV.approach(was.tilt, light.tilt * 16) };
  });
  live.chosenWeight = EV.approach(live.chosenWeight, app.chosen.size ? 160 : 0);

  // Frames: a heading of +1 runs the transition forward, -1 runs it back, 0 holds.
  const header = app.object.header;
  const perMs = Math.max(1, view.rate) * 4096;
  if (app.playing && app.heading === 0) {
    app.heading = 1;
  }
  if (app.heading > 0) {
    if (app.frame >= header.frames - 1) {
      app.heading = 0;
      app.progress = 0;
      if (app.playing && view.loop) {
        EV.goTo(app, 0);
      } else {
        app.playing = false;
      }
    } else {
      app.progress = Math.min(4096, app.progress + Math.floor((gap * perMs) / 1000));
      if (app.progress >= 4096) {
        app.frame += 1;
        app.progress = 0;
        app.stepsLeft = Math.max(0, (app.stepsLeft || 1) - 1);
        app.heading = app.playing || app.stepsLeft ? 1 : 0;
      }
    }
  } else if (app.heading < 0) {
    app.progress = Math.max(0, app.progress - Math.floor((gap * perMs) / 1000));
    if (app.progress === 0) {
      app.stepsLeft = Math.max(0, (app.stepsLeft || 1) - 1);
      if (app.stepsLeft && app.frame > 0) {
        app.frame -= 1;
        app.progress = 4096;
      } else {
        app.heading = 0;
      }
    }
  }
  if (before !== JSON.stringify(live) + app.progress + app.frame) {
    app.dirty = true;
  }
};

EV.goTo = (app, frame) => {
  app.frame = Math.max(0, Math.min(app.object.header.frames - 1, frame | 0));
  app.progress = 0;
  app.heading = 0;
  app.dirty = true;
};

EV.stepFrames = (app, count) => {
  const header = app.object.header;
  if (count > 0 && app.frame < header.frames - 1) {
    app.stepsLeft = Math.min(count, header.frames - 1 - app.frame);
    app.heading = 1;
  }
  if (count < 0 && app.frame > 0) {
    app.stepsLeft = Math.min(-count, app.frame);
    app.frame -= 1;
    app.progress = 4096;
    app.heading = -1;
  }
  app.dirty = true;
};

EV.compactKey = (app) => {
  const range = EV.frameRange(app);
  return [range.leafFirst, range.leafPast, app.view.only_chosen, app.view.min_voxels, app.view.only_chosen ? [...app.chosen].join(",") : ""].join("|");
};

EV.frameLoop = (app, now) => {
  const began = performance.now();
  const gpu = app.gpu;
  if (app.object) {
    EV.tick(app, now);
  }
  if (app.object && !app.compacting) {
    EV.fit(gpu);
    const range = EV.frameRange(app);
    const regions = EV.regions(app);
    const values = EV.layoutValues(app, range, regions);
    const key = EV.compactKey(app);
    if (key !== app.compacted) {
      app.compacting = true;
      EV.writeLayout(gpu, values);
      EV.compact(gpu, range.leafPast - range.leafFirst, range.runPast - range.runFirst).then((result) => {
        app.drawn = result.drawn;
        app.compactMs = result.ms;
        app.compacted = key;
        app.compacting = false;
        app.dirty = true;
      });
    } else if (app.dirty) {
      EV.writeLayout(gpu, values);
      const table = app.object.frames;
      const sliceFrame = app.progress >= 2048 ? Math.min(app.frame + 1, range.last) : app.frame;
      EV.render(gpu, {
        region: regions.view, sliceRegion: regions.slice, slice: !!regions.slice,
        sliceFirstRun: table[10 * sliceFrame + 3], sliceRuns: table[10 * sliceFrame + 4],
        body: values.body, wall: app.view.walls, cellFirst: range.cellFirst, cellCount: range.cellPast - range.cellFirst,
        links: app.view.links, linkFirst: app.view.tracks ? 0 : range.linkFirst,
        linkCount: app.view.tracks ? app.object.header.link_total : range.linkPast - range.linkFirst,
        edges: app.view.edges,
        background: document.documentElement.dataset.theme === "light" ? { r: 0.93, g: 0.945, b: 0.96, a: 1 } : { r: 0.027, g: 0.031, b: 0.039, a: 1 },
      });
      app.dirty = false;
      app.workMs.push(performance.now() - began);
      app.workMs.splice(0, Math.max(0, app.workMs.length - 60));
      EV.afterRender(app, regions);
    }
  }
  app.turns += 1;
};

// The frame loop runs inside a guard: a throw stops it and says so on the page, on the console and on
// window.__loopHealth, and a loop that has not turned twice a second and a half after start is reported the same way.
EV.startLoop = (app) => {
  window.__loopHealth = { ok: true, turns: 0, why: "", detail: "" };
  const alarm = EV.$("loopAlarm");
  const turn = (now) => {
    try {
      EV.frameLoop(app, now);
      window.__loopHealth.turns = app.turns;
      requestAnimationFrame(turn);
    } catch (error) {
      window.__loopHealth = { ok: false, turns: app.turns, why: "threw", detail: String(error && error.stack || error) };
      alarm.textContent = `frame loop stopped: ${error.message}`;
      alarm.hidden = false;
      console.error("[engine view] frame loop stopped", error);
    }
  };
  requestAnimationFrame(turn);
  setTimeout(() => {
    if (window.__loopHealth.ok && app.turns < 2 && document.visibilityState === "visible") {
      window.__loopHealth.why = "slow start";
      alarm.textContent = `the frame loop turned ${app.turns} times in its first 1.5 s`;
      alarm.hidden = false;
    }
  }, 1500);
};
