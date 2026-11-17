"""Prepare Comrade1280's CC BY 4.0 Generic Passenger Car Pack for EMERGENCE.

Run from the repo root with NumPy and Pillow:
    python tools/make_cars.py /path/to/20f9af9b8a404d5cb022ac6fe87f21f5.glb

The source and derivative notices are in game/art/vehicles/CREDITS.txt.
The runtime uses the committed GLBs and textures directly.
"""

import argparse
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

from gltf_mesh import write_mesh

OUTPUT = Path("game/art/vehicles")
# Body, glazing, optics and wheel material slots in the credited glTF.
FLEET = {
    "sedan": (25, 26, 27, 28),
    "hatchback": (9, 10, 11, 12),
    "estate": (37, 38, 39, 40),
    "compact": (2, 3, 4, 1),
    "minivan": (14, 15, 16, 13),
}
UP = np.array([0.0, 1.0, 0.0])


class Source:
    def __init__(self, path):
        data = path.read_bytes()
        size = struct.unpack_from("<I", data, 12)[0]
        self.doc = json.loads(data[20 : 20 + size])
        self.buffer = data[28 + size :]
        self.parts = []
        for node in self.doc["scenes"][self.doc["scene"]]["nodes"]:
            self.visit(node, np.eye(4))

    def array(self, index):
        a = self.doc["accessors"][index]
        v = self.doc["bufferViews"][a["bufferView"]]
        dtype = np.dtype({5126: "<f4", 5123: "<u2", 5125: "<u4"}[a["componentType"]])
        columns = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        return np.ndarray(
            (a["count"], columns),
            dtype,
            self.buffer,
            offset=v.get("byteOffset", 0) + a.get("byteOffset", 0),
            strides=(v.get("byteStride", columns * dtype.itemsize), dtype.itemsize),
        )

    def visit(self, index, parent):
        node = self.doc["nodes"][index]
        matrix = parent @ np.array(node.get("matrix", np.eye(4))).reshape(4, 4).T
        if "mesh" in node:
            for p in self.doc["meshes"][node["mesh"]]["primitives"]:
                a = p["attributes"]
                pos = self.array(a["POSITION"]) @ matrix[:3, :3].T + matrix[:3, 3]
                normal = self.array(a["NORMAL"]) @ np.linalg.inv(matrix[:3, :3])
                normal /= np.maximum(
                    1e-9, np.linalg.norm(normal, axis=1, keepdims=True)
                )
                uv = (
                    self.array(a["TEXCOORD_0"])
                    if "TEXCOORD_0" in a
                    else np.zeros((len(pos), 2))
                )
                faces = self.array(p["indices"]).reshape(-1, 3)
                if np.linalg.det(matrix[:3, :3]) < 0:
                    faces = faces[:, ::-1]
                self.parts.append((p["material"], pos, normal, uv, faces))
        for child in node.get("children", []):
            self.visit(child, matrix)

    def texture(self, material):
        pbr = self.doc["materials"][material]["pbrMetallicRoughness"]
        tex = self.doc["textures"][pbr["baseColorTexture"]["index"]]
        view = self.doc["bufferViews"][self.doc["images"][tex["source"]]["bufferView"]]
        start = view.get("byteOffset", 0)
        return Image.open(
            io.BytesIO(self.buffer[start : start + view["byteLength"]])
        ).convert("RGB")


def prepare(source, name, materials):
    parts = [p for p in source.parts if p[0] in materials]
    wheels = [p[1] for p in parts if p[0] == materials[3]]
    centers = np.array([(w.min(axis=0) + w.max(axis=0)) * 0.5 for w in wheels])
    _, _, axes = np.linalg.svd(centers - centers.mean(axis=0), full_matrices=False)
    forward = axes[0]
    # Red lamp texels identify the rear even for cars displayed at an angle.
    lens = source.texture(materials[2])
    _, positions, _, uv, _ = next(p for p in parts if p[0] == materials[2])
    pixels = np.asarray(lens)[
        (uv[:, 1] % 1 * lens.height).astype(int),
        (uv[:, 0] % 1 * lens.width).astype(int),
    ].astype(float)
    red = (pixels[:, 0] > pixels[:, 2] * 1.7) & (pixels[:, 0] > pixels[:, 1] * 1.45)
    if (positions[red].mean(axis=0) - centers.mean(axis=0)) @ forward > 0:
        forward = -forward
    axes = np.array([forward, UP, np.cross(forward, UP)])
    points = np.concatenate([p[1] for p in parts]) @ axes.T
    origin = (points.max(axis=0) + points.min(axis=0)) * 0.5
    origin[1] = points[:, 1].min()

    # Keep authored panel lines, vents, tyres and optical textures. The alpha
    # mask selects painted metal so individual residents can own distinct colours.
    atlas = Image.new("RGBA", (1024, 1024), (32, 32, 32, 64))
    tiles = {
        materials[0]: (0, 0, 768),
        materials[2]: (768, 0, 256),
        materials[3]: (768, 256, 256),
    }
    for mat, (x, y, size) in tiles.items():
        tile = (
            source.texture(mat)
            .resize((size, size), Image.Resampling.LANCZOS)
            .convert("RGBA")
        )
        rgba = np.array(tile)
        rgb = rgba[:, :, :3].astype(float)
        peak = rgb.max(axis=2)
        mask = np.zeros_like(peak)
        if mat == materials[0]:
            mask = np.clip((peak - rgb.min(axis=2) - 4) / (peak * 0.29 + 2), 0.0, 1.0)
            reference = np.percentile(peak[mask > 0.8], 94)
            neutral = np.minimum(
                254.0, 238 * np.power(peak / max(1.0, reference), 0.66)
            )
            rgba[:, :, :3] = (
                rgb * (1 - mask[:, :, None]) + neutral[:, :, None] * mask[:, :, None]
            )
        rgba[:, :, 3] = 64 + 191 * mask
        atlas.paste(Image.fromarray(rgba), (x, y))
    atlas.save(OUTPUT / (name + ".png"), optimize=True)

    streams = {key: [] for key in ["POSITION", "NORMAL", "TEXCOORD_0", "TEXCOORD_1"]}
    indices, count = [], 0
    for mat, pos, normals, uv, faces in parts:
        local = pos @ axes.T - origin
        tag = [0.0, materials.index(mat) * 0.1]
        tile_x, tile_y, size = tiles.get(mat, (0, 0, 1))
        if mat == materials[3]:
            axle = (local.max(axis=0) + local.min(axis=0)) * 0.5
            tag = [axle[0] / 6 + 0.5, 1.0 + axle[1]]
        atlas_uv = (
            np.clip(uv, 0, 1) * (size - 2) + np.array([tile_x + 1, tile_y + 1])
        ) / 1024
        for key, values in zip(
            streams, (local, normals @ axes.T, atlas_uv, np.tile(tag, (len(pos), 1)))
        ):
            streams[key].append(values)
        indices.append(faces.astype(int) + count)
        count += len(pos)
    write_mesh(
        OUTPUT / (name + ".glb"), streams, indices, source.doc["asset"]["extras"]
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    source = Source(parser.parse_args().source)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, materials in FLEET.items():
        prepare(source, name, materials)
