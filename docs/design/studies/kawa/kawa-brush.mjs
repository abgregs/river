// Draws the 川 concepts with a brush model, then traces them as cubic Béziers.
//
// A stroke is an elliptical brush footprint (the nib) stamped along a spine. Along the
// spine, keyframes set the pressure (the nib's long semi-axis), its aspect and its
// angle, so the entry press, the shaft's waist, a stop (止め) or a release (払い) come
// from how the brush moves, not from drawn outlines. The union of the stamps is
// sampled as an implicit field on a 0.5-unit grid, contoured with marching squares
// (sub-pixel, linear interpolation), and fitted to cubic Béziers within 0.5 units.
//
// Run: node kawa-brush.mjs ./kawa-concepts-rN.mjs > kawa-paths-rN.json   Design space 1000 x 1000, y down.

import { fitRing, setTolerance } from './kawa-fit.mjs';
// The concepts module comes from the command line, so each round keeps its own inputs:
// node kawa-brush.mjs ./kawa-concepts-r2.mjs > kawa-paths-r2.json
const { CONCEPTS } = await import(process.argv[2] ?? './kawa-concepts-r1.mjs');

setTolerance(0.5);
const GRID = 2000; // cells across the 1000-unit box: 0.5 units per cell
const SCALE = GRID / 1000;

const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const mul = (a, s) => [a[0] * s, a[1] * s];
const len = (a) => Math.hypot(a[0], a[1]);
const norm = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l]; };
const dist = (a, b) => len(sub(a, b));

function catmullRom(points, per = 300) {
  const P = [add(points[0], sub(points[0], points[1])), ...points,
    add(points.at(-1), sub(points.at(-1), points.at(-2)))];
  const out = [];
  for (let i = 1; i < P.length - 2; i++) {
    const [p0, p1, p2, p3] = [P[i - 1], P[i], P[i + 1], P[i + 2]];
    const t0 = 0, t1 = Math.sqrt(dist(p0, p1)) || 1e-3, t2 = t1 + (Math.sqrt(dist(p1, p2)) || 1e-3),
      t3 = t2 + (Math.sqrt(dist(p2, p3)) || 1e-3);
    for (let k = 0; k < per; k++) {
      const t = t1 + (t2 - t1) * (k / per);
      const A1 = add(mul(p0, (t1 - t) / (t1 - t0)), mul(p1, (t - t0) / (t1 - t0)));
      const A2 = add(mul(p1, (t2 - t) / (t2 - t1)), mul(p2, (t - t1) / (t2 - t1)));
      const A3 = add(mul(p2, (t3 - t) / (t3 - t2)), mul(p3, (t - t2) / (t3 - t2)));
      const B1 = add(mul(A1, (t2 - t) / (t2 - t0)), mul(A2, (t - t0) / (t2 - t0)));
      const B2 = add(mul(A2, (t3 - t) / (t3 - t1)), mul(A3, (t - t1) / (t3 - t1)));
      out.push(add(mul(B1, (t2 - t) / (t2 - t1)), mul(B2, (t - t1) / (t2 - t1))));
    }
  }
  out.push(points.at(-1));
  return out;
}

// Points every `step` units of arc length, with s in [0, 1].
function walk(poly, step) {
  const cum = [0];
  for (let i = 1; i < poly.length; i++) cum.push(cum[i - 1] + dist(poly[i], poly[i - 1]));
  const total = cum.at(-1), out = [];
  let j = 0;
  for (let d = 0; d <= total + 1e-9; d += step) {
    while (j < cum.length - 2 && cum[j + 1] < d) j++;
    const f = (d - cum[j]) / (cum[j + 1] - cum[j] || 1);
    out.push({ p: add(poly[j], mul(sub(poly[j + 1], poly[j]), f)), s: d / total });
  }
  return { out, total };
}

// Keyframes [s, a, aspect, angleDeg], interpolated per channel with a monotone cubic
// (Fritsch-Carlson). It is C1 smooth through every keyframe and never overshoots, so
// pressure changes read as one continuous swell or taper; easing to a stop at each
// keyframe made the width plateau there and the edges ripple.
function pchip(xs, ys, x) {
  const n = xs.length;
  if (x <= xs[0]) return ys[0];
  if (x >= xs[n - 1]) return ys[n - 1];
  const h = [], d = [];
  for (let i = 0; i < n - 1; i++) { h.push(xs[i + 1] - xs[i]); d.push((ys[i + 1] - ys[i]) / h[i]); }
  const m = new Array(n);
  m[0] = d[0]; m[n - 1] = d[n - 2];
  for (let i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) { m[i] = 0; continue; }
    const w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1];
    m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
  }
  let k = 0;
  while (x > xs[k + 1]) k++;
  const t = (x - xs[k]) / h[k], t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h[k] * m[k] +
    (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h[k] * m[k + 1];
}
function nibAt(keys, s) {
  const xs = keys.map((k) => k[0]);
  return [1, 2, 3].map((j) => pchip(xs, keys.map((k) => k[j]), s));
}

