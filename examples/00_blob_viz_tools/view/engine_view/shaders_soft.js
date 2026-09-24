// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Smooth cells. The blur: each run is an ellipsoid drawn as the ellipse it projects to, bright at its center and
// falling smoothly to nothing, so the runs of one cell merge into one translucent blob from every angle. The wall: each
// cell's solid ellipsoid of equal second moments, less the membrane, drawn into a texture of cell numbers; the
// composite traces a line wherever that number changes, in a lighter tone of the cell's color, over the blur. The
// wall is one smooth surface per cell, so no layer of the volume shows in it.
//
// Positions are integers up to the clip boundary, as everywhere; past it the ellipses and the blend are display
// arithmetic in f32 and feed no count. The blend is weighted, blended order-independent transparency (McGuire and
// Bavoil, 2013): every splat adds its weighted color to one target and multiplies its transparency into another, and
// the composite divides the first by its weight and lays the result over the page by the second. No sort is needed.
// Splats and walls take the same palette, the same step and a dissolve grain like the run's box, so the smooth cells
// move and shimmer as the voxel cells do.

EV.SOFT = EV.PRELUDE + EV.RENDER_BINDINGS + `
@group(0) @binding(4) var<storage, read> run_leaf: array<u32>;
@group(0) @binding(5) var<storage, read> compact: array<u32>;
` + EV.RENDER_COMMON + `
struct SoftOut {
  @builtin(position) place: vec4<f32>,
  @location(0) local: vec2<f32>,
  @location(1) @interpolate(flat) inverse: vec3<f32>,
  @location(2) @interpolate(flat) colour: vec4<f32>,
  @location(3) @interpolate(flat) cell: u32,
  @location(4) @interpolate(flat) far: f32,
}
struct SoftDrawn {
  @location(0) accumulated: vec4<f32>,
  @location(1) revealed: vec4<f32>,
}

struct WallDrawn {
  @location(0) pick: u32,
  @location(1) tone: vec4<f32>,
  @builtin(frag_depth) depth: f32,
}

// How far into the volume a point lies along the view: 0 at the nearest point the volume can reach and 1 at the
// farthest. The view depth is clip z * 16384 - 8192 doubled units, and no point of the volume lies farther from its
// center than the length of its half diagonal, width, height and depth * z_scale / 2 doubled units.
fn farness(clip_z: f32) -> f32 {
  let reach = length(vec3<f32>(f32(lay.width), f32(lay.height), f32(i32(lay.depth) * lay.z_scale) * 0.5));
  return clamp((clip_z * 16384.0 - 8192.0 + reach) / (2.0 * reach), 0.0, 1.0);
}

// One run as an ellipsoid in the volume, drawn as the exact ellipse it projects to. Its three semi-axes lie along x, y
// and z: along x half the run's length plus a reach of soft_radius halves of a voxel, along y that reach, and along z
// that reach in layers plus half a layer, so neighboring rows and layers overlap from every angle and the density does
// not band by layer. The reach grows with distance, by 35% at the far side, so far cells soften a little while near
// ones keep their shape.
//
// An ellipsoid with semi-axis vectors a, b, c projects orthographically to the ellipse of points p with
// p' M^-1 p <= 1, M = a a' + b b' + c c' taken on the screen: the same ellipse from any turn and tilt.
@vertex
fn soft(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> SoftOut {
  let run = compact[instance + 1u];
  let word = obj[lay.runs_at + run];
  let leaf = run_leaf[run];
  let cell = obj[lay.leaves_at + 4u * leaf];
  let frame = obj[lay.leaves_at + 4u * leaf + 1u];
  let voxel = word >> 8u;
  let span = i32(word & 255u) + 1;
  let step = step_of(cell, frame);
  let x = 2 * i32(voxel % lay.width) - i32(lay.width) + span + step.x;
  let y = 2 * i32((voxel / lay.width) % lay.height) - i32(lay.height) + 1 + step.y;
  let z = (lay.z_scale * (2 * i32(voxel / lay.plane) - i32(lay.depth) + 1)) / 2 + step.z;
  let half = vec2<f32>(f32(lay.half_w), f32(lay.half_h));
  let middle = project(x, y, z, frame);
  let centre = middle.xy * half;
  // A voxel and a layer on the screen, each measured over 32 of them so the integer turn's rounding is a 32nd.
  let across_x = (project(x + 64, y, z, frame).xy * half - centre) / 32.0;
  let across_y = (project(x, y + 64, z, frame).xy * half - centre) / 32.0;
  let across_z = (project(x, y, z + 32 * lay.z_scale, frame).xy * half - centre) / 32.0;
  // The distance is the cell's, taken at its centroid: every run of a cell carries one weight, so where two cells
  // overlap on the screen the nearer one wins throughout, never row by row.
  let own_centre = centroid(cell) + step;
  let far = farness(project(own_centre.x, own_centre.y, own_centre.z, frame).z);
  let reach = f32(lay.soft_radius) * 0.5 * (1.0 + 0.35 * far);
  let a = across_x * (f32(span) * 0.5 + reach);
  let b = across_y * reach;
  let c = across_z * (reach + 0.5);
  // Half a pixel added on the diagonal keeps an ellipse seen edge on from collapsing to a line.
  let m00 = a.x * a.x + b.x * b.x + c.x * c.x + 0.25;
  let m01 = a.x * a.y + b.x * b.y + c.x * c.y;
  let m11 = a.y * a.y + b.y * b.y + c.y * c.y + 0.25;
  let determinant = m00 * m11 - m01 * m01;
  let corner = vertex % 6u;
  let extent = vec2<f32>(sqrt(m00), sqrt(m11)) + vec2<f32>(1.0);
  let offset = vec2<f32>(select(-extent.x, extent.x, ((0x16u >> corner) & 1u) == 1u),
                         select(-extent.y, extent.y, ((0x34u >> corner) & 1u) == 1u));
  let grain = (run * 2654435761u) >> 20u;
  let eased = u32(ease(lay.progress));
  let shown = select(select(true, grain < eased, frame == lay.frame_now + 1u), grain >= eased, frame == lay.frame_now);
  var out: SoftOut;
  out.place = select(HIDDEN, vec4<f32>((centre + offset) / half, middle.z, 1.0), shown);
  out.local = offset;
  out.inverse = vec3<f32>(m11, -m01, m00) / determinant;
  out.cell = cell + 1u;
  out.far = far;
  // The cell's own lift or dim, as its body and wall take it, so the blur of neighbors of one lineage differs too.
  let own = 0.84 + 0.32 * f32((cell * 2246822519u) >> 24u) / 255.0;
  let tone = min(lit(cell, frame, 256u).rgb * own, vec3<f32>(1.0));
  out.colour = vec4<f32>(tone, f32(lay.soft_alpha) / 255.0);
  return out;
}

fn falloff_of(input: SoftOut) -> f32 {
  let d = input.local;
  let q = input.inverse.x * d.x * d.x + 2.0 * input.inverse.y * d.x * d.y + input.inverse.z * d.y * d.y;
  return clamp(1.0 - q, 0.0, 1.0);
}

// A Gaussian: the ellipse's edge lies at two and a half standard deviations, so with the reach of one and a half rows
// and two layers the deviation is 0.6 of a row and 0.8 of a layer, and Gaussians laid at that spacing sum to a density
// that ripples by under 1%: no row or layer shows as a band from any angle. The blend's weight falls as the fourth
// power of the distance into the volume, a thousand to one from the near side to the far, so a near cell holds its own
// pixels against everything behind it; a far splat is also drawn at 70% of its opacity.
@fragment
fn soft_fragment(input: SoftOut) -> SoftDrawn {
  let d = input.local;
  let q = input.inverse.x * d.x * d.x + 2.0 * input.inverse.y * d.x * d.y + input.inverse.z * d.y * d.y;
  let alpha = input.colour.a * exp(-3.125 * q) * f32(q < 1.0) * (1.0 - 0.3 * input.far);
  let far = input.far;
  let weight = alpha * clamp(1.0 / (0.001 + far * far * far * far), 0.01, 1000.0);
  return SoftDrawn(vec4<f32>(input.colour.rgb * alpha * weight, alpha * weight), vec4<f32>(alpha));
}

@group(0) @binding(6) var<storage, read> shape: array<i32>;

// A cell's ellipsoid: the solid ellipsoid with the cell's own second moments, drawn as the ellipse it projects to. A
// solid ellipsoid's second moment along a semi-axis of length r is r^2 / 5, so with the moments C in voxels squared the
// projected ellipse is M = 5 P C P', P taking a voxel along x and y and a layer along z to the screen. The wall is
// shrunk by the membrane; the body is not. Both ride the cell's step and dissolve by the cell's grain across a
// transition.
fn cell_ellipse(vertex: u32, cell: u32, wall: bool) -> SoftOut {
  let frame = frame_of_cell(cell);
  let size = obj[lay.cells_at + 4u * cell];
  let middle = centroid(cell) + step_of(cell, frame);
  let half = vec2<f32>(f32(lay.half_w), f32(lay.half_h));
  let projected = project(middle.x, middle.y, middle.z, frame);
  let centre = projected.xy * half;
  let per_x = (project(middle.x + 64, middle.y, middle.z, frame).xy * half - centre) / 32.0;
  let per_y = (project(middle.x, middle.y + 64, middle.z, frame).xy * half - centre) / 32.0;
  let per_z = (project(middle.x, middle.y, middle.z + 32 * lay.z_scale, frame).xy * half - centre) / 32.0;
  let at = 6u * cell;
  let zz = f32(shape[at]) / 256.0;
  let yy = f32(shape[at + 1u]) / 256.0;
  let xx = f32(shape[at + 2u]) / 256.0;
  let zy = f32(shape[at + 3u]) / 256.0;
  let zx = f32(shape[at + 4u]) / 256.0;
  let yx = f32(shape[at + 5u]) / 256.0;
  // M = 5 (sum over axis pairs of C_ij p_i p_j'), taken for the two screen components.
  let m00 = 5.0 * (xx * per_x.x * per_x.x + yy * per_y.x * per_y.x + zz * per_z.x * per_z.x
                   + 2.0 * (yx * per_x.x * per_y.x + zx * per_x.x * per_z.x + zy * per_y.x * per_z.x));
  let m11 = 5.0 * (xx * per_x.y * per_x.y + yy * per_y.y * per_y.y + zz * per_z.y * per_z.y
                   + 2.0 * (yx * per_x.y * per_y.y + zx * per_x.y * per_z.y + zy * per_y.y * per_z.y));
  let m01 = 5.0 * (xx * per_x.x * per_x.y + yy * per_y.x * per_y.y + zz * per_z.x * per_z.y
                   + yx * (per_x.x * per_y.y + per_y.x * per_x.y) + zx * (per_x.x * per_z.y + per_z.x * per_x.y)
                   + zy * (per_y.x * per_z.y + per_z.x * per_y.y));
  // The membrane shrinks every radius by the same number of voxels; a voxel is |per_x| pixels.
  let radius = sqrt(max(0.5 * (m00 + m11), 0.0001));
  let membrane = select(0.0, (f32(lay.wall_inset) / 65536.0) * length(per_x), wall);
  let shrink = max(radius - membrane, 0.5) / radius;
  let n00 = m00 * shrink * shrink + 0.25;
  let n11 = m11 * shrink * shrink + 0.25;
  let n01 = m01 * shrink * shrink;
  let determinant = n00 * n11 - n01 * n01;
  let corner = vertex % 6u;
  let extent = vec2<f32>(sqrt(n00), sqrt(n11)) + vec2<f32>(1.0);
  let offset = vec2<f32>(select(-extent.x, extent.x, ((0x16u >> corner) & 1u) == 1u),
                         select(-extent.y, extent.y, ((0x34u >> corner) & 1u) == 1u));
  let grain = (cell * 2654435761u) >> 20u;
  let eased = u32(ease(lay.progress));
  let now = frame == lay.frame_now;
  let next = frame == lay.frame_now + 1u;
  let shown = select(select(false, grain < eased, next), grain >= eased, now);
  let kept = select(true, chosen_bit(cell) == 1u, lay.only_chosen == 1u) && (size >= lay.min_voxels);
  var out: SoftOut;
  out.place = select(HIDDEN, vec4<f32>((centre + offset) / half, projected.z, 1.0), shown && kept);
  out.local = offset;
  out.inverse = vec3<f32>(n11, -n01, n00) / determinant;
  out.cell = cell + 1u;
  let far = farness(projected.z);
  out.far = far;
  // How much of its ellipsoid the cell fills: its voxels over the ellipsoid's volume, 4/3 pi times the product of the
  // semi-axes, sqrt(125 det C). A compact cell is near 1; a sprawling object of many cells joined is near 0, and its
  // body and wall fade out as the share falls from 0.4 to 0.1. They also fade out as the cell grows from 8 to 32 times
  // the median cell of its frame, typical_voxels: a solid fused object is compact but far larger than any one cell.
  // Either way one fused object cannot cover the cells around it, and it still shows through its runs' blur.
  let spread = xx * (yy * zz - zy * zy) - yx * (yx * zz - zy * zx) + zx * (yx * zy - yy * zx);
  let compact = clamp(f32(size) / (4.18879 * sqrt(max(125.0 * spread, 0.0001))), 0.0, 1.0);
  // Cells of one lineage share a color; each is lifted or dimmed by up to a sixth by its own number so neighbors of one
  // lineage still read as separate cells.
  let own = 0.84 + 0.32 * f32((cell * 2246822519u) >> 24u) / 255.0;
  let tone = min(lit(cell, frame, 256u).rgb * own, vec3<f32>(1.0));
  // A wall's tone is lifted toward white and its alpha carries its nearness and solidity, so the composite fades walls
  // with distance and sprawl; a body's tone is the cell's own at the body's opacity times its solidity.
  let typical = f32(max(lay.typical_voxels, 1u));
  let solid = smoothstep(0.1, 0.4, compact) * (1.0 - smoothstep(8.0 * typical, 32.0 * typical, f32(size)));
  out.colour = select(vec4<f32>(tone, solid * f32(lay.body_alpha) / 255.0),
                      vec4<f32>(tone + (vec3<f32>(1.0) - tone) * (f32(lay.wall_tone) / 255.0), (1.0 - 0.35 * far) * solid), wall);
  return out;
}

// The map's flat cells: each cell's ellipsoid turned by the camera, yaw about z and then tilt about the turned x,
// projected orthographically by dropping the view depth, and fitted so the volume's half diagonal, map_reach doubled
// units, fills the square texture of cell numbers. Nothing of zoom, pan or spread applies. The composite fills each
// cell's ellipse with its color and outlines it; the nearest cell is in front.
// The plane stays overhead and never turns: a place on it is where the cell stands seen from straight above, laid
// on the same still image the map draws under it, so the map holds while the view moves. Row zero is at the top,
// as the image has it, and the clip space counts the other way.
fn map_place(x: i32, y: i32, z: i32) -> vec3<f32> {
  let across = f32(x * lay.slice_scale) / f32(256 * max(lay.slice_w, 1));
  let down = f32(y * lay.slice_scale) / f32(256 * max(lay.slice_h, 1));
  let reach = f32(lay.map_reach);
  // Overhead, the nearest cell is the highest one, so its own height is the depth it is written at.
  return vec3<f32>(across, -down, (f32(z) + reach) / (2.0 * reach));
}

// What the camera makes of a step in the volume: the cells keep the shape the view gives them as it turns, and
// that shape is what falls on the plane below. Only the shape turns; where it falls does not.
fn map_turn(x: i32, y: i32, z: i32) -> vec2<f32> {
  let x1 = (lay.yaw_cos * x - lay.yaw_sin * y) >> 14u;
  let y1 = (lay.yaw_sin * x + lay.yaw_cos * y) >> 14u;
  let z2 = (lay.pitch_sin * y1 + lay.pitch_cos * z) >> 14u;
  let reach = f32(lay.map_reach);
  return vec2<f32>(f32(x1) / reach, f32(z2) / reach);
}

@vertex
fn map_cell(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> SoftOut {
  let cell = instance;
  let frame = frame_of_cell(cell);
  let size = obj[lay.cells_at + 4u * cell];
  let middle = centroid(cell) + step_of(cell, frame);
  // The map texture is EV.MAP_SIZE texels across; a unit of the fitted projection is half of that.
  let half = vec2<f32>(f32(${EV.MAP_SIZE}) * 0.5);
  let projected = map_place(middle.x, middle.y, middle.z);
  let centre = projected.xy * half;
  // Where it falls is overhead and still; what falls is the shape the camera is making of it.
  let turned = map_turn(middle.x, middle.y, middle.z) * half;
  let per_x = (map_turn(middle.x + 64, middle.y, middle.z) * half - turned) / 32.0;
  let per_y = (map_turn(middle.x, middle.y + 64, middle.z) * half - turned) / 32.0;
  let per_z = (map_turn(middle.x, middle.y, middle.z + 32 * lay.z_scale) * half - turned) / 32.0;
  let at = 6u * cell;
  let zz = f32(shape[at]) / 256.0;
  let yy = f32(shape[at + 1u]) / 256.0;
  let xx = f32(shape[at + 2u]) / 256.0;
  let zy = f32(shape[at + 3u]) / 256.0;
  let zx = f32(shape[at + 4u]) / 256.0;
  let yx = f32(shape[at + 5u]) / 256.0;
  let m00 = 5.0 * (xx * per_x.x * per_x.x + yy * per_y.x * per_y.x + zz * per_z.x * per_z.x
                   + 2.0 * (yx * per_x.x * per_y.x + zx * per_x.x * per_z.x + zy * per_y.x * per_z.x)) + 0.25;
  let m11 = 5.0 * (xx * per_x.y * per_x.y + yy * per_y.y * per_y.y + zz * per_z.y * per_z.y
                   + 2.0 * (yx * per_x.y * per_y.y + zx * per_x.y * per_z.y + zy * per_y.y * per_z.y)) + 0.25;
  let m01 = 5.0 * (xx * per_x.x * per_x.y + yy * per_y.x * per_y.y + zz * per_z.x * per_z.y
                   + yx * (per_x.x * per_y.y + per_y.x * per_x.y) + zx * (per_x.x * per_z.y + per_z.x * per_x.y)
                   + zy * (per_y.x * per_z.y + per_z.x * per_y.y));
  let determinant = m00 * m11 - m01 * m01;
  let corner = vertex % 6u;
  let extent = vec2<f32>(sqrt(m00), sqrt(m11)) + vec2<f32>(1.0);
  let offset = vec2<f32>(select(-extent.x, extent.x, ((0x16u >> corner) & 1u) == 1u),
                         select(-extent.y, extent.y, ((0x34u >> corner) & 1u) == 1u));
  let grain = (cell * 2654435761u) >> 20u;
  let eased = u32(ease(lay.progress));
  let shown = select(select(false, grain < eased, frame == lay.frame_now + 1u), grain >= eased, frame == lay.frame_now);
  let kept = select(true, chosen_bit(cell) == 1u, lay.only_chosen == 1u) && (size >= lay.min_voxels);
  // A fused object is left off the map as it is left out of the bodies: by its share of its ellipsoid and its size.
  let spread = xx * (yy * zz - zy * zy) - yx * (yx * zz - zy * zx) + zx * (yx * zy - yy * zx);
  let compact = clamp(f32(size) / (4.18879 * sqrt(max(125.0 * spread, 0.0001))), 0.0, 1.0);
  let typical = f32(max(lay.typical_voxels, 1u));
  let solid = smoothstep(0.1, 0.4, compact) * (1.0 - smoothstep(8.0 * typical, 32.0 * typical, f32(size)));
  var out: SoftOut;
  out.place = select(HIDDEN, vec4<f32>((centre + offset) / half, projected.z, 1.0), shown && kept && (solid >= 0.5));
  out.local = offset;
  out.inverse = vec3<f32>(m11, -m01, m00) / determinant;
  out.cell = cell + 1u;
  out.far = 0.0;
  out.colour = vec4<f32>(0.0);
  return out;
}

struct MapDrawn {
  @location(0) pick: u32,
  @builtin(frag_depth) depth: f32,
}

// Inside its ellipse a cell writes its number at its depth; outside, depth 1 never passes the cleared depth.
@fragment
fn map_cell_fragment(input: SoftOut) -> MapDrawn {
  let falloff = falloff_of(input);
  return MapDrawn(input.cell, select(1.0, input.place.z, falloff > 0.0));
}

// The plane holds the whole volume and not its near face: every cell adds its own colour where its ellipse
// covers, nothing tested against depth and nothing hidden behind anything else. The weight added beside the
// colour is what the composite divides by, so a place many cells reach reads as all of their colours together
// rather than as whichever of them happened to lie nearest the camera.
@fragment
fn map_paint_fragment(input: SoftOut) -> @location(0) vec4<f32> {
  let falloff = falloff_of(input);
  let tone = vec3<f32>(paint(input.cell - 1u)) / 255.0;
  return vec4<f32>(tone * falloff, falloff);
}

@vertex
fn wall_cell(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> SoftOut {
  return cell_ellipse(vertex, instance, true);
}

@vertex
fn body_cell(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> SoftOut {
  return cell_ellipse(vertex, instance, false);
}

// One light's contribution at a surface normal seen from the front: diffuse by the cosine to the light, and a soft
// highlight where the normal halves the way between the light and the eye. A light is its direction in view space, x
// right, y up, z toward the eye, times 256, and its strength of 255.
fn light_at(normal: vec3<f32>, x: i32, y: i32, z: i32, strength: u32, on: bool) -> f32 {
  let toward = normalize(vec3<f32>(f32(x), f32(y), f32(z)) + vec3<f32>(0.0, 0.0, 0.0001));
  let diffuse = max(dot(normal, toward), 0.0);
  let halfway = normalize(toward + vec3<f32>(0.0, 0.0, 1.0));
  let highlight = pow(max(dot(normal, halfway), 0.0), 24.0) * 0.35;
  return select(0.0, (diffuse + highlight) * f32(strength) / 255.0, on);
}

// A cell's body, lit: the ellipse read as the front of its ellipsoid, the normal tilting from facing the eye at the
// center to lying in the screen at the rim, shaded by every light that is on, and blended like the blur with its
// alpha easing out toward the rim.
@fragment
fn body_fragment(input: SoftOut) -> SoftDrawn {
  let d = input.local;
  let gradient = vec2<f32>(input.inverse.x * d.x + input.inverse.y * d.y, input.inverse.y * d.x + input.inverse.z * d.y);
  let q = d.x * gradient.x + d.y * gradient.y;
  let rim = sqrt(max(1.0 - q, 0.0));
  let tilt = gradient * inverseSqrt(max(dot(gradient, gradient) / max(q, 0.000001), 0.000001));
  let normal = normalize(vec3<f32>(tilt, rim + 0.0001));
  let count = lay.light_count;
  let shade = 0.22 + light_at(normal, lay.light0_x, lay.light0_y, lay.light0_z, lay.light0_strength, count > 0u)
                   + light_at(normal, lay.light1_x, lay.light1_y, lay.light1_z, lay.light1_strength, count > 1u)
                   + light_at(normal, lay.light2_x, lay.light2_y, lay.light2_z, lay.light2_strength, count > 2u)
                   + light_at(normal, lay.light3_x, lay.light3_y, lay.light3_z, lay.light3_strength, count > 3u);
  let falloff = clamp(1.0 - q, 0.0, 1.0);
  let alpha = input.colour.a * smoothstep(0.0, 0.12, falloff);
  let far = input.far;
  let weight = alpha * clamp(1.0 / (0.001 + far * far * far * far), 0.01, 1000.0);
  let colour = min(input.colour.rgb * shade, vec3<f32>(1.0));
  return SoftDrawn(vec4<f32>(colour * alpha * weight, alpha * weight), vec4<f32>(alpha));
}

// The wall's cell at a pixel is the nearest cell there, and between cells at one depth the one whose ellipse is most
// central: the depth written is the view depth plus the distance from the ellipse's center, scaled to about two voxels
// of depth, so the depth test keeps cells in front and settles touching cells by their rounded shapes. Outside an
// ellipse the depth is 1, which never passes the cleared depth, so the region outside every cell keeps cell 0 and the
// wall between a cell and the outside follows the ellipses' rounded union.
@fragment
fn wall_soft_fragment(input: SoftOut) -> WallDrawn {
  let falloff = falloff_of(input);
  return WallDrawn(input.cell, input.colour, select(1.0, input.place.z + (1.0 - falloff) * 0.00025, falloff > 0.0));
}`;

