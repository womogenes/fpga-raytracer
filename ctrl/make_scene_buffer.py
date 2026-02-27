# We love python <3

from pathlib import Path

from argparse import ArgumentParser
import json
import numpy as np

proj_path = Path(__file__).parent.parent
import sys
sys.path.append(str(proj_path / "sim"))

from utils import make_fp, make_fp_vec3, pack_bits, FP_BITS, FP_VEC3_BITS

parser = ArgumentParser()
parser.add_argument("scene", nargs="?", type=str)
parser.add_argument("--out-dir", type=Path, default=None)

class Material:
    def __init__(
        self,
        color: tuple[float],
        emit_color: tuple[float] = (0, 0, 0),
        spec_color: tuple[float] = None,
        smoothness: float = 0,
        specular_prob: float = 0,
        **kwargs,
    ):
        self.color = color
        self.spec_color = spec_color or color
        self.emit_color = emit_color
        self.smoothness = smoothness
        self.one_sub_smoothness = 1.0 - smoothness
        self.specular_prob = int(specular_prob * 255)   # 8

    def pack_bits(self):
        # Pack properties into bit fields
        fields = [
            (make_fp_vec3(self.color), FP_VEC3_BITS),
            (make_fp_vec3(self.emit_color), FP_VEC3_BITS),
            (make_fp_vec3(self.spec_color), FP_VEC3_BITS),
            (make_fp(self.smoothness), FP_BITS),
            (make_fp(self.one_sub_smoothness), FP_BITS),
            (self.specular_prob, 8),
        ]
        return pack_bits(fields, msb=True), sum([width for _, width in fields])
    

class Object:
    def __init__(
        self,
        mat_idx: int,
        sphere_center: tuple[float] = (),
        sphere_rad: float = 1,
        obj_type: int = 0,
        trig: tuple[tuple[float]] = None,
        trig_norm: tuple[float] | None = None,
        **kwargs,
    ):
        self.obj_type = obj_type
        self.mat_idx = mat_idx
        self.trig = trig or ((0, 0, 0),) * 3

        # Geometry:
        # - Spheres use `sphere_center`/`sphere_rad`.
        # - Trig/parallelogram/plane objects use `trig` in the hardware format:
        #     [v0, v0v1, v0v2]
        #   i.e. origin point plus two edge vectors (NOT three absolute vertices).
        if self.obj_type == 0:
            self.trig_norm = (0.0, 0.0, 0.0)
        elif trig_norm is not None:
            # Some hand-authored scenes already include normals; trust them (but ensure
            # we store a finite unit-ish vector).
            n = np.asarray(trig_norm, dtype=float)
            n_norm = float(np.linalg.norm(n))
            if (not np.isfinite(n_norm)) or n_norm < 1e-12:
                self.trig_norm = (0.0, 0.0, 0.0)
            else:
                n /= n_norm
                self.trig_norm = (float(n[0]), float(n[1]), float(n[2]))
        elif trig is not None:
            tri = np.asarray(trig, dtype=float)
            v0v1 = tri[1]
            v0v2 = tri[2]
            n = np.cross(v0v1, v0v2).astype(float)
            n_norm = float(np.linalg.norm(n))

            # If the triangle is degenerate (or contains NaNs), keep a zero normal so
            # packing doesn't crash; the hardware will effectively treat it as invalid.
            if (not np.isfinite(n_norm)) or n_norm < 1e-12:
                self.trig_norm = (0.0, 0.0, 0.0)
            else:
                n /= n_norm
                self.trig_norm = (float(n[0]), float(n[1]), float(n[2]))
        else:
            self.trig_norm = (0.0, 0.0, 0.0)

        self.sphere_center = sphere_center or (0, 0, 0)
        self.sphere_rad_sq = sphere_rad ** 2 or 0
        self.sphere_rad_inv = 1 / sphere_rad or 0

    def pack_bits(self):
        fields = [
            (self.obj_type, 2),
            (self.mat_idx, 8),
            *[(make_fp_vec3(v), 72) for v in self.trig],
            (make_fp_vec3(self.trig_norm), 72)
            ] if self.obj_type else [
                (self.obj_type, 2),
                (self.mat_idx, 8),
                (make_fp_vec3(self.sphere_center), 72),
                (make_fp(self.sphere_rad_sq), 24),
                (make_fp(self.sphere_rad_inv), 24),
                (0, 168)
            ]
        return pack_bits(fields, msb=True), sum([width for _, width in fields])


def build_material_dict(scene):
    """
    Build material dictionary from scene + deduplicates materials
    """
    mat_idx = 0
    mat_bits2idx = {}
    mat_name2idx = {}
    mat_width = None

    for mat_name, mat_json in scene["materials"].items():
        mat_bits, mat_width = Material(**mat_json).pack_bits()

        # New material?
        if mat_bits not in mat_bits2idx:
            mat_bits2idx[mat_bits] = mat_idx
            mat_idx += 1

        mat_name2idx[mat_name] = mat_bits2idx[mat_bits]

    return mat_bits2idx, mat_name2idx, mat_width


def export_scene(scene_file: str, out_dir: Path | None = None):
    """
    Export the JSON description of a scene to the .mem file
        For use in testbenching and initializing BRAM
    """
    with open(scene_file) as fin:
        scene = json.load(fin)

    # Construct material dictionary
    mat_bits2idx, mat_name2idx, mat_width = build_material_dict(scene)

    from pprint import pprint
    pprint(mat_bits2idx)
    pprint(mat_name2idx)

    for mat_bits, mat_idx in mat_bits2idx.items():
        print(mat_idx, hex(mat_bits))

    objs = scene["objects"]
    obj_objs = []
    for idx, obj in enumerate(objs):
        obj["mat_idx"] = mat_name2idx[obj["material"]]
        obj_objs.append(Object(**obj))
    objs = obj_objs

    out_dir = out_dir or (proj_path / "data")
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(str(out_dir / "scene_buffer.mem"), "w") as fout:
        for obj in objs:
            bits, obj_width = obj.pack_bits()
            n_hex_digits = (obj_width + 3) // 4
            fout.write(hex(bits)[2:].zfill(n_hex_digits) + "\n")

    with open(str(out_dir / "mat_dict.mem"), "w") as fout:
        # Sort materials by index
        mats = sorted(mat_bits2idx.items(), key=lambda x: x[1])
        for mat_bits, _ in mats:
            n_hex_digits = (mat_width + 3) // 4
            fout.write(hex(mat_bits)[2:].zfill(n_hex_digits) + "\n")

    print(f"Object width: {obj_width}")
    print(f"Scene buffer depth: {len(objs)}")

    print(f"Material width: {mat_width}")
    print(f"Material dictionary depth: {len(mat_bits2idx)}")


if __name__ == "__main__":
    args = parser.parse_args()
    export_scene(args.scene, out_dir=args.out_dir)
