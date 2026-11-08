class_name Arena
## The ring and the room, built from primitives. The canvas top is the real floor (y = 0).

const HALF := 3.0  # the ring is 6 m square inside the ropes
const RED := Color(0.8, 0.12, 0.1)
const BLUE := Color(0.12, 0.25, 0.8)


static func build(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.55)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 35, 0)
	key.light_energy = 0.5
	root.add_child(key)
	var top := OmniLight3D.new()
	top.position = Vector3(0, 5, 0)
	top.omni_range = 12.0
	top.light_energy = 1.6
	root.add_child(top)

	var size := HALF * 2 + 0.8
	_add(root, _box(Vector3(size, 0.12, size)), Color(0.82, 0.82, 0.78), Vector3(0, -0.06, 0))
	_add(root, _box(Vector3(size, 0.9, size)), Color(0.08, 0.1, 0.25), Vector3(0, -0.57, 0))
	_add(root, _box(Vector3(40, 0.1, 40)), Color(0.06, 0.06, 0.08), Vector3(0, -1.07, 0))

	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var c := RED if sx < 0 and sz > 0 else (BLUE if sx > 0 and sz < 0 else Color(0.9, 0.9, 0.9))
			_add(root, _cylinder(0.07, 1.5), c, Vector3(sx * HALF, 0.75, sz * HALF))
	for y in [0.5, 0.9, 1.3]:
		for s in [-1, 1]:
			_add(root, _cylinder(0.022, HALF * 2), Color(0.85, 0.85, 0.9), Vector3(s * HALF, y, 0), Vector3(PI / 2, 0, 0))
			_add(root, _cylinder(0.022, HALF * 2), Color(0.85, 0.85, 0.9), Vector3(0, y, s * HALF), Vector3(0, 0, PI / 2))


static func make(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return m


static func _add(root: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := make(mesh, color)
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
