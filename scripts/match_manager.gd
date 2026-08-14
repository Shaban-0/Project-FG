extends Node2D

# Runs the match: the countdown, deciding when a round is over and who won, and
# the pause and result overlays.
#
# The fighters know nothing about rounds and the HUD knows nothing about
# fighters. This script is the only thing that connects them, which means either
# side can be changed without breaking the other.
#
# Scene setup this relies on:
#   - this node's Process Mode is "Always", so pause input still gets through
#     while the tree is paused
#   - both Player nodes are "Pausable", so they actually freeze
#   - the three AudioStreamPlayers are "Always", or the win sound is cut off the
#     instant the tree pauses


# 60 seconds keeps a round short enough that the demo entertains for a few
# minutes rather than one pair occupying the stand all day.
const ROUND_LENGTH := 60.0


# --- Nodes -------------------------------------------------------------------


@onready var p1: CharacterBody2D = $Player
@onready var p2: CharacterBody2D = $Player2

@onready var p1_health: TextureProgressBar = $HUD/P1Health
@onready var p2_health: TextureProgressBar = $HUD/P2Health
@onready var timer_label: Label = $HUD/Timer

@onready var result_panel: Control = $HUD/ResultOverlay
@onready var result_label: Label = $HUD/ResultOverlay/VBox/ResultLabel
@onready var rematch_button: Button = $HUD/ResultOverlay/VBox/RematchButton

@onready var pause_panel: Control = $HUD/PauseOverlay
@onready var resume_button: Button = $HUD/PauseOverlay/VBox/ResumeButton

@onready var narrator_sound: AudioStreamPlayer = $NarratorSound
@onready var p1_wins_sound: AudioStreamPlayer = $P1WinsSound
@onready var p2_wins_sound: AudioStreamPlayer = $P2WinsSound


# --- Current state -----------------------------------------------------------


var time_remaining: float = ROUND_LENGTH
var round_over: bool = false


func _ready() -> void:
	# Listening to signals rather than checking health every frame. bind() passes
	# in which fighter was knocked out, so one handler covers both players.
	p1.health_changed.connect(_on_p1_health_changed)
	p2.health_changed.connect(_on_p2_health_changed)
	p1.knocked_out.connect(_on_fighter_knocked_out.bind(p1))
	p2.knocked_out.connect(_on_fighter_knocked_out.bind(p2))

	# The bars only update when health changes, so without this they sit at the
	# editor default of zero until the first hit lands.
	_on_p1_health_changed(p1.health, p1.MAX_HEALTH)
	_on_p2_health_changed(p2.health, p2.MAX_HEALTH)

	result_panel.hide()
	pause_panel.hide()
	_update_timer_display()

	narrator_sound.play()


func _process(delta: float) -> void:
	# This node keeps processing while paused so it can still catch the pause
	# button, which means the countdown has to be stopped by hand.
	if round_over or get_tree().paused:
		return

	time_remaining = maxf(time_remaining - delta, 0.0)
	_update_timer_display()

	if time_remaining <= 0.0:
		_end_round_on_time()


# Handled here rather than in _input so a focused button gets first go at the
# event, otherwise pressing pause can register twice.
func _unhandled_input(event: InputEvent) -> void:
	if round_over:
		return

	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _update_timer_display() -> void:
	timer_label.text = str(int(ceil(time_remaining)))


# --- Health ------------------------------------------------------------------


func _on_p1_health_changed(current: float, maximum: float) -> void:
	p1_health.max_value = maximum
	p1_health.value = current


func _on_p2_health_changed(current: float, maximum: float) -> void:
	p2_health.max_value = maximum
	p2_health.value = current


# --- Ending a round ----------------------------------------------------------


func _on_fighter_knocked_out(loser: CharacterBody2D) -> void:
	if round_over:
		return

	if loser == p1:
		_show_result("PLAYER 2 WINS", 2)
	else:
		_show_result("PLAYER 1 WINS", 1)


# If nobody is knocked out, whoever has more health left takes the round.
func _end_round_on_time() -> void:
	if p1.health > p2.health:
		_show_result("PLAYER 1 WINS", 1)
	elif p2.health > p1.health:
		_show_result("PLAYER 2 WINS", 2)
	else:
		_show_result("DRAW", 0)


# winner is 1, 2, or 0 for a draw. Focus moves to the rematch button so the
# overlay can be used with a controller straight away, without a mouse.
func _show_result(text: String, winner: int) -> void:
	round_over = true
	result_label.text = text
	result_panel.show()
	rematch_button.grab_focus()

	if winner == 1:
		p1_wins_sound.play()
	elif winner == 2:
		p2_wins_sound.play()

	get_tree().paused = true


# --- Pause -------------------------------------------------------------------


func _toggle_pause() -> void:
	if pause_panel.visible:
		_resume()
	else:
		pause_panel.show()
		resume_button.grab_focus()
		get_tree().paused = true


func _resume() -> void:
	pause_panel.hide()
	get_tree().paused = false


# --- Buttons -----------------------------------------------------------------
# Unpause before loading anything, or the new scene starts frozen.

func _on_rematch_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_resume_pressed() -> void:
	_resume()
