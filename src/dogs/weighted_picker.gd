class_name WeightedPicker
extends RefCounted


const INVALID_INDEX: int = -1


static func pick_index(weights: PackedFloat32Array, roll: float) -> int:
	if weights.is_empty():
		return INVALID_INDEX
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return INVALID_INDEX
	var cursor := clampf(roll, 0.0, 0.999999) * total
	for index in weights.size():
		cursor -= maxf(weights[index], 0.0)
		# Strict comparison advances exact cumulative boundaries into the next bucket.
		if cursor < 0.0:
			return index
	return weights.size() - 1
