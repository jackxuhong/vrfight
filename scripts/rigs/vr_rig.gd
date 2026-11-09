class_name VrRig
extends XROrigin3D
## The player in VR: headset plus Touch controllers (Rift, or Quest 2 over Link).
## Left stick walks, right stick snap-turns, B or Y held returns to the lobby.
## DesktopRig has the same methods, so the rest of the game doesn't care which one it has.

const MOVE_SPEED := 1.8
const SNAP_TURN := PI / 4
const HEAD_FROM_EYES := Vector3(0, -0.03, 0.08)  # head centre sits behind and below the eyes

var hints := {"back": "Hold B or Y", "guard": "Hold both gloves up by your face"}
var camera := XRCamera3D.new()
var hands: Array[XRController3D] = []
var _turn_ready := true


func _init() -> void:
	add_child(camera)
	for tracker in [&"left_hand", &"right_hand"]:
		var c := XRController3D.new()
		c.tracker = tracker
		add_child(c)
		hands.append(c)


func _ready() -> void:
	current = true
	camera.current = true


func head_transform() -> Transform3D:
	return camera.global_transform.translated_local(HEAD_FROM_EYES)


func glove(i: int) -> Vector3:
	return hands[i].global_position


func move(dt: float, locked: bool) -> void:
	var turn := hands[1].get_vector2(&"primary").x
	if absf(turn) > 0.7 and _turn_ready:
		_turn(-signf(turn) * SNAP_TURN)
		_turn_ready = false
	elif absf(turn) < 0.3:
		_turn_ready = true
	var stick := hands[0].get_vector2(&"primary")
	if locked or stick.length() < 0.15:
		return
	var b := camera.global_basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	global_position += (fwd * stick.y + right * stick.x) * MOVE_SPEED * dt


## Put the player's head over `pos` (floor plane), facing `yaw`.
func place(pos: Vector3, yaw: float) -> void:
	var f := -camera.global_basis.z
	_turn(yaw - atan2(-f.x, -f.z))
	var c := camera.global_position
	global_position += Vector3(pos.x - c.x, 0.0, pos.z - c.z)


func shift(delta: Vector3) -> void:
	global_position += delta


## Both gloves up by the face: how a downed boxer shows the referee they can go on.
func guard_up() -> bool:
	var h := head_transform().origin
	for i in 2:
		var g := glove(i)
		if g.distance_to(h) > 0.35 or g.y < h.y - 0.3:
			return false
	return true


func buzz(i: int, strength: float) -> void:
	hands[i].trigger_haptic_pulse(&"haptic", 0.0, clampf(strength, 0.0, 1.0), 0.08, 0.0)


func back_pressed() -> bool:
	return hands[0].is_button_pressed(&"by_button") or hands[1].is_button_pressed(&"by_button")


func _turn(angle: float) -> void:
	var pivot := camera.global_position
	var t := global_transform
	t.origin -= pivot
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	t.origin += pivot
	global_transform = t
