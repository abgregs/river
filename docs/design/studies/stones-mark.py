"""River's mark: three soft stones, inspired by a bold lowercase r.

What a few native Figma steps would give: outline the glyph, remove the slab serifs, draw
two bands over the cuts, Subtract, flatten, and set a corner radius on each piece. Cuts are
exact booleans on the outline; curves are flattened finely (48 steps per quadratic), well
under a device pixel at any size shown.

Run from the repo root with fontTools and shapely available:
    python3 docs/design/studies/stones-mark.py <bold-r-font.ttf> > docs/design/studies/stones-mark.js
"""
import json
import math
import sys

from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont
from shapely.geometry import LineString, Polygon, box
from shapely.geometry.polygon import orient

TOP = 521          # the r's ink top in font units, for flipping to SVG coordinates
GAP_SHARE = 0.3    # cut width as a share of the stem width
RADIUS_SHARE = 0.2 # corner radius as a share of the stem width


def outline(recording):
    points, current = [], None
    for op, args in recording:
        if op in ("moveTo", "lineTo"):
            current = args[0]
            points.append(current)
        elif op == "qCurveTo":
            offs, end = list(args[:-1]), args[-1]
            ons = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in zip(offs, offs[1:])] + [end]
            start = current
            for control, stop in zip(offs, ons):
                for k in range(1, 49):
                    t = k / 48
                    points.append((
                        (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t * t * stop[0],
                        (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t * t * stop[1],
                    ))
                start = stop
            current = end
    return Polygon(points)


def features(recording):
    # Indices follow the source r's outline.
    end = lambda i: recording[i][1][-1]
    stem_left, foot_top = end(2)
    stem_right, arm_bottom = end(12)
    return {
        "stem_left": stem_left,
        "stem_right": stem_right,
        "foot_top": foot_top,
        "arm_bottom": arm_bottom,
        "terminal": end(9)[0],
        "stem": stem_right - stem_left,
    }


def slanted_band(x, y, angle_degrees, width, clip):
    # A rectangle `width` wide along a line through (x, y) at the angle, kept inside `clip`.
    dx, dy = math.cos(math.radians(angle_degrees)), math.sin(math.radians(angle_degrees))
    line = LineString([(x - dx * 900, y - dy * 900), (x + dx * 900, y + dy * 900)])
    return line.buffer(width / 2, cap_style="flat").intersection(clip)


def cuts(f):
    # Serifs off. The stem cut rises 35° to the right, its top edge landing exactly on the
    # arm's root (stopping short leaves a sliver of straight stem edge that the rounding
    # turns into a wave). The arm cut leans forward at 70°. Both pieces lean the way text
    # flows. The r's arm grows out of the stem along a long seam, so the upper stem and
    # shoulder stay one piece, the hook: a detached arm reads as a blob.
    gap = round(GAP_SHARE * f["stem"])
    serifs = [box(-100, -100, f["stem_left"], 900), box(f["stem_right"], -100, 900, f["foot_top"])]
    rise = math.tan(math.radians(35))
    right_y = f["arm_bottom"] - (gap / 2) / math.cos(math.radians(35))
    centre_y = right_y - rise * f["stem"] / 2
    stem_column = box(f["stem_left"] - 1, -100, f["stem_right"], 900)
    arm_x = f["stem_right"] + 0.58 * (f["terminal"] - f["stem_right"])
    return serifs + [
        slanted_band((f["stem_left"] + f["stem_right"]) / 2, centre_y, 35, gap, stem_column),
        slanted_band(arm_x, 460, 70, gap, box(f["stem_right"] + gap, f["arm_bottom"] - 1, 2000, 2000)),
    ]


def soften(part, radius):
    # Figma's corner radius rounds convex and concave corners alike: an opening, then a
    # closing. The radius shrinks for a piece too thin to keep its shape under it.
    r = radius
    while r > 0:
        opened = part.buffer(-r, quad_segs=24, join_style="round")
        if opened.geom_type == "Polygon" and opened.area > 0:
            rounded = opened.buffer(r, quad_segs=24).buffer(r, quad_segs=24).buffer(-r, quad_segs=24)
            return rounded, r
        r -= 1
    return part, 0


def svg_path(polygon):
    def ring(coords):
        return "M" + "L".join(f"{x:.1f},{TOP - y:.1f}" for x, y in coords[:-1]) + "Z"
    polygon = orient(polygon)
    return ring(list(polygon.exterior.coords)) + "".join(ring(list(i.coords)) for i in polygon.interiors)


def main(path):
    font = TTFont(path)
    recording = RecordingPen()
    font.getGlyphSet()[font.getBestCmap()[ord("r")]].draw(recording)
    glyph = outline(recording.value)
    f = features(recording.value)
    shape = glyph
    for cut in cuts(f):
        shape = shape.difference(cut)
    parts = [p for p in getattr(shape, "geoms", [shape]) if p.area > 0.002 * glyph.area]
    if len(parts) != len(getattr(shape, "geoms", [shape])) or len(parts) != 3:
        raise SystemExit(f"{len(parts)} parts")
    parts = [soften(p, round(RADIUS_SHARE * f["stem"]))[0] for p in sorted(parts, key=lambda p: p.centroid.x)]
    out = {"stem": f["stem"], "parts": [svg_path(p) for p in parts]}
    sys.stdout.write("window.RIVER_MARK = ")
    json.dump(out, sys.stdout)
    sys.stdout.write(";\n")


if __name__ == "__main__":
    main(sys.argv[1])
