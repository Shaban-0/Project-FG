extends Node2D


# =============================================================================
#  match_manager.gd — round state and HUD coordination
#
#  Attached to:  the root node of scenes/main.tscn
#  Requirements: FR-09, FR-10, FR-11, FR-12, NFR-08
#
#  Purpose
#  -------
#  Owns everything about a round that is not a fighter's own business: the
#  countdown timer, when the round ends, and who won. The fighters know nothing
#  about rounds, and the HUD knows nothing about fighters — this script is the
#  only thing that connects them.
# =============================================================================


const ROUND_LENGTH := 15.0   # seconds; NFR-08 keeps a round under ~99s

@onready var p1: CharacterBody2D = $Player
@onready var p2: CharacterBody2D = $Player2
@onready var p1_health: ProgressBar = $HUD/P1Health
@onready var p2_health: ProgressBar = $HUD/P2Health
@onready var timer_label: Label = $HUD/Timer
@onready var result_label: Label = $HUD/RoundResult

var time_remaining: float = ROUND_LENGTH
var round_over: bool = false


func _ready() -> void:
	# Listen to each fighter rather than polling them every frame.
	p1.health_changed.connect(_on_p1_health_changed)
	p2.health_changed.connect(_on_p2_health_changed)
	p1.knocked_out.connect(_on_fighter_knocked_out.bind(p1))
	p2.knocked_out.connect(_on_fighter_knocked_out.bind(p2))

	result_label.text = ""
	_update_timer_display()


func _process(delta: float) -> void:
	if round_over:
		return

	time_remaining = max(time_remaining - delta, 0.0)
	_update_timer_display()

	# FR-11: a round also ends when the timer expires.
	if time_remaining <= 0.0:
		_end_round_on_time()


func _update_timer_display() -> void:
	timer_label.text = str(int(ceil(time_remaining)))


# --- Signal handlers ---------------------------------------------------------


func _on_p1_health_changed(current: float, maximum: float) -> void:
	p1_health.max_value = maximum
	p1_health.value = current


func _on_p2_health_changed(current: float, maximum: float) -> void:
	p2_health.max_value = maximum
	p2_health.value = current


## FR-11 / FR-12: a knockout ends the round, and the surviving fighter wins.
func _on_fighter_knocked_out(loser: CharacterBody2D) -> void:
	if round_over:
		return
	round_over = true
	var winner_name := "PLAYER 2" if loser == p1 else "PLAYER 1"
	result_label.text = "%s WINS" % winner_name


## FR-11: if time runs out, the fighter with more health remaining wins.
func _end_round_on_time() -> void:
	round_over = true
	if p1.health > p2.health:
		result_label.text = "PLAYER 1 WINS"
	elif p2.health > p1.health:
		result_label.text = "PLAYER 2 WINS"
	else:
		result_label.text = "DRAW"
