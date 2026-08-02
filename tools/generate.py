"""Generate comm-wheel style annular-sector slice art for an arbitrary radius/angle.

Measured from the vanilla 45-degree slice (content/ui/materials/hud/communication_wheel/*):
  box 190x140 ui, art 2x (380x280)
  fill band   r 130.5 .. 258.0 ui   half-angle 21.087 deg   ~1px AA, otherwise hard
  inner line  r 130.5 .. 135.0 ui   half the fill's angular width, tapered ends
  highlight   same mask, alpha 157 at the inner arc ramping to 34 at the outer
"""
import math
import png_io

SCALE = 2
SS = 4                      # supersample grid per axis
LINE_THICK = 4.5            # ui px, measured
LINE_ANG_FRAC = 0.505       # line angular width / fill angular width, measured
HL_INNER, HL_OUTER = 157.0, 34.0


def _coverage(px_x, px_y, cx, cy, r_in, r_out, half, ss=SS):
    """Fractional area of one texture pixel inside the annular sector."""
    hit = 0
    for sy in range(ss):
        fy = px_y + (sy + 0.5) / ss
        dy = cy - fy
        for sx in range(ss):
            fx = px_x + (sx + 0.5) / ss
            dx = fx - cx
            r = math.sqrt(dx * dx + dy * dy)
            if r < r_in or r > r_out:
                continue
            if abs(math.atan2(dx, dy)) <= half:
                hit += 1
    return hit / float(ss * ss)


def build(R, half_deg, r_in, r_out, box_w, box_h):
    """All radii/sizes in UI px. Returns (w, h, fill, line, highlight) as RGBA bytearrays."""
    w, h = int(round(box_w * SCALE)), int(round(box_h * SCALE))
    cx = w / 2.0
    cy = (h / 2.0) + R * SCALE          # wheel centre, below the image
    half = math.radians(half_deg)
    ri, ro = r_in * SCALE, r_out * SCALE
    band = ro - ri

    line_ro = (r_in + LINE_THICK) * SCALE
    line_half = half * LINE_ANG_FRAC

    fill = bytearray(w * h * 4)
    line = bytearray(w * h * 4)
    high = bytearray(w * h * 4)

    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            fill[i:i + 3] = line[i:i + 3] = high[i:i + 3] = b"\xff\xff\xff"

            c = _coverage(x, y, cx, cy, ri, ro, half)
            if c > 0:
                fill[i + 3] = int(round(255 * c))
                # radial position within the band, 0 at inner arc, 1 at outer
                dy, dx = cy - (y + 0.5), (x + 0.5) - cx
                t = (math.sqrt(dx * dx + dy * dy) - ri) / band
                t = 0.0 if t < 0 else (1.0 if t > 1 else t)
                high[i + 3] = int(round((HL_INNER + (HL_OUTER - HL_INNER) * t) * c))

            lc = _coverage(x, y, cx, cy, ri, line_ro, line_half)
            if lc > 0:
                # taper the stroke out over the last 30% of its angular reach
                dy, dx = cy - (y + 0.5), (x + 0.5) - cx
                a = abs(math.atan2(dx, dy)) / line_half
                fade = 1.0 if a < 0.7 else max(0.0, (1.0 - a) / 0.3)
                fade = fade * fade * (3 - 2 * fade)
                line[i + 3] = int(round(255 * lc * fade))

    return w, h, fill, line, high
