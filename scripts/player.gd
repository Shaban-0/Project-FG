extends CharacterBody2D

# Controls a fighter: movement, attacks, and the state machine that decides what
# the fighter is allowed to do at any given moment.
#
# Both players run this same script. The input_prefix export picks which set of
# input actions the instance reads, so Player 1 reads "p1_left" and Player 2
# reads "p2_left". That way there is only one file to maintain instead of two
# near-identical copies.


# The HUD listens for these instead of checking health every frame. Keeping it
# one-way means the fighter does not need to know the HUD exists.
signal health_changed(current: float, maximum: float)
signal knocked_out


# A fighter is always in exactly one state. Using an enum instead of strings
# means a typo is caught when the project builds rather than silently failing
# at runtime.
enum State { IDLE, WALK, JUMP, LIGHT_ATTACK, HEAVY_ATTACK, BLOCK, HIT, KO }


# --- Tuning Constants --------------------------------------------------------
# Everything here affects how the game feels, so it is grouped at the top to
# make it easy to adjust without reading through the logic.

const SPEED := 300.0
const JUMP_VELOCITY := -450.0     # negative because -Y is up in 2D
const GRAVITY := 1200.0

# How long each action locks the fighter in place. This is what makes attacking
# a risk as well as a threat, since you cannot cancel out of it.
const LIGHT_ATTACK_TIME := 0.25
const HEAVY_ATTACK_TIME := 0.45
const HIT_STUN_TIME := 0.30

const MAX_HEALTH := 100.0
const LIGHT_DAMAGE := 8.0
const HEAVY_DAMAGE := 15.0

# Edges of the playable area. A tester walked their fighter off the side of the
# screen in round 1, so movement is clamped to these.
const STAGE_LEFT := 60.0
const STAGE_RIGHT := 1092.0

# The fighters pass through each other rather than colliding, which fixed a bug
# where one could stand on the other's head and get stuck. This is how far apart
# they are kept instead.
const MIN_SEPARATION := 45.0

const HIT_FLASH_TIME := 0.25

const COLOUR_NORMAL := Color(1.0, 1.0, 1.0)
const COLOUR_HIT := Color(1.0, 0.35, 0.35)
const COLOUR_BLOCK := Color(0.6, 0.8, 1.0)


# --- Set per instance in the Inspector ---------------------------------------


@export var input_prefix: String = "p1"
@export var opponent_path: NodePath


# --- Node references ---------------------------------------------------------


@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox
@onready var hurtbox: Area2D = $Hurtbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var opponent: Node2D = get_node_or_null(opponent_path)

@onready var light_sound: AudioStreamPlayer = $LightSound
@onready var heavy_sound: AudioStreamPlayer = $HeavySound
@onready var block_sound: AudioStreamPlayer = $BlockSound


# --- Current state -----------------------------------------------------------


var state: State = State.IDLE
var state_timer: float = 0.0
var health: float = MAX_HEALTH
var facing: int = 1
var current_attack_damage: float = 0.0

# Held so a new flash can cancel one already running, otherwise the old tween
# keeps animating the colour and overwrites whatever the new state set.
var flash_tween: Tween = null


func _ready() -> void:
	var is_p1 := input_prefix == "p1"

	# Player 1's hurtbox sits on layer 1 and player 2's on layer 2, so each
	# hitbox only ever looks for the opponent and never for itself. Using the
	# set_collision_*_value helpers means these numbers match the checkboxes in
	# the Inspector rather than being raw bitmasks.
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = 0
	hurtbox.set_collision_layer_value(1 if is_p1 else 2, true)

	hitbox.collision_layer = 0
	hitbox.collision_mask = 0
	hitbox.set_collision_mask_value(2 if is_p1 else 1, true)

	hitbox.area_entered.connect(_on_hitbox_area_entered)

	facing = 1 if is_p1 else -1
	_update_facing()
	_set_hitbox_active(false)

	sprite.modulate = COLOUR_NORMAL
	_play_state_animation(state)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if state_timer > 0.0:
		state_timer -= delta

	_run_state()
	move_and_slide()

	# Run after move_and_slide so nothing can push a fighter out of bounds or
	# into the same space as the other one.
	_keep_within_stage()
	_keep_fighters_apart()


# --- State machine -----------------------------------------------------------


# Each state handles its own behaviour and decides its own exits. Having it all
# in one match statement means the rules about what a fighter can do are
# readable in one place, instead of being spread across a set of boolean flags.
func _run_state() -> void:
	match state:
		State.IDLE, State.WALK:
			_face_opponent()
			_ground_movement()
			_check_ground_actions()

		State.JUMP:
			_air_movement()
			if is_on_floor():
				_change_state(State.IDLE)

		State.LIGHT_ATTACK, State.HEAVY_ATTACK:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_change_state(State.IDLE)

		State.BLOCK:
			velocity.x = 0.0
			if not Input.is_action_pressed(_action("block")):
				_change_state(State.IDLE)

		State.HIT:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_change_state(State.IDLE)

		State.KO:
			velocity.x = 0.0


# Every state change goes through here, so anything that needs to happen on a
# transition (animation, hitbox, colour, sound) is defined once.
func _change_state(new_state: State, lock_time: float = 0.0) -> void:
	if state == new_state:
		return

	state = new_state
	state_timer = lock_time

	var attacking := new_state == State.LIGHT_ATTACK or new_state == State.HEAVY_ATTACK
	_set_hitbox_active(attacking)

	_apply_state_colour(new_state)
	_play_state_sound(new_state)
	_play_state_animation(new_state)


