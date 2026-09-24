// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The card's side: the device, every pipeline compiled before anything is timed, the object streamed from the wire
// or a file straight into one mapped storage buffer, the compaction, the passes and the one-pixel pick.

EV.words = (count) => Math.max(4, (count + 1) * 4);

EV.workgroups = (count) => {
  const groups = Math.max(1, Math.ceil(count / 256));
  return [Math.min(groups, 65535), Math.ceil(groups / 65535)];
};

EV.nextPower = (count) => {
  let power = 1;
  while (power < count) {
    power *= 2;
  }
  return power;
};

EV.startGpu = async (canvas) => {
  if (!navigator.gpu) {
    throw new Error("this browser has no WebGPU; Chrome 113 or later has it");
  }
  const adapter = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
  if (!adapter) {
    throw new Error("WebGPU found no adapter");
  }
  const device = await adapter.requestDevice({
    requiredLimits: {
      maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
      maxBufferSize: adapter.limits.maxBufferSize,
      maxStorageBuffersPerShaderStage: Math.min(8, adapter.limits.maxStorageBuffersPerShaderStage),
    },
  });
  device.addEventListener("uncapturederror", (event) => console.error("[engine view]", event.error.message));
  const context = canvas.getContext("webgpu");
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({ device, format, alphaMode: "opaque" });

  const began = performance.now();
  const compute = (code) => device.createComputePipelineAsync({
    layout: "auto", compute: { module: device.createShaderModule({ code }), entryPoint: "main" },
  });
  const renderModule = device.createShaderModule({ code: EV.RENDER });
  const linesModule = device.createShaderModule({ code: EV.LINES });
  const compositeModule = device.createShaderModule({ code: EV.SLICE_COMPOSITE });
  const targets = [{ format }, { format: "r32uint" }];
  const solid = { format: "depth24plus", depthWriteEnabled: true, depthCompare: "less" };
  const above = { format: "depth24plus", depthWriteEnabled: false, depthCompare: "always" };
  const draw = (module, vertex, fragment, topology, depthStencil, lineTargets) => device.createRenderPipelineAsync({
    layout: "auto",
    vertex: { module, entryPoint: vertex },
    fragment: { module, entryPoint: fragment, targets: lineTargets || targets },
    primitive: { topology, cullMode: "none" },
    depthStencil,
  });
  const quiet = [{ format }, { format: "r32uint", writeMask: 0 }];
  const softModule = device.createShaderModule({ code: EV.SOFT });
  const composeModule = device.createShaderModule({ code: EV.SOFT_COMPOSITE });
  const adding = { color: { srcFactor: "one", dstFactor: "one", operation: "add" }, alpha: { srcFactor: "one", dstFactor: "one", operation: "add" } };
  const clearing = { color: { srcFactor: "zero", dstFactor: "one-minus-src", operation: "add" }, alpha: { srcFactor: "zero", dstFactor: "one-minus-src", operation: "add" } };
  const over = { color: { srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha", operation: "add" }, alpha: { srcFactor: "one", dstFactor: "one-minus-src-alpha", operation: "add" } };
  const splatTargets = [{ format: "rgba16float", blend: adding }, { format: "r8unorm", blend: clearing }];
  const [resolve, keep, level, scatter, count, box, blob, link, edge, mapIds, mapPaint, sliceComposite, soft, softCompose, boxPick, wall, body] = await Promise.all([
    compute(EV.RESOLVE), compute(EV.KEEP), compute(EV.LEVEL), compute(EV.SCATTER), compute(EV.COUNT),
    draw(renderModule, "box", "paint_fragment", "triangle-list", solid),
    draw(renderModule, "blob", "paint_fragment", "triangle-list", solid),
    draw(linesModule, "link", "paint_fragment", "line-list", { format: "depth24plus", depthWriteEnabled: false, depthCompare: "less" }, quiet),
    draw(linesModule, "edge", "paint_fragment", "line-list", above, quiet),
    draw(softModule, "map_cell", "map_cell_fragment", "triangle-list", solid, [{ format: "r32uint" }]),
    // The plane's colour: no depth at all, every cell adding into what is already there.
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module: softModule, entryPoint: "map_cell" },
      fragment: { module: softModule, entryPoint: "map_paint_fragment",
                  targets: [{ format: "rgba16float", blend: adding }] },
      primitive: { topology: "triangle-list", cullMode: "none" },
    }),
    draw(compositeModule, "slice_cover", "slice_paint", "triangle-list", above),
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module: softModule, entryPoint: "soft" },
      fragment: { module: softModule, entryPoint: "soft_fragment", targets: splatTargets },
      primitive: { topology: "triangle-list", cullMode: "none" },
    }),
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module: composeModule, entryPoint: "cover" },
      fragment: { module: composeModule, entryPoint: "compose", targets: [{ format, blend: over }, { format: "r32uint", writeMask: 0 }] },
      primitive: { topology: "triangle-list", cullMode: "none" },
      depthStencil: above,
    }),
    draw(renderModule, "box", "paint_fragment", "triangle-list", solid, [{ format, writeMask: 0 }, { format: "r32uint" }]),
    draw(softModule, "wall_cell", "wall_soft_fragment", "triangle-list", solid, [{ format: "r32uint" }, { format: "rgba8unorm" }]),
    device.createRenderPipelineAsync({
      layout: "auto",
      vertex: { module: softModule, entryPoint: "body_cell" },
      fragment: { module: softModule, entryPoint: "body_fragment", targets: splatTargets },
      primitive: { topology: "triangle-list", cullMode: "none" },
    }),
  ]);
  const gpu = {
    adapter, device, context, format, canvas,
    pipelines: { resolve, keep, level, scatter, count, box, blob, link, edge, mapIds, mapPaint, sliceComposite, soft, softCompose, boxPick, wall, body },
    compileMs: Math.round(performance.now() - began),
    layoutBytes: new ArrayBuffer(EV.LAYOUT_WORDS * 4),
    layoutBuffer: device.createBuffer({ size: EV.LAYOUT_WORDS * 4, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }),
    drawn: device.createBuffer({ size: 32, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.INDIRECT | GPUBufferUsage.COPY_SRC }),
    drawnRead: device.createBuffer({ size: 16, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST }),
    pickRead: device.createBuffer({ size: 256, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST }),
    levels: [],
    rawTexture: null,
    object: null,
  };
  gpu.layoutU = new Uint32Array(gpu.layoutBytes);
  gpu.layoutI = new Int32Array(gpu.layoutBytes);
  for (let bit = 0; bit < 24; bit += 1) {
    const buffer = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
    device.queue.writeBuffer(buffer, 0, new Uint32Array([bit, 0, 0, 0]));
    gpu.levels.push(buffer);
  }
  EV.setRaw(gpu, null, 1, 1, 1);
  EV.fit(gpu);
  return gpu;
};

