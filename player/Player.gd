extends CharacterBody3D

const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const ANIM_RUN := &"Run"
const ANIM_JUMP := &"Jump"
const ANIM_FALL := &"Fall"

@export var walk_speed: float = 3.8
@export var sprint_speed: float = 7.4
@export var ground_acceleration: float = 18.0
@export var air_acceleration: float = 6.0
@export var braking: float = 16.0
@export var jump_velocity: float = 5.6
@export var fall_gravity_multiplier: float = 1.45
@export var max_fall_speed: float = 28.0
@export var coyote_time: float = 0.14
@export var jump_buffer_time: float = 0.16
@export var turn_speed: float = 13.0
@export var interact_radius: float = 3.0
@export var mounted_seat_offset: Vector3 = Vector3(0.0, -0.78, -0.08)

@onready var camera_pivot: Node = $CameraPivot
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var visual: Node3D = $Visual
@onready var left_arm: Node3D = $Visual/LeftArm
@onready var right_arm: Node3D = $Visual/RightArm
@onready var left_leg: Node3D = $Visual/LeftLeg
@onready var right_leg: Node3D = $Visual/RightLeg
@onready var coat_tail: Node3D = $Visual/CoatTail

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var stride_time: float = 0.0
var current_anim: StringName = &""
var animation_playback: AnimationNodeStateMachinePlayback
var mounted_horse: Node = null
var pre_mount_parent: Node = null
var pre_mount_index: int = -1


func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_animation_tree()
	_play_anim(ANIM_IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)

	var pressed_interact := event.is_action_pressed("interact")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		pressed_interact = true

	if pressed_interact:
		if mounted_horse:
			_dismount_horse()
		else:
			_try_mount_nearby_horse()


func _physics_process(delta: float) -> void:
	if mounted_horse:
		_follow_mounted_horse(delta)
		return

	var input_vector := _get_move_input()
	var move_direction := _camera_relative_direction(input_vector)
	var sprinting := _is_sprinting() and input_vector.length_squared() > 0.01
	var target_speed: float = sprint_speed if sprinting else walk_speed
	var target_horizontal_velocity := move_direction * target_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()

	_update_jump_timers(delta, grounded)
	_apply_horizontal_motion(delta, horizontal_velocity, target_horizontal_velocity, input_vector)
	_apply_vertical_motion(delta, grounded)
	_rotate_toward_motion(delta, move_direction)

	move_and_slide()
	_update_animation_state(input_vector, sprinting)
	_animate_proxy_body(delta, input_vector, sprinting)


func _get_move_input() -> Vector2:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input_vector += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vector.y += 1.0

	return input_vector.limit_length(1.0)


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector == Vector2.ZERO:
		return Vector3.ZERO

	var forward: Vector3 = camera_pivot.get_flat_forward()
	var right: Vector3 = camera_pivot.get_flat_right()
	return (right * input_vector.x + forward * -input_vector.y).normalized()


func _is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)


func _jump_was_pressed() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")


func _update_jump_timers(delta: float, grounded: bool) -> void:
	coyote_timer = coyote_time if grounded else maxf(coyote_timer - delta, 0.0)

	if _jump_was_pressed():
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)


func _apply_horizontal_motion(
	delta: float,
	horizontal_velocity: Vector3,
	target_horizontal_velocity: Vector3,
	input_vector: Vector2
) -> void:
	var rate: float = ground_acceleration if is_on_floor() else air_acceleration
	if input_vector == Vector2.ZERO and is_on_floor():
		rate = braking

	horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, rate * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


func _apply_vertical_motion(delta: float, grounded: bool) -> void:
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		return

	if grounded and velocity.y < 0.0:
		velocity.y = -0.2
		return

	var gravity_multiplier: float = fall_gravity_multiplier if velocity.y < 0.0 else 1.0
	velocity.y = maxf(velocity.y - gravity * gravity_multiplier * delta, -max_fall_speed)


func _rotate_toward_motion(delta: float, move_direction: Vector3) -> void:
	if move_direction.length_squared() < 0.001:
		return

	var wanted_yaw := atan2(move_direction.x, move_direction.z)
	rotation.y = lerp_angle(rotation.y, wanted_yaw, 1.0 - exp(-turn_speed * delta))


func _update_animation_state(input_vector: Vector2, sprinting: bool) -> void:
	if not is_on_floor():
		_play_anim(ANIM_JUMP if velocity.y > 0.0 else ANIM_FALL)
	elif input_vector.length_squared() > 0.01:
		_play_anim(ANIM_RUN if sprinting else ANIM_WALK)
	else:
		_play_anim(ANIM_IDLE)


func _play_anim(anim_name: StringName) -> void:
	if current_anim == anim_name:
		return

	current_anim = anim_name
	if animation_playback:
		animation_playback.travel(anim_name)
	else:
		animation_player.play(anim_name, 0.18)


