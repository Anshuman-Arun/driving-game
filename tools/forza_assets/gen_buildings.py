"""Pure-Python generator for upgraded architectural buildings & landmarks (content/scenery/models/*.gltf)."""
import math
import sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_builder import GltfModel, MaterialDef


def mats_palette():
    return {
        "stone": MaterialDef("StoneFoundation", (0.78, 0.76, 0.72, 1.0), roughness=0.90, tex_folder="stone_wall", normal_scale=1.0),
        "plaster": MaterialDef("StuccoPlaster", (0.86, 0.82, 0.74, 1.0), roughness=0.85),
        "barn_red": MaterialDef("BarnTimberRed", (0.58, 0.16, 0.12, 1.0), roughness=0.82, tex_folder="wood_planks", normal_scale=0.8),
        "wood": MaterialDef("TimberTrim", (0.55, 0.40, 0.26, 1.0), roughness=0.84, tex_folder="wood_planks", normal_scale=0.9),
        "dark_wood": MaterialDef("DarkTimber", (0.28, 0.20, 0.13, 1.0), roughness=0.86, tex_folder="wood_planks", normal_scale=0.8),
        "slate": MaterialDef("RoofSlate", (0.36, 0.38, 0.42, 1.0), roughness=0.78, tex_folder="roof_slate", normal_scale=0.95),
        "metal": MaterialDef("CorrugatedMetal", (0.64, 0.67, 0.70, 1.0), metallic=0.72, roughness=0.48, tex_folder="corrugated_metal", normal_scale=0.9),
        "steel": MaterialDef("StructuralSteel", (0.28, 0.31, 0.35, 1.0), metallic=0.80, roughness=0.45),
        "glass": MaterialDef("ReflectiveGlass", (0.14, 0.24, 0.34, 1.0), metallic=0.45, roughness=0.08),
        "warm_glow": MaterialDef("WindowGlow", (0.95, 0.80, 0.48, 1.0), roughness=0.2, emissive=(0.45, 0.34, 0.16)),
        "canvas": MaterialDef("SailCanvas", (0.90, 0.86, 0.76, 1.0), roughness=0.88),
        "concrete": MaterialDef("ConcreteBase", (0.48, 0.48, 0.46, 1.0), roughness=0.90, tex_folder="asphalt", normal_scale=0.45),
        "accent_red": MaterialDef("GarageAccentRed", (0.68, 0.10, 0.08, 1.0), roughness=0.45),
    }


def add_foundation_skirt(m: GltfModel, mat: MaterialDef, w: float, d: float, depth: float = 0.55):
    """Add below-ground foundation skirt (-depth .. +0.08) AFTER normalize() so buildings never float on slopes."""
    m.part(mat).add_box((0.0, -depth * 0.5 + 0.04, 0.0), (w, depth, d), uv_scale=0.35)


def add_recessed_window(m: GltfModel, pal: dict, cx: float, cy: float, cz: float, w: float, h: float, axis: str = "z", sign: float = 1.0):
    """Add projecting timber frame, sill, mullions, and reflective dark glass outside wall face."""
    p_wood = m.part(pal["dark_wood"])
    p_glass = m.part(pal["glass"])
    d = 0.12
    if axis == "z":
        # Glass just outside wall face, framed by deeper projecting casing
        p_glass.add_box((cx, cy, cz + sign * 0.03), (w - 0.14, h - 0.14, 0.04))
        p_wood.add_box((cx, cy + h * 0.5 - 0.05, cz + sign * 0.06), (w + 0.08, 0.12, d))
        p_wood.add_box((cx, cy - h * 0.5 - 0.02, cz + sign * 0.09), (w + 0.22, 0.12, d + 0.06))
        p_wood.add_box((cx - w * 0.5 + 0.05, cy, cz + sign * 0.06), (0.12, h, d))
        p_wood.add_box((cx + w * 0.5 - 0.05, cy, cz + sign * 0.06), (0.12, h, d))
        p_wood.add_box((cx, cy, cz + sign * 0.055), (0.06, h - 0.12, 0.05))
        p_wood.add_box((cx, cy + 0.05, cz + sign * 0.055), (w - 0.12, 0.06, 0.05))
    else:
        p_glass.add_box((cx + sign * 0.03, cy, cz), (0.04, h - 0.14, w - 0.14))
        p_wood.add_box((cx + sign * 0.06, cy + h * 0.5 - 0.05, cz), (d, 0.12, w + 0.08))
        p_wood.add_box((cx + sign * 0.09, cy - h * 0.5 - 0.02, cz), (d + 0.06, 0.12, w + 0.22))
        p_wood.add_box((cx + sign * 0.06, cy, cz - w * 0.5 + 0.05), (d, h, 0.12))
        p_wood.add_box((cx + sign * 0.06, cy, cz + w * 0.5 - 0.05), (d, h, 0.12))
        p_wood.add_box((cx + sign * 0.055, cy, cz), (0.05, h - 0.12, 0.06))