# Blocking turns the fighter blue. Round 1 showed the block pose on its own was
# not obvious enough, since only one of three testers found blocking unaided.
func _apply_state_colour(new_state: State) -> void:
	if new_state == State.HIT:
		return   # the hit flash handles its own colour

	_stop_flash()
	sprite.modulate = COLOUR_BLOCK if new_state == State.BLOCK else COLOUR_NORMAL


# Testers in round 1 all said there was no feedback confirming an action had
# happened. _change_state exits early when the state is unchanged, so these
# play once per transition rather than every frame.
func _play_state_sound(new_state: State) -> void:
	match new_state:
		State.LIGHT_ATTACK:
			light_sound.play()
		State.HEAVY_ATTACK:
			heavy_sound.play()
		State.BLOCK:
			block_sound.play()


# State.keys() gives the enum name as text, so IDLE becomes "idle" and
# LIGHT_ATTACK becomes "light_attack". The animations are named to match, which
# means adding a state does not need any extra branching here.
#
# Jump, walk, hit and KO have no artwork yet, so they fall back to idle. That
# keeps the game running instead of throwing a missing-animation error, and the
# remaining frames are listed as future work.
func _play_state_animation(new_state: State) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	var anim_name: String = State.keys()[new_state].to_lower()
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
	elif sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")


# --- Movement ----------------------------------------------------------------


func _ground_movement() -> void:
	# get_axis returns -1, 0 or +1, which avoids needing an if/else here.
	var direction := Input.get_axis(_action("left"), _action("right"))
	velocity.x = direction * SPEED
	_change_state(State.WALK if direction != 0.0 else State.IDLE)


func _air_movement() -> void:
	var direction := Input.get_axis(_action("left"), _action("right"))
	velocity.x = direction * SPEED


# Only called while grounded and free to act, so a fighter cannot spin round
# halfway through an attack and land it in the wrong direction.
func _face_opponent() -> void:
	if opponent == null:
		return

	var new_facing := 1 if opponent.global_position.x > global_position.x else -1
	if new_facing != facing:
		facing = new_facing
		_update_facing()


func _update_facing() -> void:
	hitbox_shape.position.x = absf(hitbox_shape.position.x) * facing
	sprite.flip_h = facing < 0


func _keep_within_stage() -> void:
	global_position.x = clampf(global_position.x, STAGE_LEFT, STAGE_RIGHT)


# Pushes the fighters apart if they get too close. They do not collide with each
# other physically, so without this they would end up standing in the same spot.
func _keep_fighters_apart() -> void:
	if opponent == null:
		return

	var gap := global_position.x - opponent.global_position.x

	# If they are exactly on top of each other the sign of the gap is undefined,
	# so nudge them in a fixed direction to break the tie.
	if is_zero_approx(gap):
		gap = 0.1 if input_prefix == "p1" else -0.1

	if absf(gap) < MIN_SEPARATION:
		var push := (MIN_SEPARATION - absf(gap)) * 0.5
		global_position.x += signf(gap) * push
		global_position.x = clampf(global_position.x, STAGE_LEFT, STAGE_RIGHT)


# --- Input -------------------------------------------------------------------


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
		# Held rather than pressed, because blocking is a stance you hold.
		_change_state(State.BLOCK)


# Builds the action name for this instance, e.g. "p1_left". Keeping it in one
# place means the naming scheme is only written down once.
func _action(action_name: String) -> String:
	return "%s_%s" % [input_prefix, action_name]


# --- Combat ------------------------------------------------------------------


func _set_hitbox_active(active: bool) -> void:
	if active:
		_update_facing()
	hitbox_shape.set_deferred("disabled", not active)


func _on_hitbox_area_entered(area: Area2D) -> void:
	var target := area.get_parent()
	if target.has_method("take_damage") and target != self:
		target.take_damage(current_attack_damage)
		_set_hitbox_active(false)   # stops one swing hitting twice


# Called by the opponent's hitbox. This is the only public entry point into the
# fighter, so the attacker does not need to know anything about how states work
# here — only that a fighter can be damaged.
func take_damage(amount: float) -> void:
	if state == State.KO:
		return

	# Blocking cancels the damage completely. Chip damage could go here later
	# without touching anything else.
	if state == State.BLOCK:
		return

	health = maxf(health - amount, 0.0)
	health_changed.emit(health, MAX_HEALTH)
	_flash_on_hit()

	if health <= 0.0:
		_change_state(State.KO)
		knocked_out.emit()
	else:
		_change_state(State.HIT, HIT_STUN_TIME)


# Flashes red on damage. Round 1 testers could not tell whether their attacks
# were landing, so this is the main visual confirmation that a hit connected.
func _flash_on_hit() -> void:
	_stop_flash()
	sprite.modulate = COLOUR_HIT
	flash_tween = create_tween()
	flash_tween.tween_property(sprite, "modulate", COLOUR_NORMAL, HIT_FLASH_TIME)


# Cancels a flash that is still fading, so it cannot carry on changing the
# colour after the fighter has moved into a different state.
func _stop_flash() -> void:
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()
	flash_tween = null