func _setup_animation_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var anims: Array[StringName] = [ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_JUMP, ANIM_FALL]

	for anim_name in anims:
		var anim_node := AnimationNodeAnimation.new()
		anim_node.animation = anim_name
		state_machine.add_node(anim_name, anim_node)

	for from_anim in anims:
		for to_anim in anims:
			if from_anim == to_anim:
				continue

			var transition := AnimationNodeStateMachineTransition.new()
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			state_machine.add_transition(from_anim, to_anim, transition)

	animation_tree.tree_root = state_machine
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _animate_proxy_body(delta: float, input_vector: Vector2, sprinting: bool) -> void:
	var grounded := is_on_floor()
	var moving := input_vector.length_squared() > 0.01 and grounded
	var pace: float = 11.5 if sprinting else 7.2
	var swing: float = 0.62 if sprinting else 0.34
	if not moving:
		pace = 1.8
		swing = 0.035

	stride_time += delta * pace

	var stride := sin(stride_time)
	var opposite := sin(stride_time + PI)
	var arm_jump_curl: float = -0.62 if not grounded else 0.0
	var target_bob: float = 0.045 * abs(stride) if moving else 0.018 * sin(stride_time)
	var camera_bob: float = 0.035 * abs(stride) if sprinting and moving else 0.0

	left_arm.rotation.x = lerp(left_arm.rotation.x, stride * swing + arm_jump_curl, delta * 13.0)
	right_arm.rotation.x = lerp(right_arm.rotation.x, opposite * swing + arm_jump_curl, delta * 13.0)
	left_leg.rotation.x = lerp(left_leg.rotation.x, opposite * swing, delta * 13.0)
	right_leg.rotation.x = lerp(right_leg.rotation.x, stride * swing, delta * 13.0)
	var coat_tail_angle: float = -0.15 - abs(stride) * 0.18 if moving else -0.08
	coat_tail.rotation.x = lerp(coat_tail.rotation.x, coat_tail_angle, delta * 8.0)
	visual.position.y = lerp(visual.position.y, target_bob, delta * 10.0)
	camera_pivot.set_head_bob(camera_bob)


func _try_mount_nearby_horse() -> void:
	var horses := get_tree().get_nodes_in_group("horses")
	var closest_horse: Node = null
	var closest_distance := interact_radius

	for horse in horses:
		if not (horse is Node3D):
			continue

		var distance := global_position.distance_to((horse as Node3D).global_position)
		if distance < closest_distance:
			closest_horse = horse
			closest_distance = distance

	if closest_horse and closest_horse.has_method("mount"):
		closest_horse.mount(self)


func mount_horse(horse: Node) -> void:
	mounted_horse = horse
	velocity = Vector3.ZERO
	pre_mount_parent = get_parent()
	pre_mount_index = get_index()
	collision_layer = 0
	collision_mask = 0
	if horse is Node:
		reparent(horse, true)
	camera_pivot.set_horseback_mode(true)


func set_horse_camera_shake(amount: float) -> void:
	camera_pivot.set_gallop_shake(amount)


func _dismount_horse() -> void:
	if mounted_horse and mounted_horse.has_method("dismount"):
		mounted_horse.dismount()


func dismount_from_horse(exit_position: Vector3) -> void:
	var old_global_transform := global_transform
	if pre_mount_parent:
		reparent(pre_mount_parent, true)
		if pre_mount_index >= 0:
			pre_mount_parent.move_child(self, mini(pre_mount_index, pre_mount_parent.get_child_count() - 1))

	mounted_horse = null
	pre_mount_parent = null
	pre_mount_index = -1
	global_transform = old_global_transform
	global_position = exit_position
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	camera_pivot.set_horseback_mode(false)
	camera_pivot.set_gallop_shake(0.0)


func _follow_mounted_horse(delta: float) -> void:
	sync_to_mounted_horse(delta)


func sync_to_mounted_horse(delta: float) -> void:
	if not mounted_horse or not (mounted_horse is Node3D):
		mounted_horse = null
		return

	if mounted_horse.has_method("get_rider_transform"):
		global_transform = mounted_horse.get_rider_transform()
	else:
		var saddle := mounted_horse.get_node_or_null("Saddle")
		if saddle and saddle is Node3D:
			global_transform = (saddle as Node3D).global_transform

	global_position += global_transform.basis * mounted_seat_offset

	rotation.x = 0.0
	rotation.z = 0.0
	_play_anim(ANIM_IDLE)
	_animate_rider_idle(delta)


func _animate_rider_idle(delta: float) -> void:
	stride_time += delta * 2.4
	var breathing := sin(stride_time) * 0.025
	visual.position.y = lerp(visual.position.y, breathing, delta * 5.0)
	left_arm.rotation.x = lerp(left_arm.rotation.x, -0.25, delta * 8.0)
	right_arm.rotation.x = lerp(right_arm.rotation.x, -0.25, delta * 8.0)
	left_leg.rotation.x = lerp(left_leg.rotation.x, -0.45, delta * 8.0)
	right_leg.rotation.x = lerp(right_leg.rotation.x, -0.45, delta * 8.0)
