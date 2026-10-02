// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Boxes warped out of runs, and cells as blobs.

EV.RENDER = EV.PRELUDE + EV.RENDER_BINDINGS + `
@group(0) @binding(4) var<storage, read> run_leaf: array<u32>;
@group(0) @binding(5) var<storage, read> compact: array<u32>;
` + EV.RENDER_COMMON + `
@vertex
fn box(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Out {
  let run = compact[instance + 1u];
  let voxel = obj[lay.runs_at + 2u * run];
  let span = i32(obj[lay.runs_at + 2u * run + 1u]);
  let leaf = run_leaf[run];
  let cell = obj[lay.leaves_at + 4u * leaf];
  let frame = obj[lay.leaves_at + 4u * leaf + 1u];
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
  out.color = lit(cell, frame, shade);
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
  out.color = lit(cell, frame, 256u - face * 40u);
  out.pick = cell + 1u;
  return out;
}

@fragment
fn paint_fragment(input: Out) -> Drawn {
  return Drawn(input.color, input.pick);
}`;
