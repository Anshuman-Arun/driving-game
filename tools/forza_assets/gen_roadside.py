"""Pure-Python generator for upgraded roadside & rural props (.glb)."""
import math
import sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_builder import GltfModel, MaterialDef


def build_guardrail():
    m = GltfModel("Guardrail4m")
    steel = MaterialDef("GalvanizedSteel", (0.72, 0.75, 0.78, 1.0), metallic=0.82, roughness=0.38)
    dark_steel = MaterialDef("PostSteel", (0.45, 0.48, 0.52, 1.0), metallic=0.75, roughness=0.52)
    refl_orange = MaterialDef("ReflectorOrange", (0.95, 0.42, 0.05, 1.0), metallic=0.1, roughness=0.22, emissive=(0.25, 0.08, 0.0))

    # W-beam corrugated rail profile in (Y, Z) extruded along X [-2.015, 2.015]
    w_prof = [
        (0.56, 0.04), (0.62, 0.10), (0.68, 0.10), (0.72, 0.05),
        (0.76, 0.10), (0.82, 0.10), (0.88, 0.04), (0.88, 0.015),
        (0.81, 0.075), (0.76, 0.075), (0.72, 0.025), (0.68, 0.075),
        (0.62, 0.075), (0.56, 0.015),
    ]
    m.part(steel).add_prism_extrude_x(w_prof, -2.015, 2.015, uv_scale=0.5)
    # Upper rub-rail bar
    m.part(steel).add_box((0.0, 0.96, 0.05), (4.03, 0.06, 0.05))

    p_post = m.part(dark_steel)
    p_refl = m.part(refl_orange)
    for px in (-1.6, 0.0, 1.6):
        # I-beam post (web + 2 flanges) + baseplate + spacer block
        p_post.add_box((px, 0.54, -0.04), (0.04, 1.08, 0.09))
        p_post.add_box((px, 0.54, -0.085), (0.10, 1.08, 0.02))
        p_post.add_box((px, 0.54, 0.005), (0.10, 1.08, 0.02))
        p_post.add_box((px, 0.015, -0.04), (0.20, 0.03, 0.18))
        p_post.add_box((px, 0.72, 0.015), (0.09, 0.28, 0.04))
    for rx in (-1.9, 1.9):
        p_refl.add_box((rx, 0.72, 0.105), (0.10, 0.07, 0.02))

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/guardrail_4m.glb")


def build_concrete_barrier():
    m = GltfModel("ConcreteBarrier")
    conc = MaterialDef("WeatheredConcrete", (0.68, 0.67, 0.65, 1.0), roughness=0.90, tex_folder="asphalt", normal_scale=0.5)
    refl = MaterialDef("SafetyYellow", (0.95, 0.78, 0.08, 1.0), roughness=0.25, emissive=(0.15, 0.12, 0.0))

    # Authentic Jersey-profile cross-section in (Y, Z) extruded along X [-1.27, 1.27]
    jersey = [
        (0.0, -0.335), (0.0, 0.335),
        (0.08, 0.335), (0.28, 0.16), (0.92, 0.10), (0.955, 0.07),
        (0.955, -0.07), (0.92, -0.10), (0.28, -0.16), (0.08, -0.335),
    ]
    m.part(conc).add_prism_extrude_x(jersey, -1.27, 1.27, uv_scale=0.4)
    p_r = m.part(refl)
    for sx in (-0.95, 0.95):
        p_r.add_box((sx, 0.80, 0.115), (0.22, 0.06, 0.015))
        p_r.add_box((sx, 0.80, -0.115), (0.22, 0.06, 0.015))

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/concrete_barrier.glb")


def build_wood_fence():
    m = GltfModel("WoodFence")
    wood = MaterialDef("TimberFence", (0.76, 0.64, 0.50, 1.0), roughness=0.86, tex_folder="wood_planks", normal_scale=0.9)
    dark_cap = MaterialDef("PostCap", (0.42, 0.34, 0.25, 1.0), roughness=0.88, tex_folder="wood_planks")

    p_w = m.part(wood)
    p_c = m.part(dark_cap)
    for px in (-1.42, 0.0, 1.42):
        p_w.add_box((px, 0.64, 0.0), (0.14, 1.28, 0.14), uv_scale=0.6)
        p_c.add_box((px, 1.30, 0.0), (0.17, 0.04, 0.17), uv_scale=0.6)
    for ry in (0.48, 0.97):
        p_w.add_box((0.0, ry, 0.075), (3.03, 0.11, 0.04), uv_scale=0.5)

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/wood_fence.glb")


