import json, struct, os

for name in ["ferrari.glb", "porsche_911.glb", "car_concept.glb"]:
    p = os.path.join(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\forza_cars", name)
    with open(p, "rb") as f:
        magic, ver, length = struct.unpack("<III", f.read(12))
        chunk_len, chunk_type = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(chunk_len).decode("utf-8"))
        print(f"=== {name} ===")
        print("asset:", gltf.get("asset"))
        if name == "car_concept.glb":
            for n in gltf.get("nodes", []):
                if "Wheel" in n.get("name", ""):
                    print("  node:", n.get("name"), "rot:", n.get("rotation"), "trans:", n.get("translation"))
