// Round 3: one figure assembled from round 1's strokes, at the maintainer's direction.
//   1. Left: round 1 gyosho's left stroke, exactly.
//   2. Middle: round 1 kaisho's middle stroke, shortened by about an eighth. Its head and
//      its stop keep their size and shape; only the shaft between them is shorter.
//   3. Right: round 1 gyosho's right stroke, exactly, except the needle: its point sits
//      on the stroke's left edge, so the taper runs from right to left instead of closing
//      in from both sides.
// 3B (same round) keeps the left stroke, makes the middle slimmer and shorter after the
// maintainer's example, and gives the needle a firm left edge with a short, straight cut.
// Strokes are imported from kawa-concepts-r1.mjs so they stay identical to round 1.

import { CONCEPTS as R1 } from './kawa-concepts-r1.mjs';

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const length = (pts) => pts.slice(1).reduce((sum, p, i) => sum + dist(p, pts[i]), 0);

// Shortens a straight vertical shaft by `by` units at its foot. Keyframes near the start
// keep their distance from the start, keyframes near the end keep their distance from the
// end, so the head and the stop are unchanged.
function shorten(stroke, by) {
  const spine = stroke.spine.map((p) => [...p]);
  const last = spine.length - 1;
  spine[last][1] -= by;
  spine[last - 1][1] -= by;
  const before = length(stroke.spine), after = length(spine);
  const nib = stroke.nib.map(([s, ...rest]) => {
    if (s <= 0.3) return [(s * before) / after, ...rest];
    if (s >= 0.7) return [1 - ((1 - s) * before) / after, ...rest];
    return [s, ...rest];
  });
  return { ...stroke, spine, nib };
}

const [gyoshoLeft, , gyoshoRight] = R1.gyosho.strokes;
const [, kaishoMiddle] = R1.kaisho.strokes;

// 3B's middle stroke, shared with 3C.
const middleB = {
      // 2. Middle: between round 1 kaisho's middle and the maintainer's example. It starts
      // lower and is shorter (about 270 units against 340), its head is about four fifths
      // as wide as the outer strokes, and it narrows from both sides along its whole
      // length to a short, blunt finish: neither the held stop nor a point.
      spine: [[480, 330], [498, 344], [508, 368], [511, 420], [512, 540], [512, 600]],
      nib: [[0, 10, 0.42, 45], [0.08, 38, 0.52, 45], [0.16, 35, 0.58, 45], [0.5, 30, 0.6, 45], [0.84, 25, 0.6, 45],
        [0.94, 22, 0.62, 45], [1, 18, 0.64, 45]],
};

// 3C's right stroke, whose left edge 3D keeps.
const rightC = {
  // 3. Right: 3A's stroke (the point on the left edge), slimming sooner and more
  // lightly: the width starts to ease about two thirds of the way down and falls
  // gradually into the needle, so the lower half reads slender.
  ...gyoshoRight,
  nib: [...gyoshoRight.nib.filter(([s]) => s <= 0.25), [0.55, 41, 0.58, 45], [0.67, 37.5, 0.58, 45],
    [0.8, 29, 0.6, 45], [0.9, 18, 0.6, 45], [0.96, 8, 0.62, 45], [1, 1.5, 0.66, 45]],
  edge: { side: 'left', from: 0.55 },
};

export const CONCEPTS = {
  mixed: {
    name: '3A, gyosho with a kaisho middle',
    strokes: [
      gyoshoLeft,
      shorten(kaishoMiddle, 44),
      // The needle's taper starts at s = 0.62, where round 1's pressure begins to fall.
      { ...gyoshoRight, edge: { side: 'left', from: 0.62 } },
    ],
  },

  mixedB: {
    name: '3B, slimmer middle, firm needle',
    strokes: [
      gyoshoLeft,
      middleB,
      {
        // 3. Right: round 1 gyosho's stroke with a firm needle. The full pressure holds
        // longer, to s = 0.84, then falls in a straight line with the nib's shape held, so
        // the right edge cuts across in a short, straight diagonal from a defined shoulder;
        // the left edge holds its line into the point.
        ...gyoshoRight,
        nib: [...gyoshoRight.nib.filter(([s]) => s <= 0.62), [0.84, 37, 0.58, 45], [0.85, 35.2, 0.58, 45], [0.925, 18.4, 0.58, 45],
          [1, 1.5, 0.58, 45]],
        edge: { side: 'left', from: 0.84 },
      },
    ],
  },

  mixedC: {
    name: '3C, wider middle, slender needle',
    strokes: [
      gyoshoLeft,
      // 2. Middle: 3B's middle, widened by the same amount at every keyframe after the first
      // touch, so the head and the finish both grow and the taper keeps its angle.
      { ...middleB, nib: middleB.nib.map(([s, a, ...rest]) => [s, s === 0 ? a : a + 5, ...rest]) },
      rightC,
    ],
  },

  mixedD: {
    name: '3D, wider middle, slender right edge',
    strokes: [
      gyoshoLeft,
      { ...middleB, nib: middleB.nib.map(([s, a, ...rest]) => [s, s === 0 ? a : a + 5, ...rest]) },
      {
        // 3. Right: 3C's left edge exactly, and a more slender right edge. From about halfway
        // the stroke's own width falls, placed against 3C's held left edge, so only the
        // right edge moves in, tapering smoothly to the point on the left edge.
        ...gyoshoRight,
        nib: [...gyoshoRight.nib.filter(([s]) => s <= 0.25), [0.45, 42, 0.58, 45], [0.6, 35, 0.58, 45], [0.72, 28.5, 0.58, 45],
          [0.82, 22, 0.6, 45], [0.9, 14, 0.6, 45], [0.96, 6.5, 0.62, 45], [1, 1.5, 0.66, 45]],
        edge: { side: 'left', match: { nib: rightC.nib, from: rightC.edge.from } },
      },
    ],
  },
};
