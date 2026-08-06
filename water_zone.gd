# water_zone.gd — Reusable Area3D that applies a movement multiplier to the player.

extends Area3D

signal player_splashed(origin: Vector3)

@export_range(0.05, 1.0, 0.05) var speed_multiplier: float = 0.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_water_zone"):
		body.call("enter_water_zone", self, speed_multiplier)
		player_splashed.emit(body.global_position)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_water_zone"):
		body.call("exit_water_zone", self)
