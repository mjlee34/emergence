"""Write a metre-scale, single-primitive GLB with indexed geometry."""

import json
import struct

import numpy as np


def write_mesh(path, streams, indices, credit):
    name = path.stem
    raw = bytearray()
    views, accessors = [], []

    def append(array, dtype, kind, target):
        data = np.ascontiguousarray(array, dtype=dtype)
        views.append(
            dict(buffer=0, byteOffset=len(raw), byteLength=data.nbytes, target=target)
        )
        a = dict(
            bufferView=len(views) - 1,
            componentType=5123 if kind == "SCALAR" else 5126,
            count=len(data),
            type=kind,
        )
        if not accessors:
            a.update(min=data.min(axis=0).tolist(), max=data.max(axis=0).tolist())
        accessors.append(a)
        raw.extend(data.tobytes())
        raw.extend(bytes(-len(raw) % 4))

    attrs = {}
    for key, items in streams.items():
        attrs[key] = len(accessors)
        append(
            np.concatenate(items),
            "<f4",
            "VEC3" if key in ("POSITION", "NORMAL") else "VEC2",
            34962,
        )
    index = len(accessors)
    append(np.concatenate(indices).reshape(-1), "<u2", "SCALAR", 34963)
    doc = dict(
        asset=dict(version="2.0", extras=credit),
        scene=0,
        scenes=[dict(nodes=[0])],
        nodes=[dict(name=name, mesh=0)],
        meshes=[dict(primitives=[dict(attributes=attrs, indices=index)])],
        buffers=[dict(byteLength=len(raw))],
        bufferViews=views,
        accessors=accessors,
    )
    header = json.dumps(doc, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    path.write_bytes(
        struct.pack("<4sII", b"glTF", 2, 28 + len(header) + len(raw))
        + struct.pack("<I4s", len(header), b"JSON")
        + header
        + struct.pack("<I4s", len(raw), b"BIN\0")
        + raw
    )
