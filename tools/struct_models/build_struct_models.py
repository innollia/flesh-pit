# Blender headless: the ten biome structures (game/main/art/fp_struct_*.gd) as
# low-poly models with one painted atlas each, the hwapongstuy texture3d way
# (C:\projects\hwapongstuy\texture3d): few polygons, every detail painted,
# boxes unfolded as a cross around FRONT, round parts as a side strip + cap,
# repeated parts share one atlas cell (same key), one scale for all islands.
# box / lathe / pack / export follow texture3d/tools/build_models.py.
#
# Run: blender --background --python build_struct_models.py -- <out_dir> [kind ...]
# Out: <out_dir>/fp_<kind>/model.glb, layout.json
#
# Coordinates: g(x, y, z) is the game's pocket space (origin = pocket floor
# centre, +Y up, mouth on +Z). glTF export turns Blender (x, y, z) into
# (x, z, -y), so a box's FRONT (Blender -Y) faces the mouth.
import bpy
import bmesh
import json
import math
import os
import random
import sys
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGV[0] if ARGV else "out")
ONLY = ARGV[1:]
TEX = 1024
PAD = 0.02


class Island:
    def __init__(self, name, hint, key=None):
        self.name = name
        self.hint = hint
        self.key = key or name
        self.faces = []
        self.labels = []

    def bbox(self):
        us = [u for _, uvs in self.faces for u, _ in uvs]
        vs = [v for _, uvs in self.faces for _, v in uvs]
        return min(us), min(vs), max(us), max(vs)


class Model:
    def __init__(self, name, title):
        self.name = name
        self.title = title
        self.bm = bmesh.new()
        self.islands = []

    def face(self, pts):
        return self.bm.faces.new([self.bm.verts.new(p) for p in pts])


