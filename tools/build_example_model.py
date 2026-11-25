"""Generate a small original GLB, in prototype metres, for the public Mod example."""
import json
import math
import struct
from pathlib import Path

positions, normals, indices = [], [], []


def face(vertices, normal):
    start = len(positions)
    positions.extend(vertices)
    normals.extend([normal] * len(vertices))
    indices.extend([start, start + 1, start + 2, start, start + 2, start + 3])


def box(x, y, z, sx, sy, sz):
    a, b = x - sx / 2, x + sx / 2
    c, d = y - sy / 2, y + sy / 2
    e, f = z - sz / 2, z + sz / 2
    face([(a, c, f), (b, c, f), (b, d, f), (a, d, f)], (0, 0, 1))
    face([(b, c, e), (a, c, e), (a, d, e), (b, d, e)], (0, 0, -1))
    face([(b, c, f), (b, c, e), (b, d, e), (b, d, f)], (1, 0, 0))
    face([(a, c, e), (a, c, f), (a, d, f), (a, d, e)], (-1, 0, 0))
    face([(a, d, f), (b, d, f), (b, d, e), (a, d, e)], (0, 1, 0))
    face([(a, c, e), (b, c, e), (b, c, f), (a, c, f)], (0, -1, 0))


for x in (-2, 2):
    for z in (-2, 2):
        box(x, 3.5, z, 0.55, 7, 0.55)
box(0, 6.8, 0, 5.2, 0.5, 5.2)
box(0, 8.8, 0, 4.6, 3.6, 4.6)
box(0, 10.8, 0, 5.1, 0.4, 5.1)
box(0, 3.8, 2.45, 0.5, 7.6, 0.2)
for i in range(15):
    box(0, 0.5 + i * 0.49, 2.65, 1.2, 0.12, 0.15)

pos = struct.pack('<' + 'f' * (len(positions) * 3), *(v for p in positions for v in p))
nrm = struct.pack('<' + 'f' * (len(normals) * 3), *(v for p in normals for v in p))
idx = struct.pack('<' + 'I' * len(indices), *indices)
binary = pos + nrm + idx
gltf = {
    'asset': {'version': '2.0', 'generator': 'Track Playground original example'},
    'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': 'WaterTower'}],
    'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'indices': 2, 'material': 0}]}],
    'materials': [{'pbrMetallicRoughness': {'baseColorFactor': [0.35, 0.51, 0.49, 1], 'metallicFactor': 0.2, 'roughnessFactor': 0.7}}],
    'buffers': [{'byteLength': len(binary)}],
    'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': len(pos), 'target': 34962},
                    {'buffer': 0, 'byteOffset': len(pos), 'byteLength': len(nrm), 'target': 34962},
                    {'buffer': 0, 'byteOffset': len(pos) + len(nrm), 'byteLength': len(idx), 'target': 34963}],
    'accessors': [
        {'bufferView': 0, 'componentType': 5126, 'count': len(positions), 'type': 'VEC3',
         'min': [min(p[i] for p in positions) for i in range(3)], 'max': [max(p[i] for p in positions) for i in range(3)]},
        {'bufferView': 1, 'componentType': 5126, 'count': len(normals), 'type': 'VEC3'},
        {'bufferView': 2, 'componentType': 5125, 'count': len(indices), 'type': 'SCALAR'}]
}
payload = json.dumps(gltf, separators=(',', ':')).encode()
payload += b' ' * ((-len(payload)) % 4)
binary += b'\0' * ((-len(binary)) % 4)
result = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(payload) + 8 + len(binary))
result += struct.pack('<II', len(payload), 0x4E4F534A) + payload
result += struct.pack('<II', len(binary), 0x004E4942) + binary
target = Path(__file__).resolve().parents[1] / 'mods' / 'alpine_pack' / 'water_tower.glb'
target.write_bytes(result)
print(f'Created {target.name}: {len(result)} bytes')
