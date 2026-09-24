// cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The object as the host holds it: the header, the small sections copied out of the mapped buffer, and what the
// panels read from them. The runs stay on the card. Every number here is an integer; a fraction is shown by
// integer division to the places asked for. The object is two files, laid end to end in one buffer: the .vbo (the
// header, frames, leaves, cells, runs and the .cfg) and the .ibo (its own short header, the links and the edges).

EV.MAGIC = 0x314F4256;
EV.INDEX_MAGIC = 0x314F4249;
EV.STATUS_NAMES = ["correct", "branched", "wrong", "no link", "missed"];
EV.NONE = 0xFFFFFFFF;

EV.grouped = (value) => String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");

// numerator / denominator to a number of places, rounded half up, by integers.
EV.decimal = (numerator, denominator, places) => {
  const scale = 10 ** places;
  const negative = (numerator < 0) !== (denominator < 0);
  const top = Math.abs(numerator) * scale * 2 + Math.abs(denominator);
  const scaled = Math.floor(top / (2 * Math.abs(denominator)));
  const whole = Math.floor(scaled / scale);
  const part = String(scaled % scale).padStart(places, "0");
  return (negative && scaled ? "-" : "") + (places ? `${whole}.${part}` : `${whole}`);
};

EV.readHeader = (bytes) => {
  const words = new Uint32Array(bytes.buffer, bytes.byteOffset, 16);
  const header = {
    magic: words[0], version: words[1], frames: words[2], depth: words[3], height: words[4], width: words[5],
    leaf_total: words[6], run_total: words[7], cell_total: words[8], link_total: words[9], edge_total: words[10],
    aberrant_leaves: words[11], aberrant_voxels: words[12], wide_sums: words[13], cfg_bytes: words[14],
  };
  header.frames_at = 16;
  header.leaves_at = header.frames_at + 10 * header.frames;
  header.cells_at = header.leaves_at + 4 * header.leaf_total;
  header.runs_at = header.cells_at + 4 * header.cell_total;
  header.cfg_at = header.runs_at + header.run_total;
  header.index_at = header.cfg_at + Math.ceil(header.cfg_bytes / 4);
  header.links_at = header.index_at + 4;
  header.edges_at = header.links_at + 2 * header.link_total;
  header.total_words = header.edges_at + 3 * header.edge_total;
  header.plane = header.height * header.width;
  return header;
};

// Compressed rows over links, one side's cell to the other side's cells.
EV.linkRows = (links, cellTotal, side) => {
  const start = new Uint32Array(cellTotal + 1);
  const count = links.length / 2;
  for (let link = 0; link < count; link += 1) {
    start[links[2 * link + side] + 1] += 1;
  }
  for (let cell = 0; cell < cellTotal; cell += 1) {
    start[cell + 1] += start[cell];
  }
  const cursor = start.slice();
  const other = new Uint32Array(count);
  for (let link = 0; link < count; link += 1) {
    const own = links[2 * link + side];
    other[cursor[own]] = links[2 * link + 1 - side];
    cursor[own] += 1;
  }
  return { start, other };
};

