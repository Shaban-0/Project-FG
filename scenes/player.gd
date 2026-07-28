extends CharacterBody2D

const SPEED := 300.0          # horizontal move speed, pixels/second
const JUMP_VELOCITY := -450.0 # upward launch (negative = up in 2D)
const GRAVITY := 1200.0       # downward pull, pixels/second squared

func _physics_process(delta: float) -> void:
	# 1. Gravity: pull down every frame we're airborne
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# 2. Jump: only when the button is first pressed AND we're grounded
	if Input.is_action_just_pressed("p1_jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. Horizontal: get_axis returns -1 (left), 0 (nothing), or +1 (right)
	var direction := Input.get_axis("p1_left", "p1_right")
	velocity.x = direction * SPEED

	# 4. Apply the velocity and slide along any collisions
	move_and_slide()
