class_name Obstacle
extends Node2D
## A solid world object fighters cannot walk through.
##
## The node origin is the object's ground contact point (its base); sprites
## are children with an offset so the art rises above that point. The
## footprint is a ground-plane rectangle in local coordinates, relative to
## the origin. Lives in the "obstacles" group so movement, AI steering and
## spawn avoidance can all find it.

@export var footprint := Rect2(-6, -3, 12, 6)
@export var solid := true


func _ready() -> void:
	add_to_group("obstacles")


## The footprint in global coordinates.
func get_blocker_rect() -> Rect2:
	return Rect2(global_position + footprint.position, footprint.size)
