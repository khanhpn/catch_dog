class_name WeightedPicker
extends RefCounted


static func pick_index(weights: PackedFloat32Array, roll: float) -> int:
	assert(not weights.is_empty())
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	var cursor := clampf(roll, 0.0, 0.999999) * total
	for index in weights.size():
		cursor -= maxf(weights[index], 0.0)
		if cursor < 0.0:
			return index
	return weights.size() - 1