EV.fit = (gpu) => {
  const ratio = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.floor(gpu.canvas.clientWidth * ratio));
  const height = Math.max(1, Math.floor(gpu.canvas.clientHeight * ratio));
  if (gpu.depth && gpu.canvas.width === width && gpu.canvas.height === height) {
    return;
  }
  gpu.canvas.width = width;
  gpu.canvas.height = height;
  gpu.depth?.destroy();
  gpu.pick?.destroy();
  gpu.depth = gpu.device.createTexture({ size: [width, height], format: "depth24plus", usage: GPUTextureUsage.RENDER_ATTACHMENT });
  gpu.pick = gpu.device.createTexture({ size: [width, height], format: "r32uint", usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC });
  for (const name of ["accumulated", "revealed", "wallIds", "wallTones", "wallDepth"]) {
    gpu[name]?.destroy();
  }
  const blended = GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING;
  gpu.accumulated = gpu.device.createTexture({ size: [width, height], format: "rgba16float", usage: blended });
  gpu.revealed = gpu.device.createTexture({ size: [width, height], format: "r8unorm", usage: blended });
  gpu.wallIds = gpu.device.createTexture({ size: [width, height], format: "r32uint", usage: blended });
  gpu.wallTones = gpu.device.createTexture({ size: [width, height], format: "rgba8unorm", usage: blended });
  gpu.wallDepth = gpu.device.createTexture({ size: [width, height], format: "depth24plus", usage: GPUTextureUsage.RENDER_ATTACHMENT });
  gpu.composeGroup = gpu.device.createBindGroup({
    layout: gpu.pipelines.softCompose.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: gpu.accumulated.createView() }, { binding: 1, resource: gpu.revealed.createView() },
      { binding: 2, resource: gpu.wallIds.createView() }, { binding: 3, resource: gpu.wallTones.createView() },
      { binding: 4, resource: { buffer: gpu.layoutBuffer } },
      { binding: 5, resource: gpu.rawTexture.createView() },
    ],
  });
};

