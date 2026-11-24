# ---------------------------------------------------------------------------
# game_state.gd: remembers things between levels. It's an autoload named "Game".
#
# When you change scene (level 1 -> level 2), Godot throws the old scene away,
# with every variable in it. So anything that has to survive (power cells
# collected, retries, time) lives here instead. Godot creates this node once
# when the game starts and keeps it alive until you quit: that's an autoload
# (also called a "singleton"). It's listed in Project Settings > Globals > Autoload.
#
# Any script can use it by its name, e.g.  Game.o2_bonus()  or  Game.go_to_level(2)
#
# The RPG side (skill points and the skill tree) lives in its own autoload,
# SkillManager (skill_manager.gd). This script saves it, together with which
# levels you've finished, to one save file (save_game / load_game), so the
# title screen can offer "Continue".
# ---------------------------------------------------------------------------
extends Node

## The folder the levels live in. Every scene in it called level_<number>.tscn
## is a level, played in number order. To add a level, save its scene there
## with the next number (level_4.tscn): the level select, the dev menu and
## Continue find it by themselves, there's no list to update. Other scenes in
## the folder (a test room, say) are left alone.
const LEVEL_FOLDER := "res://Levels/"
## The levels in the order you play them, found in LEVEL_FOLDER once when the
## game starts (_find_levels). It's written in capitals like a constant because
## nothing changes it after that.
var LEVELS: Array[String] = _find_levels()
const TITLE_SCENE := "res://Scenes/title.tscn"
## The opening cutscene, played when you start a new game (before Level 1).
const INTRO_SCENE := "res://Scenes/intro.tscn"

## The music: the team's own tracks, as Assets/audio/music_<name>.ogg.
## The number is each track's volume in dB (0 = as loud as the file, -6 = about
## half as loud). The files were mixed at different loudness, so each one gets
## its own volume to make them sound about equally loud in the game. Change
## them to taste: closer to 0 = louder.
const MUSIC := {
	"title": -18.0,   # "Title theme dramatic": the title screen
	# The level tracks are set a little louder than the title, because in a level
	# they play under the sound effects (and the wire's hum while you carry it).
	"ship": -21.0,    # "Space theme bells": inside the ship
	"space": -19.0,   # "Space theme bells 2": out on the hull (spacewalks)
	"core": -16.0,    # "Space staccato": the rogue PIP fight in Level 3
	"ending": -20.0,  # "Title theme no dramatic": after PIP reboots, to the last results
}

## Extra seconds of oxygen on a spacewalk for every power cell you charged so far.
## A small RPG reward: exploring earlier levels makes later ones easier.
const O2_PER_CELL := 5.0

## The save file. "user://" is a folder Godot keeps for this game on the
## player's computer (in a web build: inside the browser's storage).
const SAVE_PATH := "user://save.cfg"
## Settings live in their own file, so NEW GAME (which deletes the save) keeps them.
const SETTINGS_PATH := "user://settings.cfg"

## The game's font: the pixel font Departure Mono. The DYSLEXIA FONT switch
## (title screen, pause menu) changes it to OpenDyslexic, whose letters are
## heavier at the bottom so b, d, p and q don't seem to flip: that helps
## players with dyslexia. How the switch works: no scene picks a font of its
## own, they all use the theme's default font or ThemeDB.fallback_font, so
## changing those two changes all the text at once (apply_font). The fonts
## themselves: UIStyle.pixel_font() and UIStyle.dyslexic_font().
## PIP's console text size for each font, so his lines fit in its two rows
## (both fonts are wider than Godot's built-in one).
const CONSOLE_SIZE_PIXEL := 8
const CONSOLE_SIZE_DYSLEXIC := 8
const CONSOLE_SIZE_PLAIN := 9     # Godot's built-in font, if a font file is missing
signal font_changed            # the switch was flipped (the HUD resizes PIP's text)
var dyslexic_font := false
var _plain_font: Font          # Godot's built-in font (Open Sans), only if a file is missing

