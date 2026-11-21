extends RefCounted
## Self-contained deterministic UI fixture. Never controls a real physics car.
signal changed()
signal stage_changed(stage: String)
signal race_finished(results: Dictionary)

const Catalog = preload("car_catalog.gd")
const SaveService = preload("save_service.gd")

var save: RefCounted
var speed_kph: float = 0.0
var gear: String = "1"
var travel_m: float = 0.0
var yaw: float = 0.0
var paused: bool = false
var stage: String = "FREE_ROAM"  # FREE_ROAM / COUNTDOWN / RACING / RESULTS
var event_id: String = ""
var countdown_s: float = 3.0
var race_time_s: float = 0.0
var race_position: int = 4
var lap: int = 1
var result: Dictionary = {}
var notification: String = "CRUISE THE VALLEY  ·  PRESS E TO DISCOVER A RACE"
var notification_s: float = 7.0

func _init(save_service: RefCounted = null) -> void:
	save = save_service if save_service != null else SaveService.new()
	if save_service == null:
		save.load()

func set_notice(message: String, seconds: float = 4.0) -> void:
	notification = message
	notification_s = seconds
	changed.emit()

func set_paused(value: bool) -> void:
	paused = value
	changed.emit()

func start_event(id: String) -> bool:
	if Catalog.event(id).is_empty() or (stage != "FREE_ROAM" and stage != "RESULTS"):
		return false
	event_id = id
	countdown_s = 3.0
	race_time_s = 0.0
	race_position = 4
	lap = 1
	result = {}
	speed_kph = 0.0
	gear = "1"
	stage = "COUNTDOWN"
	notification = ""
	notification_s = 0.0
	stage_changed.emit(stage)
	changed.emit()
	return true

func advance(delta: float, accelerate: float = 0.0, brake: float = 0.0, steer: float = 0.0) -> void:
	if paused or delta <= 0.0:
		return
	var remaining := minf(delta, 360.0)
	if stage == "COUNTDOWN":
		var consumed := minf(remaining, countdown_s)
		countdown_s -= consumed
		remaining -= consumed
		speed_kph = 0.0
		if countdown_s <= 0.0:
			stage = "RACING"
			stage_changed.emit(stage)
	if stage == "FREE_ROAM" or stage == "RACING":
		speed_kph = clampf(speed_kph + (accelerate * 39.0 - brake * 74.0 - 10.0) * remaining, 0.0, 245.0)
		yaw = wrapf(yaw + steer * remaining * (0.15 + speed_kph / 200.0), -PI, PI)
		travel_m += speed_kph / 3.6 * remaining
		gear = "N" if speed_kph < 0.5 else str(clampi(int(speed_kph / 42.0) + 1, 1, 6))
		if stage == "RACING":
			race_time_s += remaining
			var demo_duration: float = Catalog.event(event_id).get("mock_duration", 20.0)
			var progress := clampf(race_time_s / demo_duration, 0.0, 1.0)
			lap = mini(int(Catalog.event(event_id).get("laps", 1)), int(progress * int(Catalog.event(event_id).get("laps", 1))) + 1)
			race_position = 4 if progress < 0.2 else (3 if progress < 0.47 else (2 if progress < 0.75 else 1))
			if race_time_s >= demo_duration:
				finish_event()
	if notification_s > 0.0:
		notification_s = maxf(0.0, notification_s - delta)
	changed.emit()

func finish_event() -> bool:
	if stage != "RACING":
		return false
	var event := Catalog.event(event_id)
	var position := race_position
	var actual_time := maxf(0.01, race_time_s)
	var record: Dictionary = save.record_race(event_id, actual_time, position)
	result = {
		"event_id":event_id, "event_name":event.get("name", "RACE"),
		"time_s":actual_time, "position":position,
		"record_saved":record.get("ok", false), "reward":record.get("reward", 0),
		"new_unlocks":record.get("new_unlocks", []),
		"best_time_s":record.get("best_time_s", actual_time)
	}
	stage = "RESULTS"
	speed_kph = 0.0
	gear = "N"
	stage_changed.emit(stage)
	race_finished.emit(result.duplicate(true))
	changed.emit()
	return true

func return_to_free_roam() -> void:
	stage = "FREE_ROAM"
	event_id = ""
	race_time_s = 0.0
	countdown_s = 3.0
	result = {}
	speed_kph = 0.0
	gear = "1"
	paused = false
	set_notice("BACK IN FREE ROAM  ·  DISCOVER ANOTHER EVENT")
	stage_changed.emit(stage)

func current_car() -> Dictionary:
	return Catalog.car(save.selected_car())

func current_event() -> Dictionary:
	return Catalog.event(event_id)
