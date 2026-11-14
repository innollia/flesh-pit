"""The vent being's hand as one modelled, skinned mesh (plain Python: numpy + Pillow).

    python tools/vent_hand_model/build_hand.py [out_dir]

Writes into game/main/art/vent_hand_models/blender_made/ (or out_dir):
    vent_hand.glb        hand + forearm stub, skeleton, vertex colours, separate nail mesh
    renders/*.png        back, palm, side, grip, offer, vertex colours only, sheet.jpg

Needs no Blender: the script builds a quad control cage by hand, subdivides it
once (Catmull-Clark), writes the glb itself and draws its check renders with a
small software rasteriser. Running it again gives the same bytes.
render_blender.py beside it reads the glb back through Blender's importer and
renders the same views there (renders/blender_*.png).

Frame (the game's hand frame, fp_vent.gd): wrist at the origin, fingers down -Y,
palm facing +Z, thumb on +X, metres. Mirror X for the other hand.

Proportions (docs/design/vent-npc.md "손"): middle finger 1 (knuckle to tip),
index 0.93, ring 0.95, little 0.77, thumb 0.66; the middle finger 1.3 times the
back of the hand (wrist to knuckle); palm breadth 0.7 of the middle finger; the
fingertip 0.74 of the finger's root breadth. The build measures the subdivided
mesh and corrects itself until these hold, then prints them.

Bones (local -Y runs along the bone, +Z is the palm side, so a curl toward the
palm is a negative turn about local X, the same as fp_vent.gd's finger pivots):
    forearm > wrist > palm > index_1..3 > index_nail   (middle, ring, little alike)
                           > thumb_1..3 > thumb_nail   (thumb_1 is the metacarpal)
Each *_nail bone sits at the cuticle on the back of the last joint, -Y toward
the free edge, -Z out of the nail: the place to hang a longer nail later. The
plain nails here are their own mesh ("vent_hand_nails"), each bound only to its
nail bone, so they can be hidden or replaced without touching the hand.
"""
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(
    ROOT, "game", "main", "art", "vent_hand_models", "blender_made")

# ---------------------------------------------------------------- proportions
L_MID = 0.096
RATIO = [0.93, 1.0, 0.95, 0.77]
THUMB_RATIO = 0.66
BACK_LEN = L_MID / 1.3
PALM_W = 0.7 * L_MID
PHALANX = [0.45, 0.28, 0.27]
TIP_TAPER = 0.74
FINGER = ["index", "middle", "ring", "little"]
# root half breadth of each finger (the slim build), splay toward +X in degrees
F_HALF = [0.0075, 0.0077, 0.0072, 0.0062]
F_SPLAY = [3.0, 0.0, -2.5, -7.0]
# palm columns: nine across the back (index edge .. little edge), odd ones run
# to a knuckle, even ones to a web
F_COL = [1.0, 0.729, 0.472, 0.214, -0.042, -0.298, -0.528, -0.759, -1.0]
PALM_CX = 0.001
# knuckle line per column (y), the middle knuckle furthest from the wrist
KN_Y = [-0.0650, -0.0700, -0.0722, -BACK_LEN, -0.0727, -0.0708, -0.0676, -0.0640, -0.0596]
MCP_Z = -0.0012

# thumb: carpal joint, then metacarpal / proximal / distal directions as
# (out toward +X, forward toward the palm) in degrees
THUMB_C = np.array([0.0195, -0.0100, 0.0055])
THUMB_META = 0.040
THUMB_DIR = [(38.0, 13.0), (29.0, 9.0), (25.0, 7.0)]
THUMB_SPLIT = [0.53, 0.47]
THUMB_NAIL_N = np.array([0.80, 0.05, -0.60])

ATTR = ["palmar", "knuckle", "tip", "pad", "blue", "crease"]

# skin colours (the values fp_vent.gd already uses, a little deeper where the
# old hand washed out against the white tile)
SKIN_BACK = np.array([1.0, 0.885, 0.83])
SKIN_PALM = np.array([1.0, 0.862, 0.835])
SKIN_KNUCKLE = np.array([0.99, 0.775, 0.735])
SKIN_TIP = np.array([1.0, 0.755, 0.73])
SKIN_PAD = np.array([1.0, 0.79, 0.77])
SKIN_BLUE = np.array([0.93, 0.875, 0.875])
SKIN_CREASE = np.array([0.90, 0.715, 0.68])
NAIL_WRAP = 76.0  # degrees round the fingertip from the nail's middle to its edge at full width
SHADE_TINT = np.array([0.80, 0.63, 0.60])
NAIL = np.array([0.90, 0.56, 0.60])
NAIL_MOON = np.array([0.96, 0.74, 0.75])
NAIL_TIP = np.array([0.95, 0.66, 0.68])


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=float)


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=float)


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=float)


def frame(direction, palm_side):
    """Bone frame: -Y along the bone, +Z the palm side, X = Y x Z."""
    y = -unit(direction)
    z = np.asarray(palm_side, dtype=float)
    z = unit(z - y * np.dot(z, y))
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


# ---------------------------------------------------------------- skeleton
class Bone:
    def __init__(self, name, parent, head, rest):
        self.name = name
        self.parent = parent
        self.head = np.asarray(head, dtype=float)
        self.rest = np.asarray(rest, dtype=float)


def finger_axes(i):
    a = math.radians(F_SPLAY[i])
    d = np.array([math.sin(a), -math.cos(a), 0.0])
    r = frame(d, [0, 0, 1])
    return d, r


def finger_mcp(i):
    k = 2 * i + 1
    return np.array([PALM_CX + PALM_W * 0.5 * F_COL[k], KN_Y[k], MCP_Z])


def thumb_dirs():
    out = []
    for a, f in THUMB_DIR:
        a, f = math.radians(a), math.radians(f)
        out.append(np.array([math.sin(a) * math.cos(f), -math.cos(a) * math.cos(f), math.sin(f)]))
    return out


def thumb_joints():
    d = thumb_dirs()
    length = THUMB_RATIO * L_MID
    mcp = THUMB_C + d[0] * THUMB_META
    ip = mcp + d[1] * length * THUMB_SPLIT[0]
    tip = ip + d[2] * length * THUMB_SPLIT[1]
    return [THUMB_C, mcp, ip, tip]


