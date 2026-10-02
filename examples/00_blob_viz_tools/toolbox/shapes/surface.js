// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Every parametric surface as data: each entry has a key, a label, a note and at(u, v, ctx), which gives a point and
// its normal for u and v from 0 to 1. Each transform has go(p, n, ctx), applied after the surface and before any
// value is raised on it: it changes where a cell sits without changing what the cell says.

EV.TAU = 6.283185307179586;

// What a shape reads besides (u, v): the order, the winding the order allows, and the grid the surface is sampled
// on, from which the space-filling layouts recover a cell's integer index. Shapes whose extent grows with the
// count, and not only their detail, are capped by the winding: a helicoid at 4096 turns leaves the camera behind,
// while a prism at 4096 sides is still a prism the same size.
EV.shapeContext = (order, span, depth) => ({ order, winding: Math.max(1, Math.min(48, order / 6)), span, depth });

EV.cellIndex = (ctx, u, v) => Math.round(v * Math.max(1, ctx.span - 1)) * ctx.depth + Math.round(u * Math.max(1, ctx.depth - 1));

EV.curveSide = (ctx) => {
  let side = 1;
  while (side * side < ctx.span * ctx.depth) {
    side *= 2;
  }
  return side;
};

// Wraps a position-only shape into the { p, n } a renderer wants, taking the normal from the surface itself by
// difference, and no shape can disagree with its own normal. At the far edge there is nothing ahead to difference
// against: the step is taken backward and the result negated, or the last row of every field would be lit and
// extruded upside down. The normal points away from the middle, and a closed shape grows outward along it.
EV.surface = (f) => (u, v, ctx) => {
  const step = 0.0015;
  const here = f(u, v, ctx);
  const backU = u + step > 1;
  const backV = v + step > 1;
  const alongU = f(backU ? u - step : u + step, v, ctx);
  const alongV = f(u, backV ? v - step : v + step, ctx);
  const signU = backU ? -1 : 1;
  const signV = backV ? -1 : 1;
  const du = [(alongU[0] - here[0]) * signU, (alongU[1] - here[1]) * signU, (alongU[2] - here[2]) * signU];
  const dv = [(alongV[0] - here[0]) * signV, (alongV[1] - here[1]) * signV, (alongV[2] - here[2]) * signV];
  let n = [du[1] * dv[2] - du[2] * dv[1], du[2] * dv[0] - du[0] * dv[2], du[0] * dv[1] - du[1] * dv[0]];
  const len = Math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
  if (!len || !isFinite(len)) {
    return { p: here, n: [0, 1, 0] };
  }
  n = [n[0] / len, n[1] / len, n[2] / len];
  if (n[0] * here[0] + n[1] * here[1] + n[2] * here[2] < 0) {
    n = [-n[0], -n[1], -n[2]];
  }
  return { p: here, n };
};

/** Gielis's superformula: one equation whose parameters give circles, polygons, stars and
  flowers, and whose spherical product with itself gives the solids. Gielis 2003. */
EV.superRadius = (angle, m, n1, n2, n3) => {
  let t = (m * angle) / 4;
  let one = Math.pow(Math.abs(Math.cos(t)), n2);
  let two = Math.pow(Math.abs(Math.sin(t)), n3);
  let r = Math.pow(one + two, -1 / n1);
  return isFinite(r) ? r : 0;
};

EV.superAt = (u, v, m1, a1, b1, c1, m2, a2, b2, c2, scale) => {
  let theta = (v - 0.5) * EV.TAU;
  let phi = (u - 0.5) * Math.PI;
  let r1 = EV.superRadius(theta, m1, a1, b1, c1);
  let r2 = EV.superRadius(phi, m2, a2, b2, c2);
  return [
    scale * r1 * Math.cos(theta) * r2 * Math.cos(phi),
    scale * r2 * Math.sin(phi),
    scale * r1 * Math.sin(theta) * r2 * Math.cos(phi),
  ];
};

