"""Minbar icon: a small 3D model -> Android vector drawables + a PNG preview.

The minbar (arched back panel, pulpit seat, three steps toward the viewer,
side balustrades, newel posts with ball finials) is built from convex solids,
viewed at a three-quarter angle and shaded with three tones of black by face
orientation, so depth comes from tone, not detail.

Usage: python tool/make_icon.py android/app/src/main/res tool/icon_preview.png
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(sys.argv[1])
PREVIEW = Path(sys.argv[2])

YAW = math.radians(30)     # turn the left side toward the viewer
PITCH = math.radians(18)   # look slightly down onto the treads
LIGHT_FRONT, LIGHT_SIDE, LIGHT_TOP = 17, 58, 112   # grey levels


# ------------------------------------------------------------- 3D helpers
def view(p):
    x, y, z = p
    xr = x * math.cos(YAW) + z * math.sin(YAW)
    zr = -x * math.sin(YAW) + z * math.cos(YAW)
    ys = y * math.cos(PITCH) - zr * math.sin(PITCH)
    return xr, -ys          # screen coords, y down


def facing(n):
    nx, ny, nz = n
    zr = -nx * math.sin(YAW) + nz * math.cos(YAW)
    return zr * math.cos(PITCH) + ny * math.sin(PITCH) > 1e-6


def tone(n):
    nx, ny, _ = n
    shade = max(0.0, min(1.0, 0.45 * max(0.0, -nx) + max(0.0, ny)))
    g = round(LIGHT_FRONT + shade * (LIGHT_TOP - LIGHT_FRONT))
    return f'#{g:02X}{g:02X}{g:02X}'


faces = []      # (screen polygon, colour) in painter's order


def add_face(pts3, n):
    if facing(n):
        faces.append(([view(p) for p in pts3], tone(n)))


def box(x0, y0, z0, x1, y1, z1):
    add_face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1))
    add_face([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0))
    add_face([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0))
    add_face([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], (0, 1, 0))


def extrude_xy(profile, z0, z1):
    """Convex profile in the XY plane (counter-clockwise), extruded along Z."""
    add_face([(x, y, z1) for x, y in profile], (0, 0, 1))
    n = len(profile)
    for i in range(n):
        (ax, ay), (bx, by) = profile[i], profile[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        ln = math.hypot(ex, ey)
        add_face([(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)],
                 (ey / ln, -ex / ln, 0))


def extrude_zy(profile, x0, x1):
    """Convex profile in the ZY plane, extruded along X (side balustrades)."""
    add_face([(x0, y, z) for z, y in profile], (-1, 0, 0))
    n = len(profile)
    for i in range(n):
        (az, ay), (bz, by) = profile[i], profile[(i + 1) % n]
        ez, ey = bz - az, by - ay
        ln = math.hypot(ez, ey)
        # Outward normal of a counter-clockwise (z, y) profile.
        add_face([(x0, ay, az), (x0, by, bz), (x1, by, bz), (x1, ay, az)],
                 (0, -ez / ln, ey / ln))


def sphere(c, r, n=28):
    cx, cy = view(c)
    k = 1.0   # orthographic: radius unchanged
    pts = [(cx + r * k * math.cos(2 * math.pi * i / n),
            cy + r * k * math.sin(2 * math.pi * i / n)) for i in range(n)]
    faces.append((pts, tone((0, 0, 1))))
    # Small highlight toward the light (upper-left).
    hx, hy, hr = cx - r * 0.32, cy - r * 0.36, r * 0.34
    faces.append(([(hx + hr * math.cos(2 * math.pi * i / n),
                    hy + hr * math.sin(2 * math.pi * i / n)) for i in range(n)],
                  tone((0, 1, 0))))


def arch_profile(x0, x1, y_spring, steps=24, y_base=0.0):
    r = (x1 - x0) / 2
    cx = x0 + r
    pts = [(x0, y_base), (x1, y_base), (x1, y_spring)]
    for i in range(1, steps):
        t = math.pi * i / steps
        pts.append((cx + r * math.cos(t), y_spring + r * math.sin(t)))
    pts.append((x0, y_spring))
    return pts


# ------------------------------------------------------------------ model
W = 10.0
PLAT_Y, PLAT_Z0, PLAT_Z1 = 9.0, 1.2, 5.0
STEP_DEPTH, STEPS = 3.0, 3
STEP_RISE = PLAT_Y / (STEPS + 1)
FRONT_Z = PLAT_Z1 + STEP_DEPTH * STEPS
WALL_T = 0.8
RAIL_BACK_Y, RAIL_FRONT_Y = 13.0, 6.6
post = 1.4

# Back panel with its arch, and the recessed niche on its face.
extrude_xy(arch_profile(-1.0, W + 1.0, 20.0), 0.0, PLAT_Z0)
niche = arch_profile(2.0, W - 2.0, 18.5, y_base=PLAT_Y)
faces.append(([view((x, y, PLAT_Z0 + 0.01)) for x, y in niche], '#2E2E2E'))

wall = [(PLAT_Z0, 0.0), (FRONT_Z - 0.8, 0.0), (FRONT_Z - 0.8, RAIL_FRONT_Y),
        (PLAT_Z1, RAIL_BACK_Y), (PLAT_Z0, RAIL_BACK_Y)]


def post_at(x0, z0, h):
    box(x0, 0, z0, x0 + post, h, z0 + post)
    sphere((x0 + post / 2, h + 0.95, z0 + post / 2), 0.95)


# Far (right) side first.
extrude_zy(wall, W, W + WALL_T)
post_at(W - 0.3, PLAT_Z0, RAIL_BACK_Y + 1.2)

# Seat platform and the steps, back to front.
box(0, 0, PLAT_Z0, W, PLAT_Y, PLAT_Z1)
for i in range(1, STEPS + 1):
    box(0, 0, PLAT_Z1 + STEP_DEPTH * (i - 1), W,
        PLAT_Y - STEP_RISE * i, PLAT_Z1 + STEP_DEPTH * i)
post_at(W - 0.3, FRONT_Z - post, RAIL_FRONT_Y + 1.4)

# Near (left) side last; its posts stand proud of the balustrade face.
extrude_zy(wall, -WALL_T, 0.0)
post_at(-1.1, PLAT_Z0, RAIL_BACK_Y + 1.2)
post_at(-1.1, FRONT_Z - post, RAIL_FRONT_Y + 1.4)

# Soft ground shadow (drawn first, under everything).
foot = [view(p) for p in [(-1.5, 0, 0), (W + 1.5, 0, 0), (W + 1.5, 0, FRONT_Z + 0.5),
                          (-1.5, 0, FRONT_Z + 0.5)]]
fx = [p[0] for p in foot]
fy = [p[1] for p in foot]
shadow = ((min(fx) + max(fx)) / 2, max(fy) - 0.4, (max(fx) - min(fx)) * 0.62, 2.6)


# ------------------------------------------------------------- fit + emit
def area(poly):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1])) / 2


for i, (poly, col) in enumerate(faces):
    if area(poly) < 0:              # consistent winding -> nonzero fill unions
        faces[i] = (poly[::-1], col)

allpts = [p for poly, _ in faces for p in poly]
allpts += [(shadow[0] - shadow[2], shadow[1]), (shadow[0] + shadow[2], shadow[1])]
minx, maxx = min(p[0] for p in allpts), max(p[0] for p in allpts)
miny, maxy = min(p[1] for p in allpts), max(p[1] for p in allpts)
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2


def transform(scale, center):
    def f(p):
        return (center[0] + (p[0] - cx) * scale, center[1] + (p[1] - cy) * scale)
    return f


def fit_scale(radius):
    return radius / max(math.hypot(p[0] - cx, p[1] - cy) for p in allpts)


def path_data(polys):
    return ' '.join('M' + ' L'.join(f'{x:.2f},{y:.2f}' for x, y in p) + ' Z' for p in polys)


def merged(face_list, f):
    """Merge consecutive faces of the same colour into one path."""
    out = []
    for poly, col in face_list:
        tp = [f(p) for p in poly]
        if out and out[-1][1] == col:
            out[-1][0].append(tp)
        else:
            out.append(([tp], col))
    return out


launch = transform(fit_scale(33.5), (54, 54))
s_l = fit_scale(33.5)
sx, sy = launch((shadow[0], shadow[1]))
srx, sry = shadow[2] * s_l, shadow[3] * s_l

paths = [f'''    <group android:pivotX="{sx:.2f}" android:pivotY="{sy:.2f}" android:scaleY="{sry / srx:.4f}">
        <path android:pathData="M{sx - srx:.2f},{sy:.2f} A{srx:.2f},{srx:.2f} 0 1,0 {sx + srx:.2f},{sy:.2f} A{srx:.2f},{srx:.2f} 0 1,0 {sx - srx:.2f},{sy:.2f} Z">
            <aapt:attr name="android:fillColor">
                <gradient android:type="radial" android:centerX="{sx:.2f}" android:centerY="{sy:.2f}"
                    android:gradientRadius="{srx:.2f}"
                    android:startColor="#33000000" android:endColor="#00000000" />
            </aapt:attr>
        </path>
    </group>''']
for polys, col in merged(faces, launch):
    paths.append(f'    <path android:fillColor="{col}" android:pathData="{path_data(polys)}" />')

(RES / 'drawable' / 'ic_launcher_foreground.xml').write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Three-quarter view minbar, toned in blacks on white. Generated by tool/make_icon.py. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
{chr(10).join(paths)}
</vector>
''', encoding='utf-8')

# ------------------------------------------------------- status-bar icon
# Android draws status-bar icons as a single-colour shape, so this is the 3D
# minbar's outline (all faces unioned by consistent winding + nonzero fill).
stat = transform(11.0 / max(maxx - cx, maxy - cy, cx - minx, cy - miny), (12, 12))
stat_polys = [[stat(p) for p in poly] for poly, _ in faces]
(RES / 'drawable' / 'ic_stat_mimbar.xml').write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Status-bar icon: outline of the 3D minbar. Generated by tool/make_icon.py. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="{path_data(stat_polys)}" />
</vector>
''', encoding='utf-8')


# ---------------------------------------------------------------- render
def render(px, mask=None, transparent=False):
    """The launcher icon as pixels: white tile, shadow, shaded faces."""
    ss = 4
    w = px * ss
    crop = (18, 18, 90, 90)          # the part of the 108 canvas launchers show
    k = w / (crop[2] - crop[0])
    img = Image.new('RGBA', (w, w), 'white')
    x, y = launch((shadow[0], shadow[1]))
    rx, ry = shadow[2] * s_l, shadow[3] * s_l
    g = Image.radial_gradient('L').resize((max(1, int(2 * rx * k)), max(1, int(2 * ry * k))))
    blob = Image.new('RGBA', g.size, (0, 0, 0, 0))
    blob.putalpha(g.point(lambda v: max(0, int((255 - v * 2) * 0.2)) if v < 128 else 0))
    img.alpha_composite(blob, (int((x - rx - crop[0]) * k), int((y - ry - crop[1]) * k)))
    dr = ImageDraw.Draw(img)
    for poly, col in faces:
        dr.polygon([((launch(p)[0] - crop[0]) * k, (launch(p)[1] - crop[1]) * k) for p in poly],
                   fill=col)
    if mask:
        m = Image.new('L', (w, w), 0)
        md = ImageDraw.Draw(m)
        if mask == 'circle':
            md.ellipse((0, 0, w - 1, w - 1), fill=255)
        else:
            md.rounded_rectangle((0, 0, w - 1, w - 1), radius=w * 0.28, fill=255)
        img.putalpha(m)
    img = img.resize((px, px), Image.LANCZOS)
    if transparent:
        return img
    out = Image.new('RGBA', (px, px), (226, 226, 226, 255))
    out.alpha_composite(img)
    return out.convert('RGB')


# Legacy launcher PNGs (replaces the Flutter template's logo at every density).
for folder, px in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72), ('mipmap-xhdpi', 96),
                   ('mipmap-xxhdpi', 144), ('mipmap-xxxhdpi', 192)]:
    render(px, mask='circle', transparent=True).save(RES / folder / 'ic_launcher.png')

# Full-colour icon shown inside the notification card.
(RES / 'drawable-nodpi').mkdir(exist_ok=True)
render(256, mask='circle', transparent=True).save(RES / 'drawable-nodpi' / 'notif_large.png')


# ---------------------------------------------------------------- preview
def render_stat(px, fg, bg):
    ss = 4
    w = px * ss
    img = Image.new('RGB', (w, w), bg)
    dr = ImageDraw.Draw(img)
    for poly in stat_polys:
        dr.polygon([(x * w / 24, y * w / 24) for x, y in poly], fill=fg)
    return img.resize((px, px), Image.LANCZOS)


sheet = Image.new('RGB', (1160, 420), (226, 226, 226))
sheet.paste(render(360, mask='circle'), (20, 30))
sheet.paste(render(360, mask='squircle'), (400, 30))
sheet.paste(render(96, mask='circle'), (800, 30))
sheet.paste(render(48, mask='circle'), (920, 30))
sheet.paste(render_stat(96, 'white', (32, 33, 36)), (800, 160))
sheet.paste(render_stat(24, 'white', (32, 33, 36)), (920, 160))
sheet.paste(render_stat(24, (32, 33, 36), 'white'), (960, 160))
sheet.save(PREVIEW)
print('ok', len(faces), 'faces')
