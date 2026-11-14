# Slender female hand, generated from nothing. Candidate model for the vent being's hands.
#
#   blender --background --python make_hand.py
#
# Writes slender_hand_r.glb next to this file. Right hand, lying flat:
#   Blender space: wrist at the origin, fingers along +Y, back of the hand +Z, thumb toward -X.
#   glTF space (Y up): fingers along -Z, back of the hand +Y, thumb toward -X.
# The left hand is the same model mirrored on X.
#
# How it is made: every part (palm, five fingers, thumb mound, heel, web) is a closed loft or
# ellipsoid that overlaps its neighbours. A voxel remesh fuses them into one skin, a smooth pass
# melts the seams into webbing, and a collapse decimate brings it to the triangle budget.
# Nails are separate plates on their own material and their own bone so they can be swapped.
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_NAME = "slender_hand_r.glb"

SKIN_TRIS = 3200          # skin budget; nails add 5 * 60
VOXEL = 0.0009
SMOOTH_REPEAT = 8

MID_LEN = 0.092           # middle finger, knuckle to tip
PHALANX = (0.46, 0.29, 0.25)
TIP_TAPER = 0.74          # tip half-width / root half-width

# name, knuckle x, knuckle y, length ratio, root half-width, spread deg, curl deg (mcp, pip, dip)
FINGERS = [
    ("index",  -0.0250, 0.0895, 0.93, 0.0080,  5.5, (5.0, 9.0, 6.0)),
    ("middle", -0.0082, 0.0950, 1.00, 0.0083,  1.2, (6.0, 10.0, 7.0)),
    ("ring",    0.0085, 0.0910, 0.95, 0.0078, -3.2, (7.0, 12.0, 8.0)),
    ("pinky",   0.0236, 0.0815, 0.77, 0.0067, -8.5, (8.0, 14.0, 9.0)),
]
THUMB_BASE = Vector((-0.0190, 0.0200, -0.0075))
THUMB_FWD = Vector((-0.50, 0.84, -0.20))
THUMB_BACK = Vector((-0.50, -0.30, 0.80))
THUMB_SEG = (0.042, 0.033, 0.029)
THUMB_ROOT_W = 0.0104
THUMB_CURL = (0.0, 9.0, 7.0)

SKIN_BACK = (0.80, 0.56, 0.46)
SKIN_PALM = (0.80, 0.49, 0.42)
SKIN_PAD = (0.80, 0.36, 0.32)
NAIL_COL = (0.72, 0.20, 0.26)


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def bump(s, c, sigma):
    return math.exp(-((s - c) / sigma) ** 2)


class Chain:
    """Bending centre line. s is arc length from the first joint; x is sideways, z is toward the back."""

    DS = 0.00025

    def __init__(self, base, rot, joints, s_min, s_max, blend=0.005):
        self.base, self.rot, self.s_min = base, rot, s_min
        self.samples = []
        pos = Vector((0.0, s_min, 0.0))
        n = int((s_max - s_min) / self.DS) + 2
        for i in range(n):
            s = s_min + i * self.DS
            th = sum(a * smooth01((s - (j - blend)) / (2 * blend)) for j, a in joints)
            tan = Vector((0.0, math.cos(th), -math.sin(th)))
            nor = Vector((0.0, math.sin(th), math.cos(th)))
            self.samples.append((pos.copy(), nor))
            pos += tan * self.DS

    def point(self, s, x=0.0, z=0.0):
        i = int(round((s - self.s_min) / self.DS))
        i = max(0, min(len(self.samples) - 1, i))
        pos, nor = self.samples[i]
        return self.base + self.rot @ (pos + Vector((x, 0.0, 0.0)) + nor * z)