// The nib's half-extent across the travel: how far the ellipse reaches along the normal n.
function halfAcross(nib, n) {
  const [a, aspect, angle] = nib, th = (angle * Math.PI) / 180;
  const u = [Math.cos(th), Math.sin(th)], v = [-Math.sin(th), Math.cos(th)];
  const du = u[0] * n[0] + u[1] * n[1], dv = v[0] * n[0] + v[1] * n[1];
  return Math.sqrt((a * du) ** 2 + (a * aspect * dv) ** 2);
}

// `edge: { side: 'left' | 'right', from: s0, blend }` holds one side of a tapering stroke on its
// line: from s0 on, the brush slides toward that side by as much as it narrows, so that
// edge runs straight into the point and only the other edge sweeps in. Left and right are
// as seen along the travel (screen left for a downward stroke).
//
// `edge: { side, match: { nib, from } }` instead places the stroke against another stroke's
// held edge: that edge is reproduced exactly (same spine, the reference nib held from
// `from`), and only the opposite edge follows this stroke's own, slimmer nib.
function holdEdge(out, st) {
  if (st.edge.match) return matchEdge(out, st);
  // `blend` (a share of the stroke) eases the hold in over that stretch, so neither edge
  // turns a corner where the hold begins. Without it the hold starts at full strength.
  const { side, from, blend = 0 } = st.edge;
  const n = out.length;
  const sign = side === 'left' ? 1 : -1;
  const pts = out.map((o) => o.p);
  out.forEach((o, i) => {
    if (o.s < from) return;
    const T = norm(sub(pts[Math.min(n - 1, i + 1)], pts[Math.max(0, i - 1)]));
    const N = [-T[1], T[0]];
    let shift = halfAcross(nibAt(st.nib, from), N) - halfAcross(nibAt(st.nib, o.s), N);
    if (blend > 0) { const u = Math.min(1, (o.s - from) / blend); shift *= u * u * (3 - 2 * u); }
    o.p = add(o.p, mul(N, sign * shift));
  });
}

function matchEdge(out, st) {
  const { side, match } = st.edge;
  const n = out.length;
  const sign = side === 'left' ? 1 : -1;
  const pts = out.map((o) => o.p);
  out.forEach((o, i) => {
    const T = norm(sub(pts[Math.min(n - 1, i + 1)], pts[Math.max(0, i - 1)]));
    const N = [-T[1], T[0]];
    // The reference stroke's edge offset from the spine: its own half-width, held from `from` on.
    const ref = halfAcross(nibAt(match.nib, Math.min(o.s, match.from)), N);
    const shift = ref - halfAcross(nibAt(st.nib, o.s), N);
    o.p = add(o.p, mul(N, sign * shift));
  });
}

// The field: for each cell, the largest (1 - r) over stamps, r = the ellipse's
// normalised radius at the cell. Positive inside the union, zero on its edge.
function stampField(strokes) {
  const F = new Float32Array((GRID + 1) * (GRID + 1)).fill(-1);
  const spines = [], nibs = [];
  for (const st of strokes) {
    const { out } = walk(catmullRom(st.spine), 0.5);
    if (st.edge) holdEdge(out, st);
    spines.push(out.map((o) => o.p));
    const shown = [];
    out.forEach(({ p, s }, idx) => {
      const [a, aspect, angle] = nibAt(st.nib, s);
      const b = a * aspect, th = (angle * Math.PI) / 180, c = Math.cos(th), sn = Math.sin(th);
      if (idx % Math.max(1, Math.floor(out.length / 9)) === 0) shown.push({ p, a, b, angle });
      const R = a + 2;
      const x0 = Math.max(0, Math.floor((p[0] - R) * SCALE)), x1 = Math.min(GRID, Math.ceil((p[0] + R) * SCALE));
      const y0 = Math.max(0, Math.floor((p[1] - R) * SCALE)), y1 = Math.min(GRID, Math.ceil((p[1] + R) * SCALE));
      for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
          const dx = x / SCALE - p[0], dy = y / SCALE - p[1];
          const u = (dx * c + dy * sn) / a, v = (-dx * sn + dy * c) / b;
          // Scale the field by the minor semi-axis so its slope is about one per unit everywhere.
          const f = (1 - Math.sqrt(u * u + v * v)) * b;
          const i = y * (GRID + 1) + x;
          if (f > F[i]) F[i] = f;
        }
      }
    });
    nibs.push(shown);
  }
  return { F, spines, nibs };
}