def build_bones():
    bones = [Bone("forearm", -1, [0, 0.09, 0], np.eye(3)),
             Bone("wrist", 0, [0, 0, 0], np.eye(3)),
             Bone("palm", 1, [0, -0.03, 0], np.eye(3))]
    for i in range(4):
        d, r = finger_axes(i)
        m = finger_mcp(i)
        length = RATIO[i] * L_MID
        parent = 2
        s = 0.0
        for j in range(3):
            bones.append(Bone("%s_%d" % (FINGER[i], j + 1), parent, m + d * s, r))
            parent = len(bones) - 1
            s += length * PHALANX[j]
        bones.append(Bone("%s_nail" % FINGER[i], parent, m + d * s, r))  # placed on the nail later
    d = thumb_dirs()
    j = thumb_joints()
    parent = 2
    for k in range(3):
        bones.append(Bone("thumb_%d" % (k + 1), parent, j[k], frame(d[k], -THUMB_NAIL_N)))
        parent = len(bones) - 1
    bones.append(Bone("thumb_nail", parent, j[3], frame(d[2], -THUMB_NAIL_N)))
    return bones


BONES = build_bones()
BI = {b.name: i for i, b in enumerate(BONES)}


# ---------------------------------------------------------------- control cage
class Cage:
    def __init__(self):
        self.p = []
        self.w = []
        self.a = []
        self.faces = []

    def add(self, p, w, **attr):
        self.p.append(np.asarray(p, dtype=float))
        row = np.zeros(len(BONES))
        for name, val in w.items():
            row[BI[name]] += val
        self.w.append(row / row.sum())
        self.a.append([float(attr.get(k, 0.0)) for k in ATTR])
        return len(self.p) - 1

    def strip(self, ring0, ring1, skip=()):
        n = len(ring0)
        for j in range(n):
            if j in skip:
                continue
            k = (j + 1) % n
            self.faces.append([ring0[j], ring0[k], ring1[k], ring1[j]])


def bump(f, c, w):
    return math.exp(-((f - c) / w) ** 2)


# palm rows from the forearm stub to the knuckles:
# y, half breadth, back depth, palm depth (middle), thenar, hypothenar, knuckle-arc share
PALM_ROWS = [
    (0.090, 0.0268, 0.0192, 0.0192, 0.0, 0.0, 0.0),
    (0.050, 0.0242, 0.0166, 0.0168, 0.0, 0.0, 0.0),
    (0.016, 0.0226, 0.0140, 0.0146, 0.0, 0.0, 0.0),
    (-0.006, 0.0262, 0.0128, 0.0124, 0.0052, 0.0034, 0.0),
    (-0.024, 0.0302, 0.0122, 0.0102, 0.0064, 0.0046, 0.1),
    (-0.041, 0.0326, 0.0117, 0.0096, 0.0026, 0.0038, 0.3),
    (-0.062, 0.0338, 0.0110, 0.0108, 0.0008, 0.0014, 0.65),
]
# the little-finger edge of the palm swells outward between wrist and knuckle
ULNAR = [0.0, 0.0, 0.0, 0.05, 0.07, 0.035, 0.0]
PALM_W8 = [{"forearm": 1}, {"forearm": 1}, {"forearm": 0.5, "wrist": 0.5},
           {"wrist": 0.65, "palm": 0.35}, {"palm": 1}, {"palm": 1}, {"palm": 1}]

# finger rings past the web: phalanx, share along it, breadth, back depth, palm
# depth (all of the root half breadth), shift to the palm side, weights over
# the three joints, knuckle flush, tip flush, pad flush, crease
FINGER_RINGS = [
    (0, 0.72, 1.000, 0.82, 0.93, 0.00, (1, 0, 0), 0.0, 0.0, 0.35, 0.0),
    (0, 0.92, 0.990, 0.88, 0.74, 0.00, (0.72, 0.28, 0), 1.0, 0.0, 0.0, 0.9),
    (1, 0.12, 0.965, 0.86, 0.72, 0.00, (0.28, 0.72, 0), 1.0, 0.0, 0.0, 0.9),
    (1, 0.55, 0.880, 0.74, 0.87, 0.00, (0, 1, 0), 0.0, 0.0, 0.35, 0.0),
    (1, 0.90, 0.850, 0.75, 0.68, 0.00, (0, 0.72, 0.28), 0.6, 0.15, 0.0, 0.8),
    (2, 0.13, 0.820, 0.71, 0.68, 0.00, (0, 0.28, 0.72), 0.6, 0.3, 0.0, 0.8),
    (2, 0.50, TIP_TAPER, 0.61, 0.82, 0.04, (0, 0, 1), 0.0, 0.65, 0.5, 0.0),
    (2, 0.82, 0.620, 0.57, 0.66, 0.06, (0, 0, 1), 0.0, 1.0, 0.5, 0.0),
    (2, 0.97, 0.340, 0.36, 0.34, 0.14, (0, 0, 1), 0.0, 1.0, 0.3, 0.0),
]
WEB_BACK = 0.36
WEB_PALM = 0.47
HEX = [(0.866, -0.5), (0.0, -1.0), (-0.866, -0.5), (-0.866, 0.5), (0.0, 1.0), (0.866, 0.5)]

# thumb rings past the palm: segment (0 metacarpal, 1 proximal, 2 distal), share
# along it, half breadth, nail-side depth, pad-side depth, weights
# (thumb_1, thumb_2, thumb_3, palm), knuckle, tip, pad
THUMB_RINGS = [
    (0, 0.94, 0.0104, 0.0090, 0.0102, (0.72, 0.28, 0, 0), 0.7, 0.0, 0.5),
    (1, 0.17, 0.0093, 0.0083, 0.0090, (0.28, 0.72, 0, 0), 0.7, 0.0, 0.0),
    (1, 0.55, 0.0083, 0.0073, 0.0080, (0, 1, 0, 0), 0.0, 0.0, 0.3),
    (1, 0.90, 0.0086, 0.0074, 0.0075, (0, 0.72, 0.28, 0), 0.7, 0.1, 0.0),
    (2, 0.13, 0.0085, 0.0070, 0.0076, (0, 0.28, 0.72, 0), 0.7, 0.3, 0.0),
    (2, 0.50, 0.0081, 0.0060, 0.0080, (0, 0, 1, 0), 0.0, 0.65, 0.5),
    (2, 0.84, 0.0067, 0.0055, 0.0064, (0, 0, 1, 0), 0.0, 1.0, 0.5),
    (2, 0.975, 0.0040, 0.0034, 0.0034, (0, 0, 1, 0), 0.0, 1.0, 0.3),
]