// Copies the small sections out of the mapped object and builds every host index the panels and the motion read.
EV.indexObject = (header, mapped) => {
  const all = new Uint32Array(mapped);
  const object = {
    header,
    frames: all.slice(header.frames_at, header.leaves_at),
    cells: all.slice(header.cells_at, header.runs_at),
    links: all.slice(header.links_at, header.edges_at),
    edges: all.slice(header.edges_at, header.total_words),
    cfgText: new TextDecoder().decode(new Uint8Array(mapped, header.cfg_at * 4, header.cfg_bytes)),
  };
  const cellTotal = header.cell_total;
  object.cellFrame = new Uint32Array(cellTotal);
  for (let frame = 0; frame < header.frames; frame += 1) {
    const first = object.frames[10 * frame + 5];
    object.cellFrame.fill(frame, first, first + object.frames[10 * frame + 6]);
  }
  object.forward = EV.linkRows(object.links, cellTotal, 0);
  object.backward = EV.linkRows(object.links, cellTotal, 1);

  // Doubled centroids, z in doubled voxel units before the z scale: exact floors of (2 sum + n) / n.
  const cells = object.cells;
  object.centre = new Int32Array(cellTotal * 3);
  for (let cell = 0; cell < cellTotal; cell += 1) {
    const size = Math.max(cells[4 * cell], 1);
    object.centre[3 * cell] = Math.floor((2 * cells[4 * cell + 3] + size) / size) - header.width;
    object.centre[3 * cell + 1] = Math.floor((2 * cells[4 * cell + 2] + size) / size) - header.height;
    object.centre[3 * cell + 2] = Math.floor((2 * cells[4 * cell + 1] + size) / size);
  }

  // The joint centroid of a set of cells, from their summed sums.
  const joint = (rows, cell) => {
    let size = 0;
    let x = 0;
    let y = 0;
    let z = 0;
    for (let at = rows.start[cell]; at < rows.start[cell + 1]; at += 1) {
      const other = rows.other[at];
      size += cells[4 * other];
      z += cells[4 * other + 1];
      y += cells[4 * other + 2];
      x += cells[4 * other + 3];
    }
    if (!size) {
      return null;
    }
    return [Math.floor((2 * x + size) / size) - header.width, Math.floor((2 * y + size) / size) - header.height,
            Math.floor((2 * z + size) / size)];
  };

  // Eight per cell: step to its children's joint centroid, step in from its parents', lineage root, children.
  object.motion = new Int32Array(cellTotal * 8);
  object.root = new Uint32Array(cellTotal);
  for (let cell = 0; cell < cellTotal; cell += 1) {
    const own = [object.centre[3 * cell], object.centre[3 * cell + 1], object.centre[3 * cell + 2]];
    const children = joint(object.forward, cell);
    const parents = joint(object.backward, cell);
    const at = 8 * cell;
    for (let axis = 0; axis < 3; axis += 1) {
      object.motion[at + axis] = children ? children[axis] - own[axis] : 0;
      object.motion[at + 3 + axis] = parents ? own[axis] - parents[axis] : 0;
    }
    // Cells come in frame order and every link steps one frame on, so a parent's root is already known.
    const firstParent = object.backward.start[cell] < object.backward.start[cell + 1]
      ? object.backward.other[object.backward.start[cell]] : cell;
    object.root[cell] = firstParent === cell ? cell : object.root[firstParent];
    object.motion[at + 6] = object.root[cell];
    object.motion[at + 7] = object.forward.start[cell + 1] - object.forward.start[cell];
  }
  object.shape = EV.cellShapes(header, all, object.cells);
  // Each frame's median cell volume, the lower middle of its sorted voxel counts.
  object.frameMedian = new Uint32Array(header.frames);
  for (let frame = 0; frame < header.frames; frame += 1) {
    const first = object.frames[10 * frame + 5];
    const count = object.frames[10 * frame + 6];
    const sizes = new Uint32Array(count);
    for (let slot = 0; slot < count; slot += 1) {
      sizes[slot] = object.cells[4 * (first + slot)];
    }
    sizes.sort();
    object.frameMedian[frame] = count ? sizes[(count - 1) >> 1] : 0;
  }
  object.review = EV.reviewList(object);
  return object;
};

// Each cell's second moments about its centroid, from its runs, exact: six per cell, zz yy xx zy zx yx, in voxels
// squared (z in layers) times 256, floored, with each voxel's own spread of 1/12 added on the diagonal. A run of length
// n from x0 at row y, layer z adds n, n x0 + n(n-1)/2, and n x0^2 + x0 n(n-1) + (n-1)n(2n-1)/6 to its sums. The sums
// of a view of 2^22 voxels stay below 2^53, so they are held exactly; the covariance products are taken in BigInt.
EV.cellShapes = (header, all, cells) => {
  const total = header.cell_total;
  const sums = new Float64Array(total * 9);
  const leaves = header.leaves_at;
  const width = header.width;
  const plane = header.plane;
  for (let leaf = 0; leaf < header.leaf_total; leaf += 1) {
    const cell = all[leaves + 4 * leaf];
    const first = all[leaves + 4 * leaf + 2];
    const past = first + all[leaves + 4 * leaf + 3];
    const at = 9 * cell;
    for (let run = first; run < past; run += 1) {
      const word = all[header.runs_at + run];
      const voxel = word >>> 8;
      const n = (word & 255) + 1;
      const z = Math.floor(voxel / plane);
      const y = Math.floor(voxel / width) % header.height;
      const x = voxel % width;
      const sumX = n * x + (n * (n - 1)) / 2;
      sums[at] += n * z;
      sums[at + 1] += n * y;
      sums[at + 2] += sumX;
      sums[at + 3] += n * z * z;
      sums[at + 4] += n * y * y;
      sums[at + 5] += n * x * x + x * n * (n - 1) + ((n - 1) * n * (2 * n - 1)) / 6;
      sums[at + 6] += n * z * y;
      sums[at + 7] += z * sumX;
      sums[at + 8] += y * sumX;
    }
  }
  const shape = new Int32Array(total * 6);
  const pairs = [[3, 0, 0], [4, 1, 1], [5, 2, 2], [6, 0, 1], [7, 0, 2], [8, 1, 2]];
  for (let cell = 0; cell < total; cell += 1) {
    const n = BigInt(Math.max(cells[4 * cell], 1));
    const at = 9 * cell;
    pairs.forEach(([second, left, right], slot) => {
      const spread = (n * BigInt(sums[at + second]) - BigInt(sums[at + left]) * BigInt(sums[at + right])) * 256n / (n * n);
      shape[6 * cell + slot] = Number(spread) + (slot < 3 ? 21 : 0);
    });
  }
  return shape;
};

