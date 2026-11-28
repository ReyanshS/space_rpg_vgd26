# build_team_tiles.gd: adds the team's art sheets to the Layout tileset, so you
# paint them on the Layout layer like every other tile.
#
# Each PNG in Assets/images/tiles/team/ becomes its own source in
# Assets/images/tiles/layout_tileset.tres (in the TileMap panel it's one more
# entry in the list on the left). Every tile gets a "kind", and the kind is what
# gives it its rules (see level.gd): "wall" is solid, "floor" you walk on,
# "start" / "goal" / "node" are the puzzle pads, "crate" is fixed cargo (solid
# for you and the wire), "box" is a crate you can push (only the palette's
# striped crate is one: the team's wooden crates are all fixed).
#
# The three animation strips become ONE animated tile each: paint one square and
# the whole animation plays there (Godot's tile animation: the frames sit side
# by side in the picture, and the tile steps through them).
#
# The 47 wall pieces (wall_sides.png) are plain wall tiles, shown as painted.
# tools/retile_walls.py paints the right piece for every wall of a level.
#
# Run it from the project folder after the PNGs have been imported once
# (open the project in Godot, or run `godot --headless --path . --import`):
#     godot --headless --path . --script tools/build_team_tiles.gd
# Safe to run again: it replaces the team sources if they're already there.
extends SceneTree

const TILESET := "res://Assets/images/tiles/layout_tileset.tres"
const DIR := "res://Assets/images/tiles/team/"
const FRAME_TIME := 0.1        # seconds per animation frame (change it in the TileSet editor too)

# source id -> [picture, kind for every tile (or "" = use OBJECTS below)]
const SHEETS := {
	1: ["ground.png", "floor"],
	2: ["wall.png", "wall"],          # the front faces (the team's)
	3: ["wall_sides.png", "wall"],    # the wall pieces (tools/art_wall_sides.py)
	8: ["wall_caps.png", "wall"],     # front panel ends with the skirting round the corner (tools/art_wall_caps.py)
	9: ["wall_strip.png", "wall"],    # the power strip panel without the bolt (tools/art_wall_strip.py)
	4: ["objects.png", ""],
}
# objects.png, tile by tile (column, row) -> kind. The purple bend block (3, 6)
# is left out on purpose: the team doesn't use it.
const OBJECTS := {
	Vector2i(2, 6): "node",    # orange extra time block
	Vector2i(1, 7): "goal",    # grey block: a goal without power (level.gd shows every goal like this until it's powered)
	Vector2i(2, 7): "goal",    # blue goal block
	Vector2i(3, 7): "start",   # yellow start block
	Vector2i(4, 7): "crate",   # the wooden crate: fixed cargo (only the striped crate moves, team, Nov 26 2026)
	Vector2i(5, 6): "crate", Vector2i(6, 6): "crate",   # the big 2 x 2 crate: fixed cargo,
	Vector2i(5, 7): "crate", Vector2i(6, 7): "crate",   # paint all four quarters
}
# animated tiles: source id -> [picture, kind, number of frames]
const ANIMS := {
	5: ["start_anim.png", "start", 16],
	6: ["goal_anim.png", "goal", 16],
	7: ["node_anim.png", "node", 24],    # "extra_time_block.png"
}


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	for id in SHEETS:
		var src := _fresh_source(ts, id, DIR + SHEETS[id][0])
		var tex := src.texture
		var img := tex.get_image()
		for y in tex.get_height() / 32:
			for x in tex.get_width() / 32:
				var c := Vector2i(x, y)
				var kind: String = SHEETS[id][1]
				if kind == "":
					kind = OBJECTS.get(c, "")
				if kind == "" or img.get_region(Rect2i(c * 32, Vector2i(32, 32))).is_invisible():
					continue           # empty square (or one we don't use): no tile
				src.create_tile(c)
				src.get_tile_data(c, 0).set_custom_data("kind", kind)
	for id in ANIMS:
		var src := _fresh_source(ts, id, DIR + ANIMS[id][0])
		var c := Vector2i.ZERO
		src.create_tile(c)
		src.set_tile_animation_columns(c, ANIMS[id][2])     # all the frames in one row
		src.set_tile_animation_frames_count(c, ANIMS[id][2])
		for f in ANIMS[id][2]:
			src.set_tile_animation_frame_duration(c, f, FRAME_TIME)
		src.get_tile_data(c, 0).set_custom_data("kind", ANIMS[id][1])
	# the levels find the tileset by its uid: keep the same one (saving from a
	# --script run can leave it out of the file)
	var uid := ResourceLoader.get_resource_uid(TILESET)
	var err := ResourceSaver.save(ts, TILESET)
	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(TILESET, uid)
	print("layout_tileset.tres saved (error %d), sources: %s" % [err, _list(ts)])
	quit()


## A new, empty atlas source for picture `path`, replacing source `id` if it exists.
func _fresh_source(ts: TileSet, id: int, path: String) -> TileSetAtlasSource:
	if ts.has_source(id):
		ts.remove_source(id)
	var src := TileSetAtlasSource.new()
	src.texture = load(path)
	src.texture_region_size = Vector2i(32, 32)
	ts.add_source(src, id)
	return src


func _list(ts: TileSet) -> String:
	var out := []
	for i in ts.get_source_count():
		var id := ts.get_source_id(i)
		var src := ts.get_source(id) as TileSetAtlasSource
		out.append("%d %s (%d tiles)" % [id, src.texture.resource_path.get_file(), src.get_tiles_count()])
	return ", ".join(out)