EV.SURFACES = [
  {
    key: "plane",
    label: "Plane",
    note: "nothing joined to anything: position is index and no period is implied",
    at: EV.surface((u, v, ctx) => {
      return [(u - 0.5) * 150, 0, (v - 0.5) * 150];
    }),
  },

  {
    key: "bend",
    label: "Bent plane",
    note: "the plane rolled by Order, with the ends left apart",
    at: EV.surface((u, v, ctx) => {
      let k = ctx.order / 400;
      let a = (v - 0.5) * 150 * k;
      let r = k > 0.0001 ? 1 / k : 100000;
      return [(u - 0.5) * 150, r * (1 - Math.cos(a)) - 20, r * Math.sin(a)];
    }),
  },

  {
    key: "wave",
    label: "Corrugated",
    note: "a plane folded Order times, which puts a period of your choosing into the picture",
    at: EV.surface((u, v, ctx) => {
      return [(u - 0.5) * 150, 13 * Math.sin(v * EV.TAU * Math.max(1, ctx.order / 6)), (v - 0.5) * 150];
    }),
  },

  {
    key: "saddle",
    label: "Saddle",
    note: "hyperbolic paraboloid: curvature of both signs at once",
    at: EV.surface((u, v, ctx) => {
      let x = (u - 0.5) * 2,
        z = (v - 0.5) * 2;
      return [x * 75, (x * x - z * z) * 40, z * 75];
    }),
  },

  {
    key: "disk",
    label: "Disk",
    note: "polar: depth is radius, the cut is angle",
    at: EV.surface((u, v, ctx) => {
      let a = v * EV.TAU,
        r = 14 + u * 74;
      return [r * Math.cos(a), 0, r * Math.sin(a)];
    }),
  },

  {
    key: "spiral",
    label: "Spiral",
    note: "Archimedean, flat: one continuous track, no seam",
    at: EV.surface((u, v, ctx) => {
      let turns = Math.max(1, ctx.order / 2);
      let a = v * EV.TAU * turns,
        r = 12 + v * 76;
      return [r * Math.cos(a), (u - 0.5) * 28, r * Math.sin(a)];
    }),
  },

  {
    key: "cylinder",
    label: "Tube",
    note: "joins the ends of the cut, asserting one period along it",
    at: EV.surface((u, v, ctx) => {
      let a = v * EV.TAU;
      return [(u - 0.5) * 170, 46 * Math.cos(a), 46 * Math.sin(a)];
    }),
  },

  {
    key: "prism",
    label: "Prism",
    note: "a tube with Order flat sides, which quantizes the cut and joins its ends",
    at: EV.surface((u, v, ctx) => {
      let sides = Math.max(3, Math.round(ctx.order));
      let a = v * EV.TAU;
      let wedge = EV.TAU / sides;
      let r = 46 / Math.cos((((a % wedge) + wedge) % wedge) - wedge / 2);
      return [(u - 0.5) * 170, r * Math.cos(a), r * Math.sin(a)];
    }),
  },

  {
    key: "cone",
    label: "Cone",
    note: "radius falls with depth. Late values crowd together",
    at: EV.surface((u, v, ctx) => {
      let r = 74 * (1.02 - u),
        a = v * EV.TAU;
      return [r * Math.cos(a), (u - 0.5) * 150, r * Math.sin(a)];
    }),
  },

  {
    key: "pyramid",
    label: "Pyramid",
    note: "the cone with Order sides: edges the cone hides",
    at: EV.surface((u, v, ctx) => {
      let sides = Math.max(3, Math.round(ctx.order));
      let a = v * EV.TAU;
      let wedge = EV.TAU / sides;
      let flat = 1 / Math.cos((((a % wedge) + wedge) % wedge) - wedge / 2);
      let r = 74 * (1.02 - u) * flat;
      return [r * Math.cos(a), (u - 0.5) * 150, r * Math.sin(a)];
    }),
  },

  {
    key: "paraboloid",
    label: "Paraboloid",
    note: "a dish: depth is radius, height is its square",
    at: EV.surface((u, v, ctx) => {
      let a = v * EV.TAU,
        r = u * 78;
      return [r * Math.cos(a), (r * r) / 90 - 40, r * Math.sin(a)];
    }),
  },

  {
    key: "hyperboloid",
    label: "Hyperboloid",
    note: "the waisted tube: one sheet, ruled twice over",
    at: EV.surface((u, v, ctx) => {
      let a = v * EV.TAU,
        t = (u - 0.5) * 2.1;
      let r = 34 * Math.sqrt(1 + t * t);
      return [r * Math.cos(a), t * 62, r * Math.sin(a)];
    }),
  },

  {
    key: "catenoid",
    label: "Catenoid",
    note: "the soap film between two rings: minimal, zero mean curvature",
    at: EV.surface((u, v, ctx) => {
      let a = v * EV.TAU,
        t = (u - 0.5) * 3.0;
      let r = 26 * Math.cosh(t);
      return [r * Math.cos(a), t * 30, r * Math.sin(a)];
    }),
  },

  {
    key: "helicoid",
    label: "Helicoid",
    note: "the catenoid's twin: a ramp that is also minimal",
    at: EV.surface((u, v, ctx) => {
      let a = (v - 0.5) * EV.TAU * ctx.winding;
      let r = (u - 0.5) * 150;
      return [r * Math.cos(a), a * 11, r * Math.sin(a)];
    }),
  },

  {
    key: "sphere",
    label: "Sphere",
    note: "depth as latitude, the cut as longitude, whose ends are joined",
    at: EV.surface((u, v, ctx) => {
      let ph = (0.06 + 0.88 * u) * Math.PI,
        th = v * EV.TAU;
      let sp = Math.sin(ph);
      return [sp * Math.cos(th) * 68, Math.cos(ph) * 68, sp * Math.sin(th) * 68];
    }),
  },

  {
    key: "spheroid",
    label: "Spheroid",
    note: "the sphere squashed: same topology, different sampling density",
    at: EV.surface((u, v, ctx) => {
      let ph = (0.06 + 0.88 * u) * Math.PI,
        th = v * EV.TAU;
      let sp = Math.sin(ph);
      return [sp * Math.cos(th) * 86, Math.cos(ph) * 44, sp * Math.sin(th) * 86];
    }),
  },

  {
    key: "cube",
    label: "Cube",
    note: "the superformula at high exponent: flat faces, sharp edges",
    at: EV.surface((u, v, ctx) => {
      return EV.superAt(u, v, 4, 12, 12, 12, 4, 12, 12, 12, 62);
    }),
  },

  {
    key: "hedron",
    label: "Hedron",
    note: "Order sides, up to 4096, where a polygon is a circle to within a pixel",
    at: EV.surface((u, v, ctx) => {
      let sides = Math.max(3, Math.round(ctx.order));
      return EV.superAt(u, v, sides, 34, 34, 34, sides, 34, 34, 34, 62);
    }),
  },

  {
    key: "superellipsoid",
    label: "Superellipsoid",
    note: "the squircle solid: corners rounded by a single exponent",
    at: EV.surface((u, v, ctx) => {
      return EV.superAt(u, v, 4, 2.6, 2.6, 2.6, 4, 2.6, 2.6, 2.6, 66);
    }),
  },

  {
    key: "star",
    label: "Star",
    note: "superformula with Order points: sampling density is deliberately uneven",
    at: EV.surface((u, v, ctx) => {
      let m = Math.max(3, Math.round(ctx.order));
      return EV.superAt(u, v, m, 0.3, 0.3, 0.3, 4, 6, 6, 6, 54);
    }),
  },

  {
    key: "flower",
    label: "Flower",
    note: "Order petals: lobes that fold the cut back over itself",
    at: EV.surface((u, v, ctx) => {
      let m = Math.max(3, Math.round(ctx.order));
      return EV.superAt(u, v, m, 1.2, 1.6, 1.6, 6, 1.4, 1.2, 1.2, 58);
    }),
  },

  {
    key: "splat",
    label: "Splat",
    note: "low exponents, high symmetry: the shape thrown at a wall",
    at: EV.surface((u, v, ctx) => {
      let m = Math.max(3, Math.round(ctx.order));
      return EV.superAt(u, v, m, 0.18, 1.7, 1.7, m, 0.4, 1.2, 1.2, 46);
    }),
  },

  {
    key: "balloon",
    label: "Balloon",
    note: "radius is the value. The silhouette is the field itself",
    at: EV.surface((u, v, ctx) => {
      let ph = (0.06 + 0.88 * u) * Math.PI,
        th = v * EV.TAU;
      let sp = Math.sin(ph);
      return [sp * Math.cos(th) * 40, Math.cos(ph) * 40, sp * Math.sin(th) * 40];
    }),
  },

  {
    key: "torus",
    label: "Toroid",
    note: "joins both axes, asserting a period along each",
    at: EV.surface((u, v, ctx) => {
      let th = u * EV.TAU,
        ph = v * EV.TAU;
      let big = 74 + 26 * Math.cos(ph);
      return [big * Math.cos(th), 26 * Math.sin(ph), big * Math.sin(th)];
    }),
  },

  {
    key: "knot",
    label: "Torus knot",
    note: "a tube wound Order times, which brings distant depths alongside each other",
    at: EV.surface((u, v, ctx) => {
      let p = Math.max(2, Math.round(ctx.order / 2)),
        q = 3;
      let th = u * EV.TAU;
      let r = 52 + 18 * Math.cos(q * th);
      let cx = r * Math.cos(p * th);
      let cy = 18 * Math.sin(q * th);
      let cz = r * Math.sin(p * th);
      let a = v * EV.TAU;
      return [
        cx + 9 * Math.cos(a) * Math.cos(p * th),
        cy + 9 * Math.sin(a),
        cz + 9 * Math.cos(a) * Math.sin(p * th),
      ];
    }),
  },

  {
    key: "mobius",
    label: "Mobius band",
    note: "one side and one edge: the cut comes back inverted",
    at: EV.surface((u, v, ctx) => {
      let th = u * EV.TAU;
      let w = (v - 0.5) * 46;
      let r = 62 + w * Math.cos(th / 2);
      return [r * Math.cos(th), w * Math.sin(th / 2), r * Math.sin(th)];
    }),
  },

  {
    key: "klein",
    label: "Klein bottle",
    note: "the figure-eight immersion: no inside to be on",
    at: EV.surface((u, v, ctx) => {
      let th = u * EV.TAU,
        ph = v * EV.TAU;
      let w = 26 * Math.cos(th / 2) * Math.sin(ph) - 26 * Math.sin(th / 2) * Math.sin(2 * ph);
      let r = 62 + w;
      return [
        r * Math.cos(th),
        26 * Math.sin(th / 2) * Math.sin(ph) + 26 * Math.cos(th / 2) * Math.sin(2 * ph),
        r * Math.sin(th),
      ];
    }),
  },

  {
    key: "dini",
    label: "Dini surface",
    note: "a twisted pseudosphere: constant negative curvature",
    at: EV.surface((u, v, ctx) => {
      let a = u * EV.TAU * ctx.winding;
      let t = 0.05 + v * 1.5;
      return [
        30 * Math.cos(a) * Math.sin(t),
        30 * (Math.cos(t) + Math.log(Math.tan(t / 2))) + a * 4 - 40,
        30 * Math.sin(a) * Math.sin(t),
      ];
    }),
  },

  {
    key: "shell",
    label: "Seashell",
    note: "a tube on a logarithmic spiral: growth that keeps its shape",
    at: EV.surface((u, v, ctx) => {
      let th = u * EV.TAU * 2.2;
      let grow = Math.pow(1.19, th);
      let a = v * EV.TAU;
      let r = 4.2 * grow;
      return [
        1.2 * grow * Math.cos(th) + r * Math.cos(a) * Math.cos(th) - 40,
        r * Math.sin(a) + th * 3 - 30,
        1.2 * grow * Math.sin(th) + r * Math.cos(a) * Math.sin(th),
      ];
    }),
  },

  {
    key: "enneper",
    label: "Enneper",
    note: "minimal and self-intersecting: the map is not injective",
    at: EV.surface((u, v, ctx) => {
      let x = (u - 0.5) * 3.4,
        y = (v - 0.5) * 3.4;
      return [
        12 * (x - (x * x * x) / 3 + x * y * y),
        12 * (x * x - y * y) * 0.5,
        12 * (y - (y * y * y) / 3 + y * x * x),
      ];
    }),
  },

  {
    key: "hilbert",
    label: "Hilbert curve",
    note: "locality preserving: values adjacent in the sequence stay adjacent here",
    at: EV.surface((u, v, ctx) => {
      let side = EV.curveSide(ctx);
      let xy = EV.hilbertAt(side, EV.cellIndex(ctx, u, v));
      let step = 150 / side;
      return [xy[0] * step - 75, 0, xy[1] * step - 75];
    }),
  },

  {
    key: "morton",
    label: "Morton order",
    note: "interleaved bits: cheaper than Hilbert, and the seams are visible",
    at: EV.surface((u, v, ctx) => {
      let side = EV.curveSide(ctx);
      let xy = EV.mortonAt(EV.cellIndex(ctx, u, v));
      let step = 150 / side;
      return [xy[0] * step - 75, 0, xy[1] * step - 75];
    }),
  },
];

