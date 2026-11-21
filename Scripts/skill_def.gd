# ---------------------------------------------------------------------------
# skill_def.gd: one skill on the skill tree, as a Resource.
#
# A Resource is a bundle of data Godot can save as a file (.tres) and show in
# the Inspector. Every skill is its own file in Data/skills/. SkillManager
# (the autoload) loads every file in that folder when the game starts, so:
#   - to rebalance a skill: open its .tres and change cost or amount.
#   - to add a skill: duplicate a .tres in the FileSystem dock (right click >
#     Duplicate), give it a new id, and set parent_id to the skill it hangs
#     under. The skill tree screen places it by itself.
# No code needed for either, as long as the skill uses one of the effects
# below. A brand new kind of effect also needs code that reads it
# (search for SkillManager.bonus).
# ---------------------------------------------------------------------------
class_name SkillDef
extends Resource

## The three columns of the skill tree.
enum Branch { WIRE, SUIT, LIFE_SUPPORT }
## The column headings, in the same order as Branch.
const BRANCH_NAMES: Array[String] = ["WIRE", "SUIT", "LIFE SUPPORT"]

## A unique name the code and the save file use, e.g. "longer_wire_1".
## Lower case, no spaces. Don't change it once players have saves.
@export var id := ""
## Shown on the skill tree when this skill is selected.
@export var display_name := "NEW SKILL"
## Shown under the skill's box on the tree. Keep it short (about 9 letters).
## Empty = use display_name.
@export var short_name := ""
## What it does, in plain words. Shown under the tree.
@export_multiline var description := ""
@export var branch: Branch = Branch.WIRE
## Skill points it costs to unlock.
@export_range(1, 5) var cost := 1
## The id of the skill you need first. Empty = the first skill of its branch.
@export var parent_id := ""

@export_group("Effect")
## What the skill changes. The level and Game read these by name:
##   wire_time    seconds added to the wire timer
##   cell_bonus   extra seconds each battery adds to the wire
##   walk_speed   extra walking speed (0.1 = 10% faster)
##   boots        zaps per room your boots shrug off
##   o2           extra seconds of oxygen on spacewalks
##   o2_per_cell  extra seconds of oxygen for each battery you've kept
@export_enum("wire_time", "cell_bonus", "walk_speed", "boots", "o2", "o2_per_cell") var effect := "wire_time"
## How much. Skills with the same effect add up.
@export var amount := 0.5


## The name drawn under the skill's box.
func label() -> String:
	return short_name if short_name != "" else display_name
