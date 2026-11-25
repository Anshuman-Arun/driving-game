extends RefCounted
## Garage identities and presentation statistics.
## Production handling parameters stay with the vehicle physics module.

const CARS := [
	{"id":"aventador_svj", "name":"AVENTADOR SVJ", "class":"LAMBORGHINI", "tagline":"Naturally aspirated V12 · All-wheel drive", "power_hp":759, "mass_kg":1670, "top_kph":350, "handling":89, "braking":92, "accent":"#f5b657", "unlock":"FREE ROAM"},
	{"id":"mclaren_senna", "name":"McLAREN SENNA", "class":"McLAREN", "tagline":"Twin-turbo V8 · Rear-wheel drive", "power_hp":789, "mass_kg":1380, "top_kph":335, "handling":97, "braking":98, "accent":"#78c2f0", "unlock":"FREE ROAM"},
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
	var ids: Array[String] = []
	for item in CARS:
		ids.append(item["id"])
	return ids

static func event_ids() -> Array[String]:
	return ["alder_circuit", "ridge_climb", "eastwater_dash", "aster_tour"]

static func car_name(car_id: String) -> String:
	return str(car(car_id).get("name", "UNKNOWN VEHICLE"))
