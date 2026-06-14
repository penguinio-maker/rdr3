extends Node3D

@export var target_path: NodePath = NodePath("..")
@export var follow_height: float = 1.55
@export var follow_smoothness: float = 14.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = deg_to_rad(-42.0)
@export var max_pitch: float = deg_to_rad(24.0)
@export var default_pitch: float = deg_to_rad(-12.0)
@export var rider_follow_height: float = 2.65
@export var rider_spring_length: float = 7.4

@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D

var yaw: float = 0.0
var pitch: float = default_pitch
var target: Node3D
var normal_follow_height: float
var normal_spring_length: float
var wanted_follow_height: float
var wanted_spring_length: float
var shake_strength: float = 0.0
var shake_time: float = 0.0


func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)
	set_process(false)
	normal_follow_height = follow_height
	normal_spring_length = spring_arm.spring_length
	wanted_follow_height = normal_follow_height
	wanted_spring_length = normal_spring_length
	target = get_node_or_null(target_path) as Node3D
	if target:
		global_position = target.global_position + Vector3.UP * follow_height
		yaw = target.global_rotation.y
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		_apply_rotation()


func _physics_process(delta: float) -> void:
	if not target:
		return

	follow_height = lerp(follow_height, wanted_follow_height, 1.0 - exp(-5.5 * delta))
	spring_arm.spring_length = lerp(spring_arm.spring_length, wanted_spring_length, 1.0 - exp(-5.5 * delta))
	var wanted_position: Vector3 = target.global_position + Vector3.UP * follow_height
	var follow_weight: float = 1.0 - exp(-follow_smoothness * delta)
	global_position = global_position.lerp(wanted_position, follow_weight)
	shake_time += delta * 28.0
	var shake_offset: float = sin(shake_time) * shake_strength
	pitch_pivot.position.x = lerp(pitch_pivot.position.x, shake_offset * 0.45, delta * 12.0)
	pitch_pivot.position.z = lerp(pitch_pivot.position.z, cos(shake_time * 0.7) * shake_strength * 0.25, delta * 12.0)
	_apply_rotation()


func get_flat_forward() -> Vector3:
	return -Basis(Vector3.UP, yaw).z.normalized()


func get_flat_right() -> Vector3:
	return Basis(Vector3.UP, yaw).x.normalized()


func set_head_bob(amount: float) -> void:
	pitch_pivot.position.y = lerp(pitch_pivot.position.y, amount + absf(sin(shake_time)) * shake_strength, 0.35)


func set_horseback_mode(enabled: bool) -> void:
	wanted_follow_height = rider_follow_height if enabled else normal_follow_height
	wanted_spring_length = rider_spring_length if enabled else normal_spring_length
	if not enabled:
		set_gallop_shake(0.0)


func set_gallop_shake(amount: float) -> void:
	shake_strength = clampf(amount, 0.0, 0.08)


func _apply_rotation() -> void:
	rotation.y = yaw
	pitch_pivot.rotation.x = pitch