def add_gabled_roof(part, x0: float, x1: float, y_eave: float, y_ridge: float, half_z: float, overhang: float = 0.55, thick: float = 0.28):
    prof = [
        (y_eave - 0.15, -half_z - overhang),
        (y_ridge, 0.0),
        (y_eave - 0.15, half_z + overhang),
        (y_eave + thick - 0.15, half_z + overhang),
        (y_ridge + thick, 0.0),
        (y_eave + thick - 0.15, -half_z - overhang),
    ]
    part.add_prism_extrude_x(prof, x0 - overhang, x1 + overhang, uv_scale=0.35)


def build_town_house():
    m = GltfModel("TownHouse")
    pal = mats_palette()
    # Stone foundation plinth
    m.part(pal["stone"]).add_box((0.0, 0.55, 0.0), (11.6, 1.1, 8.6), uv_scale=0.35)
    # Main two-story plaster body
    m.part(pal["plaster"]).add_box((0.0, 4.1, 0.0), (11.2, 6.0, 8.2))
    # Timber corner pilasters & horizontal belt course
    p_dw = m.part(pal["dark_wood"])
    for sx in (-5.58, 5.58):
        for sz in (-4.08, 4.08):
            p_dw.add_box((sx, 4.1, sz), (0.28, 6.0, 0.28))
    p_dw.add_box((0.0, 4.05, 0.0), (11.4, 0.22, 8.4))
    # Gabled roof + gable wall fill
    m.part(pal["plaster"]).add_prism_extrude_x([(7.1, -4.1), (10.7, 0.0), (7.1, 4.1)], -5.58, 5.58)
    add_gabled_roof(m.part(pal["slate"]), -5.6, 5.6, 7.1, 10.85, 4.1, overhang=0.65, thick=0.30)
    # Stone chimney
    m.part(pal["stone"]).add_box((3.2, 9.5, -1.6), (1.1, 3.3, 1.1), uv_scale=0.4)

    # Front porch (+Z) with steps, deck, timber posts & porch roof
    m.part(pal["stone"]).add_box((0.0, 0.35, 5.05), (5.2, 0.7, 2.1), uv_scale=0.4)
    m.part(pal["stone"]).add_box((0.0, 0.18, 6.18), (2.6, 0.36, 0.55), uv_scale=0.4)
    for px in (-2.2, 2.2):
        m.part(pal["wood"]).add_box((px, 2.15, 5.85), (0.22, 2.9, 0.22))
    m.part(pal["slate"]).add_box((0.0, 3.72, 5.15), (5.6, 0.24, 2.3), uv_scale=0.4)
    # Front door
    m.part(pal["dark_wood"]).add_box((0.0, 2.15, 4.12), (1.45, 2.45, 0.16))
    m.part(pal["warm_glow"]).add_box((0.0, 2.75, 4.21), (0.75, 0.55, 0.04))

    # Recessed windows front & back, and sides
    for wx in (-3.5, 3.5):
        add_recessed_window(m, pal, wx, 2.45, 4.10, 1.45, 1.55, "z", 1.0)
        add_recessed_window(m, pal, wx, 5.45, 4.10, 1.45, 1.55, "z", 1.0)
        add_recessed_window(m, pal, wx, 2.45, -4.10, 1.45, 1.55, "z", -1.0)
        add_recessed_window(m, pal, wx, 5.45, -4.10, 1.45, 1.55, "z", -1.0)
    add_recessed_window(m, pal, 0.0, 5.45, 4.10, 1.45, 1.55, "z", 1.0)
    for wz in (-1.8, 1.8):
        add_recessed_window(m, pal, 5.60, 2.45, wz, 1.35, 1.50, "x", 1.0)
        add_recessed_window(m, pal, -5.60, 5.45, wz, 1.35, 1.50, "x", -1.0)

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["stone"], 11.6, 8.6)
    return m.export("content/scenery/models/town_house.gltf")


