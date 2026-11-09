class_name DesktopRig
extends Node3D
## Keyboard-and-mouse stand-in for the headset, for testing without VR. Same methods as VrRig.
## Click to capture the mouse, then: mouse looks, WASD walks, left/right click throws a left/right
## punch (hold Shift to aim at the body), Space holds the guard, Esc held returns to the lobby.

const EYE_HEIGHT := 1.7
const MOVE_SPEED := 1.8
const PUNCH_TIME := 0.3
const HEAD_FROM_EYES := Vector3(0, -0.03, 0.08)

var hints := {"back": "Hold Esc", "guard": "Hold Space"}
var camera := Camera3D.new()
var _punch_t: Array[float] = [-1.0, -1.0]
var _punch_low: Array[bool] = [false, false]


func _init() -> void:
	camera.position.y = EYE_HEIGHT
	add_child(camera)


func _ready() -> void:
	camera.current = true


func _unhandled_input(e: InputEvent) -> void:
	var click := e as InputEventMouseButton
	var motion := e as InputEventMouseMotion
	if click and click.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif click.button_index == MOUSE_BUTTON_LEFT:
			_throw(0)
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			_throw(1)
	elif motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= motion.relative.x * 0.003
		camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * 0.003, -1.3, 1.3)
	elif e is InputEventKey and (e as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func head_transform() -> Transform3D:
	return camera.global_transform.translated_local(HEAD_FROM_EYES)


func glove(i: int) -> Vector3:
	var side := -0.18 if i == 0 else 0.18
	var rest := Vector3(side * 0.6, -0.02, -0.25) if guard_up() else Vector3(side, -0.25, -0.3)
	var local := rest
	if _punch_t[i] >= 0.0:
		var target := Vector3(side * 0.3, -0.45 if _punch_low[i] else -0.05, -0.75)
		local = rest.lerp(target, sin(PI * _punch_t[i] / PUNCH_TIME))  # out and back
	return camera.global_transform * local


func move(dt: float, locked: bool) -> void:
	for i in 2:
		if _punch_t[i] >= 0.0:
			_punch_t[i] += dt
			if _punch_t[i] > PUNCH_TIME:
				_punch_t[i] = -1.0
	if locked:
		return
	var d := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), 0.0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if d != Vector3.ZERO:
		global_position += global_basis * d.normalized() * MOVE_SPEED * dt


func place(pos: Vector3, yaw: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.z)
	rotation.y = yaw
	camera.rotation.x = 0.0


func shift(delta: Vector3) -> void:
	global_position += delta


func guard_up() -> bool:
	return Input.is_key_pressed(KEY_SPACE)


func buzz(_i: int, _strength: float) -> void:
	pass


func back_pressed() -> bool:
	return Input.is_key_pressed(KEY_ESCAPE)


func _throw(i: int) -> void:
	if _punch_t[i] < 0.0:
		_punch_t[i] = 0.0
		_punch_low[i] = Input.is_key_pressed(KEY_SHIFT)
