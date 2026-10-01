// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The device, bind groups, a stream read straight into one mapped storage buffer, and the one-pixel pick.

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

// The adapter, the device and the canvas context, or a throw that says which is missing. Device errors go to the
// console under the label.
EV.openDevice = async (canvas, label) => {
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
  device.addEventListener("uncapturederror", (event) => console.error(label, event.error.message));
  const context = canvas.getContext("webgpu");
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({ device, format, alphaMode: "opaque" });
  return { adapter, device, context, format };
};

// A bind group from resources in binding order: a buffer is bound whole, a view or sampler as it is.
EV.bindGroup = (device, pipeline, entries) => device.createBindGroup({
  layout: pipeline.getBindGroupLayout(0),
  entries: entries.map((resource, binding) => ({ binding, resource: resource instanceof GPUBuffer ? { buffer: resource } : resource })),
});

// A bind group by binding number, for a pipeline whose shader reads only some of the module's bindings.
EV.bindNumbered = (device, pipeline, pairs) => device.createBindGroup({
  layout: pipeline.getBindGroupLayout(0),
  entries: pairs.map(([binding, resource]) => ({ binding, resource: { buffer: resource } })),
});

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
