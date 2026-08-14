extends Control

# Title screen. A visitor at an open-day stand needs two options, start a match
# or quit, so that is all this offers.
#
# The buttons sit inside a VBoxContainer, which gives up and down navigation
# between them for free. The only thing that has to be done by hand is giving
# one of them focus on load, since without a focused control Godot's UI
# navigation has no starting point and the controller appears to do nothing.


@onready var start_button: Button = $VBox/StartButton


func _ready() -> void:
	# Clears any pause left over from quitting a match through the pause menu,
	# otherwise the menu loads frozen.
	get_tree().paused = false
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
