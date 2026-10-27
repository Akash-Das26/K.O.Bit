extends Node2D
## Desert stage built from assets/Tileset/00Atlas.png to match the pack's
## showcase scenes (assets/showcase/plat_show1..5.png): pale sky with a sun,
## mountain silhouettes, a dark purple rock lane band with a golden cobbled
## top edge, grass tufts and flowers on that edge, a plateau with a diagonal
## ramp down to the lane, floating islands, a carved water pit crossed by a
## bridge, and a ramp climbing to a plateau at the right world end.
##
## Tile roles (atlas id = row * 20 + col, all 16x16, nearest filter, no scaling):
##   34 platforms2    golden cobble lip + rock below       -> lane band / plateau edge
##   37 platforms4    lip variant                          -> lane band / plateau edge
##   41 platforms8    lip variant                          -> lane band / plateau edge
##   33 platforms1    lip, rounded LEFT end                -> left end caps
##   36 platforms3    lip, rounded RIGHT end               -> right end caps
##   5  tileMain5     flat dark purple rock (0 alpha)      -> base fill, deep rock
##   14/15/22/24      dark mottled purple rock             -> rock body (cobble fringe)
##   16/17/18/19      lighter mottled purple rock          -> body highlights, pillar
##   30/31/32         pebbles / stone clusters (mostly alpha) -> scattered on the floor
##   10/11            gold nuggets on dark rock            -> rare floor sparkle
##   43 platforms10   golden brick face                    -> pit walls, pillar block
##   54 platvariation9  gold band, drops 1 row per 2 cols  -> ramp down, first half
##   55 platvariation10 gold band, drops 1 row per 2 cols  -> ramp down, second half
##   56 platvariation11 gold band, rises 1 row per 2 cols  -> ramp up, first half
##   57 platvariation12 gold band, rises 1 row per 2 cols  -> ramp up, second half
##   73 water1        sparkling water surface              -> pit surface row
##   74 water2        deep water (0 transparent)           -> pit body
##   65/66/67/68      gold deck with hanging moss (bridge) -> bridge over the pit
##   75/77/78/79 grass1/3/4/5, 84/85/86 grass10/11/12      -> tufts and flowers
##
## Layers (back to front): parallax, scenery (plateaus, ramps, islands, pit),
## band_back (solid rock so the lane band is opaque), band (the visible lip +
## rock body), decor (grass, flowers, pebbles). Everything sits on the 16 px
## grid and the rock bodies fade out with depth, as in the pack's showcase.
##
## main_game calls setup() to move the rock/tree Obstacles into the y-sorted
## Fighters node.

const SKY: Texture2D = preload("res://assets/Background/BG-sky.png")
const SUN: Texture2D = preload("res://assets/Background/BG-sun.png")
const MOUNTAINS: Texture2D = preload("res://assets/Background/BG-mountains.png")
const RUINS: Texture2D = preload("res://assets/Background/BG-ruins.png")
const ATLAS: Texture2D = preload("res://assets/Tileset/00Atlas.png")
const ROCK_TEX := [
	preload("res://assets/props/rocks1.png"),
	preload("res://assets/props/rocks2.png"),
	preload("res://assets/props/rocks3.png"),
	preload("res://assets/props/rocks4.png"),
	preload("res://assets/props/rocks5.png"),
	preload("res://assets/props/rocks6.png"),
]
const TREE_TEX := {
	1: preload("res://assets/props/tree01.png"),
	2: preload("res://assets/props/tree02.png"),
	3: preload("res://assets/props/tree03.png"),
	4: preload("res://assets/props/tree04.png"),
}

const TILE := 16
const ATLAS_COLS := 20
const WORLD_W := 1200
const WORLD_TILES := 75                 # 1200 / 16
const BAND_ROW := 9                     # y=144: the golden cobble lip
const BOTTOM_ROW := 15                  # one past the last visible row (y=240)