EV.childrenOf = (object, cell) => Array.from(object.forward.other.subarray(object.forward.start[cell], object.forward.start[cell + 1]));
EV.parentsOf = (object, cell) => Array.from(object.backward.other.subarray(object.backward.start[cell], object.backward.start[cell + 1]));

// Every cell linked to a cell through any chain of links, in both directions, ascending.
EV.lineage = (object, seeds) => {
  const seen = new Set(seeds);
  const queue = [...seeds];
  while (queue.length) {
    const cell = queue.pop();
    for (const rows of [object.forward, object.backward]) {
      for (let at = rows.start[cell]; at < rows.start[cell + 1]; at += 1) {
        const other = rows.other[at];
        if (!seen.has(other)) {
          seen.add(other);
          queue.push(other);
        }
      }
    }
  }
  return [...seen].sort((left, right) => left - right);
};

// What a reader should look at, each item naming its frame and cells. Rankings, never cutoffs: the most linked and
// the largest cells are listed first, and the reader decides where concern starts.
EV.reviewList = (object) => {
  const header = object.header;
  const items = [];
  if (header.aberrant_leaves || header.aberrant_voxels || header.wide_sums) {
    items.push({ kind: "control", frame: 0, cells: [], text: `control: ${header.aberrant_leaves} leaves, ${header.aberrant_voxels} voxels, ${header.wide_sums} wide sums` });
  }
  for (let edge = 0; edge < header.edge_total; edge += 1) {
    const status = object.edges[3 * edge + 2];
    const source = object.edges[3 * edge];
    const target = object.edges[3 * edge + 1];
    if (status === 2 || status === 3) {
      const cells = [source, target].filter((cell) => cell !== EV.NONE);
      const frame = source !== EV.NONE ? object.cellFrame[source] : 0;
      items.push({ kind: EV.STATUS_NAMES[status], frame, cells, edge });
    }
  }
  const byDegree = [];
  const bySize = [];
  for (let cell = 0; cell < header.cell_total; cell += 1) {
    const degree = (object.forward.start[cell + 1] - object.forward.start[cell]) + (object.backward.start[cell + 1] - object.backward.start[cell]);
    byDegree.push([degree, cell]);
    bySize.push([object.cells[4 * cell], cell]);
  }
  byDegree.sort((left, right) => right[0] - left[0] || left[1] - right[1]);
  bySize.sort((left, right) => right[0] - left[0] || left[1] - right[1]);
  for (const [degree, cell] of byDegree.slice(0, 12)) {
    items.push({ kind: "most linked", frame: object.cellFrame[cell], cells: [cell], degree });
  }
  for (const [voxels, cell] of bySize.slice(0, 12)) {
    items.push({ kind: "largest", frame: object.cellFrame[cell], cells: [cell], voxels });
  }
  return items;
};

// Divisions, ends and starts of one frame: a cell with two or more children, a cell with none where the frame has
// links onward, and a cell with no parent where the frame before has links into it.
EV.frameEvents = (object, frame) => {
  const table = object.frames;
  const first = table[10 * frame + 5];
  const past = first + table[10 * frame + 6];
  const onward = table[10 * frame + 8] > 0;
  const inward = frame > 0 && table[10 * (frame - 1) + 8] > 0;
  const events = { divisions: 0, ends: 0, starts: 0, voxels: 0 };
  for (let cell = first; cell < past; cell += 1) {
    const children = object.forward.start[cell + 1] - object.forward.start[cell];
    const parents = object.backward.start[cell + 1] - object.backward.start[cell];
    events.divisions += children >= 2 ? 1 : 0;
    events.ends += onward && children === 0 ? 1 : 0;
    events.starts += inward && parents === 0 ? 1 : 0;
    events.voxels += object.cells[4 * cell];
  }
  return events;
};
