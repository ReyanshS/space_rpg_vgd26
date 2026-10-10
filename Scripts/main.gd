extends Node2D

@onready var box1 = $Box1
@onready var box2 = $Box2
@onready var power_line = $Line2D
@onready var energy_line = $EnergyLine

@onready var popup_banner = $CanvasLayer/popupBanner
@onready var instruction_text = $CanvasLayer/popupBanner/instructionText

# Animation Settings - 0.25 speed means it takes exactly 4 full seconds to complete the crawl
const FILL_SPEED = 0.75 
var fill_progress: float = 0.0
var is_animating_flow: bool = false

var start_pos: Vector2
var end_pos: Vector2

# Direct tracking strings
var first_clicked_box: String = ""

func _ready() -> void:
	power_line.clear_points()
	energy_line.clear_points()
	
	var box1_center = box1.global_position + Vector2(16, 16)
	var box2_center = box2.global_position + Vector2(16, 16)
	
	power_line.add_point(box1_center)
	power_line.add_point(box2_center)
	
	power_line.default_color = Color(0.35, 0.35, 0.35, 1.0) # Base Grey
	energy_line.default_color = Color(0.65, 1.0, 0.0, 1.0) # Neon Green-Yellow
	
	popup_banner.visible = false

# This function is called directly by the boxes to log the exact click order
func log_box_activation(box_name: String) -> void:
	if first_clicked_box == "":
		first_clicked_box = box_name

func _process(delta: float) -> void:
	# 1. TRIGGER THE FLOW ONLY AFTER BOTH BOXES ARE ACTIVATED
	if box1.is_powered and box2.is_powered and not is_animating_flow:
		is_animating_flow = true
		fill_progress = 0.0
		
		var b1_center = box1.global_position + Vector2(16, 16)
		var b2_center = box2.global_position + Vector2(16, 16)
		
		# BULLETPROOF RE-ROUTE: Explicitly lock endpoints based on the logged name
		if first_clicked_box == "Box1":
			start_pos = b1_center
			end_pos = b2_center
		else:
			start_pos = b2_center
			end_pos = b1_center

	# 2. RUN TIME PROGRESS AND DRAW EXTENSIONS EACH FRAME
	if is_animating_flow and fill_progress < 1.0:
		fill_progress += delta * FILL_SPEED
		fill_progress = clamp(fill_progress, 0.0, 1.0)
		
		var current_tip_pos = start_pos.lerp(end_pos, fill_progress)
		
		energy_line.clear_points()
		energy_line.add_point(start_pos)
		energy_line.add_point(current_tip_pos)

	# 3. INTERACTION TEXT STATE CHECKERS
	if box1.is_powered and box2.is_powered:
		if fill_progress >= 1.0:
			show_popup("Good job!")
		else:
			popup_banner.visible = false
	elif box1.is_powered or box2.is_powered:
		if box1.player_in_range or box2.player_in_range:
			if (box1.is_powered and box2.player_in_range) or (box2.is_powered and box1.player_in_range):
				show_popup("Circuit ready. Press [SPACE] to bridge the electricity!")
		else:
			if first_clicked_box != "":
				show_popup("Primary power online! Now go to the other box.")
			else:
				popup_banner.visible = false
	else:
		if box1.player_in_range or box2.player_in_range:
			show_popup("Press [SPACE] to activate the primary generator node.")
		else:
			popup_banner.visible = false

func show_popup(msg: String) -> void:
	instruction_text.text = msg
	popup_banner.visible = true