// The raw voxels of one whole frame, every layer, or none: a 1 by 1 by 1 texture keeps the binding whole when no
// stack is served.
EV.setRaw = (gpu, voxels, width, height, depth) => {
  gpu.rawTexture?.destroy();
  gpu.rawTexture = gpu.device.createTexture({
    size: [width, height, depth], dimension: "3d", format: "r16uint", usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });
  if (voxels) {
    gpu.device.queue.writeTexture({ texture: gpu.rawTexture }, voxels, { bytesPerRow: width * 2, rowsPerImage: height }, { width, height, depthOrArrayLayers: depth });
  }
  gpu.rawOn = voxels ? 1 : 0;
  gpu.compositeGroup = null;
  // The composite of the view reads these voxels too, for the slide under the cells, so its group is made again
  // against the texture that stands now and never against the one just let go.
  if (gpu.composeGroup) {
    gpu.composeGroup = gpu.device.createBindGroup({
      layout: gpu.pipelines.softCompose.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: gpu.accumulated.createView() }, { binding: 1, resource: gpu.revealed.createView() },
        { binding: 2, resource: gpu.wallIds.createView() }, { binding: 3, resource: gpu.wallTones.createView() },
        { binding: 4, resource: { buffer: gpu.layoutBuffer } },
        { binding: 5, resource: gpu.rawTexture.createView() },
      ],
    });
  }
};

EV.writeLayout = (gpu, values) => {
  EV.LAYOUT.forEach((name, slot) => {
    const value = values[name] | 0;
    if (EV.SIGNED.has(name)) {
      gpu.layoutI[slot] = value;
    } else {
      gpu.layoutU[slot] = value >>> 0;
    }
  });
  gpu.device.queue.writeBuffer(gpu.layoutBuffer, 0, gpu.layoutBytes);
};

// The first bytes of a stream, at least the count asked for unless the stream ends first.
EV.readHead = async (reader, count) => {
  let pending = new Uint8Array(0);
  while (pending.length < count) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    const joined = new Uint8Array(pending.length + value.length);
    joined.set(pending, 0);
    joined.set(value, pending.length);
    pending = joined;
  }
  return pending;
};

// The rest of a stream, its head already read, laid into the landing from a byte place; nothing lands past the limit.
// Returns the stream's whole length.
EV.streamInto = async (reader, landing, at, limit, head) => {
  let written = 0;
  let value = head;
  for (let done = false; !done;) {
    const place = at + written;
    if (place < limit) {
      landing.set(value.subarray(0, Math.min(value.length, limit - place)), place);
    }
    written += value.length;
    ({ value, done } = await reader.read());
  }
  return written;
};