class Digit:
    def __init__(self, name, base, rot, segs, root_w, curl, flat, root_in):
        self.name, self.segs, self.root_w, self.flat = name, segs, root_w, flat
        self.length = sum(segs)
        self.j1, self.j2 = segs[0], segs[0] + segs[1]
        joints = [(0.0, math.radians(curl[0])), (self.j1, math.radians(curl[1])),
                  (self.j2, math.radians(curl[2]))]
        self.root_in = root_in
        self.chain = Chain(base, rot, joints, -root_in - 0.002, self.length + 0.012)
        self.nail_from = self.length - 0.56 * segs[2]

    def width(self, s):
        """Half-width without the round tip."""
        t = max(0.0, min(1.0, s / self.length))
        w = self.root_w * (1.0 + (TIP_TAPER - 1.0) * t ** 1.15)
        w *= 1.0 + 0.08 * bump(s, 0.0, 0.007) + 0.13 * bump(s, self.j1, 0.0055) \
            + 0.085 * bump(s, self.j2, 0.0045)
        w *= 1.0 - 0.05 * bump(s, self.j1 * 0.55, 0.010) \
            - 0.05 * bump(s, (self.j1 + self.j2) * 0.5, 0.007)
        return w

    def section(self, s):
        """(half-width, back height, palm height) of the skin at s."""
        w = self.width(s)
        back = w * self.flat * (1.0 + 0.10 * bump(s, self.j1, 0.005) + 0.05 * bump(s, self.j2, 0.004))
        palm = w * (self.flat + 0.06)
        palm *= 1.0 + 0.07 * bump(s, self.j1 * 0.5, 0.010) \
            + 0.06 * bump(s, (self.j1 + self.j2) * 0.5, 0.007) \
            + 0.10 * bump(s, self.length - self.segs[2] * 0.45, 0.007)
        # nail bed: the back of the last joint sits a little lower and flatter
        back *= 1.0 - 0.10 * smooth01((s - self.nail_from + 0.002) / 0.004)
        if self.name == "thumb" and s < 0.0:
            # the thumb starts inside the wrist as a round end, not a cut cylinder
            f = math.sqrt(max(0.02, 1.0 - (s / self.root_in) ** 2))
            w, back, palm = w * f, back * f, palm * f
        tip_r = w * 1.15
        if s > self.length - tip_r:
            k = (s - (self.length - tip_r)) / tip_r
            f = math.sqrt(max(0.0, 1.0 - k * k))
            w, back, palm = w * f, back * f, palm * f
        return w, back, palm

    def stations(self):
        out, s = [], -self.root_in
        while s < self.length - 0.0002:
            out.append(s)
            tip_zone = s > self.length - self.width(s) * 1.3
            s += 0.0008 if tip_zone else 0.0025
        out.append(self.length - 0.00015)
        return out


