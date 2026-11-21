"""Rebuild the deterministic miniature v1 lane graph fixture (Python 3, standard library)."""
import json
from pathlib import Path

lanes = []

def lane(lid, points, following, speed=46, width=3.5, road=None):
    lanes.append({
        "id": lid, "road_id": road or ("r_ew" if lid.startswith(("eb_", "wb_", "east_", "west_", "feeder")) else "r_ns"),
        "points": [[float(x), 1.0, float(z)] for x, z in points],
        "width_m": width, "speed_limit_kph": speed, "surface": "asphalt", "next_lane_ids": following
    })

lane("eb_in", [(-90, 2),(-12, 2)], ["eb_cross"])
lane("eb_cross", [(-12, 2),(0, 2),(12, 2)], ["eb_out1"], 35)
lane("eb_out1", [(12, 2),(50, 2)], ["eb_out2"])
lane("eb_out2", [(50, 2),(90, 2)], ["east_turn"])
lane("east_turn", [(90, 2),(103, 2),(109, 0),(112, -5),(110, -12),(104, -16),(96, -14),(91, -9),(90, -2)], ["wb_in"], 26)
lane("wb_in", [(90, -2),(12, -2)], ["wb_cross"])
lane("wb_cross", [(12, -2),(0, -2),(-12, -2)], ["wb_out"], 35)
lane("wb_out", [(-12, -2),(-90, -2)], ["west_turn"])
lane("west_turn", [(-90, -2),(-103, -2),(-109, 0),(-112, 5),(-110, 12),(-104, 16),(-96, 14),(-91, 9),(-90, 2)], ["eb_in"], 25)
lane("sb_in", [(-2, -90),(-2, -12)], ["sb_cross"], road="r_ns")
lane("sb_cross", [(-2, -12),(-2, 0),(-2, 12)], ["sb_out1"], 35, road="r_ns")
lane("sb_out1", [(-2, 12),(-2, 44)], ["sb_out2", "feeder"], road="r_ns")
lane("sb_out2", [(-2, 44),(-2, 90)], ["south_turn"], road="r_ns")
lane("south_turn", [(-2, 90),(-2, 111),(4, 116),(18, 116),(24, 110),(24, 96),(2, 90)], ["nb_in_far"], 26, road="r_ns")
lane("nb_in_far", [(2, 90),(2, 44)], ["nb_in"], road="r_ns")
lane("nb_in", [(2, 44),(2, 12)], ["nb_cross"], road="r_ns")
lane("nb_cross", [(2, 12),(2, 0),(2, -12)], ["nb_out"], 35, road="r_ns")
lane("nb_out", [(2, -12),(2, -90)], ["north_turn"], road="r_ns")
lane("north_turn", [(2, -90),(2, -112),(-4, -116),(-18, -116),(-23, -110),(-23, -96),(-2, -90)], ["sb_in"], 26, road="r_ns")
lane("feeder", [(-2, 44),(4, 42),(18, 34),(30, 20),(43, 7),(50, 2)], ["eb_out2"], 28)

roads = []
for rid, name in [("r_ew", "Willow Street east-west loop and merge"),("r_ns", "Aspen Avenue north-south loop")]:
    roads.append({"id":rid,"name":name,"region":"test_town","lane_ids":[p["id"] for p in lanes if p["road_id"]==rid]})

data = {"schema_version": 1,"units":"meters","coordinate_system":"godot_y_up",
        "bounds":{"min_x":-160,"max_x":160,"min_z":-160,"max_z":160},"roads":roads,"lanes":lanes}
path = Path(__file__).with_name("intersection_v1.json")
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(path, f"{len(lanes)} lanes")
