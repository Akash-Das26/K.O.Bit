extends Node2D
## Street stage: the stage image with the baked props erased, plus one real
## Obstacle node per prop that existed in it.
##
## Stage image: assets/Previews/Stage/preview_stage.png. The seven baked props
## (3 lamps, 2 bushes, the car, the sidewalk hydrant) were in-painted out of it
## by copying the same rows from a measured multiple of the local pattern
## period (sidewalk 112 px, road 224 px) - see backups/preview_stage_before_prop_swap.png
## for the untouched original.
##
## Sprites: cut out of that ORIGINAL image with the prop's own art alpha, so the
## swapped stage is pixel-identical to the original look. They live in
## assets/Stage Layers/split/ and are drawn with centered = false at the exact
## top-left match coordinate, while the node origin stays at the ground contact
## point so the y-sort against fighters keeps working.
##
##   prop        match (x, y)  sprite size  base (node origin)  footprint
##   Lamp1..3    144/528/880, 101   42x139   165/549/901, 240    12x6  solid=false
##   Bush1..2    318/1134, 172      61x68    348/1164, 240       28x6  solid=false
##   Car         397, 192           144x48   469, 228            132x12 solid
##   Hydrant     321, 110           19x36    330.5, 146          10x5  solid

## Walkable depth band for this stage. Lowered from 172 to 138 so a fighter can
## walk along the sidewalk and behind the hydrant's 10x5 footprint at y 144..149
## (a fighter at y=138..140 passes behind it, at y>=152 in front of it).
const LANE_MIN_Y := 138.0
const LANE_MAX_Y := 232.0


func _ready() -> void:
	GameState.apply_lane(LANE_MIN_Y, LANE_MAX_Y)


## Called by main_game after the stage enters the tree: reparent every prop
## Obstacle into the y-sorted Fighters node (positions are preserved).
func setup(fighters: Node2D) -> void:
	for child in get_children():
		if child is Obstacle:
			child.reparent(fighters)


## Printout used by the proof harness.
func lane_limits() -> Vector2:
	return Vector2(LANE_MIN_Y, LANE_MAX_Y)
