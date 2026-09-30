class_name BeachBarService
extends Node3D

signal meal_requested

var bar_name := ""


func _ready() -> void:
	add_to_group("interiors")


func try_interact(player: PlayerController) -> bool:
	if player.driving_vehicle != null or player.global_position.distance_to(global_position) >= 2.6:
		return false
	meal_requested.emit()
	return true