# Lane band.
const T_EDGE := 34          # platforms2
const T_EDGE_B := 37        # platforms4
const T_EDGE_C := 41        # platforms8
const T_CAP_L := 33         # platforms1 - rounded left end
const T_CAP_R := 36         # platforms3 - rounded right end
const T_ROCK := 5           # tileMain5 - flat dark rock, no alpha (base fill)
const T_BODY := [14, 15, 22, 24]        # tileMain14/15/22/24 - dark mottled purple rock
const T_BODY_LIGHT := [16, 17, 18, 19]  # tileMain16..19 - lighter mottled purple rock
const T_PEBBLE := [30, 31, 32]          # tileMain30/31/32 - pebble overlays (mostly alpha)
const T_NUGGET := [10, 11]              # tileMain10/11 - gold nuggets on dark rock
# Scenery.
const T_GOLD_FACE := 43     # platforms10 - pit walls
const T_RAMP_DOWN_A := 54   # platvariation9
const T_RAMP_DOWN_B := 55   # platvariation10
const T_RAMP_UP_A := 56     # platvariation11
const T_RAMP_UP_B := 57     # platvariation12
const T_WATER_TOP := 73     # water1
const T_WATER := 74         # water2
const T_BRIDGE := [65, 66, 67, 68]   # bridge2..bridge5 - mossy deck
const T_PILLAR := [16, 17]  # tileMain16 / tileMain17
# Decor.
const T_GRASS := [75, 77, 78, 79]            # grass1, grass3, grass4, grass5
const T_FLOWER := [84, 85, 86]               # grass10, grass11, grass12

const DESERT_SEED := 20261026

## Set pieces along the 1200 px world (columns of 16 px, rows of 16 px).
##   [x0, x1_exclusive, top_row]
const LEDGE_L := [1, 8, 5]
##   [x0, top_row, pairs]  - 2 columns per pair, one row deeper per pair
const RAMP_L := [8, 5, 4]
##   [x0, x1_exclusive, row]  - floating islands
const ISLAND_A := [24, 30, 5]
const ISLAND_B := [34, 37, 6]
##   column of the decorative purple pillar with a golden block on top
const PILLAR_COL := 38
const PILLAR_TOP := 5
##   [x0, x1_exclusive, top_row, hole_x0, hole_x1_exclusive]
const PIT := [44, 65, 6, 50, 58]
##   [x0, start_row, pairs]  - climbing ramp, one row higher per pair
const RAMP_R := [66, 8, 3]
##   [x0, x1_exclusive, top_row]
const LEDGE_R := [71, 75, 6]

# Fixed seeded placements: [texture index 1..6, base position].
const ROCKS := [
	[2, Vector2(516, 218.1)],
	[4, Vector2(795.3, 206.9)],
	[3, Vector2(125.8, 224.8)],
	[2, Vector2(1089.2, 217.4)],
	[3, Vector2(738.5, 180.1)],
	[4, Vector2(691.6, 180.5)],
	[1, Vector2(1136, 226.2)],
	[1, Vector2(705, 225.7)],
	[1, Vector2(563.8, 211.3)],
]
const ROCK_FOOTPRINT := Rect2(-13, -3, 26, 6)
const ROCK_SCALE := 2.0

const TREES := [
	[2, Vector2(475.3, 189.5)],
	[4, Vector2(281.4, 210.8)],
	[1, Vector2(936.8, 193.2)],
	[3, Vector2(786.1, 156.4)],
	[1, Vector2(187.9, 157.5)],
	[2, Vector2(375.6, 159.5)],
]
const TREE_FOOTPRINT := Rect2(-6, -3, 12, 6)
const TREE_TRUNK := {
	1: Vector2(18, 64),
	2: Vector2(22, 64),
	3: Vector2(18, 48),
	4: Vector2(31, 80),
}

var _scenery: TileMapLayer
var _band_back: TileMapLayer
var _band: TileMapLayer
var _decor: TileMapLayer
## Highest scenery row placed per column (999 = column has no scenery).
var _top_of_col: Array[int] = []


func _ready() -> void:
	var parallax := ParallaxBackground.new()
	parallax.layer = -10
	add_child(parallax)
	_add_strip(parallax, 0.1, SKY, -16.0)
	_add_sun(parallax)
	_add_strip(parallax, 0.3, MOUNTAINS, -56.0)
	_add_strip(parallax, 0.6, RUINS, -76.0)
	_build_layers()
	_add_obstacles()


