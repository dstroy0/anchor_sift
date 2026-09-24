// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The drawing shaders: boxes warped out of runs, cells as blobs, links and edges as lines, and the slice.
//
// A frame change is a transition, never a cut. Across one transition the runs of frame t slide by their cell's
// step toward its children and dissolve out, while the runs of frame t + 1 slide in from their parents and dissolve
// in; progress runs 0 to 4096 and is eased by an integer smoothstep. The dissolve grain is a hash of the run.

EV.RENDER_BINDINGS = `
@group(0) @binding(0) var<storage, read> obj: array<u32>;
@group(0) @binding(1) var<uniform> lay: Layout;
@group(0) @binding(2) var<storage, read> chosen: array<u32>;
@group(0) @binding(3) var<storage, read> motion: array<i32>;
`;

EV.RENDER_COMMON = `
var<private> OKABE: array<u32, 8> = array<u32, 8>(0xE69F00u, 0x56B4E9u, 0x009E73u, 0xF0E442u, 0x0072B2u, 0xD55E00u, 0xCC79A7u, 0xBBBBBBu);
var<private> RAMP: array<u32, 8> = array<u32, 8>(0x440154u, 0x46327Eu, 0x365C8Du, 0x277F8Eu, 0x1FA187u, 0x4AC16Du, 0xA0DA39u, 0xFDE725u);
var<private> STATUS: array<u32, 5> = array<u32, 5>(0x009E73u, 0xE69F00u, 0xD55E00u, 0xCC79A7u, 0x999999u);

struct Out {
  @builtin(position) place: vec4<f32>,
  @location(0) @interpolate(flat) colour: vec4<f32>,
  @location(1) @interpolate(flat) pick: u32,
}
struct Drawn {
  @location(0) colour: vec4<f32>,
  @location(1) pick: u32,
}

${EV.CHOSEN}

fn unpack(packed: u32) -> vec3<u32> {
  return vec3<u32>((packed >> 16u) & 255u, (packed >> 8u) & 255u, packed & 255u);
}

fn hue(key: u32) -> vec3<u32> {
  var mixed = key * 2654435761u;
  mixed = mixed ^ (mixed >> 15u);
  mixed = mixed * 2246822519u;
  mixed = mixed ^ (mixed >> 13u);
  return vec3<u32>(64u + (mixed & 191u), 64u + ((mixed >> 8u) & 191u), 64u + ((mixed >> 16u) & 191u));
}

// 0 by cell, 1 by lineage, 2 by volume, 3 lineage in the Okabe-Ito colors that stay apart under color blindness.
fn paint(cell: u32) -> vec3<u32> {
  let root = u32(motion[cell * 8u + 6u]);
  let size = max(obj[lay.cells_at + 4u * cell], 1u);
  let level = min(((31u - countLeadingZeros(size)) * 8u) / 23u, 7u);
  let okabe = unpack(OKABE[(root * 2654435761u) >> 29u]);
  return select(select(select(hue(cell), hue(root), lay.palette == 1u), unpack(RAMP[level]), lay.palette == 2u),
                okabe, lay.palette == 3u);
}

fn ease(progress: u32) -> i32 {
  let p = i32(min(progress, 4096u));
  return (((p * p) >> 12u) * (12288 - 2 * p)) >> 12u;
}

// The turn: yaw about z, then pitch about the turned x, both as integers scaled by 2^14.
fn project(x: i32, y: i32, z: i32, frame: u32) -> vec4<f32> {
  let x1 = (lay.yaw_cos * x - lay.yaw_sin * y) >> 14u;
  let y1 = (lay.yaw_sin * x + lay.yaw_cos * y) >> 14u;
  let y2 = (lay.pitch_cos * y1 - lay.pitch_sin * z) >> 14u;
  let z2 = (lay.pitch_sin * y1 + lay.pitch_cos * z) >> 14u;
  let shift = ((i32(frame) - i32(lay.frame_now)) * lay.spread) - ((ease(lay.progress) * lay.spread) >> 12u);
  return vec4<f32>(f32((x1 + shift) * lay.zoom + lay.pan_x) / f32(lay.half_w * 256),
                   f32(z2 * lay.zoom + lay.pan_y) / f32(lay.half_h * 256),
                   f32(8192 + y2) / 16384.0, 1.0);
}

// A cell's step across the transition: toward its children for frame t, in from its parents for frame t + 1.
fn step_of(cell: u32, frame: u32) -> vec3<i32> {
  let at = cell * 8u;
  let eased = ease(lay.progress);
  let toward = vec3<i32>(motion[at], motion[at + 1u], (motion[at + 2u] * lay.z_scale) / 2);
  let inward = vec3<i32>(motion[at + 3u], motion[at + 4u], (motion[at + 5u] * lay.z_scale) / 2);
  let now = frame == lay.frame_now;
  let next = frame == lay.frame_now + 1u;
  return select(vec3<i32>(0), (toward * eased) / 4096, now) - select(vec3<i32>(0), (inward * (4096 - eased)) / 4096, next);
}

fn centroid(cell: u32) -> vec3<i32> {
  let at = lay.cells_at + 4u * cell;
  let size = max(obj[at], 1u);
  let doubled_z = i32((2u * obj[at + 1u] + size) / size);
  return vec3<i32>(i32((2u * obj[at + 3u] + size) / size) - i32(lay.width),
                   i32((2u * obj[at + 2u] + size) / size) - i32(lay.height),
                   (lay.z_scale * (doubled_z - i32(lay.depth))) / 2);
}

fn frame_of_cell(cell: u32) -> u32 {
  var frame = 0u;
  for (var step = 0u; step < 8u; step++) {
    let probe = frame + (128u >> step);
    let first = obj[lay.frames_at + 10u * min(probe, lay.frame_total - 1u) + 5u];
    frame = select(frame, probe, (probe < lay.frame_total) && (first <= cell));
  }
  return frame;
}

// Shaded, faded by age, grayed where cells are chosen and this one is not, lifted where it is hovered or glows.
fn lit(cell: u32, frame: u32, shade: u32) -> vec4<f32> {
  let base = (paint(cell) * shade) / 256u;
  let age = select(0u, lay.frame_now - frame, frame < lay.frame_now);
  let bright = 256u - min(age * lay.ghost_fade, 224u);
  let faded = (base * bright) / 256u;
  let picked = chosen_bit(cell);
  let dim = (lay.chosen_weight * (1u - picked)) / 1u;
  let grey = vec3<u32>((faded.x + faded.y + faded.z) / 10u);
  let shown = (faded * (256u - dim) + grey * dim) / 256u;
  let lift = 48u * u32(lay.hover_cell == cell + 1u) + 64u * lay.glow * picked;
  let raised = min(shown + vec3<u32>(lift), vec3<u32>(255u));
  return vec4<f32>(vec3<f32>(raised) / 255.0, 1.0);
}
`;

