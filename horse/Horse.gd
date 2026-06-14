extends CharacterBody3D

const HORSE_IDLE: StringName = &"HorseIdle"
const HORSE_WALK: StringName = &"HorseWalk"
const HORSE_TROT: StringName = &"HorseTrot"
const HORSE_GALLOP: StringName = &"HorseGallop"
const HORSE_JUMP: StringName = &"HorseJump"
const HORSE_LAND: StringName = &"HorseLand"

@export var walk_speed: float = 5.2
@export var trot_speed: float = 8.0
@export var gallop_speed: float = 12.8
@export var acceleration: float = 7.5
@export var deceleration: float = 9.0
@export var turn_speed: float = 3.8
@export var gravity_multiplier: float = 1.15
@export var jump_velocity: float = 6.2
@export var jump_cooldown: float = 0.75

@onready var body: Node3D = $Visual/Body
@onready var neck: Node3D = $Visual/Neck
@onready var head: Node3D = $Visual/Neck/Head
@onready var tail: Node3D = $Visual/Tail
@onready var front_left_leg: Node3D = $Visual/FrontLeftLeg
@onready var front_right_leg: Node3D = $Visual/FrontRightLeg
@onready var back_left_leg: Node3D = $Visual/BackLeftLeg
@onready var back_right_leg: Node3D = $Visual/BackRightLeg
@onready var rider_hint: Label3D = $InteractHint
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var dust_particles: GPUParticles3D = $DustParticles
@onready var hoof_audio: AudioStreamPlayer3D = $HoofAudio

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var rider: Node = null
var gait_time: float = 0.0
var current_speed: float = 0.0
var current_anim: StringName = &""
var animation_playback: AnimationNodeStateMachinePlayback
var jump_cooldown_timer: float = 0.0
var was_on_floor: bool = true
var just_landed_timer: float = 0.0
var hoof_timer: float = 0.0


func _ready() -> void:
	add_to_group("horses")
	rider_hint.visible = false
	dust_particles.emitting = false
	hoof_audio.stream = _make_hoof_wav()
	_setup_animation_tree()


func _physics_process(delta: float) -> void:
	if rider:
		_drive_with_rider(delta)
	else:
		_idle(delta)

	_apply_gravity(delta)
	var floor_before_move: bool = is_on_floor()
	move_and_slide()
	_sync_rider_after_move(0.0)
	_update_landing_state(floor_before_move)
	_update_hint()
	jump_cooldown_timer = maxf(jump_cooldown_timer - delta, 0.0)
	just_landed_timer = maxf(just_landed_timer - delta, 0.0)


func mount(new_rider: Node) -> void:
	if rider:
		return

	rider = new_rider
	if rider.has_method("mount_horse"):
		rider.mount_horse(self)
	rider_hint.visible = false


func dismount() -> void:
	if not rider:
		return

	var exit_position: Vector3 = _find_dismount_position()
	if rider.has_method("dismount_from_horse"):
		rider.dismount_from_horse(exit_position)
	if rider.has_method("set_horse_camera_shake"):
		rider.set_horse_camera_shake(0.0)
	rider = null


