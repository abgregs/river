"""Envelope for the recording bar: the slat glyph's own silhouette offset by a constant gap,
joined to a capsule around the time. All numbers in px at a 48 px glyph (3 px per glyph unit)."""
import json
from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union
U = 3.0; G = 48                      # px per glyph unit; glyph box
ROWS = [[5.5, 3.8], [4, 6.4], [3.5, 9], [4, 11.6], [5.5, 14.2]]
CAP = 0.55 * U                       # Ready stroke 1.1 units -> cap radius
P = 8.0                              # gap from any slat end to the bar edge
GAP = 6.0                            # column gap between the glyph column and the time column
TXT_W, TXT_H = 30.0, 14.0            # "0:00" at 12 px tabular, line-height 14
RF = 5.0                             # fillet radius at concave junctions
slats = [LineString([(x * U, y * U), ((16 - x) * U, y * U)]).buffer(CAP, quad_segs=24) for x, y in ROWS]
silhouette = unary_union(slats)
hull = silhouette.convex_hull
slat_r = max(s.bounds[2] for s in slats); cy = 8 * U
def tab_at(left):
    return box(left, cy - TXT_H / 2, left + TXT_W, cy + TXT_H / 2).buffer(P, quad_segs=24)
def closing(g): return g.buffer(RF, quad_segs=24).buffer(-RF, quad_segs=24)
def path(g):
    g = g.simplify(0.05)
    pts = list(g.exterior.coords)
    return 'M' + ' L'.join(f'{x:.2f} {y:.2f}' for x, y in pts[:-1]) + ' Z'
variants = {}
env_sil = silhouette.buffer(P, quad_segs=32)          # follows every slat tip
env_hull = hull.buffer(P, quad_segs=32)               # follows the group's outer form only
text_left_joined = slat_r + P + GAP
A1 = closing(unary_union([env_sil, tab_at(text_left_joined - P)]))
A2 = closing(unary_union([env_hull, tab_at(text_left_joined - P)]))
text_left_split = env_sil.bounds[2] + GAP + P
B_tab = tab_at(text_left_split - P)
for key, g, tl, extra in [('sil', A1, text_left_joined, None), ('hull', A2, text_left_joined, None), ('split', env_sil, text_left_split, B_tab)]:
    b = unary_union([g, extra]).bounds if extra is not None else g.bounds
    ox, oy = b[0], b[1]
    from shapely.affinity import translate
    d = {'w': round(b[2] - ox, 2), 'h': round(b[3] - oy, 2), 'path': path(translate(g, -ox, -oy)), 'glyph': [round(-ox, 2), round(-oy, 2)], 'text': [round(tl - ox, 2), round(cy - TXT_H / 2 - oy, 2), TXT_W, TXT_H]}
    if extra is not None: d['tab'] = path(translate(extra, -ox, -oy))
    variants[key] = d
    print(key, d['w'], d['h'], 'glyph at', d['glyph'], 'text at', d['text'], 'points', d['path'].count('L') + 1)
json.dump({'unit': U, 'glyph': G, 'pad': P, 'gap': GAP, 'variants': variants}, open('bar-shapes.json', 'w'))
# quick look
html = ['<title>bar shapes</title><style>body{background:#dfe3ea;font:12px -apple-system,sans-serif;padding:20px}div.row{display:flex;gap:30px;align-items:center;margin:16px 0}</style>']
for key, d in variants.items():
    svg = f'<svg width="{d["w"]*3}" height="{d["h"]*3}" viewBox="0 0 {d["w"]} {d["h"]}"><path d="{d["path"]}" fill="#23262B"/>'
    if 'tab' in d: svg += f'<path d="{d["tab"]}" fill="#23262B"/>'
    gx, gy = d['glyph']
    for x, y in ROWS: svg += f'<line x1="{gx + x*U}" y1="{gy + y*U}" x2="{gx + (16-x)*U}" y2="{gy + y*U}" stroke="#ECEEF1" stroke-width="{1.1*U}" stroke-linecap="round" opacity="{1 if y == 9 else .55}"/>'
    tx, ty, tw, th = d['text']; svg += f'<rect x="{tx}" y="{ty}" width="{tw}" height="{th}" fill="none" stroke="#3FA3AA" stroke-width=".5"/><text x="{tx+tw/2}" y="{ty+th-3}" font-size="12" text-anchor="middle" fill="#ECEEF1" font-family="-apple-system">0:00</text></svg>'
    html.append(f'<div class="row"><b style="width:60px">{key}</b>{svg}</div>')
open('bars.html', 'w').write('\n'.join(html))
