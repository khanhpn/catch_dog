class_name FuelModel
extends RefCounted


var capacity: float
var idle_rate: float
var throttle_rate: float
var amount: float


func _init(_capacity: float, _idle_rate: float, _throttle_rate: float) -> void:
	capacity = maxf(_capacity, 0.0)
	idle_rate = _idle_rate
	throttle_rate = _throttle_rate
	amount = capacity


func consume(delta: float, throttle: float) -> void:
	var rate := lerpf(idle_rate, throttle_rate, absf(throttle))
	amount = clampf(amount - delta * rate, 0.0, capacity)


func refill(refill_amount: float) -> void:
	amount = clampf(amount + refill_amount, 0.0, capacity)


func top_speed_scale() -> float:
	if is_zero_approx(capacity):
		return 0.35
	return lerpf(0.35, 1.0, amount / capacity)