def build_barn():
    m = GltfModel("Barn")
    pal = mats_palette()
    # Stone foundation
    m.part(pal["stone"]).add_box((0.0, 0.45, 0.0), (15.2, 0.9, 11.2), uv_scale=0.32)
    # Red timber walls
    m.part(pal["barn_red"]).add_box((0.0, 4.1, 0.0), (14.8, 6.4, 10.8), uv_scale=0.3)
    # Gambrel roof profile
    gambrel = [
        (7.3, -5.4), (10.2, -3.4), (11.8, 0.0), (10.2, 3.4), (7.3, 5.4)
    ]
    m.part(pal["barn_red"]).add_prism_extrude_x(gambrel, -7.4, 7.4, uv_scale=0.3)
    roof_prof = [
        (7.0, -5.95), (10.25, -3.55), (11.95, 0.0), (10.25, 3.55), (7.0, 5.95),
        (7.3, 6.05), (10.55, 3.65), (12.25, 0.0), (10.55, -3.65), (7.3, -6.05),
    ]
    m.part(pal["slate"]).add_prism_extrude_x(roof_prof, -7.95, 7.95, uv_scale=0.32)

    # White/cream timber trim & X-braced double barn doors on +Z & -Z
    p_w = m.part(pal["wood"])
    for sz in (5.44, -5.44):
        p_w.add_box((0.0, 2.75, sz), (4.2, 4.6, 0.14))
        p_w.add_box((0.0, 2.75, sz + (0.06 if sz > 0 else -0.06)), (0.16, 4.6, 0.10))
        p_w.add_box((0.0, 5.02, sz), (4.45, 0.22, 0.20))
        # Hayloft window
        add_recessed_window(m, pal, 0.0, 8.2, sz, 1.8, 1.8, "z", 1.0 if sz > 0 else -1.0)
    # Cupola on ridge
    m.part(pal["barn_red"]).add_box((0.0, 12.1, 0.0), (1.8, 1.3, 1.8))
    add_gabled_roof(m.part(pal["slate"]), -0.95, 0.95, 12.75, 13.65, 0.95, overhang=0.25, thick=0.14)

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["stone"], 15.2, 11.2)
    return m.export("content/scenery/models/barn.gltf")


def build_garage():
    m = GltfModel("AlderGarage")
    pal = mats_palette()
    # Concrete apron + stone foundation
    m.part(pal["concrete"]).add_box((0.0, 0.25, 0.0), (14.6, 0.5, 10.6), uv_scale=0.35)
    # Main service hall + sloped corrugated metal roof + bold red motorsport fascia
    m.part(pal["plaster"]).add_box((0.0, 3.15, -0.4), (14.0, 5.3, 9.2))
    m.part(pal["metal"]).add_box((0.0, 6.15, -0.4), (14.4, 0.85, 9.6), uv_scale=0.4)
    m.part(pal["accent_red"]).add_box((0.0, 5.65, 4.42), (14.45, 0.42, 0.25))
    add_gabled_roof(m.part(pal["metal"]), -7.2, 7.2, 6.55, 8.15, 4.8, overhang=0.45, thick=0.22)
    # Sloped overhang canopy across front (+Z)
    m.part(pal["steel"]).add_box((0.0, 4.95, 4.85), (14.5, 0.26, 1.9))
    # Two dark-framed ribbed roll-up garage doors
    p_m = m.part(pal["metal"])
    p_s = m.part(pal["steel"])
    for gx in (-3.6, 1.2):
        p_s.add_box((gx, 2.35, 4.24), (3.9, 3.9, 0.16))
        for ry in np.linspace(0.75, 3.85, 7):
            p_m.add_box((gx, float(ry), 4.32), (3.65, 0.40, 0.08))
    # Glass office storefront on right side (projected cleanly outside wall)
    add_recessed_window(m, pal, 5.2, 2.35, 4.22, 2.8, 3.1, "z", 1.0)
    # Side windows
    add_recessed_window(m, pal, -7.02, 3.2, -0.4, 2.4, 1.6, "x", -1.0)
    add_recessed_window(m, pal, 7.02, 3.2, -0.4, 2.4, 1.6, "x", 1.0)
    # Rooftop HVAC + illuminated service sign
    p_m.add_box((-3.8, 7.45, -1.0), (2.2, 0.9, 1.8))
    m.part(pal["warm_glow"]).add_box((0.0, 6.25, 4.46), (6.4, 0.65, 0.14))

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["concrete"], 14.6, 10.6)
    return m.export("content/scenery/models/garage.gltf")


