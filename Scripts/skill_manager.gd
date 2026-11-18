# ---------------------------------------------------------------------------
# skill_manager.gd  -  the skill tree's brain. It's an AUTOLOAD named "SkillManager".
#
# It holds two things that last for the whole game: your SKILL POINTS and the
# skills you've UNLOCKED. You earn points by finishing a level for the first
# time (level.gd _finish_level, the level's skill_points export). You spend
# them on the skill tree screen (skill_tree.gd).
#
# The skills themselves are DATA, not code: one SkillDef file per skill in
# Data/skills/ (see skill_def.gd). This script loads them all at the start.
#
# Anything can ask it questions:
#   SkillManager.has_skill("rubber_boots")   -> true / false
#   SkillManager.bonus("wire_time")          -> the seconds all your wire skills add up to
# and anything can LISTEN to its signals instead of checking every frame.
# That's the point of a signal: the level doesn't have to keep asking "did
# something change?", SkillManager tells it.
#
# It doesn't save anything itself: Game (game_state.gd) writes the save file
# and asks this script for to_save() / from_save().
# ---------------------------------------------------------------------------
extends Node

## Every skill file in this folder is loaded.
const SKILLS_DIR := "res://Data/skills/"

## Where a skill stands. The tree draws each one differently.
enum State {
	LOCKED,     # you need its parent skill first
	AVAILABLE,  # its parent is unlocked: you can buy it (if you have the points)
	UNLOCKED,   # yours
}

## Your points went up or down.
signal points_changed(points: int)
## You bought a skill (only sent for a real unlock, not when a save loads).
signal skill_unlocked(id: String)
## Anything changed: points, an unlock, a reset or a loaded save. The level
## listens to this to apply the skills straight away.
signal skills_changed

var points := 0
var _unlocked := {}            # skill id -> true
var _skills := {}              # skill id -> SkillDef
var _order: Array[SkillDef] = []   # every skill, sorted by file name


func _ready() -> void:
	_load_skills()


## Reads every .tres in SKILLS_DIR. ResourceLoader.list_directory also works in
## exported (web) builds, where the files are packed differently.
func _load_skills() -> void:
	var files := Array(ResourceLoader.list_directory(SKILLS_DIR))
	files.sort()
	for f: String in files:
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var s := load(SKILLS_DIR + f) as SkillDef
		if s == null:
			push_warning("SkillManager: %s isn't a SkillDef, skipped" % f)
			continue
		if s.id == "" or _skills.has(s.id):
			push_warning("SkillManager: %s has an empty or repeated id '%s', skipped" % [f, s.id])
			continue
		_skills[s.id] = s
		_order.append(s)
	# a parent that doesn't exist would make a skill impossible to unlock: say so
	for s in _order:
		if s.parent_id != "" and not _skills.has(s.parent_id):
			push_warning("SkillManager: '%s' needs '%s', which doesn't exist" % [s.id, s.parent_id])


# ------------------------------------------------------------------ questions

## Every skill, in file order.
func all_skills() -> Array[SkillDef]:
	return _order


## The skill with this id, or null.
func get_skill(id: String) -> SkillDef:
	return _skills.get(id)


func has_skill(id: String) -> bool:
	return _unlocked.has(id)


func unlocked_count() -> int:
	return _unlocked.size()


func state(id: String) -> State:
	if _unlocked.has(id):
		return State.UNLOCKED
	var s := get_skill(id)
	if s == null:
		return State.LOCKED
	if s.parent_id == "" or _unlocked.has(s.parent_id):
		return State.AVAILABLE
	return State.LOCKED


## True if you could buy it right now: its parent is unlocked and you have the points.
func can_unlock(id: String) -> bool:
	var s := get_skill(id)
	return s != null and state(id) == State.AVAILABLE and points >= s.cost


## The total of every unlocked skill with this effect (see skill_def.gd for the
## effect names). 0.0 if you have none. Rules call this, e.g. the wire timer is
## wire_time + SkillManager.bonus("wire_time").
func bonus(effect: String) -> float:
	var total := 0.0
	for id in _unlocked:
		var s := get_skill(id)
		if s and s.effect == effect:
			total += s.amount
	return total


# ------------------------------------------------------------------ changes

## Buy a skill. Returns false (and changes nothing) if you can't.
func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	points -= get_skill(id).cost
	_unlocked[id] = true
	points_changed.emit(points)
	skill_unlocked.emit(id)
	skills_changed.emit()
	return true


func add_points(amount: int) -> void:
	if amount == 0:
		return
	points = maxi(0, points + amount)
	points_changed.emit(points)
	skills_changed.emit()


## A new game: no points, no skills.
func reset() -> void:
	points = 0
	_unlocked.clear()
	points_changed.emit(points)
	skills_changed.emit()


# ------------------------------------------------------------------ save data

func to_save() -> Dictionary:
	return {"points": points, "unlocked": _unlocked.keys()}


## Ids that aren't in Data/skills/ any more (a skill was deleted) are dropped.
func from_save(data: Dictionary) -> void:
	points = int(data.get("points", 0))
	_unlocked.clear()
	for id in data.get("unlocked", []):
		if _skills.has(str(id)):
			_unlocked[str(id)] = true
	points_changed.emit(points)
	skills_changed.emit()
