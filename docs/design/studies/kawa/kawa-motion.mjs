// Data for the motion study: 3C's strokes, left to right, each with its outline, its brush
// spine (top to tip) and its box, plus the halfway centring point.
// Usage: node kawa-motion.mjs > kawa-motion-r1.json
import fs from 'fs';

const mark = JSON.parse(fs.readFileSync(new URL('./kawa-paths-r3.json', import.meta.url))).mixedC;
const centring = JSON.parse(fs.readFileSync(new URL('./kawa-centering-r1.json', import.meta.url)));

const points = (d) => {
  const n = d.match(/-?\d*\.?\d+/g).map(Number), out = [];
  for (let i = 0; i < n.length; i += 2) out.push([n[i], n[i + 1]]);
  return out;
};
const spines = mark.spines.map(points);
// Pair each outline with the spine nearest its own points.
const strokes = mark.paths.map(({ d }) => {
  const p = points(d), xs = p.map((q) => q[0]), ys = p.map((q) => q[1]);
  const box = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  const cx = (box[0] + box[2]) / 2;
  const spine = spines.reduce((a, s) => (Math.abs(s[Math.floor(s.length / 2)][0] - cx) < Math.abs(a[Math.floor(a.length / 2)][0] - cx) ? s : a));
  return { d, box, spine };
}).sort((a, b) => a.box[0] - b.box[0]);

process.stdout.write(JSON.stringify({ box: centring.box, point: centring.methods.half.point, strokes }) + '\n');
