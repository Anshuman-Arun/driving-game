extends RefCounted
## Geometry-only diagnostic for point-agent traffic states.
## These conservative rectangles are test proxies, not shipped rigid bodies.
## XZ oriented bounding boxes avoid mistaking legal ~3.4 m paired lane spacing
## for a collision, but still detect overlaps between any lane/turn pair.
const LENGTH_M := 4.5
const WIDTH_M := 1.85
const HEIGHT_M := 1.7
const SAME_LANE_MIN_CENTER_GAP_M := 5.0
const CONTACT_TOLERANCE_M := 0.02
const HALF_LENGTH_M := LENGTH_M * 0.5
const HALF_WIDTH_M := WIDTH_M * 0.5
const MAX_CENTER_DISTANCE_M := 2.0 * sqrt(HALF_LENGTH_M * HALF_LENGTH_M + HALF_WIDTH_M * HALF_WIDTH_M)


static func diagnose(a: Dictionary, b: Dictionary) -> Dictionary:
	var pa: Vector3 = a["position"]
	var pb: Vector3 = b["position"]
	if absf(pa.y - pb.y) >= HEIGHT_M:
		return {}  # Grade-separated bodies cannot occupy the same height.
	var lid_a: String = str(a["lane_id"])
	var lid_b: String = str(b["lane_id"])
	var center_gap_m: float = pa.distance_to(pb)
	var lateral_delta := Vector2(pb.x - pa.x, pb.z - pa.z)
	# A separate center-arc guard retains strict same-lane rear-end spacing.
	# It is more conservative than physical bumper contact, but applies ONLY
	# to cars on the same directed lane, never the paired opposite lane.
	if lid_a == lid_b and absf(float(a["s"]) - float(b["s"])) < SAME_LANE_MIN_CENTER_GAP_M:
		return {"kind": "same_lane_rear_end", "center_gap_m": center_gap_m}
	if lateral_delta.length() > MAX_CENTER_DISTANCE_M:
		return {}
	var ta: Vector3 = a["tangent"]
	var tb: Vector3 = b["tangent"]
	var forward_a := Vector2(ta.x, ta.z)
	var forward_b := Vector2(tb.x, tb.z)
	if forward_a.length_squared() <= 0.000001 or forward_b.length_squared() <= 0.000001:
		return {"kind": "invalid_heading", "center_gap_m": center_gap_m}
	forward_a = forward_a.normalized()
	forward_b = forward_b.normalized()
	var right_a := Vector2(-forward_a.y, forward_a.x)
	var right_b := Vector2(-forward_b.y, forward_b.x)
	# Four separating axes: each vehicle's forward and lateral axes.
	# No "opposite direction" exemption: an illegal oncoming intrusion
	# will still be reported whenever the physical rectangles intersect.
	var closest_separating_axis_gap_m: float = -INF
	for axis in [forward_a, right_a, forward_b, right_b]:
		var extent_a: float = HALF_LENGTH_M * absf(axis.dot(forward_a)) + HALF_WIDTH_M * absf(axis.dot(right_a))
		var extent_b: float = HALF_LENGTH_M * absf(axis.dot(forward_b)) + HALF_WIDTH_M * absf(axis.dot(right_b))
		var signed_gap: float = absf(lateral_delta.dot(axis)) - extent_a - extent_b
		closest_separating_axis_gap_m = maxf(closest_separating_axis_gap_m, signed_gap)
	if closest_separating_axis_gap_m >= -CONTACT_TOLERANCE_M:
		return {}
	var kind := "cross_lane_body_overlap"
	if lid_a == lid_b:
		# Distinct arc positions can geometrically overlap on a hairpin.
		kind = "same_lane_body_overlap"
	elif str(a.get("next_lane", "")) != "" and str(a.get("next_lane", "")) == str(b.get("next_lane", "")):
		kind = "unsafe_merge_body_overlap"
	elif lid_a.begins_with("turn_") or lid_b.begins_with("turn_"):
		kind = "turning_body_overlap"
	return {"kind": kind, "center_gap_m": center_gap_m,
		"sat_gap_m": closest_separating_axis_gap_m}


static func fixture(x: float, z: float, dx: float, dz: float, lane: String, s: float,
		y: float = 0.0, next_lane: String = "") -> Dictionary:
	return {"position": Vector3(x, y, z), "tangent": Vector3(dx, 0.0, dz),
		"lane_id": lane, "s": s, "next_lane": next_lane}