// Streams an object's .vbo and .ibo, from fetch responses or files, end to end into one mapped storage buffer, then
// indexes its small sections.
EV.loadObject = async (gpu, sources) => {
  const device = gpu.device;
  const began = performance.now();
  const vertex = (sources.vertex.body || sources.vertex.stream()).getReader();
  const index = (sources.index.body || sources.index.stream()).getReader();
  const vertexHead = await EV.readHead(vertex, 64);
  const indexHead = await EV.readHead(index, 16);
  const header = EV.readHeader(vertexHead.subarray(0, 64).slice());
  const indexWords = new Uint32Array(indexHead.subarray(0, 16).slice().buffer);
  if ((header.magic !== EV.MAGIC) || (indexWords[0] !== EV.INDEX_MAGIC) || (indexWords[2] !== header.link_total)
      || (indexWords[3] !== header.edge_total)) {
    throw new Error("not a .vbo and its .ibo");
  }
  const bytes = header.total_words * 4;
  const buffer = device.createBuffer({ size: bytes, usage: GPUBufferUsage.STORAGE, mappedAtCreation: true });
  const mapped = buffer.getMappedRange();
  const landing = new Uint8Array(mapped);
  const vertexBytes = await EV.streamInto(vertex, landing, 0, header.index_at * 4, vertexHead);
  const indexBytes = await EV.streamInto(index, landing, header.index_at * 4, bytes, indexHead);
  const object = EV.indexObject(header, mapped);
  buffer.unmap();
  object.streamMs = Math.round(performance.now() - began);
  object.bytes = vertexBytes + indexBytes;

  EV.releaseObject(gpu);
  const storage = (size) => device.createBuffer({ size, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  const held = {
    object: buffer,
    runLeaf: storage(EV.words(header.run_total)),
    prefix: storage(EV.words(EV.nextPower(Math.max(1, header.leaf_total)))),
    compact: storage(EV.words(header.run_total)),
    chosen: storage(EV.words((header.cell_total >>> 5) + 1)),
    motion: storage(EV.words(header.cell_total * 8)),
    shape: storage(EV.words(header.cell_total * 6)),
    ids: device.createTexture({ size: [EV.MAP_SIZE, EV.MAP_SIZE], format: "r32uint", usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING }),
    idsDepth: device.createTexture({ size: [EV.MAP_SIZE, EV.MAP_SIZE], format: "depth24plus", usage: GPUTextureUsage.RENDER_ATTACHMENT }),
    // The plane's own colour: every cell of the volume added into it, with no depth standing between them.
    painted: device.createTexture({ size: [EV.MAP_SIZE, EV.MAP_SIZE], format: "rgba16float",
                                    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING }),
  };
  device.queue.writeBuffer(held.motion, 0, object.motion);
  device.queue.writeBuffer(held.shape, 0, object.shape);
  const group = (pipeline, entries) => device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: entries.map((resource, binding) => ({ binding, resource: resource instanceof GPUBuffer ? { buffer: resource } : resource })),
  });
  // A bind group by binding number, for a pipeline whose shader reads only some of the module's bindings.
  const numbered = (pipeline, pairs) => device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: pairs.map(([binding, resource]) => ({ binding, resource: { buffer: resource } })),
  });
  const p = gpu.pipelines;
  const lay = gpu.layoutBuffer;
  held.groups = {
    resolve: group(p.resolve, [buffer, lay, held.runLeaf]),
    keep: group(p.keep, [buffer, lay, held.chosen, held.prefix]),
    levels: gpu.levels.map((level) => group(p.level, [level, lay, held.prefix])),
    scatter: group(p.scatter, [buffer, lay, held.chosen, held.prefix, held.runLeaf, held.compact]),
    count: group(p.count, [lay, held.prefix, gpu.drawn]),
    box: group(p.box, [buffer, lay, held.chosen, held.motion, held.runLeaf, held.compact]),
    boxPick: group(p.boxPick, [buffer, lay, held.chosen, held.motion, held.runLeaf, held.compact]),
    soft: group(p.soft, [buffer, lay, held.chosen, held.motion, held.runLeaf, held.compact]),
    wall: numbered(p.wall, [[0, buffer], [1, lay], [2, held.chosen], [3, held.motion], [6, held.shape]]),
    body: numbered(p.body, [[0, buffer], [1, lay], [2, held.chosen], [3, held.motion], [6, held.shape]]),
    blob: group(p.blob, [buffer, lay, held.chosen, held.motion]),
    link: group(p.link, [buffer, lay, held.chosen, held.motion]),
    edge: group(p.edge, [buffer, lay]),
    mapIds: numbered(p.mapIds, [[0, buffer], [1, lay], [2, held.chosen], [3, held.motion], [6, held.shape]]),
    mapPaint: numbered(p.mapPaint, [[0, buffer], [1, lay], [2, held.chosen], [3, held.motion], [6, held.shape]]),
  };
  gpu.held = held;
  gpu.object = object;
  gpu.compositeGroup = null;
  return object;
};

EV.releaseObject = (gpu) => {
  const held = gpu.held;
  if (!held) {
    return;
  }
  for (const name of ["object", "runLeaf", "prefix", "compact", "chosen", "motion", "shape", "ids", "idsDepth"]) {
    held[name].destroy();
  }
  gpu.held = null;
  gpu.object = null;
};

// The run's leaf for every run, once per object; run twice so the first touch and the warm pass are both measured.
EV.resolveRuns = async (gpu) => {
  const times = [];
  for (let round = 0; round < 2; round += 1) {
    const began = performance.now();
    const encoder = gpu.device.createCommandEncoder();
    const pass = encoder.beginComputePass();
    pass.setPipeline(gpu.pipelines.resolve);
    pass.setBindGroup(0, gpu.held.groups.resolve);
    pass.dispatchWorkgroups(...EV.workgroups(gpu.object.header.run_total));
    pass.end();
    gpu.device.queue.submit([encoder.finish()]);
    await gpu.device.queue.onSubmittedWorkDone();
    times.push(Math.round(performance.now() - began));
  }
  return times;
};