def build_cage(fit):
    """fit: {"tip": [5 shifts along each finger / the thumb], "wide": finger
    breadth correction, "palm": palm breadth correction, "taper": fingertip
    breadth correction}."""
    c = Cage()
    half = PALM_W * 0.5 * fit["palm"]
    rings = []
    for r, (y, hw, zd, zp, thenar, hypo, arc) in enumerate(PALM_ROWS):
        ring = [None] * 18
        hwf = hw * fit["palm"]
        for k in range(9):
            f = F_COL[k]
            g = 0.5 + 0.5 * math.sqrt(max(0.0, 1.0 - f * f))
            x = PALM_CX * min(1.0, max(0.0, -y / 0.03 + 0.5)) + hwf * f * (1.0 + (ULNAR[r] if f < 0 else 0.0))
            yy = y + arc * (KN_Y[k] - KN_Y[3])
            # tendons: a faint rise along the lines that run to the knuckles
            relief = 0.0
            if r >= 3 and 0 < k < 8:
                relief = (0.0012 if k % 2 == 1 else -0.0009) * min(1.0, (r - 2) / 3.0)
            if r == 2 and k == 7:
                relief = 0.0011  # the wrist bone on the little-finger side
            zt = -zd * g - relief
            zb = (zp + thenar * bump(f, 0.66, 0.36) + hypo * bump(f, -0.66, 0.36)) * g
            arm = 1.0 if r < 2 else 0.5 if r == 2 else 0.0
            blue_t = [0.0, 0.1, 0.3, 0.6, 1.0, 1.0, 0.7][r] * (1.0 - abs(f) ** 3)
            blue_b = [0.3, 0.6, 0.7, 0.0, 0.0, 0.0, 0.0][r] * (1.0 - abs(f) ** 2)
            pad_b = 0.0
            if r in (3, 4):
                pad_b = min(1.0, bump(f, 0.7, 0.4) + bump(f, -0.7, 0.4))
            if r == 5:
                pad_b = 0.5 * bump(f, -0.75, 0.35)
            if r == 6:
                pad_b = 0.6
            ring[k] = c.add([x, yy, zt], PALM_W8[r], palmar=0.0 if arm < 1 else 0.0, blue=blue_t)
            if not (r == 4 and k == 0):  # under the thumb, never built
                ring[17 - k] = c.add([x, yy, zb], PALM_W8[r], palmar=1.0 - 0.6 * arm, blue=blue_b, pad=pad_b)
        rings.append(ring)
    # the knuckle row
    ring = [None] * 18
    for k in range(9):
        f = F_COL[k]
        g = 0.5 + 0.5 * math.sqrt(max(0.0, 1.0 - f * f))
        x = PALM_CX + half * f
        odd = k % 2 == 1
        zt = -0.0104 * g - (0.0018 if odd else -0.0011 if 0 < k < 8 else 0.0)
        zb = 0.0114 * g
        w = {"palm": 1.0}
        if odd:
            w = {"palm": 0.8, "%s_1" % FINGER[(k - 1) // 2]: 0.2}
        ring[k] = c.add([x, KN_Y[k], zt], w, knuckle=0.9 if odd else 0.25, blue=0.2)
        ring[17 - k] = c.add([x, KN_Y[k] - 0.0045, zb], w, palmar=1.0, pad=0.75)
    rings.append(ring)
    # the web row: where the palm ends and the four fingers begin
    wide = fit["wide"]
    fr = []
    for i in range(4):
        d, r = finger_axes(i)
        fr.append((finger_mcp(i), d, r[:, 0], r[:, 2], RATIO[i] * L_MID, F_HALF[i]))
    ring = [None] * 18

    def side(i, sgn, s, zf):
        m, d, xl, zl, length, hw = fr[i]
        return m + d * (s * length * PHALANX[0]) + xl * (sgn * hw * 1.02 * wide) + zl * (zf * hw)

    for k in range(9):
        if k % 2 == 1:
            i = (k - 1) // 2
            m, d, xl, zl, length, hw = fr[i]
            p1 = length * PHALANX[0]
            w = {"palm": 0.45, "%s_1" % FINGER[i]: 0.55}
            ring[k] = c.add(m + d * (0.40 * p1) - zl * (hw * 0.86 / 0.875), w)
            ring[17 - k] = c.add(m + d * (WEB_PALM * p1) + zl * (hw * 0.90 / 0.875), w, palmar=1.0, crease=0.9)
        elif k in (0, 8):
            i = 0 if k == 0 else 3
            sgn = 1.0 if k == 0 else -1.0
            w = {"palm": 0.5, "%s_1" % FINGER[i]: 0.5}
            ring[k] = c.add(side(i, sgn, 0.34, -0.5), w)
            ring[17 - k] = c.add(side(i, sgn, 0.42, 0.5), w, palmar=1.0, crease=0.2)
        else:
            i = k // 2 - 1
            w = {"palm": 0.5, "%s_1" % FINGER[i]: 0.25, "%s_1" % FINGER[i + 1]: 0.25}
            pt = (side(i, -1.0, WEB_BACK, -0.28) + side(i + 1, 1.0, WEB_BACK, -0.28)) * 0.5
            pb = (side(i, -1.0, WEB_PALM + 0.03, 0.30) + side(i + 1, 1.0, WEB_PALM + 0.03, 0.30)) * 0.5
            ring[k] = c.add(pt, w, crease=0.8)
            ring[17 - k] = c.add(pb, w, palmar=1.0, crease=0.8)
    rings.append(ring)
    # palm and forearm skin; the thumb leaves through the hole at the thumb-side corner
    for r in range(len(rings) - 1):
        c.strip(rings[r], rings[r + 1], skip=(16, 17) if r in (3, 4) else ())
    # fingers
    for i in range(4):
        m, d, xl, zl, length, hw = fr[i]
        names = ["%s_%d" % (FINGER[i], j + 1) for j in range(3)]
        prev = [ring[2 * i], ring[2 * i + 1], ring[2 * i + 2], ring[17 - (2 * i + 2)], ring[17 - (2 * i + 1)], ring[17 - 2 * i]]
        start = [0.0, PHALANX[0], PHALANX[0] + PHALANX[1]]
        for (ph, share, wf, dzf, pzf, zs, wts, kn, tip, pad, crease) in FINGER_RINGS:
            s = (start[ph] + PHALANX[ph] * share) * length
            if ph == 2 and share > 0.3:
                s += fit["tip"][i] * (share - 0.3) / 0.675
            cen = m + d * s + zl * (zs * hw)
            if ph == 2:
                wf *= fit["taper"][i] if share > 0.3 else math.sqrt(fit["taper"][i])
            w = {names[j]: wts[j] for j in range(3) if wts[j] > 0}
            cur = []
            for (hx, hz) in HEX:
                dep = dzf if hz < 0 else pzf
                p = cen + xl * (hx * wf * hw * wide / 0.866) + zl * (hz * dep * hw / 0.875)
                pal = 0.0 if hz < -0.75 else 1.0 if hz > 0.75 else 0.15 if hz < 0 else 0.85
                cur.append(c.add(p, w, palmar=pal, knuckle=kn if hz < 0 else 0.0, tip=tip,
                                 pad=pad if hz > 0 else 0.0, crease=crease if hz > 0.75 else crease * 0.6 if hz > 0 else 0.0))
            c.strip(prev, cur)
            prev = cur
        c.faces.append([prev[0], prev[5], prev[4], prev[1]])
        c.faces.append([prev[1], prev[4], prev[3], prev[2]])
    # thumb
    hole = [rings[3][16], rings[3][17], rings[3][0], rings[4][0], rings[5][0], rings[5][17], rings[5][16], rings[4][16]]
    td = thumb_dirs()
    tj = thumb_joints()
    tlen = [THUMB_META, THUMB_RATIO * L_MID * THUMB_SPLIT[0], THUMB_RATIO * L_MID * THUMB_SPLIT[1]]
    tfr = []
    for k in range(3):
        u = unit(THUMB_NAIL_N - td[k] * np.dot(THUMB_NAIL_N, td[k]))
        tfr.append((u, np.cross(td[k], u)))
    hc = np.mean([c.p[v] for v in hole], axis=0)
    ang = [math.atan2(np.dot(c.p[v] - hc, tfr[0][0]), np.dot(c.p[v] - hc, tfr[0][1])) for v in hole]
    step = sum(math.remainder(ang[(k + 1) % 8] - ang[k], math.tau) for k in range(8))
    sgn = 1.0 if step > 0 else -1.0
    phase = math.atan2(sum(math.sin(ang[k] - sgn * k * math.pi / 4) for k in range(8)),
                       sum(math.cos(ang[k] - sgn * k * math.pi / 4) for k in range(8)))
    prev = hole
    for v in hole:
        c.w[v] = c.w[v] * 0.8
        c.w[v][BI["thumb_1"]] += 0.2
    first = True
    web_side = np.array([-0.75, -0.66, 0.0])
    web_side = unit(web_side - td[0] * np.dot(web_side, td[0]))
    for (seg, share, a, bn, bp, wts, kn, tip, pad) in THUMB_RINGS:
        s = share * tlen[seg]
        if seg == 2 and share > 0.3:
            s += fit["tip"][4] * (share - 0.3) / 0.675
        u, v = tfr[seg]
        cen = tj[seg] + td[seg] * s
        if seg == 2:
            cen = cen - u * (0.0008 * share)
        w = {"thumb_1": wts[0], "thumb_2": wts[1], "thumb_3": wts[2], "palm": wts[3]}
        w = {k: x for k, x in w.items() if x > 0}
        cur = []
        for k in range(8):
            ph = phase + sgn * k * math.pi / 4
            sn, cs = math.sin(ph), math.cos(ph)
            p = cen + v * (cs * a / 0.925) + u * (sn * (bn if sn > 0 else bp) / 0.925)
            pal = 0.5 - 0.5 * sn
            cur.append((p, w, dict(palmar=pal, knuckle=kn * max(0.0, sn), tip=tip, pad=pad * max(0.0, -sn))))
        if first:
            # the ball of the thumb: halfway from the palm's opening to the
            # thumb's knuckle ring and swollen, so the metacarpal lies in the
            # palm and the thumb only comes free at its knuckle
            first = False
            ball = []
            for k in range(8):
                q = (c.p[hole[k]] + cur[k][0]) * 0.5
                axis_pt = hc + td[0] * np.dot(q - hc, td[0])
                out = q - axis_pt
                # full toward the wrist and the palm, none on the side that faces the index
                web = max(0.0, float(np.dot(unit(out), web_side)))
                swell = 1.18 + 0.18 * max(0.0, -math.sin(phase + sgn * k * math.pi / 4)) - 0.24 * web
                ball.append(c.add(axis_pt + out * swell, {"thumb_1": 0.6, "palm": 0.4},
                                  palmar=cur[k][2]["palmar"], pad=max(0.0, -math.sin(phase + sgn * k * math.pi / 4))))
            c.strip(prev, ball)
            prev = ball
        cur = [c.add(p, w, **at) for (p, w, at) in cur]
        c.strip(prev, cur)
        prev = cur
    c.faces.append([prev[0], prev[1], prev[2], prev[3]])
    c.faces.append([prev[0], prev[3], prev[4], prev[7]])
    c.faces.append([prev[7], prev[4], prev[5], prev[6]])
    return c


# ---------------------------------------------------------------- mesh work
def compact(p, w, a, faces):
    used = sorted({v for f in faces for v in f if v is not None})
    remap = {v: i for i, v in enumerate(used)}
    return (np.array([p[v] for v in used]), np.array([w[v] for v in used]), np.array([a[v] for v in used]),
            [[remap[v] for v in f] for f in faces])


def orient(p, faces):
    """Make every face wind the same way, outward."""
    edge = {}
    for fi, f in enumerate(faces):
        for k in range(len(f)):
            edge.setdefault(frozenset((f[k], f[(k + 1) % len(f)])), []).append(fi)
    for e, fl in edge.items():
        if len(fl) > 2:
            raise ValueError("edge shared by %d faces" % len(fl))
    done = [False] * len(faces)
    done[0] = True
    stack = [0]
    while stack:
        fi = stack.pop()
        f = faces[fi]
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            for other in edge[frozenset((a, b))]:
                if done[other]:
                    continue
                g = faces[other]
                same = any(g[m] == a and g[(m + 1) % len(g)] == b for m in range(len(g)))
                if same:
                    faces[other] = g[::-1]
                done[other] = True
                stack.append(other)
    if not all(done):
        raise ValueError("cage is in more than one piece")
    vol = 0.0
    for f in faces:
        for k in range(1, len(f) - 1):
            vol += np.dot(p[f[0]], np.cross(p[f[k]], p[f[k + 1]]))
    if vol < 0:
        faces[:] = [f[::-1] for f in faces]
    return faces


def catmull_clark(nv, faces):
    """One step. Returns the (new x old) weight matrix and the new quads."""
    nf = len(faces)
    edge = {}
    for fi, f in enumerate(faces):
        for k in range(len(f)):
            e = (min(f[k], f[(k + 1) % len(f)]), max(f[k], f[(k + 1) % len(f)]))
            edge.setdefault(e, []).append(fi)
    eid = {e: i for i, e in enumerate(edge)}
    ne = len(edge)
    fp = np.zeros((nf, nv))
    for fi, f in enumerate(faces):
        fp[fi, f] = 1.0 / len(f)
    ep = np.zeros((ne, nv))
    mid = np.zeros((ne, nv))
    v_edges = [[] for _ in range(nv)]
    v_faces = [[] for _ in range(nv)]
    for e, i in eid.items():
        mid[i, e[0]] = mid[i, e[1]] = 0.5
        fl = edge[e]
        if len(fl) == 2:
            ep[i] = mid[i] * 0.5 + (fp[fl[0]] + fp[fl[1]]) * 0.25
        else:
            ep[i] = mid[i]
        v_edges[e[0]].append(e)
        v_edges[e[1]].append(e)
    for fi, f in enumerate(faces):
        for v in f:
            v_faces[v].append(fi)
    vp = np.zeros((nv, nv))
    for v in range(nv):
        border = [e for e in v_edges[v] if len(edge[e]) == 1]
        if border:
            vp[v, v] = 0.75
            for e in border:
                vp[v, e[0] if e[1] == v else e[1]] += 0.125
        else:
            n = len(v_faces[v])
            fa = np.mean([fp[fi] for fi in v_faces[v]], axis=0)
            ra = np.mean([mid[eid[e]] for e in v_edges[v]], axis=0)
            vp[v] = (fa + 2.0 * ra) / n
            vp[v, v] += (n - 3.0) / n
    quads = []
    for fi, f in enumerate(faces):
        n = len(f)
        for k in range(n):
            a, b, z = f[k], f[(k + 1) % n], f[(k - 1) % n]
            quads.append([a, nv + nf + eid[(min(a, b), max(a, b))], nv + fi, nv + nf + eid[(min(z, a), max(z, a))]])
    return np.vstack([vp, fp, ep]), quads


def vertex_normals(p, tris):
    n = np.zeros_like(p)
    fn = np.cross(p[tris[:, 1]] - p[tris[:, 0]], p[tris[:, 2]] - p[tris[:, 0]])
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12)


def triangulate(p, quads):
    """Split each quad along its shorter diagonal."""
    tris = []
    for a, b, c, d in quads:
        if np.linalg.norm(p[a] - p[c]) <= np.linalg.norm(p[b] - p[d]):
            tris += [[a, b, c], [a, c, d]]
        else:
            tris += [[a, b, d], [b, c, d]]
    return np.array(tris, dtype=np.int64)


def ray_hit(p, tris, origin, direction):
    """Nearest hit of a ray with the mesh (distance or None)."""
    v0, v1, v2 = p[tris[:, 0]], p[tris[:, 1]], p[tris[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    h = np.cross(direction, e2)
    det = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(det) > 1e-14
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = origin - v0
    u = np.einsum("ij,ij->i", s, h) * inv
    q = np.cross(s, e1)
    v = np.einsum("j,ij->i", direction, q) * inv
    t = np.einsum("ij,ij->i", e2, q) * inv
    hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-7)
    return float(t[hit].min()) if hit.any() else None


def build_mesh(fit):
    cage = build_cage(fit)
    p, w, a, faces = compact(cage.p, cage.w, cage.a, cage.faces)
    faces = orient(p, faces)
    s, quads = catmull_clark(len(p), faces)
    p2, w2, a2 = s @ p, s @ w, s @ a
    w2 = w2 / w2.sum(axis=1, keepdims=True)
    return p2, w2, a2, quads, (len(p), len(faces))


def measure(p, w):
    out = {}
    for i in range(4):
        d, r = finger_axes(i)
        m = finger_mcp(i)
        tipv = w[:, BI["%s_3" % FINGER[i]]] > 0.5
        out[FINGER[i]] = float(((p[tipv] - m) @ d).max())
        s = (p - m) @ d
        p1 = RATIO[i] * L_MID * PHALANX[0]
        root = (w[:, BI["%s_1" % FINGER[i]]] > 0.6) & (s > 0.62 * p1) & (s < 0.82 * p1)
        x = (p[root] - m) @ r[:, 0]
        out[FINGER[i] + "_root"] = float(x.max() - x.min())
        length = RATIO[i] * L_MID
        nail = tipv & (s > length * (PHALANX[0] + PHALANX[1] + PHALANX[2] * 0.42)) & (s < length * (PHALANX[0] + PHALANX[1] + PHALANX[2] * 0.58))
        x = (p[nail] - m) @ r[:, 0]
        out[FINGER[i] + "_tip"] = float(x.max() - x.min())
    td = thumb_dirs()
    tj = thumb_joints()
    tipv = w[:, BI["thumb_3"]] > 0.5
    out["thumb"] = float(((p[tipv] - tj[2]) @ td[2]).max() + THUMB_RATIO * L_MID * THUMB_SPLIT[0])
    band = (p[:, 1] < -0.058) & (p[:, 1] > -0.080) & (w[:, BI["palm"]] > 0.5)
    out["palm"] = float(p[band, 0].max() - p[band, 0].min())
    return out


def fitted():
    fit = {"tip": [0.0] * 5, "wide": 1.0, "palm": 1.0, "taper": [1.0] * 4}
    for _ in range(6):
        p, w, a, quads, _n = build_mesh(fit)
        m = measure(p, w)
        for i in range(4):
            fit["tip"][i] += RATIO[i] * L_MID - m[FINGER[i]]
        fit["tip"][4] += THUMB_RATIO * L_MID - m["thumb"]
        fit["wide"] *= float(np.mean([2 * F_HALF[i] / m[FINGER[i] + "_root"] for i in range(4)]))
        fit["palm"] *= PALM_W / m["palm"]
        for i in range(4):
            fit["taper"][i] *= TIP_TAPER / (m[FINGER[i] + "_tip"] / m[FINGER[i] + "_root"])
    return fit


def skin_colours(a, shade):
    col = np.zeros((len(a), 3))
    for i in range(len(a)):
        palmar, knuckle, tip, pad, blue, crease = a[i]
        c = SKIN_BACK + (SKIN_PALM - SKIN_BACK) * palmar
        c = c + (SKIN_BLUE - c) * 0.55 * blue
        c = c + (SKIN_KNUCKLE - c) * 0.72 * knuckle * (1.0 - palmar)
        c = c + (SKIN_PAD - c) * 0.75 * pad * palmar
        c = c + (SKIN_TIP - c) * 0.7 * tip * (0.55 + 0.45 * palmar)
        c = c + (SKIN_CREASE - c) * 0.62 * crease
        c = c * (1.0 - min(1.0, shade[i] * 1.5) * (1.0 - SHADE_TINT))
        col[i] = c
    return np.clip(col, 0.0, 1.0)


def build_nails(p, tris):
    """Short almond nails laid on the back of each last joint (rays onto the
    skin, the free edge carried on past the fingertip), and where each nail
    bone belongs."""
    verts, cols, joints, faces = [], [], [], []
    places = {}
    rows = [0.45, 0.51, 0.62, 0.79]        # cast onto the skin (share of the last joint)
    widths = [0.42, 0.74, 0.89, 0.87, 0.74, 0.50]
    cuticle = [0.03, 0.035, 0.0, 0.0]      # the cuticle is a curve: its corners sit further down the nail
    across = [-1.0, -0.667, -0.333, 0.0, 0.333, 0.667, 1.0]
    lift = [0.00015, 0.00030, 0.00040, 0.00044, 0.00040, 0.00030, 0.00015]
    nc = len(across)
    specs = []
    for i in range(4):
        d, r = finger_axes(i)
        length = RATIO[i] * L_MID
        base = finger_mcp(i) + d * length * (PHALANX[0] + PHALANX[1])
        specs.append(("%s_nail" % FINGER[i], base, d, r[:, 0], r[:, 2], length * PHALANX[2], F_HALF[i] * TIP_TAPER))
    td = thumb_dirs()
    tj = thumb_joints()
    tr = frame(td[2], -THUMB_NAIL_N)
    specs.append(("thumb_nail", tj[2], td[2], tr[:, 0], tr[:, 2], THUMB_RATIO * L_MID * THUMB_SPLIT[1], 0.0074))
    for name, base, d, xl, zl, plen, hw in specs:
        grid = []
        for ri, t in enumerate(rows):
            line = []
            for ci, x in enumerate(across):
                tt = t + cuticle[ri] * x * x
                # rays fan round the finger's axis, so the nail wraps the back of the tip
                ang = math.radians(x * widths[ri] * NAIL_WRAP)
                inward = zl * math.cos(ang) - xl * math.sin(ang)
                o = base + d * (tt * plen) - inward * 0.05
                hit = ray_hit(p, tris, o, inward)
                if hit is None:
                    raise ValueError("nail ray missed the finger: %s" % name)
                up = lift[ci] if ri > 0 else 0.00012
                line.append(o + inward * (hit - up))
            grid.append(line)
        mid3 = grid[3][nc // 2]
        slope = np.dot(grid[3][nc // 2] - grid[2][nc // 2], zl) / (plen * (rows[3] - rows[2]))
        # past the last cast row the nail runs on by itself: straight on, drooping
        # a little, narrowing to a rounded free edge 1.6 mm beyond the fingertip
        reach = plen * 0.21 + 0.0016
        for (dist, wr, back) in ((plen * 0.11, widths[4], 0.0003), (reach, widths[5], 0.0017)):
            line = []
            for ci in range(nc):
                rel = grid[3][ci] - mid3
                k = wr / widths[3]
                line.append(mid3 + d * (dist - back * across[ci] ** 2)
                            + zl * (slope * dist + 0.0011 * (dist / reach) ** 2)
                            + xl * (np.dot(rel, xl) * k) + zl * (np.dot(rel, zl) * k * k))
            grid.append(line)
        start = len(verts)
        nr = len(grid)
        for ri in range(nr):
            for ci in range(nc):
                verts.append(grid[ri][ci])
                cols.append(NAIL_MOON if ri == 0 else NAIL_TIP if ri >= nr - 1 else NAIL)
                joints.append(BI[name])
        for ri in range(nr - 1):
            for ci in range(nc - 1):
                a = start + ri * nc + ci
                faces.append([a, a + nc, a + nc + 1, a + 1])
        root, edge = grid[0][nc // 2], grid[-1][nc // 2]
        places[name] = (root, frame(unit(edge - root), zl), float(np.linalg.norm(edge - root)),
                        float(np.linalg.norm(grid[2][-1] - grid[2][0])))
    v = np.array(verts)
    t = triangulate(v, faces)
    # outward is away from the finger: flip if the first nail's normal points to the palm
    n = vertex_normals(v, t)
    if np.dot(n[2 * nc + nc // 2], specs[0][4]) > 0:
        t = t[:, ::-1].copy()
    return v, np.array(cols), np.array(joints), t, places


def bake_shade(p, n, tris, rays=20, reach=0.028):
    """How closed-in each vertex is (0 open .. 1 buried): between the fingers,
    in the webs, in the hollow of the palm. Goes into the vertex colour so the
    hand keeps its form under an unshaded material."""
    v0 = p[tris[:, 0]]
    e1 = p[tris[:, 1]] - v0
    e2 = p[tris[:, 2]] - v0
    cen = (p[tris[:, 0]] + p[tris[:, 1]] + p[tris[:, 2]]) / 3.0
    local = []
    for k in range(rays):
        z = 1.0 - (k + 0.5) / rays
        r = math.sqrt(max(0.0, 1.0 - z * z))
        a = k * 2.399963229728653
        local.append([r * math.cos(a), r * math.sin(a), z])
    local = np.array(local)
    out = np.zeros(len(p))
    for i in range(len(p)):
        nz = n[i]
        t = unit(np.cross(nz, [0.0, 1.0, 0.0] if abs(nz[1]) < 0.9 else [1.0, 0.0, 0.0]))
        b = np.cross(nz, t)
        dirs = local[:, 0:1] * t + local[:, 1:2] * b + local[:, 2:3] * nz
        o = p[i] + nz * 0.0007
        near = np.linalg.norm(cen - o, axis=1) < reach + 0.012
        a0, a1, a2 = v0[near], e1[near], e2[near]
        h = np.cross(dirs[:, None, :], a2[None, :, :])
        det = np.einsum("tj,rtj->rt", a1, h)
        ok = np.abs(det) > 1e-14
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        sv = o - a0
        u = np.einsum("tj,rtj->rt", sv, h) * inv
        q = np.cross(sv, a1)
        v = np.einsum("rj,tj->rt", dirs, q) * inv
        tt = np.einsum("tj,tj->t", a2, q)[None, :] * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (tt > 1e-6) & (tt < reach)
        dist = np.where(hit, tt, reach).min(axis=1)
        out[i] = float(np.mean((1.0 - dist / reach) * local[:, 2]) / np.mean(local[:, 2]))
    return out


# ---------------------------------------------------------------- posing (for the check renders)
def bind_matrices(bones):
    out = []
    for b in bones:
        m = np.eye(4)
        m[:3, :3] = b.rest
        m[:3, 3] = b.head
        out.append(m)
    return out


def posed_matrices(bones, pose):
    world = []
    for b in bones:
        m = np.eye(4)
        if b.parent < 0:
            m[:3, :3] = b.rest
            m[:3, 3] = b.head
        else:
            par = bones[b.parent]
            m[:3, :3] = par.rest.T @ b.rest
            m[:3, 3] = par.rest.T @ (b.head - par.head)
        if b.name in pose:
            r = np.eye(4)
            r[:3, :3] = pose[b.name]
            m = m @ r
        world.append(m if b.parent < 0 else world[b.parent] @ m)
    return world


def skin_points(p, joints, weights, bones, pose):
    bind = bind_matrices(bones)
    world = posed_matrices(bones, pose)
    mats = np.array([world[j] @ np.linalg.inv(bind[j]) for j in range(len(bones))])
    ph = np.concatenate([p, np.ones((len(p), 1))], axis=1)
    out = np.zeros((len(p), 3))
    for k in range(joints.shape[1]):
        m = mats[joints[:, k]]
        out += weights[:, k:k + 1] * np.einsum("nij,nj->ni", m, ph)[:, :3]
    return out


def curl_pose(mcp, pip, dip, thumb=(0, 0, 0), thumb_in=0.0, spread=0.0):
    pose = {}
    for i in range(4):
        k = [0.9, 1.0, 1.06, 1.15][i]
        pose["%s_1" % FINGER[i]] = rot_z(spread * (1.5 - i)) @ rot_x(-mcp * k)
        pose["%s_2" % FINGER[i]] = rot_x(-pip * k)
        pose["%s_3" % FINGER[i]] = rot_x(-dip * k)
    pose["thumb_1"] = rot_y(thumb_in) @ rot_x(-thumb[0])
    pose["thumb_2"] = rot_x(-thumb[1])
    pose["thumb_3"] = rot_x(-thumb[2])
    return pose


# ---------------------------------------------------------------- software render
def render(parts, right, up, size=(820, 1000), ss=2, pad=0.08, bg=(0.80, 0.82, 0.84), flat=False):
    """parts: [(points, normals, colours, tris, gloss)]. Orthographic, z-buffered."""
    right, up = unit(right), unit(up)
    to_cam = np.cross(right, up)
    w, h = size[0] * ss, size[1] * ss
    allp = np.concatenate([p for p, _, _, _, _ in parts])
    sx, sy = allp @ right, allp @ up
    span = max((sx.max() - sx.min()) / (1 - 2 * pad) / w, (sy.max() - sy.min()) / (1 - 2 * pad) / h)
    cx, cy = (sx.max() + sx.min()) * 0.5, (sy.max() + sy.min()) * 0.5
    zbuf = np.full((h, w), -1e9)
    nbuf = np.zeros((h, w, 3))
    cbuf = np.zeros((h, w, 3))
    gbuf = np.zeros((h, w))
    mask = np.zeros((h, w), dtype=bool)
    for p, n, col, tris, gloss in parts:
        x = (p @ right - cx) / span + w * 0.5
        y = h * 0.5 - (p @ up - cy) / span
        z = p @ to_cam
        nc = np.stack([n @ right, n @ up, n @ to_cam], axis=1)
        for a, b, c in tris:
            area = (x[b] - x[a]) * (y[c] - y[a]) - (x[c] - x[a]) * (y[b] - y[a])
            if area >= 0:  # back face (y runs down the image)
                continue
            x0, x1 = int(max(0, math.floor(min(x[a], x[b], x[c])))), int(min(w - 1, math.ceil(max(x[a], x[b], x[c]))))
            y0, y1 = int(max(0, math.floor(min(y[a], y[b], y[c])))), int(min(h - 1, math.ceil(max(y[a], y[b], y[c]))))
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            wa = ((x[b] - gx) * (y[c] - gy) - (x[c] - gx) * (y[b] - gy)) / area
            wb = ((x[c] - gx) * (y[a] - gy) - (x[a] - gx) * (y[c] - gy)) / area
            wc = 1.0 - wa - wb
            inside = (wa >= 0) & (wb >= 0) & (wc >= 0)
            if not inside.any():
                continue
            zz = wa * z[a] + wb * z[b] + wc * z[c]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            win = inside & (zz > sub)
            if not win.any():
                continue
            sub[win] = zz[win]
            nbuf[y0:y1 + 1, x0:x1 + 1][win] = (wa[..., None] * nc[a] + wb[..., None] * nc[b] + wc[..., None] * nc[c])[win]
            cbuf[y0:y1 + 1, x0:x1 + 1][win] = (wa[..., None] * col[a] + wb[..., None] * col[b] + wc[..., None] * col[c])[win]
            gbuf[y0:y1 + 1, x0:x1 + 1][win] = gloss
            mask[y0:y1 + 1, x0:x1 + 1][win] = True
    nn = nbuf / np.maximum(np.linalg.norm(nbuf, axis=2, keepdims=True), 1e-9)
    if flat:
        img = cbuf.copy()
    else:
        key = unit([-0.45, 0.55, 0.70])
        fill = unit([0.7, -0.1, 0.5])
        kd = np.clip((nn @ key + 0.35) / 1.35, 0, 1)
        fd = np.clip((nn @ fill + 0.5) / 1.5, 0, 1)
        light = 0.38 + 0.52 * kd + 0.16 * fd
        img = cbuf * light[..., None]
        # shadowed skin runs warm, never grey
        img += np.array([0.10, 0.02, 0.01]) * ((1 - kd) ** 2)[..., None] * 0.6
        rim = np.clip(1.0 - nn[..., 2], 0, 1) ** 3
        img *= (1.0 - 0.28 * rim)[..., None] * np.array([1.0, 0.96, 0.95]) ** rim[..., None]
        hv = unit(key + np.array([0, 0, 1.0]))
        spec = np.clip(nn @ hv, 0, 1) ** 60
        img += (spec * gbuf * 0.55)[..., None]
    yy = np.linspace(0, 1, h)[:, None, None]
    back = np.array(bg) * (1.04 - 0.10 * yy) * np.ones((h, w, 3))
    img = np.where(mask[..., None], img, back)
    img = np.clip(img, 0, 1).reshape(size[1], ss, size[0], ss, 3).mean(axis=(1, 3))
    return Image.fromarray((img * 255 + 0.5).astype(np.uint8))


# ---------------------------------------------------------------- glb
def quat(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return [round(float(x), 7) + 0.0 for x in q]


def write_glb(path, bones, meshes, extras):
    """meshes: [(name, points, normals, colours, joints4, weights4, tris, material)]."""
    blob = bytearray()
    views, accessors = [], []

    def push(arr, ctype, kind, target=None, minmax=False, normalized=False):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        raw = arr.tobytes()
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            view["target"] = target
        views.append(view)
        blob += raw
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    nodes = []
    for b in bones:
        if b.parent < 0:
            t, r = b.head, b.rest
        else:
            par = bones[b.parent]
            t, r = par.rest.T @ (b.head - par.head), par.rest.T @ b.rest
        nodes.append({"name": b.name, "translation": [round(float(x), 7) + 0.0 for x in t], "rotation": quat(r)})
    for i, b in enumerate(bones):
        kids = [j for j, o in enumerate(bones) if o.parent == i]
        if kids:
            nodes[i]["children"] = kids
    ibm = np.array([np.linalg.inv(m).T.reshape(16) for m in bind_matrices(bones)], dtype=np.float32)
    ibm_acc = push(ibm.reshape(-1, 16), 5126, "MAT4")
    gl_meshes = []
    scene_nodes = [0]
    for name, p, n, col, j4, w4, tris, material in meshes:
        attrs = {
            "POSITION": push(p.astype(np.float32), 5126, "VEC3", 34962, minmax=True),
            "NORMAL": push(n.astype(np.float32), 5126, "VEC3", 34962),
            "COLOR_0": push(np.concatenate([col, np.ones((len(col), 1))], axis=1).astype(np.float32), 5126, "VEC4", 34962),
            "JOINTS_0": push(j4.astype(np.uint8), 5121, "VEC4", 34962),
            "WEIGHTS_0": push(w4.astype(np.float32), 5126, "VEC4", 34962),
        }
        idx = push(tris.astype(np.uint16).reshape(-1), 5123, "SCALAR", 34963)
        gl_meshes.append({"name": name, "primitives": [{"attributes": attrs, "indices": idx, "material": material}]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1, "skin": 0})
        scene_nodes.append(len(nodes) - 1)
    doc = {
        "asset": {"version": "2.0", "generator": "flesh-pit tools/vent_hand_model/build_hand.py"},
        "scene": 0,
        "scenes": [{"name": "vent_hand", "nodes": scene_nodes, "extras": extras}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "skins": [{"name": "vent_hand", "joints": list(range(len(bones))), "skeleton": 0, "inverseBindMatrices": ibm_acc}],
        "materials": [
            {"name": "vent_hand_skin", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.62}},
            {"name": "vent_hand_nail", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.22}},
        ],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    while len(blob) % 4:
        blob += b"\0"
    doc["buffers"][0]["byteLength"] = len(blob)
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(text) % 4:
        text += b" "
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + 8 + len(blob)))
        fh.write(struct.pack("<II", len(text), 0x4E4F534A))
        fh.write(text)
        fh.write(struct.pack("<II", len(blob), 0x004E4942))
        fh.write(bytes(blob))


def top4(w):
    order = np.argsort(-w, axis=1)[:, :4]
    vals = np.take_along_axis(w, order, axis=1)
    vals[vals < 0.01] = 0.0
    vals = vals / vals.sum(axis=1, keepdims=True)
    order = np.where(vals > 0, order, 0)
    return order, vals


# ---------------------------------------------------------------- main
def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 9 + 7 * len(text), 20], fill=(0, 0, 0))
    d.text((5, 4), text, fill=(255, 230, 90))
    return img


def main():
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    fit = fitted()
    p, w, a, quads, cage_n = build_mesh(fit)
    m = measure(p, w)
    tris = triangulate(p, quads)
    n = vertex_normals(p, tris)
    col = skin_colours(a, bake_shade(p, n, tris))
    j4, w4 = top4(w)
    nv, ncol, njoint, ntris, places = build_nails(p, tris)
    for name, (head, rest, _len, _wid) in places.items():
        BONES[BI[name]].head = head
        BONES[BI[name]].rest = rest
    nn = vertex_normals(nv, ntris)
    nj4 = np.zeros((len(nv), 4), dtype=np.int64)
    nj4[:, 0] = njoint
    nw4 = np.zeros((len(nv), 4))
    nw4[:, 0] = 1.0
    seat_hit = ray_hit(p, tris, np.array([0.001, -0.058, 0.1]), np.array([0.0, 0.0, -1.0]))
    seat = [0.001, -0.058, round(0.1 - seat_hit, 5)]
    mid = m["middle"]
    extras = {
        "frame": "wrist at origin, fingers -Y, palm +Z, thumb +X, metres",
        "curl": "negative rotation about a finger bone's local X bends it toward the palm",
        "item_seat": seat,
        "triangles": {"hand": int(len(tris)), "nails": int(len(ntris))},
        "measured": {
            "middle_m": round(mid, 5),
            "index": round(m["index"] / mid, 4), "ring": round(m["ring"] / mid, 4),
            "little": round(m["little"] / mid, 4), "thumb": round(m["thumb"] / mid, 4),
            "middle_over_back": round(mid / BACK_LEN, 4), "palm_over_middle": round(m["palm"] / mid, 4),
            "tip_over_root": {f: round(m[f + "_tip"] / m[f + "_root"], 4) for f in FINGER},
        },
        "nails": {name: {"length_m": round(v[2], 5), "width_m": round(v[3], 5)} for name, v in places.items()},
    }
    write_glb(os.path.join(OUT, "vent_hand.glb"), BONES,
              [("vent_hand", p, n, col, j4, w4, tris, 0), ("vent_hand_nails", nv, nn, ncol, nj4, nw4, ntris, 1)], extras)

    def parts(pose):
        if pose:
            hp = skin_points(p, j4, w4, BONES, pose)
            np_ = skin_points(nv, nj4, nw4, BONES, pose)
        else:
            hp, np_ = p, nv
        return [(hp, vertex_normals(hp, tris), col, tris, 0.12), (np_, vertex_normals(np_, ntris), ncol, ntris, 1.0)]

    X, Y, Z = np.eye(3)
    rest = parts(None)
    relaxed = parts(curl_pose(5, 9, 6, thumb=(2, 5, 8)))
    grip = parts(curl_pose(68, 82, 48, thumb=(18, 28, 38), thumb_in=-38))
    offer = parts(curl_pose(10, 20, 13, thumb=(4, 8, 10), spread=1.5))
    shots = [
        ("back", relaxed, X, -Y, "back of the hand (relaxed)"),
        ("palm", relaxed, -X, -Y, "palm (relaxed)"),
        ("side", relaxed, Z, -Y, "thumb side (relaxed)"),
        ("grip", grip, unit(-X * 0.8 + Z * 0.6), unit(-Y + Z * 0.25 + X * 0.2), "grip"),
        ("grip_back", grip, unit(X * 0.85 + Z * 0.5), unit(-Y - Z * 0.3), "grip, from the back"),
        ("offer", offer, unit(-X + Z * 0.15), unit(-Y * 0.55 + Z * 0.85), "offer: palm up, seen from in front and above"),
        ("back_flat", rest, X, -Y, "bind pose, back, vertex colours only"),
        ("palm_flat", rest, -X, -Y, "bind pose, palm, vertex colours only"),
    ]
    images = []
    for name, pr, right, up, text in shots:
        up = unit(up - right * np.dot(up, right))
        img = render(pr, right, up, flat=name.endswith("_flat"), bg=(0.93, 0.94, 0.95) if name.endswith("_flat") else (0.80, 0.82, 0.84))
        img.save(os.path.join(OUT, "renders", "%s.png" % name))
        images.append(label(img.copy(), text))
    sheet = Image.new("RGB", (820 * 4, 1000 * 2), (30, 30, 30))
    for k, img in enumerate(images):
        sheet.paste(img, (820 * (k % 4), 1000 * (k // 4)))
    sheet.resize((820 * 2, 1000), Image.LANCZOS).save(os.path.join(OUT, "renders", "sheet.jpg"), quality=90)
    print(json.dumps({"cage": {"verts": cage_n[0], "faces": cage_n[1]}, "verts": int(len(p)), "fit": fit, **extras}, indent=1))


if __name__ == "__main__":
    main()
