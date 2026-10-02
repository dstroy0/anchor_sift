// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// A float mesh and a line, drawn four times multisampled. A mesh is a grid of (u, v) samples, each with a position,
// a normal and a value, spread to 0 to 1; a line is a run of points, each with a value. The value picks a color
// along mint, blue and violet. A surface is lit from both sides, with a rim that brightens where it turns away from
// the eye, and can carry its own parameter lines, faint and antialiased, fading where they crowd closer than a
// pixel. Every color comes from the page's theme.

EV.MESH_WGSL = `
struct Frame {
  view_projection: mat4x4<f32>,
  eye: vec4<f32>,
  light: vec4<f32>,
  low: vec4<f32>,
  middle: vec4<f32>,
  high: vec4<f32>,
  rim: vec4<f32>,
  settings: vec4<f32>,
};
@group(0) @binding(0) var<uniform> frame: Frame;

struct Sample {
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(2) value: f32,
  @location(3) uv: vec2<f32>,
};

struct Shaded {
  @builtin(position) clip: vec4<f32>,
  @location(0) world: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(2) value: f32,
  @location(3) uv: vec2<f32>,
};

fn ramp(value: f32) -> vec3<f32> {
  let t = clamp(value, 0.0, 1.0);
  let lower = mix(frame.low.rgb, frame.middle.rgb, smoothstep(0.0, 0.5, t));
  return mix(lower, frame.high.rgb, smoothstep(0.5, 1.0, t));
}

@vertex
fn surface_vertex(sample: Sample) -> Shaded {
  var out: Shaded;
  out.clip = frame.view_projection * vec4<f32>(sample.position, 1.0);
  out.world = sample.position;
  out.normal = sample.normal;
  out.value = sample.value;
  out.uv = sample.uv;
  return out;
}

@fragment
fn surface_fragment(shaded: Shaded) -> @location(0) vec4<f32> {
  let toward = normalize(frame.eye.xyz - shaded.world);
  // The face under this pixel, from the change in position across it, turned toward the eye. The smooth normal is
  // flipped only where it disagrees with that face, which keeps a silhouette seen edge-on lit.
  var face = normalize(cross(dpdx(shaded.world), dpdy(shaded.world)));
  face = select(-face, face, dot(face, toward) >= 0.0);
  var normal = normalize(shaded.normal);
  normal = select(-normal, normal, dot(normal, face) >= 0.0);
  let light = normalize(frame.light.xyz);
  let diffuse = max(dot(normal, light), 0.0);
  let half_way = normalize(light + toward);
  let shine = pow(max(dot(normal, half_way), 0.0), 48.0) * 0.35;
  let facing = 1.0 - max(dot(normal, toward), 0.0);
  let rim = pow(facing, 2.6) * frame.rim.a;
  let base = ramp(shaded.value);
  var color = base * (0.22 + 0.78 * diffuse) + vec3<f32>(shine) + frame.rim.rgb * rim;
  let count = frame.settings.x;
  if (frame.settings.y > 0.5) {
    let cells = shaded.uv * count;
    let width = fwidth(cells) * 1.1;
    let near_line = abs(fract(cells - 0.5) - 0.5) / max(width, vec2<f32>(1e-4));
    let line = 1.0 - min(min(near_line.x, near_line.y), 1.0);
    let crowded = 1.0 - smoothstep(0.25, 0.6, max(width.x, width.y));
    color = mix(color, frame.rim.rgb, line * crowded * 0.28);
  }
  return vec4<f32>(color, 1.0);
}

struct Point {
  @location(0) position: vec3<f32>,
  @location(1) value: f32,
};

struct Traced {
  @builtin(position) clip: vec4<f32>,
  @location(0) value: f32,
};

@vertex
fn line_vertex(point: Point) -> Traced {
  var out: Traced;
  out.clip = frame.view_projection * vec4<f32>(point.position, 1.0);
  out.value = point.value;
  return out;
}

@fragment
fn line_fragment(traced: Traced) -> @location(0) vec4<f32> {
  return vec4<f32>(ramp(traced.value), 1.0);
}
`;

EV.FRAME_FLOATS = 16 + 4 * 7;

EV.startMesh = async (canvas, label) => {
  const { device, context, format } = await EV.openDevice(canvas, label);
  const module = device.createShaderModule({ code: EV.MESH_WGSL });
  const depth = { format: "depth24plus", depthWriteEnabled: true, depthCompare: "less" };
  const multisample = { count: 4 };
  const [surface, line] = await Promise.all([
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module, entryPoint: "surface_vertex", buffers: [{ arrayStride: 36, attributes: [
        { shaderLocation: 0, offset: 0, format: "float32x3" }, { shaderLocation: 1, offset: 12, format: "float32x3" },
        { shaderLocation: 2, offset: 24, format: "float32" }, { shaderLocation: 3, offset: 28, format: "float32x2" },
      ] }] },
      fragment: { module, entryPoint: "surface_fragment", targets: [{ format }] },
      primitive: { topology: "triangle-list", cullMode: "none" },
      depthStencil: depth, multisample,
    }),
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module, entryPoint: "line_vertex", buffers: [{ arrayStride: 16, attributes: [
        { shaderLocation: 0, offset: 0, format: "float32x3" }, { shaderLocation: 1, offset: 12, format: "float32" },
      ] }] },
      fragment: { module, entryPoint: "line_fragment", targets: [{ format }] },
      primitive: { topology: "line-strip" },
      depthStencil: depth, multisample,
    }),
  ]);
  const frame = device.createBuffer({ size: EV.FRAME_FLOATS * 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  return {
    device, context, format, canvas, pipelines: { surface, line }, frame, frameData: new Float32Array(EV.FRAME_FLOATS),
    groups: { surface: EV.bindGroup(device, surface, [frame]), line: EV.bindGroup(device, line, [frame]) },
    mesh: null, curve: null,
  };
};

// The color and depth targets follow the canvas's size in device pixels.
EV.fitMesh = (renderer) => {
  const canvas = renderer.canvas;
  const ratio = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.floor(canvas.clientWidth * ratio));
  const height = Math.max(1, Math.floor(canvas.clientHeight * ratio));
  if (renderer.color && canvas.width === width && canvas.height === height) {
    return;
  }
  canvas.width = width;
  canvas.height = height;
  renderer.color?.destroy();
  renderer.depth?.destroy();
  renderer.color = renderer.device.createTexture({ size: [width, height], sampleCount: 4, format: renderer.format, usage: GPUTextureUsage.RENDER_ATTACHMENT });
  renderer.depth = renderer.device.createTexture({ size: [width, height], sampleCount: 4, format: "depth24plus", usage: GPUTextureUsage.RENDER_ATTACHMENT });
};

