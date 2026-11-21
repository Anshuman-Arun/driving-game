extends Node3D
## Designer-inspectable scene entry; driving_test uses the same factory directly.
var body: Vehicle

func _ready() -> void:
	body = PlayerCarFactory.create()
	add_child(body)
