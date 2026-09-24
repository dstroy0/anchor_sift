// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The map. The image holds still: the frame seen from above, as the brightest voxel of each column, or one layer's
// voxels. The cells on it are flat and move with the camera: each cell's ellipsoid is turned by the camera's yaw and
// tilt and projected orthographically into a square texture of cell numbers (map_cell, in the smooth shaders), and as
// the camera turns the flat cells shift as the volume does. The composite reads that texture and the image at each pixel of
// the map square, fills each cell with its color over the windowed intensity, and outlines it where a neighboring
// texel belongs to another cell. Integers until the texture reads.

EV.MAP_SIZE = 512;

// Steps a map pixel's ray takes across the reach. The reach is the volume's half diagonal in doubled units, so
// this many steps lands within a voxel or two of every layer without reading the whole diagonal.
EV.MAP_STEPS = 256;

EV.SLICE_COMPOSITE = EV.PRELUDE + EV.RENDER_BINDINGS + `
@group(0) @binding(4) var ids: texture_2d<u32>;
@group(0) @binding(5) var raw: texture_3d<u32>;
@group(0) @binding(7) var painted: texture_2d<f32>;
` + EV.RENDER_COMMON + `
@vertex
fn slice_cover(@builtin(vertex_index) vertex: u32) -> @builtin(position) vec4<f32> {
  let corner = vec2<i32>(i32(vertex & 1u) * 4 - 1, i32((vertex >> 1u) & 1u) * 4 - 1);
  return vec4<f32>(vec2<f32>(corner), 0.5, 1.0);
}

fn id_at(texel: vec2<i32>) -> u32 {
  let size = vec2<i32>(textureDimensions(ids));
  return textureLoad(ids, clamp(texel, vec2<i32>(0), size - vec2<i32>(1)), 0).r;
}

@fragment
fn slice_paint(@builtin(position) at: vec4<f32>) -> Drawn {
  let right = i32(at.x) - lay.slice_x0;
  let down = i32(at.y) - lay.slice_y0;
  let inside = (right >= 0) && (down >= 0) && (right < lay.slice_w) && (down < lay.slice_h);
  // The image: the volume itself laid flat on the plane. The square's pixel is a place on that plane, in the same
  // doubled and centred units the cells are turned in, and the ray behind it is walked back through the volume by
  // the camera's own turn read the other way round: what the cells' turn scatters out, this gathers in. The
  // brightest voxel along the ray stands. So the whole volume is on the plane, and none of it is a box held still.
  // The plane is overhead and holds still, so the pixel is the column straight under it, the image centred in
  // the square with row zero at the top. Nothing here turns; only what falls on the plane does.
  let column = vec2<i32>(i32(lay.width) / 2 + ((right - lay.slice_w / 2) * 256) / max(lay.slice_scale, 1),
                         i32(lay.height) / 2 + ((down - lay.slice_h / 2) * 256) / max(lay.slice_scale, 1));
  let on_image = (column.x >= 0) && (column.y >= 0) && (column.x < i32(lay.width)) && (column.y < i32(lay.height));
  // The whole volume is given up onto that one place: the brightest voxel of the column standing for all of it,
  // or one layer where the map is asked for a layer.
  let layers = select(1u, lay.depth, lay.map_projection == 1u);
  let first_layer = select(lay.slice_z, 0u, lay.map_projection == 1u);
  let at_column = clamp(column, vec2<i32>(0), vec2<i32>(i32(lay.width) - 1, i32(lay.height) - 1)) * i32(lay.raw_on);
  var raw_value = 0u;
  for (var layer = 0u; layer < max(layers, 1u); layer++) {
    let at_layer = i32(min(first_layer + layer, lay.depth - 1u)) * i32(lay.raw_on);
    raw_value = max(raw_value, textureLoad(raw, vec3<i32>(at_column, at_layer), 0).r);
  }
  raw_value = raw_value * u32(on_image) * lay.raw_on;
  let span = max(lay.window_high, lay.window_low + 1u) - lay.window_low;
  let grey = (min(max(raw_value, lay.window_low) - lay.window_low, span) * 255u) / span * lay.raw_on * u32(on_image);
  // The cells: the square's pixel read as a texel of the turned, projected cell numbers.
  let size = i32(textureDimensions(ids).x);
  let texel = vec2<i32>((right * size) / max(lay.slice_w, 1), (down * size) / max(lay.slice_h, 1));
  let id = id_at(texel);
  let outline = (id != id_at(texel + vec2<i32>(1, 0))) || (id != id_at(texel - vec2<i32>(1, 0)))
             || (id != id_at(texel + vec2<i32>(0, 1))) || (id != id_at(texel - vec2<i32>(0, 1)));
  let filled = id != 0u;
  let cell = select(0u, id - 1u, filled);
  let picked = chosen_bit(cell) * u32(filled);
  // The plane's colour is every cell that reaches this place, divided by how much of them reached it, so a cell
  // behind another still shows through: what is drawn is the whole volume flattened and not its nearest face.
  let gathered = textureLoad(painted, clamp(texel, vec2<i32>(0), vec2<i32>(size - 1)), 0);
  let reached = gathered.a;
  let flattened = vec3<u32>(clamp(gathered.rgb / max(reached, 0.0001), vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0);
  // How much of the plane this place holds, one cell's worth of cover being the whole of it.
  let covered = u32(clamp(reached, 0.0, 1.0) * 255.0);
  let alpha = select((covered * 88u) / 255u, 255u, outline && filled);
  let tone = select(flattened, vec3<u32>(255u), outline && filled && (picked == 1u));
  let mixed = (vec3<u32>(grey) * (256u - alpha) + tone * alpha) / 256u;
  let hovered = u32(filled && (lay.hover_cell == id)) * 40u;
  let shown = min(mixed + vec3<u32>(hovered), vec3<u32>(255u));
  return Drawn(select(vec4<f32>(0.03, 0.035, 0.045, 1.0), vec4<f32>(vec3<f32>(shown) / 255.0, 1.0), inside),
               select(0u, id, inside));
}`;
