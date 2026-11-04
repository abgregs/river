// Schneider's least-squares cubic Bezier fit, shared by the generators.
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const mul = (a, s) => [a[0] * s, a[1] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
const len = (a) => Math.hypot(a[0], a[1]);
const norm = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l]; };
const dist = (a, b) => len(sub(a, b));
let TOL = 0.5;
export function setTolerance(t) { TOL = t; }
// ---------- Schneider cubic fitting ----------
function bez(c, t) {
  const mt = 1 - t;
  return [
    mt * mt * mt * c[0][0] + 3 * mt * mt * t * c[1][0] + 3 * mt * t * t * c[2][0] + t * t * t * c[3][0],
    mt * mt * mt * c[0][1] + 3 * mt * mt * t * c[1][1] + 3 * mt * t * t * c[2][1] + t * t * t * c[3][1],
  ];
}
function bezD(c, t) {
  const mt = 1 - t;
  return [
    3 * mt * mt * (c[1][0] - c[0][0]) + 6 * mt * t * (c[2][0] - c[1][0]) + 3 * t * t * (c[3][0] - c[2][0]),
    3 * mt * mt * (c[1][1] - c[0][1]) + 6 * mt * t * (c[2][1] - c[1][1]) + 3 * t * t * (c[3][1] - c[2][1]),
  ];
}
function bezDD(c, t) {
  const mt = 1 - t;
  return [
    6 * mt * (c[2][0] - 2 * c[1][0] + c[0][0]) + 6 * t * (c[3][0] - 2 * c[2][0] + c[1][0]),
    6 * mt * (c[2][1] - 2 * c[1][1] + c[0][1]) + 6 * t * (c[3][1] - 2 * c[2][1] + c[1][1]),
  ];
}
function chordParams(p) {
  const u = [0];
  for (let i = 1; i < p.length; i++) u.push(u[i - 1] + dist(p[i], p[i - 1]));
  return u.map((x) => x / u[u.length - 1]);
}
function generate(p, u, t1, t2) {
  const first = p[0], last = p[p.length - 1];
  let C00 = 0, C01 = 0, C11 = 0, X0 = 0, X1 = 0;
  for (let i = 0; i < p.length; i++) {
    const t = u[i], mt = 1 - t;
    const b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t;
    const A1 = mul(t1, b1), A2 = mul(t2, b2);
    C00 += dot(A1, A1); C01 += dot(A1, A2); C11 += dot(A2, A2);
    const tmp = sub(p[i], add(add(mul(first, b0 + b1), [0, 0]), mul(last, b2 + b3)));
    X0 += dot(A1, tmp); X1 += dot(A2, tmp);
  }
  const det = C00 * C11 - C01 * C01;
  let a1 = 0, a2 = 0;
  if (Math.abs(det) > 1e-12) { a1 = (X0 * C11 - X1 * C01) / det; a2 = (C00 * X1 - C01 * X0) / det; }
  const segLen = dist(first, last);
  const eps = 1e-6 * segLen;
  if (a1 < eps || a2 < eps) { a1 = a2 = segLen / 3; }
  return [first, add(first, mul(t1, a1)), add(last, mul(t2, a2)), last];
}
function maxErr(p, c, u) {
  let m = 0, idx = Math.floor(p.length / 2);
  for (let i = 1; i < p.length - 1; i++) {
    const d = dist(bez(c, u[i]), p[i]);
    if (d > m) { m = d; idx = i; }
  }
  return { m, idx };
}
function reparam(p, c, u) {
  return u.map((t, i) => {
    const d = sub(bez(c, t), p[i]);
    const d1 = bezD(c, t), d2 = bezDD(c, t);
    const num = dot(d, d1), den = dot(d1, d1) + dot(d, d2);
    if (Math.abs(den) < 1e-12) return t;
    return Math.min(1, Math.max(0, t - num / den));
  });
}
export function fit(p, t1, t2, out) {
  if (p.length === 2) {
    const l = dist(p[0], p[1]) / 3;
    out.push([p[0], add(p[0], mul(t1, l)), add(p[1], mul(t2, l)), p[1]]);
    return;
  }
  let u = chordParams(p);
  let c = generate(p, u, t1, t2);
  let { m, idx } = maxErr(p, c, u);
  if (m < TOL) { out.push(c); return; }
  if (m < TOL * 16) {
    for (let k = 0; k < 20; k++) {
      u = reparam(p, c, u);
      c = generate(p, u, t1, t2);
      ({ m, idx } = maxErr(p, c, u));
      if (m < TOL) { out.push(c); return; }
    }
  }
  idx = Math.min(Math.max(idx, 2), p.length - 3);
  const tc = norm(sub(p[idx - 1], p[idx + 1]));
  fit(p.slice(0, idx + 1), t1, tc, out);
  fit(p.slice(idx), mul(tc, -1), t2, out);
}
function fitRun(run, closed) {
  const out = [];
  const t1 = norm(sub(run[Math.min(3, run.length - 1)], run[0]));
  const t2 = norm(sub(run[Math.max(run.length - 4, 0)], run[run.length - 1]));
  fit(run, t1, t2, out);
  return out;
}

// A closed ring with known corner indices: fit corner to corner; a ring with no
// corners is split at two opposite points with matching tangents (smooth all round).
export function fitRing(ring, corners) {
  const n = ring.length;
  const segs = [];
  if (corners.length === 0) {
    const a = 0, b = Math.floor(n / 2);
    const tan = (i) => norm(sub(ring[(i + 2) % n], ring[(i - 2 + n) % n]));
    const runA = ring.slice(a, b + 1), runB = [...ring.slice(b), ring[0]];
    const ta = tan(a), tb = tan(b);
    const outA = [], outB = [];
    fit(runA, ta, mul(tb, -1), outA);
    fit(runB, tb, mul(ta, -1), outB);
    return [...outA, ...outB];
  }
  const cs = [...new Set(corners)].sort((x, y) => x - y);
  for (let i = 0; i < cs.length; i++) {
    const a = cs[i], b = cs[(i + 1) % cs.length];
    const run = b > a ? ring.slice(a, b + 1) : [...ring.slice(a), ...ring.slice(0, b + 1)];
    segs.push(...fitRun(run));
  }
  return segs;
}


export { bez };
