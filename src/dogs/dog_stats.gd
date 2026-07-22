class_name DogStats
extends Resource


@export var id: StringName
@export var score: int
@export var weight: float
@export var run_speed_multiplier: float


func _init(
	_id: StringName = &"",
	_score: int = 0,
	_weight: float = 0.0,
	_run_speed_multiplier: float = 1.0,
) -> void:
	id = _id
	score = _score
	weight = _weight
	run_speed_multiplier = _run_speed_multiplier