## Called by main_game: move the rock/tree Obstacles into the y-sorted
## Fighters node (positions are preserved).
func setup(fighters: Node2D) -> void:
	for child in get_children():
		if child is Obstacle:
			child.reparent(fighters)


# --- parallax -----------------------------------------------------------

func _new_layer(parallax: ParallaxBackground, motion: float) -> ParallaxLayer:
	var layer := ParallaxLayer.new()
	layer.motion_scale = Vector2(motion, 0.0)
	parallax.add_child(layer)
	return layer


func _add_strip(parallax: ParallaxBackground, motion: float, tex: Texture2D, y: float) -> void:
	var layer := _new_layer(parallax, motion)
	var step := float(tex.get_width())
	var x := -512.0
	while x < 1700.0:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(x, y)
		layer.add_child(sprite)
		x += step


func _add_sun(parallax: ParallaxBackground) -> void:
	var layer := _new_layer(parallax, 0.1)
	var sun := Sprite2D.new()
	sun.texture = SUN
	sun.centered = false
	sun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sun.position = Vector2(430, 18)
	layer.add_child(sun)


# --- tiles --------------------------------------------------------------

func _build_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = ATLAS
	source.texture_region_size = Vector2i(TILE, TILE)
	for row in 5:
		for col in ATLAS_COLS:
			source.create_tile(Vector2i(col, row))
	tile_set.add_source(source, 0)
	return tile_set


func _coords(idx: int) -> Vector2i:
	return Vector2i(idx % ATLAS_COLS, idx / ATLAS_COLS)