EV.RENDER = EV.PRELUDE + EV.RENDER_BINDINGS + `
@group(0) @binding(4) var<storage, read> run_leaf: array<u32>;
@group(0) @binding(5) var<storage, read> compact: array<u32>;
` + EV.RENDER_COMMON + `
@vertex
fn box(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  let run = compact[instance + 1u];
  let word = obj[lay.runs_at + run];
  let leaf = run_leaf[run];
  let cell = obj[lay.leaves_at + 4u * leaf];
  let frame = obj[lay.leaves_at + 4u * leaf + 1u];
  let voxel = word >> 8u;
  let span = i32(word & 255u) + 1;
  let x0 = 2 * i32(voxel % lay.width) - i32(lay.width);
  let y0 = 2 * i32((voxel / lay.width) % lay.height) - i32(lay.height);
  let z0 = (lay.z_scale * (2 * i32(voxel / lay.plane) - i32(lay.depth))) / 2;
  let face = vertex / 6u;
  let corner = vertex % 6u;
  let u = i32((0x16u >> corner) & 1u);
  let v = i32((0x34u >> corner) & 1u);
  let top = face == 0u;
  let side_x = face == 1u;
  let x_face = select(x0, x0 + 2 * span, lay.yaw_sin < 0);
  let y_face = select(y0, y0 + 2, lay.yaw_cos < 0);
  let z_face = select(z0, z0 + lay.z_scale, lay.pitch_sin > 0);
  let step = step_of(cell, frame);
  let x = select(x0 + u * 2 * span, x_face, side_x) + step.x;
  let y = select(select(y_face, y0 + u * 2, side_x), y0 + v * 2, top) + step.y;
  let z = select(z0 + v * lay.z_scale, z_face, top) + step.z;
  let facing = select(select(select(-lay.light_y, lay.light_y, lay.yaw_cos < 0),
                             select(-lay.light_x, lay.light_x, lay.yaw_sin < 0), side_x),
                      select(-lay.light_z, lay.light_z, lay.pitch_sin > 0), top);
  let shade = select(256u - face * 40u, u32(72 + (max(facing, 0) * 184) / 256), lay.shade_on == 1u);
  let grain = (run * 2654435761u) >> 20u;
  let eased = u32(ease(lay.progress));
  let shown = select(select(true, grain < eased, frame == lay.frame_now + 1u), grain >= eased, frame == lay.frame_now);
  var out: Out;
  out.place = select(HIDDEN, project(x, y, z, frame), shown);
  out.colour = lit(cell, frame, shade);
  out.pick = cell + 1u;
  return out;
}

// A cell as one blob at its centroid, the size of a cube of its volume, riding its step across the transition.
@vertex
fn blob(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  let cell = instance;
  let frame = frame_of_cell(cell);
  let size = obj[lay.cells_at + 4u * cell];
  var side = 0u;
  for (var step = 0u; step < 8u; step++) {
    let probe = side + (128u >> step);
    side = select(side, probe, probe * probe * probe <= size);
  }
  let middle = centroid(cell) + step_of(cell, frame);
  let half = i32(side);
  let face = vertex / 6u;
  let corner = vertex % 6u;
  let u = i32((0x16u >> corner) & 1u);
  let v = i32((0x34u >> corner) & 1u);
  let top = face == 0u;
  let side_x = face == 1u;
  let low = middle - vec3<i32>(half, half, half * lay.z_scale / 2);
  let high = middle + vec3<i32>(half, half, half * lay.z_scale / 2);
  let x_face = select(low.x, high.x, lay.yaw_sin < 0);
  let y_face = select(low.y, high.y, lay.yaw_cos < 0);
  let z_face = select(low.z, high.z, lay.pitch_sin > 0);
  let x = select(low.x + u * (high.x - low.x), x_face, side_x);
  let y = select(select(y_face, low.y + u * (high.y - low.y), side_x), low.y + v * (high.y - low.y), top);
  let z = select(low.z + v * (high.z - low.z), z_face, top);
  let kept = select(true, chosen_bit(cell) == 1u, lay.only_chosen == 1u) && (size >= lay.min_voxels);
  let in_range = (frame + lay.ghost_frames >= lay.frame_now) && (frame <= lay.frame_now);
  var out: Out;
  out.place = select(HIDDEN, project(x, y, z, frame), kept && in_range);
  out.colour = lit(cell, frame, 256u - face * 40u);
  out.pick = cell + 1u;
  return out;
}

@fragment
fn paint_fragment(input: Out) -> Drawn {
  return Drawn(input.colour, input.pick);
}`;