// Marching squares at iso 0; returns closed loops in design units.
function contours(F) {
  const W = GRID + 1;
  const val = (x, y) => F[y * W + x];
  const key = (x, y, e) => `${x},${y},${e}`; // edge id: e=0 horizontal (x..x+1, y), e=1 vertical (x, y..y+1)
  const pt = (x, y, e) => {
    if (e === 0) { const a = val(x, y), b = val(x + 1, y); const t = a / (a - b); return [(x + t) / SCALE, y / SCALE]; }
    const a = val(x, y), b = val(x, y + 1); const t = a / (a - b); return [x / SCALE, (y + t) / SCALE];
  };
  const next = new Map();
  for (let y = 0; y < GRID; y++) {
    for (let x = 0; x < GRID; x++) {
      const a = val(x, y) > 0, b = val(x + 1, y) > 0, c = val(x + 1, y + 1) > 0, d = val(x, y + 1) > 0;
      const idx = (a ? 8 : 0) | (b ? 4 : 0) | (c ? 2 : 0) | (d ? 1 : 0);
      if (idx === 0 || idx === 15) continue;
      const T = key(x, y, 0), Rr = key(x + 1, y, 1), B = key(x, y + 1, 0), L = key(x, y, 1);
      // Segments oriented so the inside is on the right of travel (clockwise on screen).
      const segs = {
        1: [[L, B]], 2: [[B, Rr]], 3: [[L, Rr]], 4: [[Rr, T]], 5: [[L, T], [Rr, B]], 6: [[B, T]], 7: [[L, T]],
        8: [[T, L]], 9: [[T, B]], 10: [[T, Rr], [B, L]], 11: [[T, Rr]], 12: [[Rr, L]], 13: [[Rr, B]], 14: [[B, L]],
      }[idx];
      for (const [p, q] of segs) next.set(p, q);
    }
  }
  const loops = [], seen = new Set();
  for (const startKey of next.keys()) {
    if (seen.has(startKey)) continue;
    const loop = [];
    let k = startKey;
    while (k && !seen.has(k)) {
      seen.add(k);
      const [x, y, e] = k.split(',').map(Number);
      loop.push(pt(x, y, e));
      k = next.get(k);
    }
    if (loop.length > 20) loops.push(loop);
  }
  return loops;
}

const area = (l) => l.reduce((s, p, i) => { const q = l[(i + 1) % l.length]; return s + p[0] * q[1] - q[0] * p[1]; }, 0) / 2;

// Corners: points where the outline turns sharply over a short window (a release's tip).
function corners(loop) {
  const n = loop.length, w = 6, out = [];
  for (let i = 0; i < n; i++) {
    const a = norm(sub(loop[i], loop[(i - w + n) % n])), b = norm(sub(loop[(i + w) % n], loop[i]));
    const turn = Math.acos(Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1])));
    if (turn > (70 * Math.PI) / 180) out.push({ i, turn });
  }
  // Keep the sharpest point of each cluster.
  const picked = [];
  for (const c of out) {
    const last = picked.at(-1);
    if (last && c.i - last.i < 2 * w) { if (c.turn > last.turn) picked[picked.length - 1] = c; } else picked.push(c);
  }
  return picked.map((c) => c.i);
}

const r1 = (x) => Math.round(x * 10) / 10;
const toPath = (segs) => `M${r1(segs[0][0][0])} ${r1(segs[0][0][1])}` +
  segs.map((c) => `C${r1(c[1][0])} ${r1(c[1][1])} ${r1(c[2][0])} ${r1(c[2][1])} ${r1(c[3][0])} ${r1(c[3][1])}`).join('') + 'Z';
const polyPath = (pts) => { const st = Math.max(1, Math.floor(pts.length / 80)); return pts.filter((_, i) => i % st === 0 || i === pts.length - 1).map((p, i) => `${i ? 'L' : 'M'}${r1(p[0])} ${r1(p[1])}`).join(''); };

const result = {};
for (const [id, concept] of Object.entries(CONCEPTS)) {
  const { F, spines, nibs } = stampField(concept.strokes);
  const loops = contours(F).filter((l) => Math.abs(area(l)) > 50);
  const paths = loops.map((l) => { const segs = fitRing(l, corners(l)); return { d: toPath(segs), segments: segs.length }; });
  let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
  for (const l of loops) for (const [x, y] of l) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
  result[id] = {
    name: concept.name,
    paths,
    bbox: [r1(minX), r1(minY), r1(maxX), r1(maxY)],
    spines: spines.map(polyPath),
    entries: spines.map((s) => s[0].map(r1)),
    nibs: nibs.map((list) => list.map(({ p, a, b, angle }) => ({ x: r1(p[0]), y: r1(p[1]), a: r1(a), b: r1(b), angle: r1(angle) }))),
  };
}
process.stdout.write(JSON.stringify(result));
