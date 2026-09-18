#!/usr/bin/env python3
"""Measure the grille grooves of the reference microphone photo.

Reproduces the measured numbers in mic-groove-geometry.json. Standard library
only; uses macOS `sips` to decode the WebP. Usage:

    curl -sL -o /tmp/mic-ref.png '<source URL from mic-groove-geometry.json>'
    python3 docs/design/studies/measure-mic-grooves.py /tmp/mic-ref.png

Method: classify opaque pixels as dark groove (luminance < 80) or chrome, take
the head as the first contiguous run of rows at least 55% as wide as the widest
row in the top half of the image, then flood-fill dark connected regions inside
the head's bounding box. Each region's bounding box is one groove; the small
square region near the center is the emblem ring and its core.
"""
import os
import struct
import subprocess
import sys
import tempfile
from collections import deque

src = sys.argv[1]
bmp = os.path.join(tempfile.mkdtemp(), "mic.bmp")
subprocess.run(["sips", "-s", "format", "bmp", src, "--out", bmp], check=True, capture_output=True)
d = open(bmp, "rb").read()
off = struct.unpack_from("<I", d, 10)[0]
w, hs = struct.unpack_from("<ii", d, 18)
topdown, h = hs < 0, abs(hs)
row = ((w * 32 // 8) + 3) // 4 * 4

cls = bytearray(w * h)  # 0 transparent, 1 chrome, 2 groove
for y in range(h):
    yy = y if topdown else h - 1 - y
    for x in range(w):
        i = off + yy * row + x * 4
        b, g, r, a = d[i], d[i + 1], d[i + 2], d[i + 3]
        if a >= 128:
            cls[y * w + x] = 2 if (r * 299 + g * 587 + b * 114) // 1000 < 80 else 1

widths = [sum(1 for x in range(w) if cls[y * w + x]) for y in range(h)]
maxw = max(widths[: h // 2])
rows = [y for y in range(h) if widths[y] >= maxw * 0.55]
hy0 = hy1 = rows[0]
for y in rows[1:]:
    if y != hy1 + 1:
        break
    hy1 = y
hx0 = min(x for y in range(hy0, hy1) for x in range(w) if cls[y * w + x])
hx1 = max(x for y in range(hy0, hy1) for x in range(w) if cls[y * w + x])
print(f"head: x {hx0}-{hx1}  y {hy0}-{hy1}  ({hx1 - hx0} x {hy1 - hy0} px)")

seen = bytearray(w * h)
for y in range(hy0, hy1 + 1):
    for x in range(hx0, hx1 + 1):
        i = y * w + x
        if cls[i] != 2 or seen[i]:
            continue
        q, n = deque([i]), 0
        seen[i] = 1
        x0 = x1 = x
        y0 = y1 = y
        while q:
            j = q.popleft()
            n += 1
            jy, jx = divmod(j, w)
            x0, x1, y0, y1 = min(x0, jx), max(x1, jx), min(y0, jy), max(y1, jy)
            for k in (j - 1, j + 1, j - w, j + w):
                ky, kx = divmod(k, w)
                if 0 <= k < w * h and not seen[k] and cls[k] == 2 and hx0 <= kx <= hx1 and hy0 <= ky <= hy1:
                    seen[k] = 1
                    q.append(k)
        if n > 60:
            print(f"groove  head-space x {x0 - hx0:3d}-{x1 - hx0:3d}  y {y0 - hy0:3d}-{y1 - hy0:3d}"
                  f"  ({x1 - x0 + 1} x {y1 - y0 + 1}, area {n})")
