extends Node3D

var acquired_count: int = 0
var released_count: int = 0

func on_pool_acquired() -> void:
	acquired_count += 1

func on_pool_released() -> void:
	released_count += 1