def box(m, name, hint, size, mat=Matrix(), omit=(), key=None):
    W, D, H = size
    x0, x1, y0, y1, z0, z1 = -W / 2, W / 2, -D / 2, D / 2, 0.0, H
    vb = 0.0 if "bottom" in omit else D
    faces = {
        "front": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
                  lambda x, y, z: (D + (x - x0), vb + z)),
        "right": ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
                  lambda x, y, z: (D + W + (y - y0), vb + z)),
        "back": ([(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
                 lambda x, y, z: (2 * D + W + (x1 - x), vb + z)),
        "left": ([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
                 lambda x, y, z: (y1 - y, vb + z)),
        "top": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
                lambda x, y, z: (D + (x - x0), vb + H + (y - y0))),
        "bottom": ([(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
                   lambda x, y, z: (D + (x - x0), y1 - y)),
    }
    isl = Island(name, hint, key)
    for side, (pts, uvf) in faces.items():
        if side in omit:
            continue
        f = m.face([mat @ Vector(p) for p in pts])
        uvs = [uvf(*p) for p in pts]
        isl.faces.append((f, uvs))
        isl.labels.append((side.upper(), sum(u for u, _ in uvs) / 4, sum(v for _, v in uvs) / 4))
    m.islands.append(isl)
    return isl


def lathe(m, name, hint, rings, n, mat=Matrix(), noise=0.0, seed=0, rot=0.0,
          cap_top=True, cap_bottom=False, key=None, cap_key=None):
    """rings: [(z, r)] bottom to top. r=0 is an apex."""
    rnd = random.Random(seed)
    ring_pts = []
    for k, (z, r) in enumerate(rings):
        if r <= 1e-6:
            ring_pts.append(None)
            continue
        pts = []
        for i in range(n):
            a = rot + 2 * math.pi * i / n
            rr = r * (1 + rnd.uniform(-noise, noise))
            zz = z + (rnd.uniform(-noise, noise) * r * 0.4 if k > 0 else 0.0)
            pts.append(Vector((rr * math.cos(a), rr * math.sin(a), zz)))
        ring_pts.append(pts)

    def apex(k):
        return Vector((0.0, 0.0, rings[k][0]))

    chords = [(pts[0] - pts[1]).length for pts in ring_pts if pts]
    cw = sum(chords) / len(chords)
    vrow = [0.0]
    for k in range(len(rings) - 1):
        lo, up = ring_pts[k], ring_pts[k + 1]
        d = [((lo[i] if lo else apex(k)) - (up[i] if up else apex(k + 1))).length for i in range(n)]
        vrow.append(vrow[-1] + sum(d) / n)

    side = Island(name, hint, key)
    for k in range(len(rings) - 1):
        lo, up = ring_pts[k], ring_pts[k + 1]
        v0, v1 = vrow[k], vrow[k + 1]
        for i in range(n):
            j = (i + 1) % n
            u0, u1 = i * cw, (i + 1) * cw
            if up is None:
                pts, uvs = [lo[i], lo[j], apex(k + 1)], [(u0, v0), (u1, v0), ((u0 + u1) / 2, v1)]
            elif lo is None:
                pts, uvs = [apex(k), up[j], up[i]], [((u0 + u1) / 2, v0), (u1, v1), (u0, v1)]
            else:
                pts, uvs = [lo[i], lo[j], up[j], up[i]], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            side.faces.append((m.face([mat @ p for p in pts]), uvs))
    side.labels.append(("SIDE", n * cw / 2, vrow[-1] / 2))
    m.islands.append(side)

    def cap(pts, label, ck, top):
        order = pts if top else list(reversed(pts))
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        uvs = [(p.x - min(xs), (p.y - min(ys)) if top else (max(ys) - p.y)) for p in order]
        isl = Island(f"{name} {label}", hint, ck)
        isl.faces.append((m.face([mat @ p for p in order]), uvs))
        isl.labels.append((label.upper(), (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2))
        m.islands.append(isl)

    if cap_top and ring_pts[-1]:
        cap(ring_pts[-1], "top", cap_key, True)
    if cap_bottom and ring_pts[0]:
        cap(ring_pts[0], "bottom", cap_key, False)
    return side


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(s):
    return Matrix.Scale(s, 4)


# ---------------------------------------------------------------- game-space helpers

def G(x, y, z):
    """Game pocket point -> Blender point."""
    return T(x, -z, y)


def gb(m, name, hint, c, h, omit=(), key=None, yaw=0.0, tilt=0.0):
    """Box with game centre c and game half size h (x, y up, z depth).
    yaw turns it around up (degrees, game +Y), tilt leans it toward the mouth."""
    mat = G(c[0], c[1] - h[1], c[2]) @ R(-yaw, "Z") @ R(tilt, "X")
    return box(m, name, hint, (2 * h[0], 2 * h[2], 2 * h[1]), mat=mat, omit=omit, key=key)


def floor(m, name, hint, hx, hz, y=0.0):
    """Only the top face: a floor strip over the pocket floor."""
    return gb(m, name, hint, (0, y - 0.01, 0), (hx, 0.01, hz),
              omit=("front", "back", "left", "right", "bottom"))


def panel(m, name, hint, c, hx, hy, key=None):
    """A flat painted panel facing the mouth (front face only), e.g. a wall
    strip or a warning plate."""
    return gb(m, name, hint, c, (hx, hy, 0.01), omit=("back", "left", "right", "top", "bottom"), key=key)


def lump(m, name, hint, c, r, seed, key=None, squash=1.0):
    """A low-poly growth mass (fat, cartilage, cloth wad, hair mat)."""
    rings = [(0.0, r * 0.75), (r * 0.6 * squash, r), (r * 1.2 * squash, r * 0.7), (r * 1.6 * squash, 0.0)]
    return lathe(m, name, hint, rings, 6, mat=G(c[0], c[1] - r * 0.5, c[2]), noise=0.22, seed=seed,
                 cap_top=False, cap_bottom=False, key=key)


def cyl(m, name, hint, c, r, h, n=6, key=None, cap_key=None, axis=None, caps=True):
    """Upright (axis None), or lying along game 'x' / 'z', centred at c."""
    if axis == "x":
        mat = G(*c) @ R(90, "Y") @ T(z=-h / 2)
    elif axis == "z":
        mat = G(*c) @ R(90, "X") @ T(z=-h / 2)
    else:
        mat = G(c[0], c[1] - h / 2, c[2])
    return lathe(m, name, hint, [(0, r), (h, r)], n, mat=mat, cap_top=caps, key=key, cap_key=cap_key or (f"{key} cap" if key else None))


SWALLOWED = ("swallowed long ago by a living flesh world; worn, grimy, faded paint, rust and dark stains "
             "toward the bottom")


# ---------------------------------------------------------------- the ten structures

def s_laundromat():
    m = Model("fp_laundromat", "1970s coin laundromat corner (biome structure, PS1-era horror game)")
    floor(m, "lino", "avocado green and mustard checker linoleum floor, worn through to grey in places, "
          "a trail of spilled clothes and brown stains", 1.5, 0.9)
    for i, x in enumerate((-0.75, 0.0, 0.75)):
        hint = ("white enamel front-loading washing machine, yellowed; FRONT has a round chrome-ringed porthole "
                "door with dark glass and a small coin slot plate; rust drip under the door")
        key = "washer"
        if i == 0:
            hint = ("white enamel front-loading washing machine, yellowed; FRONT has a round porthole with the "
                    "door open and twisted clothes spilling out of the dark drum")
            key = "washer open"
        gb(m, f"washer{i}", hint, (x, 0.43, -0.6), (0.29, 0.43, 0.3), omit=("bottom",), key=key)
        gb(m, f"strip{i}", "beige control strip with two black round knobs and a grey indicator window, no text",
           (x, 0.94, -0.84), (0.29, 0.09, 0.07), omit=("bottom",), key="control strip")
    gb(m, "table top", "folding table top, pale grey formica with a chipped edge; TOP has a stack of folded "
       "clothes painted on it", (1.22, 0.74, 0.25), (0.24, 0.025, 0.45), key="table top")
    for sx in (-1, 1):
        for sz in (-1, 1):
            gb(m, "table leg", "thin chrome table leg", (1.22 + sx * 0.2, 0.36, 0.25 + sz * 0.4),
               (0.02, 0.36, 0.02), omit=("top", "bottom"), key="table leg")
    gb(m, "folded stack", "a stack of folded faded shirts and towels", (1.2, 0.84, 0.2), (0.16, 0.08, 0.14),
       omit=("bottom",))
    panel(m, "warning plate", "square yellow enamel warning plate with a black border: a pictogram of a "
          "lumpy wad of clothes and a long, slow curved arrow (the clothes barely grow back); no letters",
          (-1.25, 1.45, -0.86), 0.16, 0.16)
    for c, r, s in (((-1.3, 0.25, -0.75), 0.32, 1), ((1.35, 1.75, -0.7), 0.3, 2), ((-1.25, 1.85, -0.65), 0.28, 3),
                    ((0.4, 2.0, -0.8), 0.3, 4), ((-0.7, 0.1, 0.2), 0.22, 5)):
        lump(m, "cloth wad", "a wad of swallowed clothes pressed together: denim, beige, dull red cloth "
             "folds with blood-brown creases, a sleeve end", c, r, s, key="cloth wad")
    gb(m, "tube fixture", "white metal fluorescent fixture housing", (0.0, 2.15, -0.2), (0.6, 0.03, 0.08),
       omit=("bottom",))
    return m


def s_phone_booth():
    m = Model("fp_phone_booth", "1960s public telephone booth (biome structure, PS1-era horror game)")
    floor(m, "pavement", "square grey pavement slabs with dark cracks and yellow fat smears", 0.9, 0.9)
    B, H = 0.72, 2.2
    for name, c, h, hint in (
            ("back wall", (0, H / 2, -B), (B, H / 2, 0.02),
             "booth back wall: green-grey painted steel frame, low kick panel, upper part dark bluish glass "
             "with a white crack; a black coin telephone with a rotary dial (finger holes only) and a "
             "hanging handset on a coiled cord"),
            ("side wall", (-B, H / 2, 0), (0.02, H / 2, B),
             "booth side wall: green-grey painted steel frame, low kick panel, upper part dark bluish glass, "
             "one pane missing")):
        gb(m, name, hint, c, h, omit=("bottom", "top"))
    gb(m, "side wall r", "booth side wall: green-grey painted steel frame, low kick panel, upper part dark "
       "bluish glass, one pane cracked; a square sticker: a telephone handset with an arrow sinking into "
       "wavy flesh, no letters", (B, H / 2, 0), (0.02, H / 2, B), omit=("bottom", "top"))
    gb(m, "door", "folding glass door left ajar: green-grey steel frame, two tall dark bluish glass panes",
       (0.35, H / 2, B + 0.05), (0.35, H / 2 - 0.02, 0.02), omit=("bottom", "top"), yaw=-25)
    gb(m, "roof", "booth roof: green-grey steel, TOP covered by soft yellow fat", (0, H + 0.04, 0),
       (B + 0.04, 0.04, B + 0.04))
    gb(m, "shelf", "small steel shelf with a chained thick phone directory", (0.2, 0.95, -0.6),
       (0.25, 0.03, 0.1))
    for c, r, s in (((0.45, 2.42, -0.45), 0.3, 1), ((-0.4, 2.45, 0.1), 0.28, 2), ((0.82, 1.85, -0.82), 0.24, 3),
                    ((0.84, 1.1, -0.84), 0.22, 4), ((0.82, 0.35, -0.82), 0.26, 5)):
        lump(m, "fat", "soft yellow rendered fat, waxy lumps with pale highlights and orange drips",
             c, r, s, key="fat lump")
    return m


def s_boiler_room():
    m = Model("fp_boiler_room", "1930s boiler room corner (biome structure, PS1-era horror game)")
    floor(m, "floor", "dark oily concrete floor with coal dust and yellow fat drips", 1.4, 1.4)
    cyl(m, "boiler", "riveted black-grey iron boiler drum, rows of rivets, rust streaks", (0.0, 0.75, -0.75),
        0.62, 2.0, n=8, axis="x", key="boiler drum", cap_key="boiler end")
    gb(m, "firebox", "boiler firebox front: iron door with a slotted draft grille, orange glow in the slots, "
       "a round pressure gauge (dial and needle, no digits) above it", (0.0, 0.55, -0.1), (0.35, 0.55, 0.06),
       omit=("bottom", "back"))
    for x in (-1.15, 1.2):
        cyl(m, "pipe", "rusty iron steam pipe, flange rings", (x, 1.2, -1.25), 0.07, 2.4, n=5, key="pipe", caps=False)
    cyl(m, "pipe across", "rusty iron steam pipe, flange rings", (0.0, 2.25, -1.25), 0.07, 2.5, n=5,
        axis="x", key="pipe", caps=False)
    cyl(m, "valve wheel", "red painted valve wheel with spokes", (1.2, 1.3, -1.12), 0.14, 0.03, n=8,
        axis="z", key="valve")
    gb(m, "shovel", "coal shovel leaning on the wall: dark iron blade, worn wooden handle", (-0.9, 0.6, -1.2),
       (0.1, 0.6, 0.02), omit=("bottom", "top", "back"), tilt=-10)
    panel(m, "plate hot", "square white enamel warning plate with a red border: a hand, heat waves and a red "
          "slash (hot pipe, do not touch); no letters", (0.75, 1.55, -1.32), 0.15, 0.15)
    panel(m, "plate close", "square white enamel warning plate with a red border: two arrows meeting in the "
          "middle (the gap closes again); no letters", (-0.55, 1.55, -1.32), 0.15, 0.15)
    gb(m, "lamp cage", "caged amber bulkhead lamp, iron wire cage", (-1.32, 1.75, 0.3), (0.06, 0.1, 0.1),
       omit=("left",))
    for c, r, s in (((-0.3, 2.35, -1.15), 0.32, 1), ((1.3, 2.35, -0.9), 0.3, 2), ((-1.3, 2.3, -0.45), 0.3, 3),
                    ((-1.25, 1.0, -1.25), 0.3, 4), ((1.0, 1.1, -1.25), 0.24, 5), ((0.5, 1.45, -0.7), 0.26, 6)):
        lump(m, "fat", "soft yellow rendered fat, waxy lumps with pale highlights and orange drips",
             c, r, s, key="fat lump")
    return m


def s_subway_turnstile():
    m = Model("fp_subway_turnstile", "1970s metro fare-gate line (biome structure, PS1-era horror game)")
    floor(m, "floor", "station floor: small grey and cream square tiles, black grime in the grout", 1.8, 1.0)
    panel(m, "tile wall", "station wall: cream square tiles with a green tile band at waist height, cracked "
          "and stained, a few tiles missing", (0, 1.15, -0.95), 1.8, 1.15)
    for x in (-1.35, -0.25, 0.85):
        gb(m, "gate body", "brushed steel turnstile cabinet: a brass token slot on TOP, a small round red "
           "lamp on FRONT, scuffed", (x, 0.5, -0.1), (0.15, 0.5, 0.35), omit=("bottom",), key="gate body")
        for k, ang in enumerate((0, 120, 240)):
            cyl(m, "gate arm", "polished steel tube arm", (x + 0.32, 0.85 + 0.05 * k, -0.1), 0.025, 0.5, n=4,
                axis="x", key="gate arm", caps=False)
    gb(m, "sign", "hanging square sign, white with a black border: an arrow pointing down beside a knife "
       "(below here you need a blade); no letters", (0.6, 1.9, 0.1), (0.25, 0.2, 0.015), omit=("top", "bottom"))
    gb(m, "tube fixture", "broken fluorescent fixture: white metal housing, one tube snapped", (-0.6, 2.1, 0.0),
       (0.45, 0.03, 0.07), omit=("bottom",), tilt=15)
    cyl(m, "spine", "white-blue cartilage, glossy and gristly with pink veins", (0.0, 2.32, -0.85), 0.11, 3.7,
        n=6, axis="x", key="cartilage", caps=False)
    for x in (-1.55, -0.62, 0.42, 1.5):
        cyl(m, "rib", "white-blue cartilage, glossy and gristly with pink veins", (x, 1.25, -0.85), 0.09, 2.2,
            n=5, key="cartilage", caps=False)
    return m


def s_elevator_car():
    m = Model("fp_elevator_car", "1950s service elevator car (biome structure, PS1-era horror game)")
    C, H = 0.85, 2.2
    floor(m, "floor", "steel checker-plate elevator floor, scratched, dark grime in the corners", C, C)
    panel(m, "back wall", "brushed steel elevator back wall with a horizontal handrail; a square plate with "
          "a black border: an elevator car with an up arrow, crossed out in red; no letters", (0, H / 2, -C), C, H / 2)
    for sx in (-1, 1):
        gb(m, "side wall", "brushed steel elevator side wall with a horizontal handrail, scratches and dents",
           (sx * C, H / 2, 0), (0.01, H / 2, C), omit=("bottom", "top", "front", "back"), key="side wall")
    gb(m, "ceiling", "elevator ceiling: steel panel, BOTTOM has a domed lamp and a bent-up roof hatch with "
       "cartilage pushing through", (0, H + 0.02, 0), (C, 0.02, C), omit=("top",))
    for sx in (-1, 1):
        gb(m, "door leaf", "brushed steel sliding door leaf, stuck half open, scratched", (sx * 0.62, H / 2, C),
           (0.24, H / 2, 0.02), omit=("bottom", "top"), key="door leaf")
    gb(m, "indicator", "floor indicator over the door: a row of five round lamps, only the lowest lit amber, "
       "no digits", (0, H + 0.12, C + 0.02), (0.4, 0.08, 0.02), omit=("bottom", "top", "back"))
    gb(m, "buttons", "button panel: brass plate with a column of plain round black buttons", (0.75, 1.1, -0.2),
       (0.01, 0.2, 0.08), omit=("bottom", "top", "right", "front", "back"))
    lump(m, "cartilage mass", "white-blue cartilage mass, glossy and gristly with pink veins", (0.2, 2.2, -0.3),
         0.32, 1, key="cartilage")
    cyl(m, "door rib", "white-blue cartilage, glossy and gristly with pink veins", (0.0, 2.36, C + 0.1), 0.08,
        2.0, n=5, axis="x", key="cartilage rib", caps=False)
    for sx in (-1, 1):
        cyl(m, "door rib post", "white-blue cartilage, glossy and gristly with pink veins", (sx * 0.98, 1.15, C + 0.1),
            0.08, 2.3, n=5, key="cartilage rib", caps=False)
    return m


def s_school_lockers():
    m = Model("fp_school_lockers", "1960s school corridor lockers (biome structure, PS1-era horror game)")
    floor(m, "lino", "school corridor linoleum: grey-green speckled, scuffed with black heel marks", 1.6, 0.8)
    for i in range(6):
        x = -1.05 + i * 0.42
        if i == 4:
            gb(m, "open locker", "steel school locker with its door hanging open: empty dark inside, a shelf "
               "and a coat hook; faded green enamel", (x, 0.98, -0.55), (0.2, 0.98, 0.18), omit=("bottom",),
               tilt=-6)
            continue
        key = "locker green" if i % 2 == 0 else "locker grey"
        hint = ("tall steel school locker, faded {} enamel; FRONT has pressed vent slots at the top and a lift "
                "handle, rust on the lower edge").format("green" if i % 2 == 0 else "grey")
        if i == 1:
            key = "locker plate"
            hint = ("tall steel school locker, faded grey enamel, vent slots, lift handle; a square yellow plate "
                    "on the door: two walls squeezing a small figure between them; no letters")
        gb(m, f"locker{i}", hint, (x, 0.98, -0.55), (0.2, 0.98, 0.18), omit=("bottom",), key=key, tilt=-6)
    gb(m, "bench", "varnished wooden bench, worn pale where children sat", (0.0, 0.42, 0.1), (1.0, 0.03, 0.15))
    for x in (-0.85, 0.85):
        gb(m, "bench leg", "dark varnished wood", (x, 0.2, 0.1), (0.03, 0.2, 0.12), omit=("top", "bottom"),
           key="bench leg")
    for c, r, s in (((-1.3, 2.05, -0.65), 0.34, 1), ((-0.3, 2.15, -0.7), 0.36, 2), ((0.8, 2.1, -0.65), 0.34, 3),
                    ((1.45, 1.4, -0.6), 0.3, 4)):
        lump(m, "muscle", "red-brown gut muscle, wet striated folds with dark creases", c, r, s, key="muscle")
    return m


def s_fountain_alcove():
    m = Model("fp_fountain_alcove", "1950s public drinking fountain alcove (biome structure, PS1-era horror game)")
    floor(m, "floor", "small pale blue and white floor tiles, a stained drain stain around the middle", 0.9, 0.8)
    panel(m, "back wall", "tiled back wall: pale blue and white small tiles with a blue band at waist height, "
          "grime toward the floor, a few tiles missing; a square plate: a clock ring whose beat mark is a "
          "squeeze; no letters", (0, 0.96, -0.78), 0.86, 0.96)
    for sx in (-1, 1):
        gb(m, "side wall", "tiled side wall: pale blue and white small tiles with a blue band at waist height, "
           "grime toward the floor", (sx * 0.86, 0.96, -0.27), (0.01, 0.96, 0.52),
           omit=("bottom", "top", "front", "back"), key="side wall")
    gb(m, "soffit", "tiled soffit, BOTTOM is cracked tiles with red muscle bulging through", (0, 1.94, -0.27),
       (0.86, 0.02, 0.52), omit=("top",))
    gb(m, "fountain", "white vitreous china wall fountain bowl with a chrome bubbler on TOP and a chrome push "
       "button on FRONT, rust stain", (0.0, 0.85, -0.62), (0.22, 0.12, 0.16), omit=("back",))
    cyl(m, "supply pipe", "chrome pipe, tarnished", (0.0, 0.37, -0.7), 0.025, 0.74, n=4, caps=False)
    gb(m, "wall lamp", "small enamel wall lamp housing, cream", (0.55, 1.55, -0.72), (0.08, 0.06, 0.06),
       omit=("back",))
    for c, r, s in (((-0.75, 1.6, -0.6), 0.3, 1), ((0.6, 1.85, -0.3), 0.28, 2), ((-0.8, 0.3, -0.5), 0.24, 3)):
        lump(m, "muscle", "red-brown gut muscle, wet striated folds with dark creases", c, r, s, key="muscle")
    return m


def s_bus_shelter():
    m = Model("fp_bus_shelter", "1980s city bus shelter (biome structure, PS1-era horror game)")
    floor(m, "paving", "grey square paving slabs, a few darker, a kerb strip along the FRONT edge, litter",
          1.6, 0.9)
    for x in (-1.45, 1.45):
        for z in (-0.75, 0.45):
            gb(m, "post", "square painted steel post, chipped dark green paint", (x, 1.1, z), (0.04, 1.1, 0.04),
               omit=("top", "bottom"), key="post")
    panel(m, "back glass", "three scratched safety-glass back panels in steel frames; the middle panel is "
          "smashed out and stuffed with a wad of clothes", (0, 1.15, -0.76), 1.45, 0.95)
    gb(m, "side glass", "scratched safety-glass side panel; a timetable frame with coloured route bars only, "
       "no letters", (-1.46, 1.15, -0.15), (0.01, 0.95, 0.55), omit=("bottom", "top", "front", "back", "left"))
    gb(m, "roof", "slanted steel shelter roof, dark green, BOTTOM has a fluorescent fixture; TOP is covered "
       "with clothing wads", (0, 2.2, -0.15), (1.6, 0.04, 0.7), tilt=-5)
    gb(m, "bench", "long slatted bench, faded orange wooden slats on a steel frame", (0.0, 0.45, -0.55),
       (1.1, 0.04, 0.15))
    cyl(m, "stop pole", "painted steel bus stop pole, grey", (1.25, 1.1, 0.7), 0.035, 2.2, n=4, caps=False)
    cyl(m, "stop sign", "round bus stop sign, white with a red ring: a bus with an upward arrow above it "
        "(the street is just above); no letters", (1.25, 2.05, 0.72), 0.22, 0.02, n=10, axis="z",
        key="stop sign side", cap_key="stop sign face")
    for c, r, s in (((0.0, 1.1, -0.7), 0.34, 1), ((-0.9, 2.35, -0.3), 0.32, 2), ((0.8, 2.35, -0.1), 0.3, 3),
                    ((1.4, 0.2, -0.6), 0.3, 4)):
        lump(m, "cloth wad", "a wad of swallowed clothes pressed together: denim, beige, dull red cloth folds "
             "with blood-brown creases, a sleeve end", c, r, s, key="cloth wad")
    return m


def s_street_lamp():
    m = Model("fp_street_lamp", "1960s cast-iron sodium street lamp (biome structure, PS1-era horror game)")
    floor(m, "pavement", "broken pavement slab and a granite kerb, cracked asphalt chunks and a round iron "
          "manhole cover toward the FRONT", 1.0, 1.0)
    lathe(m, "base", "fluted cast-iron lamp base, dark green paint flaking to rust",
          [(0, 0.16), (0.35, 0.12), (0.5, 0.07)], 6, mat=G(-0.5, 0.0, -0.62), cap_top=False)
    # the flesh pushed the pole over toward the middle of the pocket
    pole = G(-0.5, 0.5, -0.62) @ R(18, "Y")
    lathe(m, "pole", "cast-iron lamp pole, dark green paint flaking to rust, hair caught on it",
          [(0, 0.06), (2.3, 0.045)], 5, mat=pole, cap_top=False)
    gb(m, "head", "sodium street lamp head: dark iron hood on TOP, BOTTOM is the glowing orange lens",
       (0.3, 2.68, -0.62), (0.26, 0.07, 0.11), tilt=0)
    panel(m, "plate", "square yellow warning plate strapped to the pole: a ring of hair with a red arrow "
          "closing its gap (hair closes fast behind you); no letters", (-0.5, 1.45, -0.54), 0.17, 0.17)
    for c, r, s in (((0.6, 0.15, -0.6), 0.34, 1), ((-0.85, 0.2, 0.3), 0.3, 2), ((0.75, 2.6, -0.7), 0.34, 3),
                    ((-0.8, 2.7, -0.6), 0.3, 4), ((0.2, 0.1, 0.6), 0.26, 5)):
        lump(m, "hair mat", "matted dark brown and black hair growing from pink scalp patches, hanging in "
             "locks", c, r, s, key="hair mat")
    return m


def s_barber_chair():
    m = Model("fp_barber_chair", "1950s barber shop corner (biome structure, PS1-era horror game)")
    floor(m, "checker", "black and white checker floor tiles, heaps of cut hair, cracked", 1.2, 1.0)
    panel(m, "mirror wall", "barber shop wall: mint green paint; a wide mirror gone dark and cloudy; a square "
          "yellow plate on the counter edge: scissors over a lock of hair; no letters", (0, 1.4, -0.98), 1.2, 0.7)
    gb(m, "counter", "mint green barber counter with a white top, a glass jar of combs painted on TOP",
       (0, 0.45, -0.85), (1.0, 0.45, 0.13), omit=("bottom",))
    cyl(m, "pedestal", "polished chrome hydraulic pedestal, tarnished", (0.28, 0.25, -0.05), 0.18, 0.5, n=8)
    gb(m, "seat", "cracked red leatherette barber chair seat with chrome trim", (0.28, 0.6, -0.05),
       (0.28, 0.1, 0.28), yaw=-28, omit=("bottom",))
    gb(m, "backrest", "cracked red leatherette barber chair backrest with a headrest, chrome frame",
       (0.28, 1.0, -0.3), (0.26, 0.32, 0.06), yaw=-28, tilt=-10)
    gb(m, "footrest", "chrome footrest bar plate", (0.4, 0.2, 0.32), (0.2, 0.02, 0.08), yaw=-28)
    cyl(m, "barber pole", "barber pole: red, white and blue diagonal stripes, chrome caps", (-1.12, 1.4, -0.4),
        0.07, 0.8, n=6, key="barber pole", cap_key="barber pole cap")
    for c, r, s in (((-1.0, 0.15, 0.4), 0.3, 1), ((1.05, 2.0, -0.75), 0.32, 2), ((-1.0, 2.05, -0.8), 0.3, 3),
                    ((0.9, 0.12, 0.5), 0.26, 4)):
        lump(m, "hair mat", "matted dark brown and black hair growing from pink scalp patches, hanging in "
             "locks", c, r, s, key="hair mat")
    return m


STRUCTS = {
    "laundromat": s_laundromat, "phone_booth": s_phone_booth, "boiler_room": s_boiler_room,
    "subway_turnstile": s_subway_turnstile, "elevator_car": s_elevator_car, "school_lockers": s_school_lockers,
    "fountain_alcove": s_fountain_alcove, "bus_shelter": s_bus_shelter, "street_lamp": s_street_lamp,
    "barber_chair": s_barber_chair,
}


# ---------------------------------------------------------------- packing and export

def pack(m):
    """One cell per key. Shelf packing without rotation, shrinking the scale
    until everything fits."""
    groups = {}
    for isl in m.islands:
        groups.setdefault(isl.key, []).append(isl)
    sizes = {}
    for k, isls in groups.items():
        x0, y0, x1, y1 = isls[0].bbox()
        sizes[k] = (x1 - x0, y1 - y0)
    area = sum(w * h for w, h in sizes.values())
    scale = math.sqrt(0.75 / area)
    order = sorted(sizes, key=lambda k: -sizes[k][1])
    while True:
        place, x, y, shelf, ok = {}, PAD, PAD, 0.0, True
        for k in order:
            w, h = sizes[k][0] * scale, sizes[k][1] * scale
            if x + w > 1 - PAD:
                x, y, shelf = PAD, y + shelf + PAD, 0.0
            if x + w > 1 - PAD or y + h > 1 - PAD:
                ok = False
                break
            place[k] = (x, y, w, h)
            x += w + PAD
            shelf = max(shelf, h)
        if ok:
            return place, scale
        scale *= 0.96


def export(m):
    place, scale = pack(m)
    uv = m.bm.loops.layers.uv.new("UVMap")
    data = {"name": m.name, "title": m.title, "tex": TEX, "px_per_m": round(scale * TEX, 1), "islands": []}
    seen = set()

    def to_uv(isl, rect, u, v):
        x0, y0, x1, y1 = isl.bbox()
        rx, ry, rw, rh = rect
        return rx + (u - x0) / max(x1 - x0, 1e-9) * rw, ry + (v - y0) / max(y1 - y0, 1e-9) * rh

    for isl in m.islands:
        rect = place[isl.key]
        for f, uvs in isl.faces:
            for loop, (u, v) in zip(f.loops, uvs):
                loop[uv].uv = to_uv(isl, rect, u, v)
        if isl.key in seen:
            next(e for e in data["islands"] if e["key"] == isl.key)["used_by"] += 1
            continue
        seen.add(isl.key)
        px = lambda u, v: (round(to_uv(isl, rect, u, v)[0] * TEX, 1), round((1 - to_uv(isl, rect, u, v)[1]) * TEX, 1))
        data["islands"].append({
            "key": isl.key, "name": isl.name, "hint": isl.hint, "used_by": 1,
            "rect_px": [round(rect[0] * TEX), round((1 - rect[1] - rect[3]) * TEX),
                        round((rect[0] + rect[2]) * TEX), round((1 - rect[1]) * TEX)],
            "faces": [[px(u, v) for u, v in uvs] for _, uvs in isl.faces],
            "labels": [[t, *px(u, v)] for t, u, v in isl.labels],
        })

    data["tris"] = sum(len(f.verts) - 2 for f in m.bm.faces)
    mesh = bpy.data.meshes.new(m.name)
    m.bm.to_mesh(mesh)
    m.bm.free()
    obj = bpy.data.objects.new(m.name, mesh)
    obj.data.materials.append(bpy.data.materials.new(m.name))
    bpy.context.scene.collection.objects.link(obj)
    for o in bpy.context.scene.objects:
        o.select_set(o is obj)
    bpy.context.view_layer.objects.active = obj
    d = os.path.join(OUT, m.name)
    os.makedirs(d, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(d, "model.glb"), export_format="GLB", use_selection=True)
    with open(os.path.join(d, "layout.json"), "w", encoding="utf-8") as fp:
        json.dump(data, fp, ensure_ascii=False, indent=1)
    bpy.data.objects.remove(obj)
    print(f"[build] {m.name}: {data['tris']} tris, {len(data['islands'])} islands, {data['px_per_m']} px/m")


bpy.ops.wm.read_factory_settings(use_empty=True)
for kind, make in STRUCTS.items():
    if ONLY and kind not in ONLY:
        continue
    export(make())
