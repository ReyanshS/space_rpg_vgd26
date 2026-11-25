# art_crate_icon.gd: puts the movable crate into the Layout palette
# (Assets/images/tiles/layout_tiles.png, frame 23 = tile kind "box").
# It draws the crate with the same code the game uses (push_crate.gd
# draw_crate), so the palette icon always matches. Run from the project folder
# (it needs a window, not --headless):
#     godot --path . --script tools/art_crate_icon.gd
# Safe to run again: it replaces frame 23 if it's already there.
extends SceneTree

const PALETTE := "res://Assets/images/tiles/layout_tiles.png"
const FRAME := 23


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(32, 32)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var art := Node2D.new()
	var crate_script := load("res://Scripts/push_crate.gd")
	art.draw.connect(func() -> void:
		art.draw_rect(Rect2(0, 0, 32, 32), Color(0.24, 0.27, 0.33))      # a floor backing, like the other icons
		crate_script.draw_crate(art, Vector2(16, 17)))
	vp.add_child(art)
	for i in 6:
		await process_frame
	var icon := vp.get_texture().get_image()
	icon.convert(Image.FORMAT_RGBA8)
	var pal := Image.load_from_file(ProjectSettings.globalize_path(PALETTE))
	pal.convert(Image.FORMAT_RGBA8)
	var w := maxi(pal.get_width(), (FRAME + 1) * 32)
	var out := Image.create(w, 32, false, Image.FORMAT_RGBA8)
	out.blit_rect(pal, Rect2i(0, 0, pal.get_width(), 32), Vector2i.ZERO)
	out.blit_rect(icon, Rect2i(0, 0, 32, 32), Vector2i(FRAME * 32, 0))
	out.save_png(ProjectSettings.globalize_path(PALETTE))
	print("crate icon written to frame %d of %s" % [FRAME, PALETTE])
	quit()
