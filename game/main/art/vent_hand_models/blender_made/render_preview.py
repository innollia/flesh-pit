# Loads the exported hand back from the .glb and renders a four-view sheet next to it.
#
#   blender --background --python render_preview.py
#
# Views: back of the hand, palm, three-quarter, and three-quarter with the fingers curled by the
# rig (a check of the weights, not a game pose).
import bpy
import math
import os
import numpy as np
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 640
CENTRE = Vector((-0.012, 0.070, 0.0))


def look_from(cam, where, up_axis='Y'):
    cam.location = CENTRE + where
    d = (CENTRE - cam.location).normalized()
    cam.rotation_euler = d.to_track_quat('-Z', up_axis).to_euler()


def curl(rig, amount):
    for b in rig.pose.bones:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = Euler((0, 0, 0))
        if b.name.endswith("_nail") or b.name in ("hand", "forearm"):
            continue
        k = {"1": 0.7, "2": 1.0, "3": 0.6}[b.name[-1]]
        if b.name.startswith("thumb"):
            k *= 0.45
        b.rotation_euler = Euler((-amount * k, 0, 0))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "slender_hand_r.glb"))
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = 'PNG'
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.035, 0.03, 0.035, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 0.25
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, pos, energy, size in (("key", (-0.25, 0.05, 0.45), 5.0, 0.15),
                                    ("fill", (0.35, -0.2, -0.35), 3.0, 0.5),
                                    ("rim", (0.2, 0.5, 0.15), 3.0, 0.2)):
        light = bpy.data.lights.new(name, 'AREA')
        light.energy, light.size = energy, size
        obj = bpy.data.objects.new(name, light)
        obj.location = CENTRE + Vector(pos)
        obj.rotation_euler = (CENTRE - obj.location).to_track_quat('-Z', 'Y').to_euler()
        scene.collection.objects.link(obj)

    views = [("back", (0, 0, 0.6), 'Y', 0.0), ("palm", (0, 0, -0.6), 'Y', 0.0),
             ("three_quarter", (-0.30, 0.42, 0.30), 'Z', 0.0),
             ("curled", (-0.42, 0.20, 0.30), 'Z', math.radians(48))]
    tiles = []
    for name, where, up, amount in views:
        curl(rig, amount)
        look_from(cam, Vector(where), up)
        path = os.path.join(bpy.app.tempdir, "hand_%s.png" % name)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path)
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4))
    sheet = np.concatenate([np.concatenate(tiles[2:], axis=1), np.concatenate(tiles[:2], axis=1)], axis=0)
    out = bpy.data.images.new("sheet", SIZE * 2, SIZE * 2, alpha=False)
    out.pixels = sheet.ravel()
    out.filepath_raw = os.path.join(HERE, "preview.png")
    out.file_format = 'PNG'
    out.save()
    print("PREVIEW: wrote", out.filepath_raw)


main()
