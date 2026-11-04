// The 川 concepts as brush movements. Each stroke, in stroke order (left, middle,
// right): the spine the brush travels, and nib keyframes [s, a, aspect, angle] along
// it. `a` is the footprint's long semi-axis (the pressure), `aspect` its short axis as
// a share of the long one, `angle` the long axis in degrees on screen (0 points right,
// 45 points down-right: the brush held with its tip to the upper left).
// Design space 1000 x 1000, y down.

export const CONCEPTS = {
  kaisho: {
    name: 'Kaisho',
    strokes: [
      {
        // 1. Left: enters with a press, falls straight, then releases to the lower left (縦払い).
        // The nib turns with the release so the tail thins along its travel.
        spine: [[296, 150], [314, 166], [324, 194], [327, 270], [326, 450], [316, 616], [290, 742], [250, 832], [206, 898]],
        nib: [[0, 10, 0.42, 45], [0.035, 48, 0.5, 45], [0.08, 44, 0.58, 45], [0.45, 42, 0.6, 45], [0.66, 37, 0.6, 52],
          [0.84, 22, 0.6, 80], [1, 2, 0.66, 110]],
      },
      {
        // 2. Middle: short, starts lower, and stops (止め): the brush pushes down-right, then lifts back.
        spine: [[478, 300], [498, 314], [509, 338], [512, 400], [512, 600], [512, 640]],
        nib: [[0, 10, 0.42, 45], [0.07, 45, 0.5, 45], [0.14, 42, 0.58, 45], [0.55, 40, 0.6, 45], [0.92, 42, 0.6, 45],
          [1, 42, 0.6, 45]],
      },
      {
        // 3. Right: the longest and heaviest, with the firmest stop.
        spine: [[678, 92], [702, 108], [714, 134], [718, 200], [719, 500], [719, 834], [719, 876]],
        nib: [[0, 10, 0.42, 45], [0.035, 53, 0.5, 45], [0.075, 49, 0.58, 45], [0.2, 46, 0.6, 45], [0.5, 43, 0.6, 45],
          [0.92, 45, 0.6, 45], [1, 46, 0.6, 45]],
      },
    ],
  },

  gyosho: {
    name: 'Gyosho',
    strokes: [
      {
        // 1. Left: a lighter touch, leaning with the writing; releases down-left and lets
        // the tip turn toward the middle stroke as the brush leaves the paper.
        spine: [[312, 170], [328, 184], [336, 210], [334, 300], [322, 460], [302, 600], [274, 706], [244, 784], [222, 830]],
        nib: [[0, 9, 0.42, 45], [0.04, 42, 0.5, 45], [0.1, 41, 0.58, 46], [0.45, 40, 0.58, 46], [0.66, 34, 0.58, 54],
          [0.85, 17, 0.6, 82], [1, 2, 0.66, 108]],
      },
      {
        // 2. Middle: a pressed, rounded stroke that flicks up (はね) toward the right stroke's entry.
        spine: [[476, 330], [494, 348], [505, 380], [508, 450], [510, 510], [524, 538], [552, 532], [596, 482]],
        nib: [[0, 9, 0.42, 45], [0.08, 40, 0.5, 45], [0.3, 42, 0.58, 45], [0.58, 44, 0.6, 45], [0.7, 33, 0.6, 30],
          [0.82, 18, 0.6, 0], [0.92, 8, 0.62, -25], [1, 1.5, 0.66, -40]],
      },
      {
        // 3. Right: long with a slight bow, ending in a hanging-needle release (懸針).
        spine: [[694, 106], [714, 124], [726, 156], [727, 280], [723, 500], [714, 700], [704, 846], [700, 914]],
        nib: [[0, 9, 0.42, 45], [0.035, 49, 0.5, 45], [0.08, 46, 0.58, 46], [0.25, 44, 0.58, 45], [0.62, 40, 0.58, 45],
          [0.82, 31, 0.6, 45], [0.94, 12, 0.62, 45], [1, 1.5, 0.66, 45]],
      },
    ],
  },
};
