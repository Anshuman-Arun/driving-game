extends RefCounted
## Adapter for authoritative World PR #3 traffic pack and Traffic PR #4 API.
## Call after successful TrafficSimulation.load_road_graph(), once per graph load.
const DEFAULT_PATH := "res://content/traffic/controls_v1.json"
var errors: Array[String] = []
var report: Dictionary = {}


func read_file(path: String = DEFAULT_PATH) -> Dictionary:
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("missing traffic pack: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		errors.append("traffic pack is not a JSON object: " + path)
		return {}
	return parsed


func apply_file(simulation: Object, path: String = DEFAULT_PATH) -> bool:
	var pack: Dictionary = read_file(path)
	if pack.is_empty():
		return false
	return apply_pack(pack, simulation)


func apply_pack(pack: Dictionary, simulation: Object) -> bool:
	if not validate_pack(pack, simulation):
		return false
	if not bool(simulation.call("configure_junctions", native_definitions(pack))):
		errors.append("native configure_junctions failed: reload graph before retrying; partial mutation possible")
		return false
	report["applied_controls"] = 8
	return true


func native_definitions(pack: Dictionary) -> Array:
	var result: Array = []
	for entry in pack.get("junctions", []):
		if not (entry is Dictionary):
			continue
		var mode: String = str(entry.get("mode", ""))
		if not ["stop", "yield"].has(mode):
			continue
		var definition: Dictionary = {"id": entry["id"],
			"incoming_lane_ids": entry["incoming_lane_ids"].duplicate(),
			"mode": mode, "clearance_m": float(entry["clearance_m"])}
		if mode == "stop":
			definition["stop_s"] = float(entry["stop_s"])
		result.append(definition)
	return result


func validate_pack(pack: Dictionary, simulation: Object) -> bool:
	errors.clear()
	report.clear()
	if pack.get("schema_version") != 1:
		errors.append("unsupported traffic schema_version; expected 1")
	if simulation == null or not simulation.has_method("configure_junctions"):
		errors.append("not a TrafficSimulation compatible object")
		return false
	if simulation.get("graph_valid") != true:
		errors.append("call load_road_graph successfully before configuring controls")
		return false
	var graph_value: Variant = simulation.get("graph")
	if not (graph_value is Object):
		errors.append("simulation graph object unavailable")
		return false
	var graph: Object = graph_value
	var lanes_value: Variant = graph.get("lanes")
	var roads_value: Variant = graph.get("roads")
	if not (lanes_value is Dictionary) or not (roads_value is Dictionary):
		errors.append("simulation graph lanes/roads unavailable")
		return false
	var lanes: Dictionary = lanes_value
	var roads: Dictionary = roads_value
	var existing_mapping_value: Variant = simulation.get("inbound_junction")
	var existing_groups_value: Variant = simulation.get("junctions")
	if not (existing_mapping_value is Dictionary) or not (existing_groups_value is Dictionary):
		errors.append("simulation implicit merge state unavailable")
		return false
	var mapping: Dictionary = existing_mapping_value
	var groups: Dictionary = existing_groups_value
	var source_value: Variant = pack.get("source_graph")
	if not (source_value is Dictionary):
		errors.append("source_graph metadata missing")
		return false
	var source: Dictionary = source_value
	if str(source.get("git_blob_sha", "")).length() != 40:
		errors.append("source_graph Git blob SHA invalid")
	if source.get("corridors") != 16 or source.get("corridor_lanes") != 32 or source.get("turn_lanes") != 72 or source.get("physical_junctions") != 11:
		errors.append("source_graph manifest counts invalid")
	var physical_roads := 0
	var junction_roads := 0
	var turn_lanes := 0
	for rid in roads:
		if str(rid).begins_with("junction_"):
			junction_roads += 1
		else:
			physical_roads += 1
	for lid in lanes:
		if str(lid).begins_with("turn_"):
			turn_lanes += 1
	if physical_roads != 16 or junction_roads != 11 or lanes.size() != 104 or turn_lanes != 72:
		errors.append("live graph is not canonical 16-corridor/104-lane/11-node topology")
	var raw_nodes: Variant = pack.get("junctions")
	if not (raw_nodes is Array):
		errors.append("junctions is not an array")
		return false
	var nodes: Array = raw_nodes
	var seen_nodes: Dictionary = {}
	var seen_travel: Dictionary = {}
	var seen_turn: Dictionary = {}
	var controlled := 0
	var travel_count := 0
	for value in nodes:
		if not (value is Dictionary):
			errors.append("junction is not an object")
			continue
		var j: Dictionary = value
		var jid: String = str(j.get("id", ""))
		if jid.is_empty() or seen_nodes.has(jid):
			errors.append("duplicate/empty junction id " + jid)
			continue
		seen_nodes[jid] = true
		if not roads.has(jid) or not jid.begins_with("junction_"):
			errors.append("unknown physical junction " + jid)
			continue
		var mode: String = str(j.get("mode", ""))
		if not ["stop", "yield", "pass_through"].has(mode):
			errors.append("incompatible junction mode at " + jid)
			continue
		var incoming_value: Variant = j.get("incoming_lane_ids")
		var turns_value: Variant = j.get("turn_lane_ids")
		var outgoing_value: Variant = j.get("outgoing_lane_ids")
		if not (incoming_value is Array) or not (turns_value is Array) or not (outgoing_value is Array):
			errors.append(jid + " must have incoming/turn/outgoing arrays")
			continue
		var incoming: Array = incoming_value
		var turns: Array = turns_value
		var outgoing: Array = outgoing_value
		if incoming.is_empty() or turns.is_empty() or outgoing.is_empty() or not _unique(incoming) or not _unique(turns) or not _unique(outgoing):
			errors.append(jid + " invalid/duplicate/empty lane lists")
			continue
		if not _same_ids(turns, roads[jid]["lane_ids"]):
			errors.append(jid + " connector inventory differs from canonical world")
		var derived_sources: Array = []
		var derived_targets: Array = []
		var shortest: float = INF
		for turn_id in turns:
			if not lanes.has(turn_id):
				errors.append(jid + " nonexistent turn " + str(turn_id))
				continue
			var turn: Dictionary = lanes[turn_id]
			if str(turn["road_id"]) != jid or seen_turn.has(turn_id):
				errors.append(jid + " foreign/duplicate turn " + str(turn_id))
			seen_turn[turn_id] = true
			shortest = minf(shortest, float(turn["length"]))
			var targets: Array = turn["next_lane_ids"]
			if targets.size() != 1 or not lanes.has(targets[0]):
				errors.append(jid + " unreachable outbound turn " + str(turn_id))
			elif not derived_targets.has(targets[0]):
				derived_targets.append(targets[0])
			var sources: Array = []
			for source_id in lanes:
				if lanes[source_id]["next_lane_ids"].has(turn_id):
					sources.append(source_id)
			if sources.size() != 1 or str(sources[0]).begins_with("turn_"):
				errors.append(jid + " unreachable/multiply sourced turn " + str(turn_id))
			elif not derived_sources.has(sources[0]):
				derived_sources.append(sources[0])
		if not _same_ids(incoming, derived_sources) or not _same_ids(outgoing, derived_targets):
			errors.append(jid + " incorrect incoming/outgoing lane mapping")
		for lid in incoming:
			if not lanes.has(lid):
				errors.append(jid + " nonexistent inbound lane " + str(lid))
				continue
			if seen_travel.has(lid):
				errors.append("duplicate incoming lane mapping " + str(lid))
			seen_travel[lid] = jid
			travel_count += 1
			if mapping.has(lid):
				errors.append("incoming lane " + str(lid) + " already reserved by " + str(mapping[lid]))
			for next_id in lanes[lid]["next_lane_ids"]:
				if not turns.has(next_id):
					errors.append(jid + " inbound has nonlocal turn " + str(next_id))
		if mode == "pass_through":
			if incoming.size() != 2 or turns.size() != 2:
				errors.append(jid + " pass_through is not a two-way continuation")
		else:
			controlled += 1
			if incoming.size() < 2 or turns.size() < 2 or groups.has(jid):
				errors.append(jid + " duplicate/invalid controlled intersection")
			if not _finite(j.get("clearance_m")):
				errors.append(jid + " clearance is nonnumeric")
			else:
				var clearance: float = float(j["clearance_m"])
				if clearance < 4.0 or clearance >= shortest - 0.5:
					errors.append(jid + " clearance can be clamped or never released on shortest turn")
			if mode == "stop" and (not _finite(j.get("stop_s")) or float(j.get("stop_s", 0)) <= 0.0):
				errors.append(jid + " stop must have positive stop_s")
	if nodes.size() != 11 or seen_nodes.size() != 11 or seen_turn.size() != 72 or controlled != 8:
		errors.append("missing/extra physical junctions, turns, or runtime controls")
	# Existing merge reservations map turn connectors, not approach travel lanes.
	var incoming_to: Dictionary = {}
	for lid in lanes:
		for next_id in lanes[lid]["next_lane_ids"]:
			if not incoming_to.has(next_id):
				incoming_to[next_id] = []
			incoming_to[next_id].append(lid)
	var implicit := 0
	for successor in incoming_to:
		var parents: Array = incoming_to[successor]
		if parents.size() < 2:
			continue
		implicit += 1
		var mid: String = "merge:%s" % str(successor)
		if not groups.has(mid):
			errors.append("missing implicit merge group " + mid)
		for parent in parents:
			if mapping.get(parent, "") != mid:
				errors.append("incorrect implicit merge lane mapping " + str(parent))
	if implicit != 22:
		errors.append("unexpected implicit merge topology: " + str(implicit))
	report = {"physical_junctions": seen_nodes.size(), "explicit_controls": controlled,
		"incoming_travel_lanes": travel_count, "turn_connectors": seen_turn.size(),
		"implicit_merges": implicit, "error_count": errors.size()}
	return errors.is_empty()


func _unique(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if not (value is String) or value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true


func _same_ids(a: Array, b: Array) -> bool:
	if a.size() != b.size() or not _unique(a) or not _unique(b):
		return false
	for value in a:
		if not b.has(value):
			return false
	return true


func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