func _new_tile_layer(parent: Node, tile_set: TileSet, modulate: Color, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.modulate = modulate
	layer.z_index = z
	parent.add_child(layer)
	return layer


func _place(layer: TileMapLayer, col: int, row: int, idx: int) -> void:
	if col < 0 or col >= WORLD_TILES or row < 0 or row >= BOTTOM_ROW:
		return
	layer.set_cell(Vector2i(col, row), 0, _coords(idx))


func _note_top(col: int, row: int) -> void:
	if col < 0 or col >= WORLD_TILES:
		return
	if row < _top_of_col[col]:
		_top_of_col[col] = row


func _build_layers() -> void:
	for i in WORLD_TILES:
		_top_of_col.append(BAND_ROW)

	var tile_set := _build_tileset()
	_scenery = _new_tile_layer(self, tile_set, Color(1, 1, 1), 0)
	_band_back = _new_tile_layer(self, tile_set, Color(1, 1, 1), 1)
	_band = _new_tile_layer(self, tile_set, Color(1, 1, 1), 2)
	_decor = _new_tile_layer(self, tile_set, Color(1, 1, 1), 3)

	_build_band_back()
	_build_band()
	_build_scenery()
	_build_decor()


## Solid rock under the whole lane band so every band pixel stays opaque
## even where the edge tiles have a few transparent pixels.
func _build_band_back() -> void:
	for col in WORLD_TILES:
		for row in range(BAND_ROW, BOTTOM_ROW):
			_place(_band_back, col, row, T_ROCK)


## Deterministic edge/fill choice, so the band is not monotone.
func _edge_for(col: int) -> int:
	match (col * 7) % 11:
		0, 1:
			return T_EDGE_B
		2:
			return T_EDGE_C
		_:
			return T_EDGE


## Deterministic rock body, chosen by how far below the surface it sits:
## a solid cobble fringe under the golden lip that fades out into dark rock,
## the way the pack's own showcase scenes are built.
##   depth 1  full cobble fringe       depth 2  half fringe
##   depth 3  sparse cobbles           depth 4+ mostly flat dark rock
func _body_tile(col: int, row: int, depth: int) -> int:
	var h := int(abs((col * 73856093) ^ (row * 19349663) ^ DESERT_SEED)) % 100
	if depth <= 1:
		return T_BODY[h % T_BODY.size()]
	if depth == 2:
		return T_BODY[h % T_BODY.size()] if h < 45 else T_ROCK
	var keep := 18
	if depth == 4:
		keep = 8
	elif depth > 4:
		keep = 4
	if h < keep:
		return T_BODY_LIGHT[h % T_BODY_LIGHT.size()]
	return T_ROCK


func _build_band() -> void:
	for col in WORLD_TILES:
		_place(_band, col, BAND_ROW, _edge_for(col))
		for row in range(BAND_ROW + 1, BOTTOM_ROW):
			_place(_band, col, row, _body_tile(col, row, row - BAND_ROW))
	# Rounded golden corners at both world ends.
	_place(_band, 0, BAND_ROW, T_CAP_L)
	_place(_band, WORLD_TILES - 1, BAND_ROW, T_CAP_R)


# --- scenery ------------------------------------------------------------

## A plateau: golden edge row plus rock body down to the lane band.
func _mass(x0: int, x1: int, top_row: int) -> void:
	for col in range(x0, x1):
		var edge := _edge_for(col)
		if col == x0:
			edge = T_CAP_L
		elif col == x1 - 1:
			edge = T_CAP_R
		_place(_scenery, col, top_row, edge)
		_note_top(col, top_row)
		for row in range(top_row + 1, BAND_ROW):
			_place(_scenery, col, row, _body_tile(col, row, row - top_row))


## Diagonal ramp down to the right: two columns drop one row per pair.
func _ramp_down(x0: int, top_row: int, pairs: int) -> void:
	var col := x0
	for i in pairs:
		var row := top_row + i
		_place(_scenery, col, row, T_RAMP_DOWN_A)
		_place(_scenery, col + 1, row, T_RAMP_DOWN_B)
		_note_top(col, row)
		_note_top(col + 1, row)
		for c in [col, col + 1]:
			for r in range(row + 1, BAND_ROW):
				_place(_scenery, c, r, _body_tile(c, r, r - row))
		col += 2


## Diagonal ramp up to the right: two columns climb one row per pair.
func _ramp_up(x0: int, start_row: int, pairs: int) -> void:
	var col := x0
	for i in pairs:
		var row := start_row - i
		_place(_scenery, col, row, T_RAMP_UP_A)
		_place(_scenery, col + 1, row, T_RAMP_UP_B)
		_note_top(col, row)
		_note_top(col + 1, row)
		for c in [col, col + 1]:
			for r in range(row + 1, BAND_ROW):
				_place(_scenery, c, r, _body_tile(c, r, r - row))
		col += 2


## A floating island: golden edge tiles with one row of rock hanging under
## them, like the floating platforms in the pack's showcase scenes.
func _island(x0: int, x1: int, row: int) -> void:
	for col in range(x0, x1):
		var edge := _edge_for(col)
		if col == x0:
			edge = T_CAP_L
		elif col == x1 - 1:
			edge = T_CAP_R
		_place(_scenery, col, row, edge)
		# The rock hangs under the middle of the island only, so the rounded
		# end caps stay readable instead of sitting on a wider slab.
		if col > x0 and col < x1 - 1:
			_place(_scenery, col, row + 1, _body_tile(col, row + 1, 1))
		_note_top(col, row)


## Raised water pit with a mossy bridge deck, like showcases 1 and 5.
func _pit() -> void:
	var x0: int = PIT[0]
	var x1: int = PIT[1]
	var top: int = PIT[2]
	var hole0: int = PIT[3]
	var hole1: int = PIT[4]
	for col in range(x0, x1):
		var edge := _edge_for(col)
		if col == x0:
			edge = T_CAP_L
		elif col == x1 - 1:
			edge = T_CAP_R
		if col >= hole0 and col < hole1:
			# The bridge deck crosses the pit at plateau level.
			_place(_scenery, col, top, T_BRIDGE[(col - hole0) % T_BRIDGE.size()])
			_note_top(col, top)
			_place(_scenery, col, top + 1, T_WATER_TOP)
			_place(_scenery, col, top + 2, T_WATER)
			continue
		_place(_scenery, col, top, edge)
		_note_top(col, top)
		for row in range(top + 1, BAND_ROW):
			_place(_scenery, col, row, _body_tile(col, row, row - top))
	# Golden walls down both sides of the hole.
	for row in range(top + 1, BAND_ROW):
		_place(_scenery, hole0 - 1, row, T_GOLD_FACE)
		_place(_scenery, hole1, row, T_GOLD_FACE)


## Purple rock column with a golden block on top (showcase 3).
func _pillar() -> void:
	_place(_scenery, PILLAR_COL, PILLAR_TOP, T_GOLD_FACE)
	_note_top(PILLAR_COL, PILLAR_TOP)
	for row in range(PILLAR_TOP + 1, BAND_ROW):
		_place(_scenery, PILLAR_COL, row, T_PILLAR[(row - PILLAR_TOP) % 2])


func _build_scenery() -> void:
	# 1. left plateau with a ramp down to the lane band
	_mass(LEDGE_L[0], LEDGE_L[1], LEDGE_L[2])
	_ramp_down(RAMP_L[0], RAMP_L[1], RAMP_L[2])
	# 2. two floating islands and a decorated pillar
	_island(ISLAND_A[0], ISLAND_A[1], ISLAND_A[2])
	_island(ISLAND_B[0], ISLAND_B[1], ISLAND_B[2])
	_pillar()
	# 3. the water pit with its bridge
	_pit()
	# 4. a ramp climbing to a plateau at the right world end
	_ramp_up(RAMP_R[0], RAMP_R[1], RAMP_R[2])
	_mass(LEDGE_R[0], LEDGE_R[1], LEDGE_R[2])


## Grass and flowers stand on top of the lane edge, on the plateau edges and
## (sparser) on the ramps - never in the middle of a cliff or over the pit.
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DESERT_SEED + 1
	for col in range(1, WORLD_TILES - 1):
		var top := _top_of_col[col]
		if top <= 0:
			continue
		if col >= PIT[3] - 1 and col <= PIT[4]:
			continue   # nothing grows on the bridge deck
		var roll := rng.randf()
		var on_band := top >= BAND_ROW
		if on_band:
			if roll >= 0.28:
				continue
		elif roll >= 0.30:
			continue
		var tile: int
		if roll < 0.07:
			tile = T_FLOWER[int(rng.randf() * T_FLOWER.size())]
		elif roll < 0.20:
			tile = T_GRASS[0]
		else:
			tile = T_GRASS[1 + int(rng.randf() * (T_GRASS.size() - 1))]
		_place(_decor, col, top - 1, tile)
	# Sparse pebbles and gold nuggets lying on the rock floor.
	for col in range(2, WORLD_TILES - 2):
		var roll := rng.randf()
		if roll > 0.12:
			continue
		var row := BAND_ROW + 2 + int(rng.randf() * 3.0)
		if roll < 0.03:
			_place(_decor, col, row, T_NUGGET[int(rng.randf() * float(T_NUGGET.size()))])
		else:
			_place(_decor, col, row, T_PEBBLE[int(rng.randf() * float(T_PEBBLE.size()))])


# --- rocks and trees (solid obstacles) -----------------------------------

func _add_obstacles() -> void:
	for entry in ROCKS:
		var obs := Obstacle.new()
		obs.footprint = ROCK_FOOTPRINT
		add_child(obs)
		obs.position = entry[1]
		var spr := Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = ROCK_TEX[int(entry[0]) - 1]
		spr.centered = false
		spr.scale = Vector2(ROCK_SCALE, ROCK_SCALE)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Vector2(-TILE * 0.5 * ROCK_SCALE, -TILE * ROCK_SCALE)
		obs.add_child(spr)
	for entry in TREES:
		var obs := Obstacle.new()
		obs.footprint = TREE_FOOTPRINT
		add_child(obs)
		obs.position = entry[1]
		var trunk: Vector2 = TREE_TRUNK[int(entry[0])]
		var spr := Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = TREE_TEX[int(entry[0])]
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Vector2(-trunk.x, -trunk.y)
		obs.add_child(spr)


## Printout used by the proof harness.
func lane_limits() -> Vector2:
	return Vector2(GameState.LANE_MIN_Y_DESERT, GameState.LANE_MAX_Y_DESERT)