EV.writeChosen = (gpu, chosen) => {
  const bits = new Uint32Array(Math.max(1, (gpu.object.header.cell_total >>> 5) + 2));
  for (const cell of chosen) {
    bits[cell >>> 5] |= (1 << (cell & 31)) >>> 0;
  }
  gpu.device.queue.writeBuffer(gpu.held.chosen, 0, bits);
};

// Counts the kept runs of each leaf in range, prefix sums them in place, scatters the kept runs into one list and
// writes the draw count where drawIndirect reads it. The layout must already hold the range.
EV.compact = async (gpu, leafSpan, runSpan) => {
  const began = performance.now();
  const groups = gpu.held.groups;
  const p = gpu.pipelines;
  const pow2 = EV.nextPower(Math.max(1, leafSpan));
  const encoder = gpu.device.createCommandEncoder();
  const pass = encoder.beginComputePass();
  pass.setPipeline(p.keep);
  pass.setBindGroup(0, groups.keep);
  pass.dispatchWorkgroups(...EV.workgroups(pow2));
  pass.setPipeline(p.level);
  for (let bit = 0; (1 << bit) < pow2; bit += 1) {
    pass.setBindGroup(0, groups.levels[bit]);
    pass.dispatchWorkgroups(...EV.workgroups(pow2 >>> 1));
  }
  pass.setPipeline(p.scatter);
  pass.setBindGroup(0, groups.scatter);
  pass.dispatchWorkgroups(...EV.workgroups(runSpan));
  pass.setPipeline(p.count);
  pass.setBindGroup(0, groups.count);
  pass.dispatchWorkgroups(1);
  pass.end();
  encoder.copyBufferToBuffer(gpu.drawn, 0, gpu.drawnRead, 0, 16);
  gpu.device.queue.submit([encoder.finish()]);
  await gpu.drawnRead.mapAsync(GPUMapMode.READ);
  const drawn = new Uint32Array(gpu.drawnRead.getMappedRange().slice(0))[1];
  gpu.drawnRead.unmap();
  return { drawn, ms: Math.round(performance.now() - began) };
};

