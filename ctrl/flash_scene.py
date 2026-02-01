# We love python <3

from pathlib import Path
import sys

proj_path = Path(__file__).parent.parent

sys.path.append(str(proj_path / "sim"))
from utils import make_fp, make_fp_vec3, pack_bits, FP_VEC3_BITS
from make_scene_buffer import Material, Object, build_material_dict

import wave
import serial
import sys
import json
import numpy as np

from tqdm import tqdm

from struct import unpack
import time

from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument("scene", nargs="?", type=str)

args = parser.parse_args()

# Communication Parameters
SERIAL_PORTNAME = "/dev/ttyUSB2"  # CHANGE ME to match your system's serial port name!
BAUD = 115200  # Make sure this matches your UART receiver


if __name__ == "__main__":
    ser = serial.Serial(SERIAL_PORTNAME, BAUD)

    # ser.write((0b10000000).to_bytes(1))
    # print((FP_VEC3_BITS + 7) // 8)
    # for i in range(100):
    #     ser.write((0).to_bytes(1))
    #     input(i+1)
    # exit()

    def set_cam(
        origin: tuple[float] = None,
        forward: tuple[float] = None,
        right: tuple[float] = None,
        up: tuple[float] = None,
    ):
        for cmd, vec in zip([0x00, 0x01, 0x02, 0x03], [origin, forward, right, up]):
            if vec is None:
                continue

            ser.write((cmd).to_bytes(1, "big"))
            data = make_fp_vec3(vec)
            ser.write(data.to_bytes((FP_VEC3_BITS + 7) // 8, "big"))

    def set_obj(obj_idx: int, obj: Object):
        obj_bits, obj_num_bits = obj.pack_bits()
        ser.write((0x04).to_bytes(1, "big"))
        ser.write(obj_idx.to_bytes(2, "big"))

        obj_num_bytes = ((obj_num_bits + 7) // 8)
        ser.write((0x05).to_bytes(1, "big"))
        ser.write(obj_bits.to_bytes(obj_num_bytes, "big"))

    def set_num_objs(num_objs: int):
        assert num_objs > 0, "Cannot set zero objects"
        ser.write((0x06).to_bytes(1, "big"))
        ser.write(num_objs.to_bytes(2, "big"))

    def set_mat(mat_idx: int, mat_bits: int, mat_width: int):
        ser.write((0x08).to_bytes(1, "big"))
        ser.write(mat_idx.to_bytes(1, "big"))

        mat_num_bytes = ((mat_width + 7) // 8)
        ser.write((0x09).to_bytes(1, "big"))
        ser.write(mat_bits.to_bytes(mat_num_bytes, "big"))

    def set_max_bounces(max_bounces: int):
        ser.write((0x07).to_bytes(1, "big"))
        ser.write(max_bounces.to_bytes(1, "big"))

    with open(args.scene) as fin:
        scene = json.load(fin)

    forward = np.array(scene["camera"]["forward"])
    right = np.array(scene["camera"]["right"])
    up = np.array(scene["camera"]["up"])
    pitch = scene["camera"].get("pitch", 0)
    yaw = scene["camera"].get("yaw", 0)
    
    # Create rotation matrices for pitch and yaw
    # Pitch rotation matrix around right vector
    cos_pitch = np.cos(pitch)
    sin_pitch = np.sin(pitch)
    pitch_mat = np.array([
        [1, 0, 0],
        [0, cos_pitch, -sin_pitch],
        [0, sin_pitch, cos_pitch]
    ])
    
    # Yaw rotation matrix around up vector
    cos_yaw = np.cos(yaw)
    sin_yaw = np.sin(yaw)
    yaw_mat = np.array([
        [cos_yaw, 0, sin_yaw],
        [0, 1, 0],
        [-sin_yaw, 0, cos_yaw]
    ])
    
    # Combined rotation matrix: apply yaw first, then pitch
    rotmat = pitch_mat @ yaw_mat
    
    # Apply rotations to get new vectors
    forward = tuple(rotmat @ forward)
    right = tuple(rotmat @ right)
    up = tuple(rotmat @ up)

    set_cam(
        origin=scene["camera"]["origin"],
        forward=forward,
        right=right,
        up=up,
    )

    # Build build mat dict
    mat_bits2idx, mat_name2idx, mat_width = build_material_dict(scene)

    # Flash mat dict
    mats = sorted(mat_bits2idx.items(), key=lambda x: x[1])
    for mat_bits, mat_idx_val in mats:
        set_mat(mat_idx_val, mat_bits, mat_width)

    # Flash objects
    objs = scene["objects"]
    print(f"Flashing {len(objs)} objects")

    for idx, obj in enumerate(objs):
        # Look up material index in dictionary
        obj["mat_idx"] = mat_name2idx[obj["material"]]
        del obj["material"]
        set_obj(idx, Object(**obj))

    set_num_objs(len(objs))

    set_max_bounces(int(scene["max_bounces"]))
