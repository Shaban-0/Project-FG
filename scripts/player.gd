extends CharacterBody2D

# =============================================================================
#  player.gd — fighter controller and finite state machine
#
#  Attached to:  Player (CharacterBody2D) in scenes/player.tscn
#  Used by:      Both fighters. One instance per player; the `input_prefix`
#                export decides which set of input actions the instance reads.
#  Requirements: FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-08,
#                FR-16, FR-17, FR-18, NFR-05
#
#  Purpose
#  -------
#  Governs everything a fighter can do: horizontal movement, jumping, and the
#  state machine that decides which actions are legal at any given moment.
#  A fighter is always in exactly one state, which is what prevents illegal
#  combinations such as attacking while blocking while airborne.
# =============================================================================


# --- Tuning constants --------------------------------------------------------
# Grouped at the top and named in CAPS so that game feel can be tuned in one
# place without reading the logic below.


const SPEED := 300.0            # horizontal movement, pixels per second
const JUMP_VELOCITY := -450.0   # upward launch; negative because -Y is up in 2D
const GRAVITY := 1200.0         # downward acceleration, pixels per second squared

# How long, in seconds, each committed action locks the fighter in place.
# "Commitment" is central to fighting games: once an attack starts, the player
# cannot cancel it, which is what makes attacking a risk as well as a threat.
const LIGHT_ATTACK_TIME := 0.25
const HEAVY_ATTACK_TIME := 0.45
const HIT_STUN_TIME := 0.30

const MAX_HEALTH := 100.0

const LIGHT_DAMAGE := 8.0
const HEAVY_DAMAGE := 15.0

var current_attack_damage: float = 0.0


# --- Per-instance configuration ---------------------------------------------
# Exported so it can be set separately on each fighter in the Inspector.
# Player 1's instance reads "p1_left", "p1_jump", ...; Player 2's reads
# "p2_left", "p2_jump", ... This is why one script can serve both players
# rather than duplicating the file (FR-01, FR-18, NFR-05).


@export var input_prefix: String = "p1"


# --- State ------------------------------------------------------------------
# The full set of states a fighter can occupy. Using an enum rather than
# strings means a typo is a compile-time error, not a silent bug at runtime.


enum State { IDLE, WALK, JUMP, LIGHT_ATTACK, HEAVY_ATTACK, BLOCK, HIT, KO }

var state: State = State.IDLE
var state_timer: float = 0.0    # while greater than zero, the state is locked
var health: float = MAX_HEALTH


# --- Main loop ---------------------------------------------------------------


## Runs at a fixed 60 times per second. Physics and movement live here rather
## than in _process so that behaviour is identical regardless of frame rate.
func _physics_process(delta: float) -> void:
	# Gravity applies in every state, so it sits outside the state machine.
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Count down the lock on any committed action.
	if state_timer > 0.0:
		state_timer -= delta

	_run_state()

	# Applies `velocity`, resolves collisions, and refreshes is_on_floor().
	move_and_slide()

	## Text overlay above each fighter, which updates the state changes 
	## in real time. It's useful for debugging.
	$Label.text = "%s  %d" % [get_state_name(), health]


# --- State machine -----------------------------------------------------------


## Executes the behaviour of the current state and decides its transitions.
## Every state is handled in exactly one place, so the rules governing what a
## fighter may do are readable in a single screen of code.
func _run_state() -> void:
	match state:
		State.IDLE, State.WALK:
			# Grounded and free to act.
			_ground_movement()
			_check_ground_actions()

		State.JUMP:
			# Airborne: steering is allowed, new actions are not.
			_air_movement()
			if is_on_floor():
				_change_state(State.IDLE)

		State.LIGHT_ATTACK, State.HEAVY_ATTACK:
			# Attacks commit the fighter: no movement until the timer expires.
			velocity.x = 0.0
			if state_timer <= 0.0:
				_change_state(State.IDLE)

		State.BLOCK:
			# Blocking roots the fighter and lasts only while the button is held.
			velocity.x = 0.0
			if not Input.is_action_pressed(_action("block")):
				_change_state(State.IDLE)

		State.HIT:
			# Hit stun: the fighter is briefly unable to act.
			velocity.x = 0.0
			if state_timer <= 0.0:
				_change_state(State.IDLE)

		State.KO:
			# Terminal state for this round; no input is accepted.
			velocity.x = 0.0


## The single point of entry for every state change.
## Routing all transitions through one function means new behaviour (playing an
## animation, emitting a signal) can be added in one place later.
func _change_state(new_state: State, lock_time: float = 0.0) -> void:
	if state == new_state:
		return
	state = new_state
	state_timer = lock_time
	
	# The hitbox is live only during an attack state.
	var attacking := new_state == State.LIGHT_ATTACK or new_state == State.HEAVY_ATTACK
	_set_hitbox_active(attacking)


# --- Movement helpers --------------------------------------------------------


