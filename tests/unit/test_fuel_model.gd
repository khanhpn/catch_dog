extends "res://tests/test_case.gd"


const FuelModelRule = preload("res://src/vehicle/fuel_model.gd")


func test_refill_clamps_and_low_fuel_reduces_speed() -> void:
	var fuel := FuelModelRule.new(100.0, 1.0, 4.0)
	fuel.consume(10.0, 1.0)
	check(is_equal_approx(fuel.amount, 60.0), "Full throttle consumption must use the throttle rate")
	check(fuel.top_speed_scale() < 1.0, "Fuel below capacity must reduce top speed")
	fuel.refill(35.0)
	check(is_equal_approx(fuel.amount, 95.0), "Refilling must increase fuel by the requested amount")


func test_fuel_amount_stays_within_capacity() -> void:
	var fuel := FuelModelRule.new(100.0, 1.0, 4.0)
	fuel.consume(100.0, 1.0)
	check(is_equal_approx(fuel.amount, 0.0), "Consumption must not reduce fuel below zero")
	fuel.refill(150.0)
	check(is_equal_approx(fuel.amount, 100.0), "Refilling must not exceed capacity")