def build_bollard():
    m = GltfModel("Bollard")
    body = MaterialDef("BollardWhite", (0.88, 0.89, 0.90, 1.0), roughness=0.45)
    base = MaterialDef("BollardBase", (0.22, 0.24, 0.26, 1.0), metallic=0.6, roughness=0.55)
    band = MaterialDef("BollardReflect", (0.95, 0.25, 0.08, 1.0), roughness=0.22, emissive=(0.18, 0.04, 0.01))

    m.part(base).add_cylinder_y((0, 0, 0), 0.13, 0.12, 0.06, segs=16)
    m.part(body).add_cylinder_y((0, 0.06, 0), 0.105, 0.095, 0.74, segs=16)
    m.part(band).add_cylinder_y((0, 0.80, 0), 0.098, 0.098, 0.14, segs=16)
    m.part(body).add_cylinder_y((0, 0.94, 0), 0.095, 0.075, 0.13, segs=16)

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/bollard.glb")


def build_warning_sign():
    m = GltfModel("WarningSign")
    post = MaterialDef("SignPost", (0.62, 0.65, 0.68, 1.0), metallic=0.78, roughness=0.42)
    yellow = MaterialDef("SignYellow", (0.96, 0.76, 0.08, 1.0), roughness=0.30)
    black = MaterialDef("SignBlack", (0.08, 0.08, 0.09, 1.0), roughness=0.55)

    p_post = m.part(post)
    p_post.add_box((0.0, 1.18, -0.02), (0.07, 2.36, 0.05))
    p_post.add_box((0.0, 0.02, -0.02), (0.18, 0.04, 0.16))

    # Diamond plate rotated 45 deg in XY (centered at y=2.25, z=0.02)
    s = 0.56
    h = s * math.sqrt(0.5)
    plate = [(0.0, h), (h, 0.0), (0.0, -h), (-h, 0.0)]
    plate_y = [(x, y + 2.25) for x, y in plate]
    m.part(black).add_prism_extrude_z(plate_y, 0.005, 0.035, uv_scale=1.0)
    h_in = h * 0.88
    plate_in = [(0.0, h_in + 2.25), (h_in, 2.25), (0.0, -h_in + 2.25), (-h_in, 2.25)]
    m.part(yellow).add_prism_extrude_z(plate_in, 0.035, 0.045, uv_scale=1.0)

    # Exclamation bar & dot
    p_b = m.part(black)
    p_b.add_box((0.0, 2.32, 0.052), (0.07, 0.28, 0.014))
    p_b.add_box((0.0, 2.09, 0.052), (0.075, 0.075, 0.014))

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/warning_sign.glb")


def build_street_lamp():
    m = GltfModel("StreetLamp")
    pole = MaterialDef("LampPole", (0.48, 0.51, 0.55, 1.0), metallic=0.80, roughness=0.40)
    dark = MaterialDef("LampHousing", (0.18, 0.20, 0.22, 1.0), metallic=0.65, roughness=0.45)
    lens = MaterialDef("LampLens", (1.0, 0.92, 0.75, 1.0), roughness=0.15, emissive=(1.0, 0.88, 0.65))

    p_pole = m.part(pole)
    p_pole.add_cylinder_y((0, 0, 0), 0.135, 0.135, 0.06, segs=12)
    p_pole.add_cylinder_y((0, 0.06, 0), 0.105, 0.06, 4.35, segs=12)
    # Curved/angled arm extending toward +X up to ~1.28m
    p_pole.add_box((0.38, 4.46, 0.0), (0.78, 0.075, 0.075), rot_y=0.0)
    p_pole.add_box((0.88, 4.54, 0.0), (0.35, 0.065, 0.065))

    m.part(dark).add_box((1.12, 4.58, 0.0), (0.36, 0.09, 0.22))
    m.part(lens).add_box((1.14, 4.525, 0.0), (0.28, 0.025, 0.16))

    # Keep pole at origin, bottom at y=0 (do not center_xz so pole stays at local XZ=0)
    m.normalize(center_xz=False, bottom_y=0.0)
    return m.export("assets/curated/models/environment/street_lamp.glb")


def build_hay_bale():
    m = GltfModel("HayBale")
    hay = MaterialDef("HayStraw", (0.85, 0.74, 0.45, 1.0), roughness=0.92, tex_folder="hay", normal_scale=1.0)
    twine = MaterialDef("SisalTwine", (0.45, 0.32, 0.18, 1.0), roughness=0.85)

    def hay_disp(v: np.ndarray) -> float:
        return 1.0 + 0.06 * math.sin(v[0] * 11.0) * math.cos(v[2] * 9.0)

    # Rounded organic hay bale (~1.22 x 1.01 x 0.77)
    p_h = m.part(hay)
    p_h.add_icosphere((0.0, 0.505, 0.0), (0.61, 0.505, 0.385), subdivs=2, displace_fn=hay_disp, uv_scale=0.9, smooth=False)
    # Two twine bands
    p_t = m.part(twine)
    for tx in (-0.26, 0.26):
        p_t.add_box((tx, 0.505, 0.0), (0.025, 0.96, 0.74))

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/hay_bale.glb")


def main():
    build_guardrail()
    build_concrete_barrier()
    build_wood_fence()
    build_bollard()
    build_warning_sign()
    build_street_lamp()
    build_hay_bale()


if __name__ == "__main__":
    main()