## Horizontal movement while grounded, and the idle/walk distinction.
func _ground_movement() -> void:
	# get_axis returns -1 (left), 0 (neither or both), or +1 (right).
	var direction := Input.get_axis(_action("left"), _action("right"))
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	velocity.x = direction * SPEED
	_change_state(State.WALK if direction != 0.0 else State.IDLE)


## Air control. Kept separate from ground movement so the two can be tuned
## independently later without disturbing each other.
func _air_movement() -> void:
	var direction := Input.get_axis(_action("left"), _action("right"))
	velocity.x = direction * SPEED


# --- Input -------------------------------------------------------------------


## Actions that may be started from the ground, in priority order.
## Attacks and jumps use just_pressed so they fire once per press; block uses
## is_action_pressed because it is a held stance rather than a one-off action.
func _check_ground_actions() -> void:
	if Input.is_action_just_pressed(_action("jump")):
		velocity.y = JUMP_VELOCITY
		_change_state(State.JUMP)
	elif Input.is_action_just_pressed(_action("light")):
		current_attack_damage = LIGHT_DAMAGE
		_change_state(State.LIGHT_ATTACK, LIGHT_ATTACK_TIME)
	elif Input.is_action_just_pressed(_action("heavy")):
		current_attack_damage = HEAVY_DAMAGE
		_change_state(State.HEAVY_ATTACK, HEAVY_ATTACK_TIME)
	elif Input.is_action_pressed(_action("block")):
		_change_state(State.BLOCK)


## Builds the input action name for this instance, e.g. "p1_left".
## Isolating this here means the input naming scheme is defined once.
func _action(action_name: String) -> String:
	return "%s_%s" % [input_prefix, action_name]


# --- Combat interface --------------------------------------------------------


## Called by the opponent's hitbox when this fighter is struck.
## Public so that the hitbox system can reach it, while the state machine's
## internals stay private (low coupling: the hitbox needs to know nothing about
## how states work, only that a fighter can be damaged).
func take_damage(amount: float) -> void:
	# A knocked-out fighter cannot be hit again.
	if state == State.KO:
		return

	# Blocking negates the damage entirely for now. Chip damage could be
	# introduced here later without touching any other script.
	if state == State.BLOCK:
		return

	health = max(health - amount, 0.0)

	if health <= 0.0:
		_change_state(State.KO)
	else:
		_change_state(State.HIT, HIT_STUN_TIME)


## Returns the current state's name as text, for the on-screen debug label
## and for screenshots used as evidence in the report.
func get_state_name() -> String:
	return State.keys()[state]


# --- Node references ---------------------------------------------------------


@onready var hitbox: Area2D = $Hitbox
@onready var hurtbox: Area2D = $Hurtbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

# Which way this fighter is facing: 1 = right, -1 = left.
var facing: int = 1

## Configures collision layers so that a fighter's hitbox can only ever strike
## the opponent's hurtbox, never its own. Called once when the node enters the
## scene tree, driven by the same input_prefix that selects the input actions.
func _ready() -> void:
	var is_p1 := input_prefix == "p1"

	# Hurtbox announces itself on this player's layer; it detects nothing.
	# Hitbox announces nothing; it looks for the opponent's hurtbox layer.
	# Layer numbers here match the Inspector checkboxes exactly (1-based).
	# Layer 1 = p1_hurtbox, layer 2 = p2_hurtbox.
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = 0
	hurtbox.set_collision_layer_value(1 if is_p1 else 2, true)

	hitbox.collision_layer = 0
	hitbox.collision_mask = 0
	hitbox.set_collision_mask_value(2 if is_p1 else 1, true)


	# Connect the overlap signal to our handler (FR-07).
	hitbox.area_entered.connect(_on_hitbox_area_entered)


	# P2 starts on the right, facing left.
	facing = 1 if is_p1 else -1
	_update_facing()          # apply facing immediately, not just on attack
	_set_hitbox_active(false)

	print("[%s] ready. hurtbox layer=%d, hitbox mask=%d, facing=%d"
		% [input_prefix, hurtbox.collision_layer, hitbox.collision_mask, facing])


## Mirrors the hitbox to whichever side the fighter is facing.
func _update_facing() -> void:
	hitbox_shape.position.x = abs(hitbox_shape.position.x) * facing
	if has_node("Sprite2D"):
		$Sprite2D.flip_h = facing < 0


## Enables or disables the attack hitbox. Kept as its own function so the state
## machine never touches the collision shape directly (low coupling).
func _set_hitbox_active(active: bool) -> void:
	if active:
		_update_facing()
	hitbox_shape.set_deferred("disabled", not active)


## Fired when this fighter's active hitbox overlaps an opponent hurtbox.
## Damage is applied through the opponent's public take_damage interface, so
## this script needs to know nothing about how their state machine works.
func _on_hitbox_area_entered(area: Area2D) -> void:
	var opponent := area.get_parent()
	print("[%s] hitbox overlapped: %s" % [input_prefix, opponent.name])
	if opponent.has_method("take_damage") and opponent != self:
		opponent.take_damage(current_attack_damage)
		_set_hitbox_active(false)  # one hit per attack
		
