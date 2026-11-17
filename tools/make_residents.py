"""Bake relaxed street poses from Microsoft Rocketbox FBX models.

Requires bpy, Pillow and NumPy. Pass a folder with the eight original FBXs
and their *_color.tga textures. The resulting assets are included in the game.
"""

import argparse
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

from gltf_mesh import write_mesh

OUTPUT = Path("game/art/residents")
MODELS = [
    "Male_Adult_01",
    "Female_Adult_03",
    "Male_Adult_04",
    "Female_Adult_02",
    "Male_Adult_03",
    "Female_Adult_01",
    "Male_Adult_05",
    "Female_Adult_04",
]
CREDIT = {
    "author": "Microsoft",
    "license": "MIT",
    "source": "https://github.com/microsoft/Microsoft-Rocketbox",
}


def bake(source, name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source / (name + ".fbx")), use_anim=False)
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    body = next(
        o for o in bpy.context.scene.objects if o.type == "MESH" and "hipoly" in o.name
    )
    for side, sign in [("L", 1), ("R", -1)]:
        arm = next(b for b in rig.pose.bones if b.name.endswith(side + " UpperArm"))
        shoulder = rig.matrix_world @ arm.head
        rotate = Matrix.Rotation(math.radians(38) * sign, 4, "Y")
        world = Matrix.Translation(shoulder) @ rotate @ Matrix.Translation(-shoulder)
        arm.matrix = rig.matrix_world.inverted() @ world @ rig.matrix_world @ arm.matrix
    bpy.context.view_layer.update()
    simplify = body.modifiers.new("Street resolution", "DECIMATE")
    simplify.ratio = min(1.0, 2600 / (len(body.data.polygons) * 1.15))
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    world = evaluated.matrix_world
    normal_matrix = world.to_3x3().inverted().transposed()

    atlas = Image.new("RGBA", (1024, 1024), (90, 90, 90, 255))
    tiles = {"body": (0, 0), "head": (512, 0), "opacity": (0, 512)}
    slots = []
    for material in mesh.materials:
        material_name = material.name.lower().split(".")[0]
        kind = next(k for k in tiles if k in material_name)
        texture = source / (material_name + "_color.tga")
        tile = (
            Image.open(texture)
            .convert("RGBA")
            .resize((512, 512), Image.Resampling.LANCZOS)
        )
        atlas.paste(tile, tiles[kind])
        slots.append(tiles[kind])
    atlas.save(OUTPUT / (name + ".png"), optimize=True)

    points, normals, texcoords, weights, faces = [], [], [], [], []
    vertices = {}
    for tri in mesh.loop_triangles:
        face = []
        for loop in tri.loops:
            corner = mesh.loops[loop]
            v = mesh.vertices[corner.vertex_index]
            uv = mesh.uv_layers.active.data[loop].uv
            tile = slots[tri.material_index]
            key = (
                v.index,
                tri.material_index,
                tuple(uv),
                tuple(mesh.corner_normals[loop].vector),
            )
            if key not in vertices:
                vertices[key] = len(points)
                p = world @ v.co
                n = (normal_matrix @ mesh.corner_normals[loop].vector).normalized()
                points.append((p.x, p.z, -p.y))
                normals.append((n.x, n.z, -n.y))
                texcoords.append(
                    (
                        (tile[0] + 1 + 510 * uv.x) / 1024,
                        (tile[1] + 1 + 510 * (1 - uv.y)) / 1024,
                    )
                )
                arm_weight, leg_weight = 0.0, 0.0
                for group in v.groups:
                    bone = body.vertex_groups[group.group].name
                    sign = 1 if " L " in bone else -1 if " R " in bone else 0
                    if any(
                        part in bone
                        for part in ("UpperArm", "Forearm", "Hand", "Finger")
                    ):
                        arm_weight += sign * group.weight
                    if any(part in bone for part in ("Thigh", "Calf", "Foot", "Toe")):
                        leg_weight += sign * group.weight
                weights.append((0.5 + 0.5 * arm_weight, 0.5 + 0.5 * leg_weight))
            face.append(vertices[key])
        faces.append(face)
    points = np.array(points)
    points[:, 1] -= points[:, 1].min()
    streams = {
        key: [data]
        for key, data in zip(
            ("POSITION", "NORMAL", "TEXCOORD_0", "TEXCOORD_1"),
            (points, normals, texcoords, weights),
        )
    }
    write_mesh(OUTPUT / (name + ".glb"), streams, [np.array(faces)], CREDIT)
    evaluated.to_mesh_clear()
    print(name, len(faces), "triangles", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    source = parser.parse_args().source
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for model in MODELS:
        bake(source, model)