def build_windmill():
    m = GltfModel("GreenValleyWindmill")
    pal = mats_palette()
    # Octagonal tapered stone base + timber upper tower
    m.part(pal["stone"]).add_cylinder_y((0.0, 0.0, 0.0), 3.4, 2.75, 5.2, segs=8, uv_scale=0.35, smooth=False)
    m.part(pal["wood"]).add_cylinder_y((0.0, 5.2, 0.0), 2.75, 2.05, 6.8, segs=8, uv_scale=0.35, smooth=False)
    # Conical slate cap
    m.part(pal["slate"]).add_cylinder_y((0.0, 12.0, 0.0), 2.45, 0.18, 2.7, segs=8, uv_scale=0.4, smooth=False)
    # Arched timber doorway + recessed windows
    m.part(pal["dark_wood"]).add_box((0.0, 1.35, 3.15), (1.45, 2.5, 0.35))
    add_recessed_window(m, pal, 0.0, 7.2, 2.52, 1.1, 1.3, "z", 1.0)
    add_recessed_window(m, pal, 0.0, 7.2, -2.52, 1.1, 1.3, "z", -1.0)

    # Sail hub + 4 lattice sails facing +Z
    p_dw = m.part(pal["dark_wood"])
    p_cv = m.part(pal["canvas"])
    hub_y, hub_z = 11.4, 2.55
    p_dw.add_box((0.0, hub_y, hub_z - 0.35), (0.65, 0.65, 1.1))
    for i in range(4):
        ang = (i * math.pi * 0.5) + 0.38
        ca, sa = math.cos(ang), math.sin(ang)
        # Main spar
        for step in np.linspace(0.6, 6.8, 8):
            sx = ca * float(step)
            sy = hub_y + sa * float(step)
            p_dw.add_box((sx, sy, hub_z + 0.15), (0.18, 0.18, 0.18))
        # Canvas sail panel (10 steps along blade)
        p_cv.add_box((ca * 4.0 - sa * 0.55, hub_y + sa * 4.0 + ca * 0.55, hub_z + 0.18), (1.1 if abs(sa) > 0.5 else 5.2, 5.2 if abs(sa) > 0.5 else 1.1, 0.06), rot_y=0.0)

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["stone"], 6.6, 6.6)
    return m.export("content/scenery/models/windmill.gltf")


def build_stone_arch():
    m = GltfModel("StoneArch")
    pal = mats_palette()
    p_st = m.part(pal["stone"])
    # Left & right buttressed piers (total X span [-4.7, 4.7], Z [-1.55, 1.55])
    for sx in (-3.65, 3.65):
        p_st.add_box((sx, 0.35, 0.0), (2.1, 0.7, 3.1), uv_scale=0.35)
        p_st.add_box((sx, 2.35, 0.0), (1.75, 3.3, 2.5), uv_scale=0.35)
    # Arch voussoir segments spanning across top
    n_seg = 11
    for i in range(n_seg):
        t = i / (n_seg - 1)
        ang = math.pi * (1.0 - t)
        r = 3.25
        ax = math.cos(ang) * r
        ay = 3.85 + math.sin(ang) * 2.35
        scale = 1.18 if i == n_seg // 2 else 1.0
        p_st.add_box((ax, ay, 0.0), (1.05 * scale, 0.95 * scale, 2.55 * scale), uv_scale=0.38)
    # Upper spandrel & coping capstones
    p_st.add_box((0.0, 6.45, 0.0), (9.4, 0.65, 2.8), uv_scale=0.35)

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("content/scenery/models/stone_arch.gltf")


def build_overlook():
    m = GltfModel("StarfallOverlook")
    pal = mats_palette()
    # Stone retaining terrace
    m.part(pal["stone"]).add_box((0.0, 0.75, 0.0), (11.6, 1.5, 7.6), uv_scale=0.32)
    # Timber viewing deck
    m.part(pal["wood"]).add_box((0.0, 1.60, 0.0), (12.0, 0.22, 8.0), uv_scale=0.4)
    # Perimeter timber posts & double rails
    p_dw = m.part(pal["dark_wood"])
    for px in np.linspace(-5.7, 5.7, 7):
        p_dw.add_box((float(px), 2.35, 3.82), (0.20, 1.4, 0.20))
        p_dw.add_box((float(px), 2.35, -3.82), (0.20, 1.4, 0.20))
    for pz in (-1.9, 0.0, 1.9):
        p_dw.add_box((-5.82, 2.35, pz), (0.20, 1.4, 0.20))
        p_dw.add_box((5.82, 2.35, pz), (0.20, 1.4, 0.20))
    for ry in (2.25, 2.85):
        p_dw.add_box((0.0, ry, 3.82), (11.8, 0.12, 0.12))
        p_dw.add_box((0.0, ry, -3.82), (11.8, 0.12, 0.12))
        p_dw.add_box((-5.82, ry, 0.0), (0.12, 0.12, 7.8))
        p_dw.add_box((5.82, ry, 0.0), (0.12, 0.12, 7.8))
    # Viewing bench
    m.part(pal["wood"]).add_box((0.0, 2.05, -2.4), (3.4, 0.12, 0.7))

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["stone"], 11.6, 7.6)
    return m.export("content/scenery/models/overlook.gltf")


