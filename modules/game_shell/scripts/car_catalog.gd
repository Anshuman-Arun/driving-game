extends RefCounted
## Fictional car identities and mock-only presentation statistics.
## Production handling parameters stay with the vehicle physics module.

const CARS := [
	{"id":"vela_gt", "name":"VELA GT", "class":"GRAND TOURER", "tagline":"Balanced rear-drive precision", "power_hp":315, "mass_kg":1430, "top_kph":245, "handling":78, "braking":76, "accent":"#f2ae65", "unlock":"STARTER"},
	{"id":"orion_rs", "name":"ORION RS", "class":"LIGHTWEIGHT SPORT", "tagline":"Built for the switchbacks", "power_hp":278, "mass_kg":1190, "top_kph":228, "handling":93, "braking":87, "accent":"#72d5c1", "unlock":"COMPLETE 1 EVENT"},
	{"id":"kestrel_xr", "name":"KESTREL XR", "class":"TRACK-FOCUSED COUPE", "tagline":"Power with a sharp edge", "power_hp":462, "mass_kg":1540, "top_kph":285, "handling":84, "braking":90, "accent":"#a7abf5", "unlock":"COMPLETE 3 DISTINCT EVENTS"}
]

## Mock durations are deliberately short for demonstration, NOT real course records.
const EVENTS := [
	{"id":"alder_circuit", "name":"ALDER STREET CIRCUIT", "region":"Alder Town", "kind":"CIRCUIT", "laps":3, "mock_duration":24.0, "distance":"~1.5 km/lap"},
	{"id":"ridge_climb", "name":"NORTH RIDGE CLIMB", "region":"North Ridge", "kind":"SPRINT", "laps":1, "mock_duration":19.0, "distance":"~2.3 km"},
	{"id":"eastwater_dash", "name":"EASTWATER DASH", "region":"Eastwater Lake", "kind":"SPRINT", "laps":1, "mock_duration":17.0, "distance":"~2.0 km"},
	{"id":"aster_tour", "name":"ASTER TOUR", "region":"Valley + ridge", "kind":"CIRCUIT", "laps":2, "mock_duration":32.0, "distance":"~4.0 km"}
]

static func car(car_id: String) -> Dictionary:
	for item in CARS:
		if item["id"] == car_id:
			return item.duplicate(true)
	return {}

static func event(event_id: String) -> Dictionary:
	for item in EVENTS:
		if item["id"] == event_id:
			return item.duplicate(true)
	return {}

static func car_ids() -> Array[String]:
	return ["vela_gt", "orion_rs", "kestrel_xr"]

static func event_ids() -> Array[String]:
	return ["alder_circuit", "ridge_climb", "eastwater_dash", "aster_tour"]

static func car_name(car_id: String) -> String:
	return str(car(car_id).get("name", "UNKNOWN VEHICLE"))
