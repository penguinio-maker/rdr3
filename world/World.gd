extends Node3D

@export var terrain_size: int = 320
@export var terrain_resolution: int = 88
@export var hill_height: float = 7.0
@export var grass_count: int = 1600
@export var bush_count: int = 90
@export var rock_scatter_count: int = 130
@export var cactus_count: int = 42
@export var day_length_seconds: float = 180.0

@onready var terrain_mesh: MeshInstance3D = $Ground/TerrainMesh
@onready var terrain_collision: CollisionShape3D = $Ground/CollisionShape3D
@onready var grass: MultiMeshInstance3D = $Grass
@onready var bushes: MultiMeshInstance3D = $Bushes
@onready var scattered_rocks: MultiMeshInstance3D = $ScatteredRocks
@onready var cacti: MultiMeshInstance3D = $Cacti
@onready var sun: DirectionalLight3D = $SunsetLight
@onready var wind_audio: AudioStreamPlayer = $WindAudio

var time_of_day: float = 0.22


func _ready() -> void:
	_build_terrain()
	_build_grass()
	_build_bushes()
	_build_rocks()
	_build_cacti()
	_snap_terrain_props()
	_setup_wind()


func _process(delta: float) -> void:
	_update_day_night(delta)


func get_height_at(world_x: float, world_z: float) -> float:
	return _height(world_x, world_z)


func _build_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_size := terrain_size * 0.5
	var step := float(terrain_size) / float(terrain_resolution)

	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var x0 := -half_size + x * step
			var x1 := x0 + step
			var z0 := -half_size + z * step
			var z1 := z0 + step

			_add_quad(surface, Vector3(x0, _height(x0, z0), z0), Vector3(x1, _height(x1, z0), z0), Vector3(x1, _height(x1, z1), z1), Vector3(x0, _height(x0, z1), z1))

	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	terrain_mesh.mesh = mesh
	terrain_collision.shape = mesh.create_trimesh_shape()


func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.set_uv(Vector2(a.x, a.z) * 0.08)
	surface.add_vertex(a)
	surface.set_uv(Vector2(b.x, b.z) * 0.08)
	surface.add_vertex(b)
	surface.set_uv(Vector2(c.x, c.z) * 0.08)
	surface.add_vertex(c)
	surface.set_uv(Vector2(a.x, a.z) * 0.08)
	surface.add_vertex(a)
	surface.set_uv(Vector2(c.x, c.z) * 0.08)
	surface.add_vertex(c)
	surface.set_uv(Vector2(d.x, d.z) * 0.08)
	surface.add_vertex(d)


func _height(x: float, z: float) -> float:
	var broad: float = sin(x * 0.026) * cos(z * 0.023) * hill_height
	var ridge: float = sin((x + z) * 0.047) * 1.2
	var detail: float = sin((x - z) * 0.11) * 0.36 + cos(z * 0.15) * 0.28
	var arroyo: float = -pow(maxf(0.0, 1.0 - absf(sin((x + z * 0.45) * 0.025)) * 5.0), 2.0) * 2.2
	return broad * 0.55 + ridge + detail + arroyo


func _build_grass() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = grass.multimesh.mesh
	multi.instance_count = grass_count
	grass.multimesh = multi

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var half_size := terrain_size * 0.46

	for i in range(grass_count):
		var x := rng.randf_range(-half_size, half_size)
		var z := rng.randf_range(-half_size, half_size)
		var y := _height(x, z)
		var scale := rng.randf_range(0.55, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, rng.randf_range(0.7, 1.5), scale))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, y + 0.05, z)))


func _build_bushes() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = bushes.multimesh.mesh
	multi.instance_count = bush_count
	bushes.multimesh = multi

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var half_size := terrain_size * 0.43

	for i in range(bush_count):
		var x := rng.randf_range(-half_size, half_size)
		var z := rng.randf_range(-half_size, half_size)
		var y := _height(x, z)
		var scale := rng.randf_range(0.7, 1.8)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, rng.randf_range(0.45, 0.9), scale))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, y + 0.16, z)))


func _snap_terrain_props() -> void:
	for prop in get_tree().get_nodes_in_group("terrain_props"):
		if not (prop is Node3D):
			continue

		var prop_3d: Node3D = prop as Node3D
		var pos: Vector3 = prop_3d.global_position
		pos.y = _height(pos.x, pos.z)
		prop_3d.global_position = pos


func _build_rocks() -> void:
	_fill_multimesh(scattered_rocks, rock_scatter_count, 5151, 0.18, 0.85, 0.08)


func _build_cacti() -> void:
	_fill_multimesh(cacti, cactus_count, 9191, 0.9, 1.8, 0.35)


func _fill_multimesh(target: MultiMeshInstance3D, count: int, seed: int, min_scale: float, max_scale: float, y_offset: float) -> void:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = target.multimesh.mesh
	multi.instance_count = count
	target.multimesh = multi
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var half_size: float = terrain_size * 0.45
	for i in range(count):
		var x: float = rng.randf_range(-half_size, half_size)
		var z: float = rng.randf_range(-half_size, half_size)
		var y: float = _height(x, z)
		var s: float = rng.randf_range(min_scale, max_scale)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.75, 1.35), s))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, y + y_offset, z)))


func _update_day_night(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
	var sun_angle: float = time_of_day * TAU - PI * 0.5
	sun.rotation = Vector3(sin(sun_angle) * 0.85, -0.7, cos(sun_angle) * 0.25)
	var daylight: float = clampf(sin(time_of_day * PI), 0.05, 1.0)
	sun.light_energy = lerp(0.15, 4.8, daylight)
	sun.light_color = Color(1.0, lerp(0.28, 0.72, daylight), lerp(0.18, 0.5, daylight), 1.0)


func _setup_wind() -> void:
	wind_audio.stream = _make_wind_wav()
	wind_audio.volume_db = -18.0
	wind_audio.play()


func _make_wind_wav() -> AudioStreamWAV:
	var sample_rate: int = 16000
	var sample_count: int = sample_rate * 3
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 404
	for i in range(sample_count):
		var t: float = float(i) / float(sample_rate)
		var gust: float = 0.5 + 0.5 * sin(t * TAU * 0.37)
		var sample: int = clampi(int(rng.randf_range(-1.0, 1.0) * gust * 3800.0), -32768, 32767)
		bytes.encode_s16(i * 2, sample)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.data = bytes
	return wav
