class_name DummyBrain
extends RefCounted
## A practice dummy: stands at `pos` facing you, optionally sways its head, wobbles when hit.
## Its gloves hang low so the head is open.

var me: Fighter
var pos: Vector3
var sway: bool
var _t := 0.0
var _wobble := Vector3.ZERO


func _init(fighter: Fighter, at: Vector3, sways: bool) -> void:
	me = fighter
	pos = at
	sway = sways


func update(dt: float, target: Vector3) -> void:
	_t += dt
	var fwd := target - pos
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	_wobble = _wobble.lerp(Vector3.ZERO, 1.0 - exp(-5.0 * dt))
	var h := pos + Vector3(0, 1.7, 0) + _wobble
	if sway:
		h += right * sin(_t * 1.4) * 0.18
	me.head = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), h)
	me.gloves[0] = h + fwd * 0.2 - right * 0.22 + Vector3(0, -0.4, 0)
	me.gloves[1] = h + fwd * 0.2 + right * 0.22 + Vector3(0, -0.4, 0)


func hit(push: Vector3) -> void:
	_wobble += push.limit_length(0.12)
