extends Control

# =============================================================================
#  main_menu.gd — title screen
#
#  Attached to:  the root Control node of scenes/main_menu.tscn
#  Requirements: FR-15, FR-19, NFR-11
#
#  Purpose
#  -------
#  The entry point of the game. Offers the two options a visitor at an open-day
#  stand needs — start a match, or quit — and nothing else.
#
#  Controller operation
#  --------------------
#  Focus is given to the Start button as soon as the scene loads. Without an
#  explicitly focused control, Godot's UI navigation has no starting point and a
#  controller appears to do nothing. Placing the buttons inside a VBoxContainer
#  means up and down navigation between them works without any manual wiring
#  of focus neighbours (FR-19).
# =============================================================================


@onready var start_button: Button = $VBox/StartButton


func _ready() -> void:
	# Clear any pause state left over from a previous match, so the menu is
	# responsive even if the player quit from a paused game.
	get_tree().paused = false
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
