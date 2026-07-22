class_name DogCatalog
extends Resource


const DogStatsResource = preload("res://src/dogs/dog_stats.gd")


var dogs: Array[Resource] = [
	DogStatsResource.new(&"street_dog", 10, 55.0, 0.85),
	DogStatsResource.new(&"corgi", 25, 25.0, 0.95),
	DogStatsResource.new(&"golden_retriever", 40, 13.0, 1.05),
	DogStatsResource.new(&"shiba_inu", 50, 7.0, 1.15),
]