func _drive_with_rider(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input_vector += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	input_vector = input_vector.limit_length(1.0)

	var sprinting: bool = Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	var target_speed: float = gallop_speed if sprinting else trot_speed
	var forward_amount: float = -input_vector.y
	var turn_amount: float = input_vector.x
	if absf(forward_amount) < 0.05:
		target_speed = 0.0
	elif not sprinting and absf(forward_amount) < 0.65:
		target_speed = walk_speed

	var speed_ratio: float = clampf(absf(current_speed) / gallop_speed, 0.25, 1.0)
	rotate_y(-turn_amount * turn_speed * speed_ratio * delta)

	var target_signed_speed: float = forward_amount * target_speed
	var rate: float = acceleration if absf(target_signed_speed) > absf(current_speed) else deceleration
	current_speed = move_toward(current_speed, target_signed_speed, rate * delta)
	var target_velocity: Vector3 = -global_transform.basis.z * current_speed
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z
	var move_amount: float = clampf(absf(current_speed) / gallop_speed, 0.0, 1.0)
	if _jump_pressed() and _can_jump():
		_start_jump()
	_animate_horse(delta, move_amount, sprinting)
	_update_dust(move_amount, sprinting)
	_update_rider_camera_shake(move_amount, sprinting)
	_update_hoofbeats(delta, move_amount, sprinting)


func _idle(delta: float) -> void:
	current_speed = move_toward(current_speed, 0.0, deceleration * delta)
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_animate_horse(delta, 0.0, false)
	_update_dust(0.0, false)
	hoof_timer = 0.0


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.1
	else:
		velocity.y -= gravity * gravity_multiplier * delta


func get_rider_transform() -> Transform3D:
	var saddle: Node = get_node_or_null("Saddle")
	if saddle and saddle is Node3D:
		return (saddle as Node3D).global_transform

	return global_transform.translated(Vector3.UP * 1.45)


func _find_dismount_position() -> Vector3:
	var side_position: Vector3 = global_position + global_transform.basis.x * 1.55 + Vector3.UP * 0.8
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(side_position + Vector3.UP * 4.0, side_position + Vector3.DOWN * 8.0)
	query.exclude = [self.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.has("position"):
		return (hit["position"] as Vector3) + Vector3.UP * 0.08

	return side_position


func _animate_horse(delta: float, move_amount: float, sprinting: bool) -> void:
	var pace: float = 12.5 if sprinting else 7.5
	var swing: float = 0.72 if sprinting else 0.42
	var gait_rate: float = pace if move_amount > 0.05 else 1.4
	gait_time += delta * gait_rate

	var stride: float = sin(gait_time) * swing * move_amount
	var opposite: float = sin(gait_time + PI) * swing * move_amount
	body.position.y = lerp(body.position.y, 0.96 + abs(stride) * 0.06, delta * 8.0)
	body.rotation.z = lerp(body.rotation.z, -Input.get_axis("move_left", "move_right") * 0.08 * move_amount, delta * 5.0)
	neck.rotation.x = lerp(neck.rotation.x, -0.22 + abs(stride) * 0.12, delta * 6.0)
	head.rotation.x = lerp(head.rotation.x, 0.12 - abs(stride) * 0.1, delta * 6.0)
	tail.rotation.x = lerp(tail.rotation.x, 0.42 + sin(gait_time * 0.7) * 0.14, delta * 5.0)
	front_left_leg.rotation.x = lerp(front_left_leg.rotation.x, stride, delta * 12.0)
	back_right_leg.rotation.x = lerp(back_right_leg.rotation.x, stride, delta * 12.0)
	front_right_leg.rotation.x = lerp(front_right_leg.rotation.x, opposite, delta * 12.0)
	back_left_leg.rotation.x = lerp(back_left_leg.rotation.x, opposite, delta * 12.0)
	_play_anim(_wanted_anim(move_amount, sprinting))


func _wanted_anim(move_amount: float, sprinting: bool) -> StringName:
	if just_landed_timer > 0.0:
		return HORSE_LAND
	if not is_on_floor():
		return HORSE_JUMP
	if move_amount < 0.05:
		return HORSE_IDLE
	if sprinting or move_amount > 0.72:
		return HORSE_GALLOP
	if move_amount > 0.42:
		return HORSE_TROT
	return HORSE_WALK


func _play_anim(anim_name: StringName) -> void:
	if current_anim == anim_name:
		return

	current_anim = anim_name
	if animation_playback:
		animation_playback.travel(anim_name)
	else:
		animation_player.play(anim_name, 0.18)


func _setup_animation_tree() -> void:
	var state_machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	var anims: Array[StringName] = [HORSE_IDLE, HORSE_WALK, HORSE_TROT, HORSE_GALLOP, HORSE_JUMP, HORSE_LAND]

	for anim_name in anims:
		var anim_node: AnimationNodeAnimation = AnimationNodeAnimation.new()
		anim_node.animation = anim_name
		state_machine.add_node(anim_name, anim_node)

	for from_anim in anims:
		for to_anim in anims:
			if from_anim == to_anim:
				continue

			var transition: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			state_machine.add_transition(from_anim, to_anim, transition)

	animation_tree.tree_root = state_machine
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_play_anim(HORSE_IDLE)


func _jump_pressed() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)


func _can_jump() -> bool:
	return is_on_floor() and jump_cooldown_timer <= 0.0


func _start_jump() -> void:
	velocity.y = jump_velocity
	jump_cooldown_timer = jump_cooldown
	just_landed_timer = 0.0
	_play_anim(HORSE_JUMP)
	dust_particles.restart()
	dust_particles.emitting = true


func _update_landing_state(floor_before_move: bool) -> void:
	var grounded_now: bool = is_on_floor()
	if not floor_before_move and grounded_now:
		just_landed_timer = 0.22
		_play_anim(HORSE_LAND)
		dust_particles.restart()
		dust_particles.emitting = true
	was_on_floor = grounded_now


func _update_dust(move_amount: float, sprinting: bool) -> void:
	var should_emit: bool = is_on_floor() and move_amount > 0.18
	dust_particles.emitting = should_emit
	var dust_amount: float = 1.0 if sprinting else 0.45
	dust_particles.amount_ratio = dust_amount


func _update_rider_camera_shake(move_amount: float, sprinting: bool) -> void:
	if not rider or not rider.has_method("set_horse_camera_shake"):
		return

	var shake: float = 0.065 * move_amount if sprinting and is_on_floor() else 0.0
	rider.set_horse_camera_shake(shake)


func _update_hoofbeats(delta: float, move_amount: float, sprinting: bool) -> void:
	if not is_on_floor() or move_amount < 0.12:
		return

	hoof_timer -= delta
	if hoof_timer > 0.0:
		return

	hoof_timer = 0.16 if sprinting else 0.28
	hoof_audio.pitch_scale = randf_range(0.88, 1.16) if sprinting else randf_range(0.78, 1.02)
	hoof_audio.volume_db = -5.0 if sprinting else -9.0
	hoof_audio.play()


func _make_hoof_wav() -> AudioStreamWAV:
	var sample_rate: int = 16000
	var sample_count: int = int(0.09 * sample_rate)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for i in range(sample_count):
		var t: float = float(i) / float(sample_rate)
		var thump: float = sin(t * TAU * 90.0) * exp(-t * 34.0)
		var grit: float = rng.randf_range(-0.35, 0.35) * exp(-t * 40.0)
		var sample: int = clampi(int((thump + grit) * 22000.0), -32768, 32767)
		bytes.encode_s16(i * 2, sample)

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _sync_rider_after_move(delta: float) -> void:
	if rider and rider.has_method("sync_to_mounted_horse"):
		rider.sync_to_mounted_horse(delta)


func _update_hint() -> void:
	if rider:
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if not player or not (player is Node3D):
		rider_hint.visible = false
		return

	rider_hint.visible = global_position.distance_to((player as Node3D).global_position) < 3.0