# One entry per level number, e.g. results[1] = {"time": 140.2, "cells": 7, ...}
var results := {}
## True once a level was loaded by the game (title -> level, or "next level").
## Stays false when you run one level scene straight from the editor with F6:
## that's the only time a level's TestStart marker is used.
var playing_through := false
## Judge mode (switched on at the title screen): every level can be picked from
## the title, and in a level R makes PIP walk the room for you (autopilot.gd).
## It's for the TSA judges, who must be able to see all three levels.
var judge_mode := false
## The dev menu (dev_menu.gd) sets this to the room to start in when the next
## level loads (-1 = the normal start). The level reads it once and resets it.
var dev_room := -1
## NODE REST, a rule to try out (the dev menu switches it on and off): while the
## wire is latched on a node and you stand close to it, the timer waits.
## level.gd _node_rest() reads it. Not saved: every run starts with it off.
var node_rest := false
# Tips PIP already gave (so he explains something only once, even across levels)
var _tips_seen := {}


## Forget everything and delete the save (the title screen's "new game").
func new_game() -> void:
	results.clear()
	SkillManager.reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _ready() -> void:
	_plain_font = ThemeDB.fallback_font
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		dyslexic_font = cfg.get_value("settings", "dyslexic_font", false)
	apply_font()
	# Buying a skill saves straight away, so quitting mid level doesn't lose it.
	SkillManager.skill_unlocked.connect(func(_id: String) -> void: save_game())
	# Menu buttons react to the "ui_accept" action (Enter and Space). Add E to it
	# too, so E presses the selected button, like it moves PIP's lines on.
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	if not InputMap.action_has_event("ui_accept", e):
		InputMap.action_add_event("ui_accept", e)
	# The dev menu (the ` key): only when the game runs from the Godot editor,
	# never in an exported or web build, so judges can't open it by accident.
	if OS.has_feature("editor"):
		add_child(preload("res://Scripts/dev_menu.gd").new())


## Puts the chosen font on every piece of text (see the notes above dyslexic_font).
func apply_font() -> void:
	var f := _current_font()
	# Labels and Buttons ask the project theme (Assets/ui/theme.tres) for a font
	# first, so it goes there (only while the game runs; the file isn't changed).
	# Text drawn in code (UIStyle.text, the console's pages) uses the fallback font.
	var theme := ThemeDB.get_project_theme()
	if theme:
		theme.default_font = f
	ThemeDB.fallback_font = f
	font_changed.emit()


## The font in use: OpenDyslexic with the switch on, else Departure Mono (or
## Godot's built-in font if that file is missing).
func _current_font() -> Font:
	if dyslexic_font and UIStyle.dyslexic_font():
		return UIStyle.dyslexic_font()
	if UIStyle.pixel_font():
		return UIStyle.pixel_font()
	return _plain_font


## PIP's console text size for the font in use (hud.gd), so his lines fit.
func console_font_size() -> int:
	var f := _current_font()
	if f == UIStyle.dyslexic_font():
		return CONSOLE_SIZE_DYSLEXIC
	if f == UIStyle.pixel_font():
		return CONSOLE_SIZE_PIXEL
	return CONSOLE_SIZE_PLAIN


## The DYSLEXIA FONT switch: change the font now and remember it.
func set_dyslexic_font(on: bool) -> void:
	dyslexic_font = on
	apply_font()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)              # (keeps any other settings in the file)
	cfg.set_value("settings", "dyslexic_font", on)
	cfg.save(SETTINGS_PATH)


## The text on the switch's button.
func font_switch_text() -> String:
	return "DYSLEXIA FONT: " + ("ON" if dyslexic_font else "OFF")


## The level calls this when you finish it. It also saves the game.
func record_level(number: int, stats: Dictionary) -> void:
	results[number] = stats
	save_game()


## True if you've finished level `number` before (in this save).
func has_finished(number: int) -> bool:
	return results.has(number)


## Power cells charged in every level finished so far.
func cells_collected() -> int:
	var n := 0
	for stats in results.values():
		n += int(stats.get("cells", 0))
	return n


## Seconds of oxygen each kept battery gives (CELL CHARGER skill adds to it).
func o2_per_cell() -> float:
	return O2_PER_CELL + SkillManager.bonus("o2_per_cell")