def build_pier():
    m = GltfModel("EastwaterPier")
    pal = mats_palette()
    p_dw = m.part(pal["dark_wood"])
    p_w = m.part(pal["wood"])
    # Submerged timber pilings (-3.2 to +1.25)
    for px in (-3.3, 0.0, 3.3):
        for pz in (-2.8, 0.5, 3.8):
            p_dw.add_cylinder_y((px, -3.2, pz), 0.18, 0.16, 4.45, segs=10)
    # Cross-beams & boardwalk deck at y=0.05..0.30
    for pz in (-2.8, 0.5, 3.8):
        p_dw.add_box((0.0, -0.08, pz), (7.4, 0.22, 0.26))
    for i in range(18):
        pz = -3.2 + i * 0.48
        p_w.add_box((0.0, 0.14, pz), (7.5, 0.12, 0.42), uv_scale=0.5)
    # Side railings & mooring bollards
    for sx in (-3.55, 3.55):
        p_dw.add_box((sx, 1.15, 0.5), (0.12, 0.12, 8.2))
        p_dw.add_box((sx, 0.70, 0.5), (0.10, 0.10, 8.2))
        p_dw.add_cylinder_y((sx * 0.9, 0.20, 4.6), 0.15, 0.13, 0.55, segs=10)

    # Preserve Y=-3.2 bottom so deck sits flush at water level
    m.normalize(center_xz=True, bottom_y=-3.2)
    return m.export("content/scenery/models/pier.gltf")


def build_quarry_hopper():
    m = GltfModel("QuarryHopper")
    pal = mats_palette()
    p_c = m.part(pal["concrete"])
    p_s = m.part(pal["steel"])
    p_m = m.part(pal["metal"])
    # 4 concrete pier footings
    for sx in (-5.6, 5.6):
        for sz in (-4.4, 4.4):
            p_c.add_box((sx, 0.5, sz), (1.8, 1.0, 1.8), uv_scale=0.4)
            p_s.add_box((sx, 3.4, sz), (0.55, 5.2, 0.55))
    # Cross-bracing girders
    p_s.add_box((0.0, 5.6, 4.4), (11.8, 0.55, 0.55))
    p_s.add_box((0.0, 5.6, -4.4), (11.8, 0.55, 0.55))
    p_s.add_box((-5.6, 5.6, 0.0), (0.55, 0.55, 9.2))
    p_s.add_box((5.6, 5.6, 0.0), (0.55, 0.55, 9.2))
    # Corrugated steel ore hopper funnel
    p_m.add_box((0.0, 7.6, 0.0), (12.4, 2.8, 9.8), uv_scale=0.35)
    p_m.add_box((0.0, 5.2, 0.0), (8.2, 2.0, 6.2), uv_scale=0.4)
    p_s.add_box((0.0, 3.8, 0.0), (3.4, 1.2, 3.0))
    # Upper catwalk & safety railing
    p_s.add_box((0.0, 9.15, 5.6), (13.6, 0.16, 1.4))
    p_s.add_box((0.0, 9.68, 6.25), (13.6, 0.10, 0.10))
    for px in np.linspace(-6.5, 6.5, 7):
        p_s.add_box((float(px), 9.40, 6.25), (0.10, 0.65, 0.10))

    m.normalize(center_xz=True, bottom_y=0.0)
    add_foundation_skirt(m, pal["concrete"], 13.0, 10.6)
    return m.export("content/scenery/models/quarry_hopper.gltf")


def main():
    build_town_house()
    build_barn()
    build_garage()
    build_windmill()
    build_stone_arch()
    build_overlook()
    build_pier()
    build_quarry_hopper()


if __name__ == "__main__":
    main()