def loft(bm, rings):
    rows = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rows[0])
    for a, b in zip(rows, rows[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    for row, flip in ((rows[0], True), (rows[-1], False)):
        c = bm.verts.new(sum((v.co for v in row), Vector()) / n)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((c, row[j], row[i]) if flip else (c, row[i], row[j]))


def ellipsoid(bm, centre, radii, rot=None):
    m = Matrix.Translation(centre) @ (rot.to_4x4() if rot else Matrix.Identity(4)) \
        @ Matrix.Diagonal((*radii, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0, matrix=m)


def digit_shell(bm, d, sides=16):
    rings = []
    for s in d.stations():
        w, back, palm = d.section(s)
        ring = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            z = math.sin(a)
            ring.append(d.chain.point(s, w * math.cos(a), (back if z > 0 else palm) * z))
        rings.append(ring)
    loft(bm, rings)


def lerp_table(table, y):
    for (y0, *a), (y1, *b) in zip(table, table[1:]):
        if y <= y1:
            t = smooth01((y - y0) / (y1 - y0))
            return [p + (q - p) * t for p, q in zip(a, b)]
    return list(table[-1][1:])


# y, half-width, centre x, back thickness, palm thickness
PALM = [
    (-0.060, 0.0225, 0.0000, 0.0150, 0.0150),
    (-0.030, 0.0205, 0.0000, 0.0140, 0.0140),
    (-0.004, 0.0195, 0.0000, 0.0125, 0.0125),
    (0.014, 0.0230, -0.0005, 0.0120, 0.0135),
    (0.036, 0.0295, -0.0010, 0.0115, 0.0140),
    (0.060, 0.0325, -0.0015, 0.0105, 0.0128),
    (0.080, 0.0325, -0.0020, 0.0092, 0.0108),
    (0.091, 0.0315, -0.0020, 0.0080, 0.0090),
    (0.097, 0.0280, -0.0020, 0.0055, 0.0062),
]


def knuckle_line(x):
    pts = [(-0.040, 0.082)] + [(f[1], f[2]) for f in FINGERS] + [(0.036, 0.072)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * smooth01((x - x0) / (x1 - x0))
    return pts[-1][1]


def palm_shell(bm, sides=32):
    rings = []
    steps = 44
    for k in range(steps + 1):
        y = PALM[0][0] + (PALM[-1][0] - PALM[0][0]) * k / steps
        half, cx, back, palm = lerp_table(PALM, y)
        ring = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            c, s = math.cos(a), math.sin(a)
            x = cx + half * math.copysign(abs(c) ** 0.85, c)
            z = (back if s > 0 else palm) * math.copysign(abs(s) ** 0.85, s)
            # the far edge follows the arc of the knuckles instead of a straight cut
            yy = y + (knuckle_line(x) - 0.095) * smooth01((y - 0.030) / 0.060)
            ring.append(Vector((x, yy, z + 0.0008)))
        rings.append(ring)
    loft(bm, rings)


def make_digits():
    digits = []
    for name, x, y, ratio, root_w, spread, curl in FINGERS:
        rot = Matrix.Rotation(math.radians(spread), 3, 'Z')
        segs = tuple(MID_LEN * ratio * p for p in PHALANX)
        digits.append(Digit(name, Vector((x, y, 0.0012)), rot, segs, root_w, curl, 0.86, 0.016))
    fwd = THUMB_FWD.normalized()
    back = (THUMB_BACK - fwd * THUMB_BACK.dot(fwd)).normalized()
    rot = Matrix((fwd.cross(back), fwd, back)).transposed()
    digits.append(Digit("thumb", THUMB_BASE, rot, THUMB_SEG, THUMB_ROOT_W, THUMB_CURL, 0.80, 0.014))
    return digits


def build_skin(digits):
    bm = bmesh.new()
    palm_shell(bm)
    for d in digits:
        digit_shell(bm, d)
    thumb = digits[-1]
    # thumb mound, heel of the hand, web between thumb and index, soft knuckle heads
    ellipsoid(bm, thumb.chain.point(0.020, 0.002, -0.004), (0.0125, 0.027, 0.0105), thumb.chain.rot)
    ellipsoid(bm, Vector((0.0140, 0.036, -0.0065)), (0.0120, 0.032, 0.0072))
    ellipsoid(bm, Vector((-0.0270, 0.064, -0.0010)), (0.0100, 0.0200, 0.0048),
              Matrix.Rotation(math.radians(24), 3, 'Z'))
    for d in digits[:4]:
        ellipsoid(bm, d.chain.point(-0.001, 0.0, 0.0018), (d.root_w * 0.95, 0.0085, d.root_w * 0.72),
                  d.chain.rot)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("slender_hand_skin")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("slender_hand_skin", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def apply_modifier(obj, mod):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def fuse_and_reduce(obj):
    m = obj.modifiers.new("fuse", 'REMESH')
    m.mode = 'VOXEL'
    m.voxel_size = VOXEL
    m.adaptivity = 0.0
    apply_modifier(obj, m)
    m = obj.modifiers.new("melt", 'SMOOTH')
    m.factor = 0.5
    m.iterations = SMOOTH_REPEAT
    apply_modifier(obj, m)
    dense = tri_count(obj)
    m = obj.modifiers.new("reduce", 'DECIMATE')
    m.ratio = SKIN_TRIS / dense
    m.use_collapse_triangulate = True
    apply_modifier(obj, m)
    for p in obj.data.polygons:
        p.use_smooth = True
    return dense


def nail_plate(d, cols=6, rows=5):
    """Almond plate over the far 56% of the last joint, on its own material and bone."""
    s0 = d.nail_from
    s1 = d.length + 0.0028
    ref = d.length - 0.30 * d.segs[2]
    w = d.width(ref)
    back = w * d.flat * 0.90
    half = math.radians(58)
    verts, faces = [], []
    for r in range(rows + 1):
        v = r / rows
        shape = 0.62 + 0.38 * smooth01(v / 0.22)
        shape *= 1.0 - 0.56 * smooth01((v - 0.58) / 0.42)
        for c in range(cols + 1):
            u = 2.0 * c / cols - 1.0
            a = u * half * shape
            vv = v + 0.10 * u * u * (1 - v) ** 3 - 0.10 * u * u * v ** 3
            s = s0 + (s1 - s0) * vv
            z = back * math.cos(a) * (1.0 - 0.10 * v * v) + 0.00035
            verts.append(d.chain.point(s, w * 0.97 * math.sin(a), z))
    for r in range(rows):
        for c in range(cols):
            i = r * (cols + 1) + c
            faces.append((i, i + 1, i + cols + 2, i + cols + 1))
    root = d.chain.point(s0, 0.0, back)
    tip = d.chain.point(s1, 0.0, back * 0.90)
    return verts, faces, root, tip


def build_nails(digits):
    verts, faces, groups, bones = [], [], {}, {}
    for d in digits:
        v, f, root, tip = nail_plate(d)
        off = len(verts)
        verts += v
        faces += [tuple(i + off for i in q) for q in f]
        groups[d.name + "_nail"] = list(range(off, off + len(v)))
        bones[d.name] = (root, tip)
    mesh = bpy.data.meshes.new("slender_hand_nails")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new("slender_hand_nails", mesh)
    bpy.context.collection.objects.link(obj)
    for name, idx in groups.items():
        obj.vertex_groups.new(name=name).add(idx, 1.0, 'REPLACE')
    for p in mesh.polygons:
        p.use_smooth = True
    return obj, bones


def build_rig(digits, nail_bones):
    arm = bpy.data.armatures.new("slender_hand_rig")
    rig = bpy.data.objects.new("slender_hand_rig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')

    def bone(name, head, tail, parent, up, connect=False):
        b = arm.edit_bones.new(name)
        b.head, b.tail, b.parent, b.use_connect = head, tail, parent, connect
        b.align_roll(up)
        return b

    up = Vector((0, 0, 1))
    forearm = bone("forearm", Vector((0, -0.060, 0)), Vector((0, -0.002, 0)), None, up)
    hand = bone("hand", Vector((0, -0.002, 0)), Vector((0, 0.050, 0)), forearm, up, True)
    for d in digits:
        c, dorsal = d.chain, d.chain.rot.col[2]
        cuts = (0.0, d.j1, d.j2, d.length)
        parent = hand
        for k in range(3):
            parent = bone("%s_%d" % (d.name, k + 1), c.point(cuts[k]), c.point(cuts[k + 1]),
                          parent, dorsal, k > 0)
        root, tip = nail_bones[d.name]
        bone(d.name + "_nail", root, tip, parent, dorsal).use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def fallback_weights(skin, rig):
    """Only used when automatic weights fail: inverse distance to the bone segments."""
    segs = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones if b.use_deform]
    for name, _, _ in segs:
        if name not in skin.vertex_groups:
            skin.vertex_groups.new(name=name)
    for v in skin.data.vertices:
        ws = []
        for name, a, b in segs:
            ab = b - a
            t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
            ws.append((1.0 / ((v.co - (a + ab * t)).length ** 4 + 1e-12), name))
        ws.sort(reverse=True)
        total = sum(w for w, _ in ws[:3])
        for w, name in ws[:3]:
            skin.vertex_groups[name].add([v.index], w / total, 'REPLACE')
    mod = skin.modifiers.new("rig", 'ARMATURE')
    mod.object = rig
    skin.parent = rig


def bind(skin, rig):
    bpy.ops.object.select_all(action='DESELECT')
    skin.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    weighted = sum(1 for v in skin.data.vertices if v.groups)
    if weighted < len(skin.data.vertices) * 0.98:
        print("HAND: automatic weights failed (%d of %d), using distance weights"
              % (weighted, len(skin.data.vertices)))
        skin.vertex_groups.clear()
        skin.modifiers.clear()
        fallback_weights(skin, rig)
    return weighted


def paint(skin, digits):
    """Vertex colour: pale back, warmer palm, warmer still on the fingertip pads and knuckles."""
    col = skin.data.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    pads = [d.chain.point(d.length - d.segs[2] * 0.4, 0.0, -d.width(d.length) * 0.8) for d in digits]
    knuckles = [d.chain.point(s, 0.0, d.width(s) * 0.8) for d in digits for s in (0.0, d.j1)]
    thumb_back = digits[-1].chain.rot.col[2]
    for v in skin.data.vertices:
        p = v.co
        near_thumb = smooth01(1.0 - (p - digits[-1].chain.point(0.06)).length / 0.03)
        facing = v.normal.z * (1 - near_thumb) + v.normal.dot(thumb_back) * near_thumb
        k = smooth01(0.5 - facing * 1.6)
        c = Vector(SKIN_BACK).lerp(Vector(SKIN_PALM), k)
        pad = max(smooth01(1.0 - (p - q).length / 0.011) for q in pads) * k
        kn = max(smooth01(1.0 - (p - q).length / 0.008) for q in knuckles) * (1 - k) * 0.35
        c = c.lerp(Vector(SKIN_PAD), max(pad, kn))
        col.data[v.index].color = (c.x, c.y, c.z, 1.0)


def material(name, colour, rough, vertex_colour=False, two_sided=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not two_sided
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if vertex_colour:
        node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        node.layer_name = "Col"
        mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    digits = make_digits()
    skin = build_skin(digits)
    dense = fuse_and_reduce(skin)
    paint(skin, digits)
    skin.data.materials.append(material("hand_skin", SKIN_BACK, 0.55, vertex_colour=True))
    nails, nail_bones = build_nails(digits)
    nails.data.materials.append(material("hand_nail", NAIL_COL, 0.12, two_sided=True))
    rig = build_rig(digits, nail_bones)
    weighted = bind(skin, rig)
    skin_tris, nail_tris = tri_count(skin), tri_count(nails)

    for b in rig.data.bones:
        b.use_deform = True
    bpy.ops.object.select_all(action='DESELECT')
    nails.select_set(True)
    skin.select_set(True)
    bpy.context.view_layer.objects.active = skin
    bpy.ops.object.join()
    skin.name = skin.data.name = "slender_hand"
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)

    bpy.ops.object.select_all(action='SELECT')
    args = dict(filepath=os.path.join(OUT_DIR, OUT_NAME), export_format='GLB', use_selection=True,
                export_yup=True, export_skins=True, export_animations=False, export_apply=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='MATERIAL', **args)
    except TypeError:
        bpy.ops.export_scene.gltf(**args)
    print("HAND: voxel tris %d -> skin %d + nails %d = %d, verts %d, auto-weighted %d, bones %d"
          % (dense, skin_tris, nail_tris, skin_tris + nail_tris, len(skin.data.vertices), weighted,
             len(rig.data.bones)))


main()