// One frame of the view: the slice's cell numbers first, then the 3D region and the slice region in one pass.
EV.render = (gpu, plan) => {
  const device = gpu.device;
  const held = gpu.held;
  const p = gpu.pipelines;
  const encoder = device.createCommandEncoder();
  if (plan.slice) {
    const ids = encoder.beginRenderPass({
      colorAttachments: [{ view: held.ids.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: "clear", storeOp: "store" }],
      depthStencilAttachment: { view: held.idsDepth.createView(), depthClearValue: 1, depthLoadOp: "clear", depthStoreOp: "store" },
    });
    ids.setPipeline(p.mapIds);
    ids.setBindGroup(0, held.groups.mapIds);
    ids.draw(6, plan.cellCount, 0, plan.cellFirst);
    ids.end();
    // The same cells again with no depth between them, adding their colours into the plane, so the plane holds
    // the whole volume and not the face of it nearest the camera.
    const painted = encoder.beginRenderPass({
      colorAttachments: [{ view: held.painted.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 },
                           loadOp: "clear", storeOp: "store" }],
    });
    painted.setPipeline(p.mapPaint);
    painted.setBindGroup(0, held.groups.mapPaint);
    painted.draw(6, plan.cellCount, 0, plan.cellFirst);
    painted.end();
  }
  const [x, y, width, height] = plan.region;
  if (plan.body === 1) {
    const splats = encoder.beginRenderPass({
      colorAttachments: [
        { view: gpu.accumulated.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: "clear", storeOp: "store" },
        { view: gpu.revealed.createView(), clearValue: { r: 1, g: 1, b: 1, a: 1 }, loadOp: "clear", storeOp: "store" },
      ],
    });
    splats.setViewport(x, y, width, height, 0, 1);
    splats.setPipeline(p.soft);
    splats.setBindGroup(0, held.groups.soft);
    splats.drawIndirect(gpu.drawn, 16);
    splats.setPipeline(p.body);
    splats.setBindGroup(0, held.groups.body);
    splats.draw(6, plan.cellCount, 0, plan.cellFirst);
    splats.end();
    const walls = encoder.beginRenderPass({
      colorAttachments: [
        { view: gpu.wallIds.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: "clear", storeOp: "store" },
        { view: gpu.wallTones.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: "clear", storeOp: "store" },
      ],
      depthStencilAttachment: { view: gpu.wallDepth.createView(), depthClearValue: 1, depthLoadOp: "clear", depthStoreOp: "store" },
    });
    if (plan.wall) {
      walls.setViewport(x, y, width, height, 0, 1);
      walls.setPipeline(p.wall);
      walls.setBindGroup(0, held.groups.wall);
      walls.draw(6, plan.cellCount, 0, plan.cellFirst);
    }
    walls.end();
  }
  const pass = encoder.beginRenderPass({
    colorAttachments: [
      { view: gpu.context.getCurrentTexture().createView(), clearValue: plan.background, loadOp: "clear", storeOp: "store" },
      { view: gpu.pick.createView(), clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: "clear", storeOp: "store" },
    ],
    depthStencilAttachment: { view: gpu.depth.createView(), depthClearValue: 1, depthLoadOp: "clear", depthStoreOp: "store" },
  });
  pass.setViewport(x, y, width, height, 0, 1);
  pass.setScissorRect(x, y, width, height);
  if (plan.body === 0) {
    pass.setPipeline(p.box);
    pass.setBindGroup(0, held.groups.box);
    pass.drawIndirect(gpu.drawn, 0);
  } else if (plan.body === 1) {
    // The boxes still fill the pick target and the depth, unseen, so a smooth cell is picked where its voxels are.
    pass.setPipeline(p.boxPick);
    pass.setBindGroup(0, held.groups.boxPick);
    pass.drawIndirect(gpu.drawn, 0);
    pass.setPipeline(p.softCompose);
    pass.setBindGroup(0, gpu.composeGroup);
    pass.draw(3);
  } else {
    pass.setPipeline(p.blob);
    pass.setBindGroup(0, held.groups.blob);
    pass.draw(18, plan.cellCount, 0, plan.cellFirst);
  }
  if (plan.links) {
    pass.setPipeline(p.link);
    pass.setBindGroup(0, held.groups.link);
    pass.draw(2, plan.linkCount, 0, plan.linkFirst);
  }
  if (plan.edges) {
    pass.setPipeline(p.edge);
    pass.setBindGroup(0, held.groups.edge);
    pass.draw(2, gpu.object.header.edge_total, 0, 0);
  }
  if (plan.slice) {
    if (!gpu.compositeGroup) {
      gpu.compositeGroup = device.createBindGroup({
        layout: p.sliceComposite.getBindGroupLayout(0),
        entries: [
          // The plane's colours come from the painted texture now, so the composite reads no cell of the object
          // and no motion of one: the bindings it takes are the ones its own code still names.
          { binding: 1, resource: { buffer: gpu.layoutBuffer } },
          { binding: 2, resource: { buffer: held.chosen } },
          { binding: 4, resource: held.ids.createView() }, { binding: 5, resource: gpu.rawTexture.createView() },
          { binding: 7, resource: held.painted.createView() },
        ],
      });
    }
    const [sx, sy, sw, sh] = plan.sliceRegion;
    pass.setViewport(sx, sy, sw, sh, 0, 1);
    pass.setScissorRect(sx, sy, sw, sh);
    pass.setPipeline(p.sliceComposite);
    pass.setBindGroup(0, gpu.compositeGroup);
    pass.draw(3);
  }
  pass.end();
  device.queue.submit([encoder.finish()]);
};

// The cell under one device pixel, plus one, or 0 for none.
EV.pickAt = async (gpu, x, y) => {
  const encoder = gpu.device.createCommandEncoder();
  const clampedX = Math.max(0, Math.min(gpu.canvas.width - 1, x));
  const clampedY = Math.max(0, Math.min(gpu.canvas.height - 1, y));
  encoder.copyTextureToBuffer({ texture: gpu.pick, origin: { x: clampedX, y: clampedY } }, { buffer: gpu.pickRead, bytesPerRow: 256 }, { width: 1, height: 1 });
  gpu.device.queue.submit([encoder.finish()]);
  await gpu.pickRead.mapAsync(GPUMapMode.READ);
  const picked = new Uint32Array(gpu.pickRead.getMappedRange().slice(0, 4))[0];
  gpu.pickRead.unmap();
  return picked;
};
