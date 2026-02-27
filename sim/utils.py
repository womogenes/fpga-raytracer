# Convert bit representations

import math
import ctypes

import cocotb
from cocotb.binary import BinaryValue

FP_EXP_BITS = 7
FP_MANT_BITS = 16

FP_EXP_OFFSET = (2 ** (FP_EXP_BITS - 1)) - 1
FP_BITS = 1 + FP_EXP_BITS + FP_MANT_BITS
FP_VEC3_BITS = 3 * FP_BITS

# ===== FP REPRESENTATIONS =====
def make_fp(x: float):
    """
    Convert Python float to fp value
    """
    if x == 0:
        return 0
    
    sign = int(x < 0)
    value = abs(x)

    exp = int(math.floor(math.log2(value)))
    exp_biased = exp + FP_EXP_OFFSET
    assert 0 <= exp_biased < 2 ** FP_EXP_BITS, f"FP exponent out of range, got {x} ({exp=})"

    frac = value / (2 ** exp)

    mant = int((frac - 1.0) * (1 << FP_MANT_BITS) + 0.5)
    return (sign << (FP_EXP_BITS + FP_MANT_BITS)) | (exp_biased << FP_MANT_BITS) | mant

def convert_fp(f: BinaryValue):
    """
    Convert fp value to Python float
    """
    if isinstance(f, BinaryValue) and not f.is_resolvable:
        # Not a valid float
        return None
        
    # If all but the sign bit is zero, this represents zero
    EXP_MANT_MASK = (1 << (FP_EXP_BITS + FP_MANT_BITS)) - 1
    EXP_MASK = (1 << FP_EXP_BITS) - 1
    MANT_MASK = (1 << FP_MANT_BITS) - 1

    if f & EXP_MANT_MASK == 0:
        return 0
    
    sign = -1 if (f >> (FP_EXP_BITS + FP_MANT_BITS)) & 1 else 1
    exp = ((f >> FP_MANT_BITS) & EXP_MASK) - FP_EXP_OFFSET
    mant = 1 + (f & MANT_MASK) / (1 << FP_MANT_BITS)

    return sign * (2 ** exp) * mant

def make_fp_vec3(vec3: tuple[float]):
    """
    Convert (x, y, z) to packed fp_vec3
    """
    x, y, z = vec3
    return pack_bits([
        (make_fp(x), FP_BITS),
        (make_fp(y), FP_BITS),
        (make_fp(z), FP_BITS),
    ])

def convert_fp_vec3(vec3: BinaryValue):
    """
    Unpack vec3 into tuple of 3 floats
    """
    if isinstance(vec3, BinaryValue) and not vec3.is_resolvable:
        return (None, None, None)

    mask = (1 << FP_BITS) - 1
    x = convert_fp((vec3 >> (FP_BITS * 2)) & mask)
    y = convert_fp((vec3 >> (FP_BITS * 1)) & mask)
    z = convert_fp((vec3 >> (FP_BITS * 0)) & mask)
    return (x, y, z)

def make_material(
    color=0,
    emit_color=0,
    spec_color=0,
    smooth=0,
    one_sub_smooth=0,
    specular=0,
):
    return pack_bits([
        (color, FP_VEC3_BITS),
        (emit_color, FP_VEC3_BITS),
        (spec_color, FP_VEC3_BITS),
        (smooth, FP_BITS),
        (one_sub_smooth, FP_BITS),
        (specular, 8),
    ])

# Pack bits together
def pack_bits(values: list[int, int], msb=True):
    """
    value is a list of (value, width) pairs
    """
    # If MSB, this is NOT the natural ordering for 0-index
    values = values[::-1] if msb else values

    pos = 0
    res = 0
    for value, width in values:
        res += (value & ((1 << width) - 1)) << pos
        pos += width

    return res