## Extra oxygen on spacewalks: from batteries you kept, and the Life Support skills.
func o2_bonus() -> float:
	return cells_collected() * o2_per_cell() + SkillManager.bonus("o2")


## True the first time it's asked about `tip`, false every time after that.
## e.g.  if Game.first_time("cell_kept"): hud.say(...)   -> PIP explains it once.
func first_time(tip: String) -> bool:
	if _tips_seen.has(tip):
		return false
	_tips_seen[tip] = true
	return true


## Loads music track `track_name` (a key of `MUSIC`) and makes it loop forever.
## Returns null if the file isn't there (the game just stays quiet).
func load_music(track_name: String) -> AudioStream:
	var path := "res://Assets/audio/music_%s.ogg" % track_name
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true        # when it reaches the end, start again from the top
	return s


## Looks in LEVEL_FOLDER for level_1.tscn, level_2.tscn ... and returns their
## paths in number order. The numbers must go 1, 2, 3 with none missing,
## because a level's number is its place in this list (go_to_level(2) loads
## the 2nd one). So a file after a gap is left out, with a warning.
static func _find_levels() -> Array[String]:
	var by_number := {}
	var name_rule := RegEx.create_from_string("^level_(\\d+)\\.tscn$")
	# ResourceLoader.list_directory, not DirAccess: it also works in the exported
	# web build, where Godot stores scenes converted, under other file names.
	for file in ResourceLoader.list_directory(LEVEL_FOLDER):
		var m := name_rule.search(file)
		if m:
			by_number[int(m.get_string(1))] = LEVEL_FOLDER + file
	var found: Array[String] = []
	while by_number.has(found.size() + 1):
		found.append(by_number[found.size() + 1])
	for n in by_number:
		if n > found.size():
			push_warning("%s is left out: there's no level_%d.tscn before it." % [by_number[n], found.size() + 1])
	if found.is_empty():
		push_warning("No levels found. Save them in %s as level_1.tscn, level_2.tscn ..." % LEVEL_FOLDER)
	return found


func has_level(number: int) -> bool:
	return number >= 1 and number <= LEVELS.size()


func go_to_level(number: int) -> void:
	get_tree().paused = false       # pausing survives a scene change, so make sure it's off
	if has_level(number):
		playing_through = true
		get_tree().change_scene_to_file(LEVELS[number - 1])
	else:
		go_to_title()


## Dev menu: load level `number` and start in room `room` (0 = the normal start),
## with every room before it already powered.
func dev_jump(number: int, room: int) -> void:
	dev_room = room
	go_to_level(number)


func go_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## The opening cutscene (it loads Level 1 itself when it's over).
func go_to_intro() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(INTRO_SCENE)


## Values that story text can use: write {cells}, {o2_bonus} or {o2_per_cell} inside a line.
func story_values() -> Dictionary:
	return {"cells": cells_collected(), "o2_bonus": int(o2_bonus()), "o2_per_cell": int(o2_per_cell())}


# ------------------------------------------------------------------ the save file
# A ConfigFile is a simple text file with [sections] and key = value lines,
# like project.godot. Godot can store dictionaries and arrays in it directly.

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "results", results)
	var skills := SkillManager.to_save()
	cfg.set_value("skills", "points", skills["points"])
	cfg.set_value("skills", "unlocked", skills["unlocked"])
	cfg.set_value("settings", "judge_mode", judge_mode)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Couldn't save the game (error %d)" % err)


## Loads the save file if there is one. Returns false if there isn't.
func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	results = cfg.get_value("progress", "results", {})
	judge_mode = cfg.get_value("settings", "judge_mode", false)
	SkillManager.from_save({
		"points": cfg.get_value("skills", "points", 0),
		"unlocked": cfg.get_value("skills", "unlocked", []),
	})
	return true


## There's a game to continue: you finished at least one level.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and not results.is_empty()


## The level "Continue" goes to: the one after the last you finished
## (or the last level again, if you've finished them all).
func continue_level() -> int:
	var last := 0
	for n in results:
		last = maxi(last, int(n))
	return clampi(last + 1, 1, LEVELS.size())
