extends "res://tests/test_case.gd"


const DogCatalogRule = preload("res://src/dogs/dog_catalog.gd")
const WeightedPickerRule = preload("res://src/dogs/weighted_picker.gd")


func test_weight_boundaries() -> void:
	var weights := PackedFloat32Array([55.0, 25.0, 13.0, 7.0])
	check(WeightedPickerRule.pick_index(weights, 0.00) == 0, "A zero roll must select the first weight")
	check(WeightedPickerRule.pick_index(weights, 0.55) == 1, "The 55 percent boundary must select index 1")
	check(WeightedPickerRule.pick_index(weights, 0.80) == 2, "The 80 percent boundary must select index 2")
	check(WeightedPickerRule.pick_index(weights, 0.93) == 3, "The 93 percent boundary must select index 3")


func test_dog_catalog_uses_required_data() -> void:
	var catalog := DogCatalogRule.new()
	var dogs: Array = catalog.get("dogs") as Array
	check(dogs.size() == 4, "Dog catalog must contain four dogs")
	var expected: Array[Dictionary] = [
		{"id": &"street_dog", "score": 10, "weight": 55.0, "speed": 0.85},
		{"id": &"corgi", "score": 25, "weight": 25.0, "speed": 0.95},
		{"id": &"golden_retriever", "score": 40, "weight": 13.0, "speed": 1.05},
		{"id": &"shiba_inu", "score": 50, "weight": 7.0, "speed": 1.15},
	]
	for index in mini(dogs.size(), expected.size()):
		var dog: Resource = dogs[index] as Resource
		var values := expected[index]
		check(dog.get("id") == values.id, "Dog id must match the required catalog order")
		check(dog.get("score") == values.score, "Dog score must match the required catalog data")
		check(is_equal_approx(dog.get("weight"), values.weight), "Dog weight must match the required catalog data")
		check(is_equal_approx(dog.get("run_speed_multiplier"), values.speed), "Dog speed must match the required catalog data")
