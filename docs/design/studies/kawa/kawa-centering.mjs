// Centring metrics for the chosen mark (3C): the reference points each centring method
// puts at the frame's centre. Usage: node kawa-centering.mjs > kawa-centering-r1.json
// Design space 1000 x 1000, y down; outlines from kawa-paths-r3.json.
import fs from 'fs';

const mark = JSON.parse(fs.readFileSync(new URL('./kawa-paths-r3.json', import.meta.url))).mixedC;

// Each path flattened to polygons (24 points per cubic), for area and edge queries.
function flatten(d) {
  const t = d.match(/[MLCZz]|-?\d*\.?\d+/g), rings = [];
  let ring = null, cur = [0, 0], cmd, i = 0;
  while (i < t.length) {
    if (/[MLCZz]/.test(t[i])) cmd = t[i++];
    if (cmd === 'M') { cur = [+t[i++], +t[i++]]; ring = [cur]; rings.push(ring); cmd = 'L'; }
    else if (cmd === 'L') { cur = [+t[i++], +t[i++]]; ring.push(cur); }
    else if (cmd === 'C') {
      const p = [cur, [+t[i++], +t[i++]], [+t[i++], +t[i++]], [+t[i++], +t[i++]]];
      for (let k = 1; k <= 24; k++) {
        const u = k / 24, v = 1 - u;
        ring.push([0, 1].map((a) => v * v * v * p[0][a] + 3 * v * v * u * p[1][a] + 3 * v * u * u * p[2][a] + u * u * u * p[3][a]));
      }
      cur = p[3];
    } else cmd = null;
  }
  return rings;
}

const strokes = mark.paths.map((p) => {
  const rings = flatten(p.d);
  let a = 0, x = 0, y = 0;
  const pts = rings.flat();
  for (const r of rings) for (let k = 0; k < r.length; k++) {
    const [x0, y0] = r[k], [x1, y1] = r[(k + 1) % r.length], c = x0 * y1 - x1 * y0;
    a += c; x += (x0 + x1) * c; y += (y0 + y1) * c;
  }
  return {
    rings, area: Math.abs(a / 2), cx: x / (3 * a), cy: y / (3 * a),
    box: [Math.min(...pts.map((p) => p[0])), Math.min(...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[1]))],
  };
});

// Where a horizontal line at y crosses a stroke's outline: [leftmost, rightmost].
function across(stroke, y) {
  const xs = [];
  for (const r of stroke.rings) for (let k = 0; k < r.length; k++) {
    const [x0, y0] = r[k], [x1, y1] = r[(k + 1) % r.length];
    if ((y0 - y) * (y1 - y) <= 0 && y0 !== y1) xs.push(x0 + ((y - y0) / (y1 - y0)) * (x1 - x0));
  }
  return [Math.min(...xs), Math.max(...xs)];
}

// The strokes sorted left to right; the middle one is the axis people read.
strokes.sort((a, b) => a.cx - b.cx);
const middle = strokes[1];
// The middle stroke's axis: the centre line of its shaft, between head and finish.
const [, my0, , my1] = middle.box, samples = [];
for (let y = my0 + 0.3 * (my1 - my0); y <= my0 + 0.8 * (my1 - my0); y += 2) {
  const [l, r] = across(middle, y); samples.push((l + r) / 2);
}
const axis = samples.reduce((s, x) => s + x, 0) / samples.length;

const box = [Math.min(...strokes.map((s) => s.box[0])), Math.min(...strokes.map((s) => s.box[1])),
  Math.max(...strokes.map((s) => s.box[2])), Math.max(...strokes.map((s) => s.box[3]))];
const area = strokes.reduce((s, k) => s + k.area, 0);
const ink = [strokes.reduce((s, k) => s + k.cx * k.area, 0) / area, strokes.reduce((s, k) => s + k.cy * k.area, 0) / area];
const centre = [(box[0] + box[2]) / 2, (box[1] + box[3]) / 2];
const half = [(centre[0] + ink[0]) / 2, (centre[1] + ink[1]) / 2];
const r1 = (v) => Math.round(v * 10) / 10;

// Each method: the design-space point that lands on the frame's centre.
const methods = {
  box: { name: 'Bounding box', point: centre },
  middle: { name: 'Middle stroke', point: [axis, half[1]] },
  half: { name: 'Halfway', point: half },
  ink: { name: 'Ink centroid', point: ink },
};
for (const m of Object.values(methods)) m.point = m.point.map(r1);

process.stdout.write(JSON.stringify({
  name: mark.name, paths: mark.paths.map((p) => p.d), box: box.map(r1),
  strokes: strokes.map((s) => ({ area: Math.round(s.area), centroid: [r1(s.cx), r1(s.cy)], box: s.box.map(r1) })),
  axis: r1(axis), centre: centre.map(r1), ink: ink.map(r1), methods,
}, null, 1) + '\n');