// A transform is applied to the surface after the embedding and before the value is raised.
// It changes where a cell sits without changing what the cell says. Same discipline as the
// shapes: anything that survives a transform is in the data, anything that appears under one is
// in the map.
EV.unit = (n) => {
  let len = Math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
  return len ? [n[0] / len, n[1] / len, n[2] / len] : [0, 1, 0];
};

EV.SURFACE_TRANSFORMS = [
  {
    key: "none",
    label: "None",
    note: "the embedding as written",
    go: (p, n, ctx) => {
      return { p: p, n: n };
    },
  },

  {
    key: "invert",
    label: "Inversion",
    note: "through a sphere: near and far trade places, angles survive",
    go: (p, n, ctx) => {
      let d2 = p[0] * p[0] + p[1] * p[1] + p[2] * p[2];
      if (d2 < 1) {
        d2 = 1;
      }
      let k = (70 * 70) / d2;
      return { p: [p[0] * k, p[1] * k, p[2] * k], n: n };
    },
  },

  {
    key: "shadow",
    label: "Shadow",
    note: "dropped flat to the ground: the silhouette from above",
    go: (p, n, ctx) => {
      return { p: [p[0], 0, p[2]], n: [0, 1, 0] };
    },
  },

  {
    key: "wall",
    label: "Projection",
    note: "cast sideways onto a wall: one axis discarded",
    go: (p, n, ctx) => {
      return { p: [p[0], p[1], -70], n: [0, 0, 1] };
    },
  },

  {
    key: "spherize",
    label: "Spherize",
    note: "every point pushed to one radius: shape gone, sampling kept",
    go: (p, n, ctx) => {
      let u = EV.unit(p);
      return { p: [u[0] * 66, u[1] * 66, u[2] * 66], n: u };
    },
  },

  {
    key: "logradius",
    label: "Log radius",
    note: "radius compressed: six decades of extent on one axis",
    go: (p, n, ctx) => {
      let d = Math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
      if (d < 0.0001) {
        return { p: p, n: n };
      }
      let k = (Math.log(1 + d) * 26) / d;
      return { p: [p[0] * k, p[1] * k, p[2] * k], n: n };
    },
  },

  {
    key: "twist",
    label: "Twist",
    note: "rotated about the upright by height, at Order turns",
    go: (p, n, ctx) => {
      let a = (p[1] / 150) * EV.TAU * Math.max(1, ctx.order / 6);
      let cs = Math.cos(a),
        sn = Math.sin(a);
      return {
        p: [p[0] * cs - p[2] * sn, p[1], p[0] * sn + p[2] * cs],
        n: [n[0] * cs - n[2] * sn, n[1], n[0] * sn + n[2] * cs],
      };
    },
  },

  {
    key: "mirror",
    label: "Point reflection",
    note: "inversion through the origin: every coordinate negated, chirality reversed",
    go: (p, n, ctx) => {
      return { p: [-p[0], -p[1], -p[2]], n: [-n[0], -n[1], -n[2]] };
    },
  },

  {
    key: "fold",
    label: "Fold",
    note: "reflected at the middle. The two halves land on each other",
    go: (p, n, ctx) => {
      return { p: [Math.abs(p[0]) - 40, p[1], p[2]], n: n };
    },
  },
];