EV.LINES = EV.PRELUDE + EV.RENDER_BINDINGS + EV.RENDER_COMMON + `
@vertex
fn link(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  let at = lay.links_at + 2u * instance;
  let source = obj[at];
  let cell = obj[at + (vertex & 1u)];
  let frame = frame_of_cell(source) + (vertex & 1u);
  let middle = centroid(cell);
  let either = chosen_bit(obj[at]) | chosen_bit(obj[at + 1u]);
  let kept = select(true, either == 1u, lay.only_chosen == 1u);
  let tone = (paint(cell) * (96u + 160u * either)) / 256u;
  var out: Out;
  out.place = select(HIDDEN, project(middle.x, middle.y, middle.z, frame), kept);
  out.colour = vec4<f32>(vec3<f32>(tone) / 255.0, 1.0);
  out.pick = 0u;
  return out;
}

@vertex
fn edge(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  let at = lay.edges_at + 3u * instance;
  let source = obj[at];
  let status = min(obj[at + 2u], 4u);
  let whole = (source != 0xFFFFFFFFu) && (obj[at + 1u] != 0xFFFFFFFFu);
  let cell = select(0u, obj[at + (vertex & 1u)], whole);
  let middle = centroid(cell);
  let from_frame = frame_of_cell(select(0u, source, whole));
  let near = (from_frame + lay.ghost_frames >= lay.frame_now) && (from_frame <= lay.frame_now + 1u);
  let wanted = ((lay.status_mask >> status) & 1u) == 1u;
  var out: Out;
  out.place = select(HIDDEN, project(middle.x, middle.y, middle.z, from_frame + (vertex & 1u)), whole && near && wanted);
  out.colour = vec4<f32>(vec3<f32>(unpack(STATUS[status])) / 255.0, 1.0);
  out.pick = 0u;
  return out;
}

@fragment
fn paint_fragment(input: Out) -> Drawn {
  return Drawn(input.colour, input.pick);
}`;