EV.SOFT_COMPOSITE = EV.PRELUDE + `
@group(0) @binding(0) var accumulated: texture_2d<f32>;
@group(0) @binding(1) var revealed: texture_2d<f32>;
@group(0) @binding(2) var wall_ids: texture_2d<u32>;
@group(0) @binding(3) var wall_tones: texture_2d<f32>;
@group(0) @binding(4) var<uniform> lay: Layout;
@group(0) @binding(5) var raw: texture_3d<u32>;

// The slide under the cells: the microscope's own voxels, gathered along the very ray the view is looking down,
// so the image and what the engine made of it stand in the same place at the same turn. The pixel is carried back
// through the turn, the brightest voxel along it stands, and the slider says how much of it is seen against the
// representation. Nothing of the two is drawn twice: one fades in as the other fades out.
fn slide_grey(pixel: vec2<i32>) -> vec2<f32> {
  let wide = i32(lay.half_w);
  let high = i32(lay.half_h);
  // Back through the view's own placing: the pixel as the turned place it came from, before the zoom and the pan.
  let across = (((pixel.x - wide) * 256 * 128) / max(lay.zoom, 1) - lay.pan_x * 128 / max(lay.zoom, 1)) / 128;
  let up = (((high - pixel.y) * 256 * 128) / max(lay.zoom, 1) - lay.pan_y * 128 / max(lay.zoom, 1)) / 128;
  let reach = i32(lay.map_reach);
  var brightest = 0u;
  var held_any = false;
  for (var step = 0u; step < ${EV.MAP_STEPS}u; step++) {
    let deep = -reach + i32((2u * u32(reach) * step) / (${EV.MAP_STEPS}u - 1u));
    let y1 = (lay.pitch_cos * deep + lay.pitch_sin * up) >> 14u;
    let turned_z = (lay.pitch_cos * up - lay.pitch_sin * deep) >> 14u;
    let turned_x = (lay.yaw_cos * across + lay.yaw_sin * y1) >> 14u;
    let turned_y = (lay.yaw_cos * y1 - lay.yaw_sin * across) >> 14u;
    let voxel = vec3<i32>((turned_x + i32(lay.width)) / 2, (turned_y + i32(lay.height)) / 2,
                          ((turned_z * 2) / max(i32(lay.z_scale), 1) + i32(lay.depth)) / 2);
    let held = (voxel.x >= 0) && (voxel.y >= 0) && (voxel.z >= 0) && (voxel.x < i32(lay.width))
            && (voxel.y < i32(lay.height)) && (voxel.z < i32(lay.depth));
    held_any = held_any || held;
    let at_voxel = clamp(voxel, vec3<i32>(0), vec3<i32>(i32(lay.width) - 1, i32(lay.height) - 1, i32(lay.depth) - 1));
    let read = textureLoad(raw, at_voxel * i32(lay.raw_on), 0).r;
    brightest = max(brightest, read * u32(held) * lay.raw_on);
  }
  let span = max(lay.window_high, lay.window_low + 1u) - lay.window_low;
  let grey = f32(min(max(brightest, lay.window_low) - lay.window_low, span)) / f32(span);
  return vec2<f32>(grey * f32(lay.raw_on), select(0.0, 1.0, held_any && (lay.raw_on == 1u)));
}

@vertex
fn cover(@builtin(vertex_index) vertex: u32) -> @builtin(position) vec4<f32> {
  let corner = vec2<i32>(i32(vertex & 1u) * 4 - 1, i32((vertex >> 1u) & 1u) * 4 - 1);
  return vec4<f32>(vec2<f32>(corner), 0.5, 1.0);
}

fn wall_at(pixel: vec2<i32>) -> u32 {
  let size = vec2<i32>(textureDimensions(wall_ids));
  return textureLoad(wall_ids, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0).r;
}

@fragment
fn compose(@builtin(position) at: vec4<f32>) -> @location(0) vec4<f32> {
  let pixel = vec2<i32>(at.xy);
  // Alpha smoothing: both blend targets are read through a 3 by 3 tent, weights 1 2 1 by 1 2 1 over 16, before the
  // color is resolved, so the edges of blobs and the grain of the dissolve soften by a pixel.
  let limit = vec2<i32>(textureDimensions(accumulated)) - vec2<i32>(1);
  var sum = vec4<f32>(0.0);
  var clear = 0.0;
  for (var row = -1; row <= 1; row++) {
    for (var column = -1; column <= 1; column++) {
      let weight = f32((2 - abs(row)) * (2 - abs(column))) / 16.0;
      let near = clamp(pixel + vec2<i32>(column, row), vec2<i32>(0), limit);
      sum += textureLoad(accumulated, near, 0) * weight;
      clear += textureLoad(revealed, near, 0).r * weight;
    }
  }
  let blob_alpha = 1.0 - clear;
  let blob = sum.rgb / max(sum.a, 0.00001);
  // A wall pixel lies inside a shrunken cell and beside a pixel of another cell or of none.
  let own = wall_at(pixel);
  // Two pixels wide: a wall pixel has another cell, or none, within one pixel in any of the eight directions.
  var differs = false;
  for (var row = -1; row <= 1; row++) {
    for (var column = -1; column <= 1; column++) {
      differs = differs || (own != wall_at(pixel + vec2<i32>(column, row)));
    }
  }
  let edge = (own != 0u) && differs;
  // A wall is drawn at its tone's alpha: full for a near compact cell, 65% at the far side, less with sprawl.
  let wall_tone = textureLoad(wall_tones, pixel, 0);
  let wall_alpha = select(0.0, f32(lay.wall_alpha) / 255.0, edge && (lay.wall_on == 1u)) * wall_tone.a;
  let wall = wall_tone.rgb;
  let alpha = blob_alpha + wall_alpha * (1.0 - blob_alpha);
  let mixed = (blob * blob_alpha * (1.0 - wall_alpha) + wall * wall_alpha) / max(alpha, 0.00001);
  // The slider between what the microscope saw and what the engine made of it: at nothing only the cells stand,
  // at full only the slide, and between them each is there in its own measure, in the same place at the same turn.
  let slide = f32(lay.slide) / 255.0;
  let seen = slide_grey(pixel);
  let slide_alpha = seen.y * slide;
  let ours = alpha * (1.0 - slide);
  let together = ours + slide_alpha * (1.0 - ours);
  let shown = (mixed * ours * (1.0 - slide_alpha) + vec3<f32>(seen.x) * slide_alpha) / max(together, 0.00001);
  return vec4<f32>(shown, together);
}`;
