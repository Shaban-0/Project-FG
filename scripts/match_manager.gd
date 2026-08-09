extends Node2D

# =============================================================================
#  match_manager.gd — round state, HUD coordination, pause and result overlays
#
#  Attached to:  the root node of scenes/main.tscn
#  Requirements: FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-19, FR-20, NFR-08
#
#  Purpose
#  -------
#  Owns everything about a round that is not a fighter's own business: the
#  countdown, when the round ends, who won, and the pause and result overlays.
#  The fighters know nothing about rounds; the HUD knows nothing about fighters.
#  This script is the only thing that connects the two, which keeps both sides
#  independently testable and replaceable (low coupling, NFR-05).
#
#  Scene requirements
#  ------------------
#  The root node's Process Mode must be set to "Always" so that pause input is
#  still received while the tree is paused. Player and Player2 must each be set
#  to "Pausable" so that they freeze. See the report for the rationale.
# =============================================================================


## Round length in seconds. NFR-08 requires a round to stay short enough that
## the demo entertains for a few minutes rather than occupying an open-day stand.
const ROUND_LENGTH := 60.0


# --- Node references ---------------------------------------------------------

@onready var p1: CharacterBody2D = $Player
@onready var p2: CharacterBody2D = $Player2

@onready var p1_health: ProgressBar = $HUD/P1Health
@onready var p2_health: ProgressBar = $HUD/P2Health
@onready var timer_label: Label = $HUD/Timer

@onready var result_panel: Control = $HUD/ResultOverlay
@onready var result_label: Label = $HUD/ResultOverlay/VBox/ResultLabel
@onready var rematch_button: Button = $HUD/ResultOverlay/VBox/RematchButton

@onready var pause_panel: Control = $HUD/PauseOverlay
@onready var resume_button: Button = $HUD/PauseOverlay/VBox/ResumeButton


# --- State -------------------------------------------------------------------

var time_remaining: float = ROUND_LENGTH
var round_over: bool = false


func _ready() -> void:
	# Listen to each fighter rather than polling them every frame. bind() passes
	# which fighter was knocked out, so one handler serves both players.
	p1.health_changed.connect(_on_p1_health_changed)
	p2.health_changed.connect(_on_p2_health_changed)
	p1.knocked_out.connect(_on_fighter_knocked_out.bind(p1))
	p2.knocked_out.connect(_on_fighter_knocked_out.bind(p2))

	# Show full bars before any damage is taken. Without this the bars sit at
	# their editor default of zero until the first hit lands.
	_on_p1_health_changed(p1.health, p1.MAX_HEALTH)
	_on_p2_health_changed(p2.health, p2.MAX_HEALTH)

	result_panel.hide()
	pause_panel.hide()
	_update_timer_display()


func _process(delta: float) -> void:
	# The root node runs with Process Mode "Always" so that pause input is still
	# received, which means the countdown must be stopped explicitly.
	if round_over or get_tree().paused:
		return

	time_remaining = max(time_remaining - delta, 0.0)
	_update_timer_display()

	# FR-11: a round also ends when the timer expires.
	if time_remaining <= 0.0:
		_end_round_on_time()


## FR-20: the pause menu opens and closes on the Start button or Escape.
## Handled in _unhandled_input so that a focused button consumes its own input
## first and the pause key does not fire twice.
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


# --- Round end ---------------------------------------------------------------

## FR-11 / FR-12: a knockout ends the round and the surviving fighter wins.
func _on_fighter_knocked_out(loser: CharacterBody2D) -> void:
	if round_over:
		return
	_show_result("PLAYER 2 WINS" if loser == p1 else "PLAYER 1 WINS")


## FR-11: if time runs out, the fighter with more health remaining wins.
func _end_round_on_time() -> void:
	if p1.health > p2.health:
		_show_result("PLAYER 1 WINS")
	elif p2.health > p1.health:
		_show_result("PLAYER 2 WINS")
	else:
		_show_result("DRAW")


## Displays the result overlay and freezes the match beneath it.
## Focus is moved to the rematch button so that the overlay is immediately
## operable with a controller and no mouse is required (FR-19).
func _show_result(text: String) -> void:
	round_over = true
	result_label.text = text
	result_panel.show()
	rematch_button.grab_focus()
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


# --- Button handlers ---------------------------------------------------------
# The tree must be unpaused before changing or reloading a scene, otherwise the
# newly loaded scene starts frozen.

## FR-13: restart the match from the result overlay.
func _on_rematch_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## FR-14: return to the main menu from the result overlay or the pause menu.
func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_resume_pressed() -> void:
	_resume()
