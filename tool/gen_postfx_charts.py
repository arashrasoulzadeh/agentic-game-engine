#!/usr/bin/env python3
"""Draws docs/img/postfx-*.svg from docs/data/postfx-benchmark.json (no dependencies).

    python3 tool/gen_postfx_charts.py
"""
import json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
d = json.load(open(root / 'docs/data/postfx-benchmark.json'))
TEXT, GRID, OLD, NEW = '#9aa3b2', '#4a5160', '#526b91', '#c8a66a'

def frame_time_chart():
    names = d['presets']; a = d['before_pixel_cap']['avg']; b = d['after_pixel_cap']['avg']
    W, row, left, top = 760, 44, 190, 56
    H = top + row * len(names) + 40
    scale = (W - left - 70) / 40.0  # 0..40 ms
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="system-ui,sans-serif" font-size="13">',
         f'<text x="{left}" y="22" fill="{TEXT}" font-size="15" font-weight="600">Frame time by preset (ms, lower is better)</text>']
    for k, c, t in ((0, OLD, 'before: snapshot at 5.2 MP'), (1, NEW, 'after: capped to 1.6 MP')):
        o.append(f'<rect x="{left + k * 230}" y="32" width="12" height="12" fill="{c}"/><text x="{left + k * 230 + 18}" y="43" fill="{TEXT}">{t}</text>')
    for ms in range(0, 41, 10):
        x = left + ms * scale
        o.append(f'<line x1="{x}" y1="{top}" x2="{x}" y2="{H - 30}" stroke="{GRID}" stroke-width="1" stroke-dasharray="3 4"/>'
                 f'<text x="{x}" y="{H - 12}" fill="{TEXT}" text-anchor="middle">{ms}</text>')
    for i, n in enumerate(names):
        y = top + i * row
        o.append(f'<text x="{left - 10}" y="{y + 22}" fill="{TEXT}" text-anchor="end">{n}</text>')
        for k, (v, c) in enumerate(((a[i], OLD), (b[i], NEW))):
            yy = y + 6 + k * 15
            o.append(f'<rect x="{left}" y="{yy}" width="{max(v * scale, 1):.1f}" height="12" rx="2" fill="{c}"/>'
                     f'<text x="{left + v * scale + 6:.1f}" y="{yy + 10}" fill="{TEXT}" font-size="11">{v:g}</text>')
    o.append('</svg>')
    (root / 'docs/img/postfx-frame-time.svg').write_text('\n'.join(o))

def cost_chart():
    mp = d['snapshot_cost']['megapixels']; ms = d['snapshot_cost']['extra_ms']
    W, H, l, t, r, b = 620, 300, 60, 50, 30, 50
    sx = (W - l - r) / 6.0; sy = (H - t - b) / 36.0
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="system-ui,sans-serif" font-size="13">',
         f'<text x="{l}" y="24" fill="{TEXT}" font-size="15" font-weight="600">What the snapshot costs: extra ms per frame against pixels</text>']
    for v in range(0, 37, 12):
        y = H - b - v * sy
        o.append(f'<line x1="{l}" y1="{y}" x2="{W - r}" y2="{y}" stroke="{GRID}" stroke-dasharray="3 4"/><text x="{l - 8}" y="{y + 4}" fill="{TEXT}" text-anchor="end">{v}</text>')
    for v in range(0, 7):
        x = l + v * sx
        o.append(f'<text x="{x}" y="{H - b + 20}" fill="{TEXT}" text-anchor="middle">{v}</text>')
    o.append(f'<text x="{(l + W - r) / 2}" y="{H - 8}" fill="{TEXT}" text-anchor="middle">snapshot megapixels</text>')
    pts = [(l + m * sx, H - b - v * sy) for m, v in zip(mp, ms)]
    o.append(f'<polyline points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" fill="none" stroke="{NEW}" stroke-width="2"/>')
    for (x, y), m, v in zip(pts, mp, ms):
        o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="5" fill="{NEW}"/><text x="{x + 8:.1f}" y="{y - 8:.1f}" fill="{TEXT}">{m} MP: +{v} ms</text>')
    o.append('</svg>')
    (root / 'docs/img/postfx-cost-vs-pixels.svg').write_text('\n'.join(o))

frame_time_chart(); cost_chart()
print('wrote docs/img/postfx-frame-time.svg and postfx-cost-vs-pixels.svg')
