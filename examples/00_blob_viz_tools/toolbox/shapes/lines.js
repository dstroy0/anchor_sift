// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Links and edges as lines.

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
  out.color = vec4<f32>(vec3<f32>(tone) / 255.0, 1.0);
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
  out.color = vec4<f32>(vec3<f32>(unpack(STATUS[status])) / 255.0, 1.0);
  out.pick = 0u;
  return out;
}

@fragment
fn paint_fragment(input: Out) -> Drawn {
  return Drawn(input.color, input.pick);
}`;
