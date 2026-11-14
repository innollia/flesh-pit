"""Blender check of vent_hand.glb: import it, report the rig, render four views.

    blender --background --factory-startup --python tools/vent_hand_model/render_blender.py -- [glb] [out_dir]

Blender here is C:/tools/blender/blender-4.5.3-windows-x64/blender.exe.
Writes blender_back.png, blender_palm.png, blender_side.png, blender_grip.png
and blender_sheet.jpg into out_dir (default: the glb's renders/ folder). The
hand itself is made by build_hand.py; this only reads the glb back through
Blender's own importer, so a broken skin or normal shows here.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB = os.path.abspath(ARGV[0]) if ARGV else os.path.join(
    ROOT, "game", "main", "art", "vent_hand_models", "blender_made", "vent_hand.glb")
OUT = os.path.abspath(ARGV[1]) if len(ARGV) > 1 else os.path.join(os.path.dirname(GLB), "renders")
FINGERS = ["index", "middle", "ring", "little"]


def skin_material(name, gloss):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    # the glb's colours are the numbers the game's own skin shader shows as
    # they are; Blender reads them as linear light, so bring them back down
    attr = nt.nodes.new("ShaderNodeVertexColor")
    gamma = nt.nodes.new("ShaderNodeGamma")
    gamma.inputs["Gamma"].default_value = 2.2
    nt.links.new(attr.outputs["Color"], gamma.inputs["Color"])
    nt.links.new(gamma.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.2 if gloss else 0.55
    if not gloss:
        bsdf.inputs["Subsurface Weight"].default_value = 0.25
        bsdf.inputs["Subsurface Radius"].default_value = (0.012, 0.005, 0.003)
        bsdf.inputs["Subsurface Scale"].default_value = 0.4
    return mat


def pose(arm, curl, thumb):
    """curl = (knuckle, middle joint, last joint) degrees toward the palm."""
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    for i, f in enumerate(FINGERS):
        k = [0.9, 1.0, 1.06, 1.15][i]
        for j in range(3):
            arm.pose.bones["%s_%d" % (f, j + 1)].matrix_basis = Matrix.Rotation(math.radians(-curl[j] * k), 4, "X")
    for j in range(3):
        m = Matrix.Rotation(math.radians(-thumb[j]), 4, "X")
        if j == 0:
            m = Matrix.Rotation(math.radians(thumb[3]), 4, "Y") @ m
        arm.pose.bones["thumb_%d" % (j + 1)].matrix_basis = m
    bpy.context.view_layer.update()


def shot(cam, name, eye, target, scale):
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = scale
    bpy.context.scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("vent_hand")]:
        bpy.data.objects.remove(o)  # the importer's bone-shape helper
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    print("RIG bones", len(arm.data.bones), [b.name for b in arm.data.bones])
    for o in meshes:
        bad = 0
        for v in o.data.vertices:
            s = sum(g.weight for g in v.groups)
            if abs(s - 1.0) > 1e-3:
                bad += 1
        print("MESH", o.name, "verts", len(o.data.vertices), "tris", sum(len(p.vertices) - 2 for p in o.data.polygons),
              "groups", len(o.vertex_groups), "weights not summing to 1:", bad,
              "colour layers", [c.name for c in o.data.color_attributes])
        o.data.materials.clear()
        o.data.materials.append(skin_material(o.name + "_check", "nail" in o.name))
        for p in o.data.polygons:
            p.use_smooth = True
    # fingers up in the picture: turn the whole hand over about the view axis
    turn = bpy.data.objects.new("turn", None)
    bpy.context.scene.collection.objects.link(turn)
    for o in bpy.data.objects:
        if o.parent is None and o is not turn:
            o.parent = turn
    turn.rotation_euler = (0.0, math.pi, 0.0)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 820
    scene.render.resolution_y = 1000
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.80, 0.82, 0.84, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.42
    scene.world = world
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.clip_end = 10.0
    scene.collection.objects.link(cam)
    scene.camera = cam
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 5.0
    key.data.size = 0.5
    scene.collection.objects.link(key)

    def light(eye):
        key.location = eye
        key.rotation_euler = (Vector((0, 0, 0.04)) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()

    centre = (0.0, 0.0, 0.04)
    pose(arm, (5, 9, 6), (2, 5, 8, 0))
    light((0.35, 0.6, 0.55))
    shot(cam, "blender_back.png", (0, 1.0, 0.04), centre, 0.30)
    light((-0.35, -0.6, 0.55))
    shot(cam, "blender_palm.png", (0, -1.0, 0.04), centre, 0.30)
    light((-0.6, -0.4, 0.5))
    shot(cam, "blender_side.png", (-1.0, 0, 0.04), centre, 0.30)
    pose(arm, (68, 82, 48), (18, 28, 38, -38))
    light((-0.2, -0.6, 0.6))
    shot(cam, "blender_grip.png", (-0.6, -0.8, 0.25), (0.0, 0.0, 0.02), 0.26)

    names = ["blender_back.png", "blender_palm.png", "blender_side.png", "blender_grip.png"]
    sheet = bpy.data.images.new("sheet", 820 * 4, 1000)
    px = [0.0] * (820 * 4 * 1000 * 4)
    for k, name in enumerate(names):
        img = bpy.data.images.load(os.path.join(OUT, name))
        src = list(img.pixels)
        for y in range(1000):
            a = (y * 820 * 4 + k * 820) * 4
            px[a:a + 820 * 4] = src[y * 820 * 4:(y + 1) * 820 * 4]
    sheet.pixels = px
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 90
    sheet.save_render(os.path.join(OUT, "blender_sheet.jpg"), scene=scene)
    print("DONE", OUT)


main()
