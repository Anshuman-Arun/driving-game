extends SceneTree
## Run from an integration worktree containing the read-only World PR #3 graph,
## Traffic PR #4 module, and Traffic Content PR #22 controls:
## godot --headless --path . --script res://modules/traffic/tests/run_junction_safety.gd
## This suite deliberately does NOT count cars passing on separate opposing
## directed travel lanes as a junction collision.
const TrafficSimulation = preload("../src/traffic_simulation.gd")
const GRAPH_PATH := "res://data/world/road_graph_v1.json"
const CONTROLS_PATH := "res://content/traffic/controls_v1.json"
const COMPLEX := ["junction_alder", "junction_cedar", "junction_ridge",
    "junction_valley", "junction_lake", "junction_pine"]
const DT := 1.0 / 30.0

var passed := 0
var failed := 0
var world: Dictionary = {}
var controls: Array = []


func _initialize() -> void:
    call_deferred("_run")


func _check(ok: bool, message: String) -> void:
    if ok:
        passed += 1
        print("PASS ", message)
    else:
        failed += 1
        printerr("FAIL ", message)


func _read(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        printerr("Missing read-only canonical dependency: ", path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


func _simulation(seed_value: int):
    var sim = TrafficSimulation.new()
    if not sim.load_road_graph(world):
        printerr("World graph invalid: ", sim.graph.errors)
        return null
    if not sim.configure_junctions(controls):
        printerr("Junction configuration rejected")
        return null
    sim.reset(seed_value)
    sim.set_density(0)
    return sim


func _run() -> void:
    world = _read(GRAPH_PATH)
    var pack: Dictionary = _read(CONTROLS_PATH)
    if world.is_empty() or pack.is_empty():
        quit(2)
        return
    for raw in pack.get("junctions", []):
        if not ["yield", "stop"].has(str(raw.get("mode", ""))):
            continue
        var entry: Dictionary = {
            "id": raw["id"], "incoming_lane_ids": raw["incoming_lane_ids"],
            "mode": raw["mode"], "clearance_m": raw["clearance_m"]}
        if raw["mode"] == "stop":
            entry["stop_s"] = raw["stop_s"]
        controls.append(entry)
    var sim = _simulation(20261121)
    if sim == null:
        quit(2)
        return
    _check(sim.junctions.size() == 30, "canonical eight controls plus 22 implicit merges")
    _test_geometry(sim)
    _test_short_connector(sim)
    _test_nonconflicting_turns()
    _test_opposing_flow()
    _test_cleanup()
    _test_stop_dwell_during_conflict()
    _test_cost_weighted_turn_choice()
    for jid in COMPLEX:
        _test_conflicting_movements(str(jid))
    _test_seeded_flow()
    print("JUNCTION SAFETY: %d pass / %d fail" % [passed, failed])
    quit(0 if failed == 0 else 1)


func _incoming(sim, junction_id: String, turn_id: String) -> String:
    for lane_id in sim.junctions[junction_id]["inbound"]:
        if sim.graph.lanes[lane_id]["next_lane_ids"].has(turn_id):
            return str(lane_id)
    return ""


func _pick_conflicting_pair(sim, junction_id: String) -> Array[String]:
    var turns: Array[String] = []
    for movement in sim.movement_junction:
        if sim.movement_junction[movement] == junction_id:
            turns.append(str(movement))
    turns.sort()
    var best: Array[String] = []
    var best_distance := -1.0
    for i in range(turns.size()):
        for j in range(i + 1, turns.size()):
            var first: String = turns[i]
            var second: String = turns[j]
            if not sim.movement_conflicts[first].has(second):
                continue
            if _incoming(sim, junction_id, first) == _incoming(sim, junction_id, second):
                continue
            var score: float = maxf(float(sim.movement_release[first]), float(sim.movement_release[second]))
            if score > best_distance:
                best_distance = score
                best = [first, second]
    return best


func _test_geometry(sim) -> void:
    for jid in COMPLEX:
        var pair: Array[String] = _pick_conflicting_pair(sim, str(jid))
        _check(pair.size() == 2, str(jid) + " has genuine conflicting approach turns")
        var max_release := 0.0
        var min_length := INF
        for movement in sim.movement_junction:
            if sim.movement_junction[movement] != jid:
                continue
            max_release = maxf(max_release, float(sim.movement_release[movement]))
            min_length = minf(min_length, sim.graph.lane_length(str(movement)))
        _check(max_release > float(sim.junctions[jid]["clearance_m"]) + 12.0,
            str(jid) + " uses late geometric conflicts, not shared clearance")
        _check(min_length < max_release, str(jid) + " preserves short connector exits")
    _check(sim.movement_junction.size() == 66, "all 66 controlled World turning movements indexed")
    _check(sim.inbound_stop_offsets.size() == 26, "26 authored approach stop lines indexed")
    for jid in COMPLEX:
        var clear := true
        var offsets_vary := false
        var first_offset := -1.0
        for incoming in sim.junctions[jid]["inbound"]:
            var approach: String = str(incoming)
            var stop_m: float = float(sim.inbound_stop_offsets[approach])
            offsets_vary = offsets_vary or first_offset >= 0.0 and absf(stop_m - first_offset) > 0.1
            first_offset = stop_m
            var position: Vector3 = sim.graph.get_pose(approach,
                sim.graph.lane_length(approach) - stop_m)["position"]
            for movement in sim.movement_junction:
                if sim.movement_junction[movement] == jid and sim._near_movement(position, str(movement)):
                    clear = false
        _check(clear, str(jid) + " every waiting stop line lies outside swept turns")
        if jid == "junction_alder":
            _check(offsets_vary, "Alder approach stop positions adapt independently")


func _spawn_routed(sim, junction_id: String, turn_id: String) -> int:
    var incoming: String = _incoming(sim, junction_id, turn_id)
    if incoming == "":
        return -1
    for offset in [27.0, 34.0, 45.0, 57.0]:
        var s: float = maxf(0.1, sim.graph.lane_length(incoming) - offset)
        var id: int = sim.spawn_agent(incoming, s, 0.0, 1.0)
        if id <= 0:
            continue
        var outgoing: String = str(sim.graph.lanes[turn_id]["next_lane_ids"][0])
        var route: Array[String] = [incoming, turn_id, outgoing]
        if not sim.assign_route(id, route):
            sim.despawn_agent(id)
            return -1
        return id
    return -1


func _test_conflicting_movements(junction_id: String) -> void:
    var sim = _simulation(73)
    if sim == null:
        _check(false, junction_id + " setup")
        return
    var pair: Array[String] = _pick_conflicting_pair(sim, junction_id)
    if pair.size() != 2:
        _check(false, junction_id + " pair")
        return
    var first: int = _spawn_routed(sim, junction_id, pair[0])
    var second: int = _spawn_routed(sim, junction_id, pair[1])
    _check(first > 0 and second > 0, junction_id + " both approach vehicles spawn")
    if first <= 0 or second <= 0:
        return
    var viewer: Vector3 = sim.graph.get_pose(pair[0], 0.0)["position"]
    var visited_first := false
    var visited_second := false
    var conflicting_ownership := false
    var overlapping_turns := false
    var early_release := false
    var released_first := false
    var released_second := false
    var exit_first: String = str(sim.graph.lanes[pair[0]]["next_lane_ids"][0])
    var exit_second: String = str(sim.graph.lanes[pair[1]]["next_lane_ids"][0])
    for _tick in range(1800):
        sim.step(DT, viewer)
        var a: Dictionary = sim.get_state(first)
        var b: Dictionary = sim.get_state(second)
        if a.is_empty() or b.is_empty():
            break
        visited_first = visited_first or a["lane_id"] == pair[0]
        visited_second = visited_second or b["lane_id"] == pair[1]
        var in_a: bool = a["lane_id"] == pair[0]
        var in_b: bool = b["lane_id"] == pair[1]
        if a["reservation_zone"] == junction_id and b["reservation_zone"] == junction_id:
            # Both may hold distinct reservation keys once the first has
            # passed this pair's last shared crossing, even while finishing
            # other conflicts. Check *actual* unsafe overlapping ownership.
            var first_progress: float = sim._movement_progress(a, pair[0])
            var second_progress: float = sim._movement_progress(b, pair[1])
            if first_progress < float(sim.movement_pair_release[pair[0]][pair[1]]) and (
                    second_progress < float(sim.movement_pair_release[pair[1]][pair[0]])):
                conflicting_ownership = true
        if (in_a or in_b) and a["position"].distance_to(b["position"]) < 3.6:
            overlapping_turns = true
        if in_a and a["reserved_junction"] == "":
            early_release = true
        if in_b and b["reserved_junction"] == "":
            early_release = true
        released_first = released_first or a["lane_id"] == exit_first and a["reserved_junction"] == ""
        released_second = released_second or b["lane_id"] == exit_second and b["reserved_junction"] == ""
        if released_first and released_second:
            break
    _check(visited_first and visited_second, junction_id + " both routes traverse a turn")
    _check(not conflicting_ownership, junction_id + " conflicting turns never own overlapping unsafe conflict intervals")
    _check(not overlapping_turns, junction_id + " overlapping turn occupancy excluded")
    _check(not early_release, junction_id + " turn ownership retained until geometric release")
    _check(released_first and released_second, junction_id + " both vehicles reach their outgoing lanes")
    _check(sim.reservations.is_empty(), junction_id + " no reservation stranded after connector exit")


func _test_short_connector(sim) -> void:
    var found := false
    for movement in sim.movement_release:
        var turn_id: String = str(movement)
        var len_m: float = sim.graph.lane_length(turn_id)
        if len_m >= 20.0 or float(sim.movement_release[movement]) <= len_m:
            continue
        var jid: String = str(sim.movement_junction[movement])
        var point: Dictionary = sim._reservation_exit(
            {"next_lane": turn_id}, jid, sim.junctions[jid])
        found = point["lane"] != turn_id and float(point["s"]) > 0.0 and (
            float(point["s"]) < sim.graph.lane_length(str(point["lane"])))
        if found:
            break
    _check(found, "short turn releases on successor travel lane rather than leaking")


func _test_nonconflicting_turns() -> void:
    var sim = _simulation(9)
    if sim == null:
        _check(false, "nonconflicting fixture setup")
        return
    var independent: Array[String] = []
    var turns: Array[String] = []
    for turn_id in sim.movement_junction:
        if sim.movement_junction[turn_id] == "junction_alder":
            turns.append(str(turn_id))
    turns.sort()
    for i in range(turns.size()):
        if independent.size() == 2:
            break
        for j in range(i + 1, turns.size()):
            if not sim.movement_conflicts[turns[i]].has(turns[j]) and (
                    _incoming(sim, "junction_alder", turns[i]) !=
                    _incoming(sim, "junction_alder", turns[j])):
                independent = [turns[i], turns[j]]
                break
    _check(independent.size() == 2, "real Alder network includes independent turn movements")
    if independent.size() != 2:
        return
    var first: int = _spawn_routed(sim, "junction_alder", independent[0])
    var second: int = _spawn_routed(sim, "junction_alder", independent[1])
    _check(first > 0 and second > 0, "independent approach agents can spawn")
    if first <= 0 or second <= 0:
        return
    sim.agents[first]["reservation_zone"] = "junction_alder"
    sim.agents[first]["reservation_movement"] = independent[0]
    sim.agents[first]["reserved_junction"] = "junction_alder@%d" % first
    sim.reservations[sim.agents[first]["reserved_junction"]] = first
    sim.agents[second]["stop_done"] = true
    _check(not sim._junction_blocked(sim.agents[second], "junction_alder",
        sim.junctions["junction_alder"]), "independent movements are not serialized unnecessarily")
    sim.despawn_agent(first)
    _check(sim.reservations.is_empty(), "independent movement ownership cleans up")


func _test_opposing_flow() -> void:
    var sim = _simulation(21)
    if sim == null:
        _check(false, "opposing flow setup")
        return
    var ab := "lane_orchard_lake_ab"
    var ba := "lane_orchard_lake_ba"
    var len_m: float = sim.graph.lane_length(ab)
    var a: int = sim.spawn_agent(ab, len_m * 0.40, 12.0, 1.0)
    var b: int = sim.spawn_agent(ba, sim.graph.lane_length(ba) * 0.40, 12.0, 1.0)
    _check(a > 0 and b > 0, "ordinary opposing-lane cars can spawn")
    if a <= 0 or b <= 0:
        return
    var viewer: Vector3 = sim.graph.get_pose(ab, len_m * 0.5)["position"]
    var passing := false
    var blocked := false
    for _tick in range(480):
        sim.step(DT, viewer)
        var one: Dictionary = sim.get_state(a)
        var two: Dictionary = sim.get_state(b)
        if one.is_empty() or two.is_empty():
            break
        if one["lane_id"] != ab or two["lane_id"] != ba:
            break
        var d: float = one["position"].distance_to(two["position"])
        if d < 3.6 and d > 2.0 and one["speed_mps"] > 0.5 and two["speed_mps"] > 0.5:
            passing = true
        blocked = blocked or one["reserved_junction"] != "" or two["reserved_junction"] != ""
    _check(passing, "3.4m-separated opposing travel lanes pass without collision classification")
    _check(not blocked, "two-way passing needs no intersection reservation")


func _test_cleanup() -> void:
    var sim = _simulation(18)
    if sim == null:
        _check(false, "cleanup setup")
        return
    var pair: Array[String] = _pick_conflicting_pair(sim, "junction_alder")
    var id: int = _spawn_routed(sim, "junction_alder", pair[0])
    var held := false
    for _tick in range(480):
        sim.step(DT, sim.graph.get_pose(pair[0], 0.0)["position"])
        var state: Dictionary = sim.get_state(id)
        if state.is_empty():
            break
        if state["reserved_junction"] != "":
            held = true
            break
    _check(held and not sim.reservations.is_empty(), "cleanup fixture acquires movement reservation")
    sim.despawn_agent(id)
    _check(sim.reservations.is_empty(), "despawn releases the exact owned reservation")
    id = _spawn_routed(sim, "junction_alder", pair[0])
    for _tick in range(450):
        sim.step(DT, sim.graph.get_pose(pair[0], 0.0)["position"])
        if not sim.get_state(id).is_empty() and sim.get_state(id)["reserved_junction"] != "":
            break
    sim.reset(18)
    _check(sim.reservations.is_empty() and sim.agents.is_empty(), "reset removes all reservation ownership")


func _test_stop_dwell_during_conflict() -> void:
    var sim = _simulation(18)
    if sim == null:
        _check(false, "stop dwell fixture setup")
        return
    var jid := "junction_alder"
    var pair: Array[String] = _pick_conflicting_pair(sim, jid)
    if pair.size() != 2:
        _check(false, "stop dwell fixture uses conflicting turns")
        return
    var first: int = _spawn_routed(sim, jid, pair[0])
    var second: int = _spawn_routed(sim, jid, pair[1])
    if first <= 0 or second <= 0:
        _check(false, "stop dwell fixture spawns both approaches")
        return
    var owner: Dictionary = sim.agents[first]
    var waiting: Dictionary = sim.agents[second]
    var key := "%s@%d" % [jid, first]
    owner["reservation_zone"] = jid
    owner["reservation_movement"] = pair[0]
    owner["reserved_junction"] = key
    sim.reservations[key] = first
    var lane: String = waiting["lane_id"]
    waiting["s"] = sim.graph.lane_length(lane) - float(sim.inbound_stop_offsets[lane])
    waiting["speed_mps"] = 0.0
    var control: Dictionary = sim.junctions[jid]
    var blocked := true
    for i in range(ceili(float(control["stop_s"]) / DT) + 2):
        blocked = sim._junction_blocked(waiting, jid, control) and blocked
    _check(blocked, "stopped car cannot enter while a conflicting reservation is held")
    _check(bool(waiting["stop_done"]), "mandatory stop dwell accrues while yielding")
    sim.despawn_agent(first)
    _check(not sim._junction_blocked(waiting, jid, control),
        "completed dwell permits immediate grant only after conflict release")
    waiting["stop_done"] = false
    waiting["wait_s"] = float(control["stop_s"]) - DT * 0.5
    waiting["speed_mps"] = 1.0
    _check(sim._junction_blocked(waiting, jid, control) and float(waiting["wait_s"]) == 0.0,
        "rolling before completing dwell resets the stop timer")


func _test_cost_weighted_turn_choice() -> void:
    var sim = _simulation(81)
    if sim == null:
        _check(false, "cost-weighted turn fixture setup")
        return
    var options: Array = sim.graph.lanes["lane_alder_market_ba"]["next_lane_ids"]
    var counts: Dictionary = {}
    for i in range(1600):
        var chosen: String = sim._choose_next(options)
        counts[chosen] = int(counts.get(chosen, 0)) + 1
    _check(counts.size() == options.size(), "all legal authored turns remain selectable")
    var short := "turn_alder_alder_market_ba__alder_cedar_ab"
    var long := "turn_alder_alder_market_ba__chapel_alder_ba"
    _check(int(counts.get(short, 0)) > 2 * int(counts.get(long, 0)),
        "spontaneous route selection favors lower traversal cost")
    var id: int = _spawn_routed(sim, "junction_alder", long)
    _check(id > 0 and sim.get_state(id).get("next_lane", "") == long,
        "explicit routing can still select long connector")


func _seed_trace(seed_value: int) -> Dictionary:
    var sim = _simulation(seed_value)
    if sim == null:
        return {"ok": false, "trace": ""}
    sim.set_density(20)
    var viewer: Vector3 = sim.graph.get_pose("turn_alder_alder_cedar_ba__alder_depot_ab", 0.0)["position"]
    var fingerprint: int = 1
    var peak := 0
    var transitions := 0
    var previous: Dictionary = {}
    var safe := true
    var wait_ticks: Dictionary = {}
    var longest_wait := 0
    var longest_wait_context: Dictionary = {}
    for _tick in range(1350):
        sim.step(DT, viewer)
        var states: Array = sim.get_states()
        peak = maxi(peak, states.size())
        if states.size() > 20:
            safe = false
        var now: Dictionary = {}
        for a in states:
            var aid: int = int(a["id"])
            now[aid] = a["lane_id"]
            if previous.has(aid) and previous[aid] != a["lane_id"]:
                transitions += 1
            if a["reserved_junction"] != "" and int(sim.reservations.get(a["reserved_junction"], -1)) != aid:
                safe = false
            var snap: String = "%s:%s:%.3f:%s" % [aid, a["lane_id"], float(a["s"]), a["reserved_junction"]]
            fingerprint = posmod(fingerprint * 131 + int(snap.hash()), 2147483647)
            if a["state"] == "WAIT_AT_JUNCTION":
                wait_ticks[aid] = int(wait_ticks.get(aid, 0)) + 1
                if int(wait_ticks[aid]) > longest_wait:
                    longest_wait = int(wait_ticks[aid])
                    var owner_states: Array[Dictionary] = []
                    for owner_id in sim.reservations.values():
                        var owner: Dictionary = sim.agents.get(owner_id, {})
                        if owner.is_empty():
                            continue
                        var movement: String = str(owner["reservation_movement"])
                        owner_states.append({"id": owner_id, "lane": owner["lane_id"],
                            "s": owner["s"], "speed": owner["speed_mps"], "movement": movement,
                            "release_lane": owner["entered_lane"], "release_s": owner["clearance_m"]})
                    longest_wait_context = {"agent": aid, "lane": a["lane_id"],
                        "s": a["s"], "speed": a["speed_mps"], "next": a["next_lane"],
                        "stop_done": sim.agents[aid]["stop_done"], "tick": _tick,
                        "owners": owner_states}
            else:
                wait_ticks.erase(aid)
        previous = now
        var keys: Array = sim.reservations.keys()
        for i in range(keys.size()):
            var first_owner: int = int(sim.reservations[keys[i]])
            if not sim.agents.has(first_owner):
                safe = false
                continue
            var first: Dictionary = sim.agents[first_owner]
            for j in range(i + 1, keys.size()):
                var second_owner: int = int(sim.reservations[keys[j]])
                if not sim.agents.has(second_owner):
                    safe = false
                    continue
                var second: Dictionary = sim.agents[second_owner]
                if first["reservation_zone"] == second["reservation_zone"] and first["reservation_zone"] != "":
                    var movement: String = str(first["reservation_movement"])
                    var other_movement: String = str(second["reservation_movement"])
                    if movement == other_movement:
                        # Multiple following cars may own entrance keys after
                        # 12m headway; inspect their real lane clearance.
                        if first["lane_id"] == second["lane_id"] and (
                                absf(float(first["s"]) - float(second["s"])) < sim.MIN_GAP_M - 0.05):
                            safe = false
                    elif sim.movement_conflicts.has(movement) and (
                            sim.movement_conflicts[movement].has(other_movement)):
                        if sim._movement_progress(first, movement) < float(
                                sim.movement_pair_release[movement][other_movement]) and (
                                sim._movement_progress(second, other_movement) < float(
                                sim.movement_pair_release[other_movement][movement])):
                            safe = false
    return {"ok": safe and peak > 0 and transitions > 0 and longest_wait < 900,
        "trace": fingerprint,
        "peak": peak, "transitions": transitions, "safe": safe, "longest_wait_ticks": longest_wait, "longest_wait_context": longest_wait_context}


func _test_seeded_flow() -> void:
    for seed_value in [20261121, 73]:
        var a: Dictionary = _seed_trace(seed_value)
        var b: Dictionary = _seed_trace(seed_value)
        print("CANONICAL FLOW seed=", seed_value, " first=", a, " replay=", b)
        _check(bool(a["ok"]) and bool(b["ok"]), "45-second canonical flow/cap/conflicts/queues seed %d" % seed_value)
        _check(a["trace"] == b["trace"], "45-second fixed-seed replay identical %d" % seed_value)