// The samples of one surface on an n by n grid, after its transform, each with a value from valueOf.
EV.sampleSurface = (shape, transform, ctx, n, valueOf) => {
  const side = n + 1;
  const vertices = new Float32Array(side * side * 9);
  let sum = 0;
  let squares = 0;
  for (let row = 0; row < side; row++) {
    for (let column = 0; column < side; column++) {
      const u = column / n;
      const v = row / n;
      const raw = shape.at(u, v, ctx);
      const moved = transform.go(raw.p, raw.n, ctx);
      const at = (row * side + column) * 9;
      vertices.set(moved.p, at);
      vertices.set(moved.n, at + 3);
      vertices[at + 6] = valueOf(u, v, moved.p, moved.n);
      vertices[at + 7] = u;
      vertices[at + 8] = v;
      sum += vertices[at + 6];
      squares += vertices[at + 6] * vertices[at + 6];
    }
  }
  // Values spread over two standard deviations each side of their mean. A field whose values crowd the
  // middle still reaches both ends of the ramp.
  const count = side * side;
  const mean = sum / count;
  const spread = Math.sqrt(Math.max(0, squares / count - mean * mean)) * 4 || 1;
  for (let at = 6; at < vertices.length; at += 9) {
    vertices[at] = Math.max(0, Math.min(1, 0.5 + (vertices[at] - mean) / spread));
  }
  const indices = new Uint32Array(n * n * 6);
  let write = 0;
  for (let row = 0; row < n; row++) {
    for (let column = 0; column < n; column++) {
      const corner = row * side + column;
      indices.set([corner, corner + 1, corner + side, corner + 1, corner + side + 1, corner + side], write);
      write += 6;
    }
  }
  return { vertices, indices };
};

EV.uploadMesh = (renderer, mesh, curve) => {
  const device = renderer.device;
  for (const old of [renderer.mesh?.vertices, renderer.mesh?.indices, renderer.curve?.points]) {
    old?.destroy();
  }
  renderer.mesh = null;
  renderer.curve = null;
  if (mesh) {
    const vertices = device.createBuffer({ size: mesh.vertices.byteLength, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
    const indices = device.createBuffer({ size: mesh.indices.byteLength, usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST });
    device.queue.writeBuffer(vertices, 0, mesh.vertices);
    device.queue.writeBuffer(indices, 0, mesh.indices);
    renderer.mesh = { vertices, indices, count: mesh.indices.length };
  }
  if (curve) {
    const points = device.createBuffer({ size: curve.byteLength, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
    device.queue.writeBuffer(points, 0, curve);
    renderer.curve = { points, count: curve.length / 4 };
  }
};

// One frame. `look` holds the view-projection matrix, the eye, the light, the theme's colors and the grid settings.
EV.drawMesh = (renderer, look) => {
  EV.fitMesh(renderer);
  const data = renderer.frameData;
  data.set(look.viewProjection, 0);
  data.set([...look.eye, 1], 16);
  data.set([...look.light, 0], 20);
  data.set([...look.low, 1], 24);
  data.set([...look.middle, 1], 28);
  data.set([...look.high, 1], 32);
  data.set([...look.rim, look.rimStrength], 36);
  data.set([look.gridCount, look.grid ? 1 : 0, 0, 0], 40);
  const device = renderer.device;
  device.queue.writeBuffer(renderer.frame, 0, data);
  const encoder = device.createCommandEncoder();
  const pass = encoder.beginRenderPass({
    colorAttachments: [{ view: renderer.color.createView(), resolveTarget: renderer.context.getCurrentTexture().createView(),
                         clearValue: look.background, loadOp: "clear", storeOp: "discard" }],
    depthStencilAttachment: { view: renderer.depth.createView(), depthClearValue: 1, depthLoadOp: "clear", depthStoreOp: "discard" },
  });
  if (renderer.mesh) {
    pass.setPipeline(renderer.pipelines.surface);
    pass.setBindGroup(0, renderer.groups.surface);
    pass.setVertexBuffer(0, renderer.mesh.vertices);
    pass.setIndexBuffer(renderer.mesh.indices, "uint32");
    pass.drawIndexed(renderer.mesh.count);
  }
  if (renderer.curve) {
    pass.setPipeline(renderer.pipelines.line);
    pass.setBindGroup(0, renderer.groups.line);
    pass.setVertexBuffer(0, renderer.curve.points);
    pass.draw(renderer.curve.count);
  }
  pass.end();
  device.queue.submit([encoder.finish()]);
};
